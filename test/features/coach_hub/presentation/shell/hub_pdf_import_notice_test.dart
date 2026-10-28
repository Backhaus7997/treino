// La lectura del PDF del Coach Hub sobrevive a la pantalla de subida (Codex,
// #1657): irse por el sidebar mientras se lee no tira un resultado que ya se
// pagó con cupo. Al terminar con el PF en otra sección, el shell avisa con el
// toast del kit; en «Importar plan» la pantalla se encarga sola. Cambiar de
// cuenta reinicia la lectura.
//
// Se monta el `CoachHubScaffold` REAL dentro de un `ShellRoute`, como en
// producción: el aviso vive en el shell.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/coach_hub_session_resolving_provider.dart';
import 'package:treino/features/coach_hub/application/hub_pdf_import_job_provider.dart';
import 'package:treino/features/coach_hub/application/pdf_import_quota_provider.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/application/plan_pdf_import_providers.dart';
import 'package:treino/features/coach_hub/data/plan_pdf_import_service.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_upload_plan_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../../helpers/onboarding_test_helpers.dart';
import '../periodized_draft_fixtures.dart';

const _listo = 'Tu plan está listo';
const _verVistaPrevia = 'VER VISTA PREVIA';
const _fallo = 'No pudimos leer tu plan.';
const _verDetalle = 'VER DETALLE';

/// Servicio de test: cada llamada queda pendiente hasta [complete].
class _FakeService implements PlanPdfImportService {
  final calls = <String>[];
  Completer<PdfImportResult>? _pending;

  void complete(PdfImportResult r) => _pending!.complete(r);

  @override
  Future<PdfImportResult> importPdf({
    required Uint8List bytes,
    required String fileName,
    String? athleteId,
  }) {
    calls.add(fileName);
    _pending = Completer<PdfImportResult>();
    return _pending!.future;
  }
}

/// El uid de la sesión, cambiable desde el test (logout / otra cuenta).
final _uid = StateProvider<String?>((ref) => kTrainerUid);

class _Harness {
  _Harness(this.router, this.container, this.service);
  final GoRouter router;
  final ProviderContainer container;
  final _FakeService service;
}

Future<_Harness> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(const {});
  final sp = await SharedPreferences.getInstance();
  FilePicker.platform = FakeFilePicker(
    PlatformFile(name: 'plan_fuerza.pdf', size: 1024, bytes: Uint8List(8)),
  );
  final service = _FakeService();

  final router = GoRouter(
    initialLocation: '/upload-plan',
    routes: [
      ShellRoute(
        pageBuilder: (ctx, state, child) =>
            NoTransitionPage(child: CoachHubScaffold(child: child)),
        routes: [
          GoRoute(
            path: '/upload-plan',
            builder: (_, __) => const CoachHubUploadPlanScreen(),
            routes: [
              GoRoute(
                path: 'preview',
                builder: (_, __) => const CoachHubPlanPreviewScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/alumnos',
            builder: (_, __) => const Text('SECCION_ALUMNOS'),
          ),
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const Text('SECCION_DASHBOARD'),
          ),
        ],
      ),
    ],
  );

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
    coachHubSessionResolvingProvider.overrideWithValue(false),
    // Con el tour ya visto: si no, `CoachHubTourGate` lo empuja encima del
    // shell y tapa todo.
    userProfileProvider.overrideWith((ref) => Stream.value(
        trainerProfile().copyWith(onboardingSeen: allSurfacesSeen()))),
    currentUidProvider.overrideWith((ref) => ref.watch(_uid)),
    routineRepositoryProvider.overrideWithValue(MockRoutineRepo()),
    exerciseRepositoryProvider.overrideWithValue(exerciseRepoWith(const [])),
    trainerLinksStreamProvider.overrideWith(
      (ref) => Stream.value([
        TrainerLink(
          id: 'link-$kAthleteId',
          trainerId: kTrainerUid,
          athleteId: kAthleteId,
          status: TrainerLinkStatus.active,
          requestedAt: DateTime.utc(2026, 1, 1),
        ),
      ]),
    ),
    userPublicProfileProvider(kAthleteId).overrideWith(
      (ref) => Stream.value(
        const UserPublicProfile(uid: kAthleteId, displayName: 'Ana'),
      ),
    ),
    pdfImportGateProvider.overrideWithValue(PdfImportGate.enabled),
    planPdfImportServiceProvider.overrideWithValue(service),
    pdfImportRemainingProvider.overrideWithValue(null),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return _Harness(router, container, service);
}

/// Elige el PDF y aprieta PROCESAR PLAN. La barra de progreso anima para
/// siempre: de acá en más, `pump` con duración mientras se lee.
Future<void> _startReading(WidgetTester tester) async {
  await tester.tap(find.text('Elegir archivo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('PROCESAR PLAN'));
  await tester.pump();
  expect(find.text('Leyendo tu plan…'), findsOneWidget);
}

/// Navega como el sidebar (`context.go`), que no pasa por ningún `PopScope`.
Future<void> _goTo(WidgetTester tester, _Harness h, String route) async {
  h.router.go(route);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets(
      'irse a otra sección mientras lee: el borrador llega igual y el shell '
      'avisa con VER VISTA PREVIA, que abre la vista previa', (tester) async {
    final h = await _pump(tester);
    await _startReading(tester);
    await _goTo(tester, h, '/alumnos');
    expect(find.text('SECCION_ALUMNOS'), findsOneWidget);
    expect(find.byType(CoachHubUploadPlanScreen), findsNothing);

    h.service
        .complete(PdfImportSuccess(draft: pdfDraft(), quota: null, model: 'm'));
    await tester.pumpAndSettle();

    expect(h.container.read(periodizedImportProvider), isNotNull);
    expect(find.text(_listo), findsOneWidget);
    await tester.tap(find.text(_verVistaPrevia));
    await tester.pumpAndSettle();

    expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
    expect(find.text('Sugerencia: Remo con barra'), findsOneWidget);
    expect(h.container.read(hubPdfImportJobProvider), isA<HubPdfImportIdle>());
  });

  testWidgets(
      'si ignora el aviso y vuelve a «Importar plan», el plan listo lo espera',
      (tester) async {
    final h = await _pump(tester);
    await _startReading(tester);
    await _goTo(tester, h, '/alumnos');
    h.service
        .complete(PdfImportSuccess(draft: pdfDraft(), quota: null, model: 'm'));
    await tester.pumpAndSettle();

    await _goTo(tester, h, '/upload-plan');
    await tester.pumpAndSettle();
    expect(find.byType(CoachHubPlanPreviewScreen), findsNothing);
    // La tarjeta de la pantalla, no el toast del shell (que puede seguir
    // visible): se cierra para que el tap no caiga en él.
    ScaffoldMessenger.of(tester.element(find.byType(CoachHubUploadPlanScreen)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text(_verVistaPrevia), findsOneWidget);
    final ready = find.byKey(const Key('pdf_import_ready'));
    expect(find.descendant(of: ready, matching: find.text(_listo)),
        findsOneWidget);
    await tester
        .tap(find.descendant(of: ready, matching: find.text(_verVistaPrevia)));
    await tester.pumpAndSettle();
    expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
  });

  testWidgets(
      'falla con el PF afuera: aviso con VER DETALLE, y en la subida el error '
      'tipado con su acción', (tester) async {
    final h = await _pump(tester);
    await _startReading(tester);
    await _goTo(tester, h, '/alumnos');

    h.service.complete(const PdfImportTimeout());
    await tester.pumpAndSettle();
    expect(find.text(_fallo), findsOneWidget);

    await tester.tap(find.text(_verDetalle));
    await tester.pumpAndSettle();
    expect(find.byType(CoachHubUploadPlanScreen), findsOneWidget);
    expect(find.byKey(const Key('pdf_import_error')), findsOneWidget);
    expect(find.textContaining('tardó demasiado'), findsOneWidget);

    // «Reintentar» anda aunque la pantalla nueva no tenga el archivo: los
    // bytes los guardó la lectura.
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(h.service.calls, ['plan_fuerza.pdf', 'plan_fuerza.pdf']);
    expect(find.text('Leyendo tu plan…'), findsOneWidget);
  });

  testWidgets(
      'volver a «Importar plan» mientras lee muestra la espera y no deja '
      'empezar otra lectura', (tester) async {
    final h = await _pump(tester);
    await _startReading(tester);
    await _goTo(tester, h, '/alumnos');
    await _goTo(tester, h, '/upload-plan');

    expect(find.text('Leyendo tu plan…'), findsOneWidget);
    expect(find.text('plan_fuerza.pdf'), findsOneWidget);
    expect(find.byKey(const Key('pdf_import_progress')), findsOneWidget);
    expect(find.text('PROCESAR PLAN'), findsNothing);

    // Ni por la pantalla ni por el notifier: una lectura a la vez.
    await tester.tap(find.text('Elegir archivo'));
    await tester.pump();
    await h.container
        .read(hubPdfImportJobProvider.notifier)
        .start(bytes: Uint8List(8), fileName: 'otro.pdf');
    await tester.pump();
    expect(h.service.calls, ['plan_fuerza.pdf']);
    expect(find.text('Leyendo tu plan…'), findsOneWidget);
  });

  testWidgets(
      'termina con el PF en la pantalla: abre la vista previa, sin aviso del '
      'shell', (tester) async {
    final h = await _pump(tester);
    await _startReading(tester);

    h.service
        .complete(PdfImportSuccess(draft: pdfDraft(), quota: null, model: 'm'));
    await tester.pumpAndSettle();

    expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
    expect(find.text(_listo), findsNothing);
    expect(find.text(_verVistaPrevia), findsNothing);
  });

  group('cambiar de cuenta reinicia la lectura', () {
    testWidgets(
        'logout mientras lee: el resultado que llega después no se guarda ni '
        'se avisa', (tester) async {
      final h = await _pump(tester);
      await _startReading(tester);
      await _goTo(tester, h, '/alumnos');

      h.container.read(_uid.notifier).state = null;
      await tester.pump();
      expect(
          h.container.read(hubPdfImportJobProvider), isA<HubPdfImportIdle>());

      h.service.complete(
          PdfImportSuccess(draft: pdfDraft(), quota: null, model: 'm'));
      await tester.pumpAndSettle();
      expect(h.container.read(periodizedImportProvider), isNull);
      expect(
          h.container.read(hubPdfImportJobProvider), isA<HubPdfImportIdle>());
      expect(find.text(_listo), findsNothing);
    });

    testWidgets('otra cuenta: el borrador listo de la anterior se borra',
        (tester) async {
      final h = await _pump(tester);
      await _startReading(tester);
      await _goTo(tester, h, '/alumnos');
      h.service.complete(
          PdfImportSuccess(draft: pdfDraft(), quota: null, model: 'm'));
      await tester.pumpAndSettle();
      expect(h.container.read(periodizedImportProvider), isNotNull);

      h.container.read(_uid.notifier).state = 'otro-pf';
      await tester.pump();
      expect(h.container.read(periodizedImportProvider), isNull);
      expect(
          h.container.read(hubPdfImportJobProvider), isA<HubPdfImportIdle>());
    });
  });
}
