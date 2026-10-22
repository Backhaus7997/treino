// Pantalla de subida del import de PDF (docs/plan-import-pdf.md, pasos 2 y
// 3): aviso exacto, cupo sólo si se sabe, tope de 5 MB antes de mandar,
// espera explícita sin reenvío ni salida muda, y cada error en pantalla.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/plan_pdf_import_upload_screen.dart';
import 'package:treino/features/coach_hub/application/pdf_import_quota_provider.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/application/plan_pdf_import_providers.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/data/plan_pdf_import_service.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../coach_hub/presentation/periodized_draft_fixtures.dart'
    show FakeFilePicker;

const _aviso = 'Usamos IA para leer tu PDF y armar el plan. No guardamos el '
    'archivo. Subí solo los datos de tu alumno que sean necesarios.';

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
    calls.add('$fileName:$athleteId');
    _pending = Completer<PdfImportResult>();
    return _pending!.future;
  }
}

void _pickReturns(String name, int size) {
  FilePicker.platform = FakeFilePicker(
    PlatformFile(name: name, size: size, bytes: Uint8List(8)),
  );
}

PeriodizedImportDraft _draft() => const PeriodizedImportDraft(
      plan: PeriodizedPlan(numWeeks: 4, days: [
        PeriodizedDay(dayNumber: 1, rows: []),
        PeriodizedDay(dayNumber: 2, rows: []),
      ]),
      warnings: [],
      name: 'plan',
      assignments: {},
      suggestions: {},
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeService service, {
  PdfImportRemaining? remaining,
}) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('FICHA')),
        routes: [
          GoRoute(
            path: 'import',
            builder: (_, __) =>
                const PlanPdfImportUploadScreen(athleteId: 'ath-1'),
          ),
        ],
      ),
    ],
  );
  final container = ProviderContainer(overrides: [
    planPdfImportServiceProvider.overrideWithValue(service),
    pdfImportRemainingProvider.overrideWithValue(remaining),
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
  router.push('/home/import');
  await tester.pumpAndSettle();
  return container;
}

Future<void> _pickAndProcess(WidgetTester tester) async {
  await tester.tap(find.text('Elegir PDF'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('PROCESAR PLAN'));
  await tester.pump();
}

void main() {
  testWidgets('el aviso de privacidad es el texto exacto de la spec',
      (tester) async {
    await _pump(tester, _FakeService());
    expect(find.text(_aviso), findsOneWidget);
  });

  testWidgets('el cupo sale sólo si se sabe', (tester) async {
    await _pump(tester, _FakeService(),
        remaining: (week: 5, day: 2, limitWeekly: 7, limitDaily: 7));
    expect(find.text('Te quedan 5 esta semana y 2 hoy.'), findsOneWidget);
  });

  testWidgets('sin cupo conocido no hay ningún número', (tester) async {
    await _pump(tester, _FakeService());
    expect(find.byKey(const Key('pdf_import_quota')), findsNothing);
    expect(find.textContaining('Te quedan'), findsNothing);
  });

  testWidgets('pantalla chica y letra grande: sin desbordes', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final service = _FakeService();
    await _pump(tester, service,
        remaining: (week: 5, day: 2, limitWeekly: 7, limitDaily: 7));
    _pickReturns('un-nombre-de-archivo-muy-largo-del-plan-de-mi-alumno.pdf', 9);
    await tester.ensureVisible(find.text('Elegir PDF'));
    await tester.tap(find.text('Elegir PDF'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('PROCESAR PLAN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PROCESAR PLAN'));
    await tester.pump(const Duration(milliseconds: 300));
    service.complete(const PdfImportTimeout());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(service.calls, hasLength(1));
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('un PDF de más de 5 MB se rechaza sin llamar al servidor',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    _pickReturns('grande.pdf', kPdfImportMaxBytes + 1);

    await tester.tap(find.text('Elegir PDF'));
    await tester.pumpAndSettle();

    expect(find.text('El archivo pesa más de 5 MB. Elegí uno más liviano.'),
        findsOneWidget);
    expect(find.text('Elegir otro archivo'), findsOneWidget);
    expect(find.text('PROCESAR PLAN'), findsNothing);
    expect(service.calls, isEmpty);
  });

  testWidgets('justo 5 MB pasa y se puede procesar', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    _pickReturns('justo.pdf', kPdfImportMaxBytes);

    await _pickAndProcess(tester);
    expect(service.calls, ['justo.pdf:ath-1']);
  });

  testWidgets(
      'procesando: progreso indeterminado y el texto de espera, sin '
      'reenviar; salir pide confirmación', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    _pickReturns('plan.pdf', 1000);
    await _pickAndProcess(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('pdf_import_progress')), findsOneWidget);
    expect(find.text('Leyendo tu plan…'), findsOneWidget);
    expect(
        find.text(
            'Puede tardar hasta un par de minutos. No cierres esta pantalla.'),
        findsOneWidget);
    // No hay botón para reenviar mientras procesa.
    expect(find.text('PROCESAR PLAN'), findsNothing);

    // Atrás: pregunta, y «Cancelar» se queda.
    await tester.tap(find.byTooltip('Volver'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('¿Salir mientras se lee el plan?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leyendo tu plan…'), findsOneWidget);

    // Atrás del sistema, y confirmar: sale.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Salir'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('FICHA'), findsOneWidget);
    expect(service.calls, hasLength(1));
    service.complete(const PdfImportTimeout());
  });

  testWidgets('éxito: el borrador queda para la vista previa', (tester) async {
    final service = _FakeService();
    final container = await _pump(tester, service);
    _pickReturns('plan.pdf', 1000);
    await _pickAndProcess(tester);

    final draft = _draft();
    service.complete(PdfImportSuccess(draft: draft, quota: null, model: 'm'));
    await tester.pumpAndSettle();

    expect(container.read(periodizedImportProvider), same(draft));
    expect(find.text('Leímos 2 días y 4 semanas.'), findsOneWidget);
    expect(find.byKey(const Key('pdf_import_error')), findsNothing);
  });

  // Cada error tipado, con su texto y su acción, en la pantalla.
  final casos = <(PdfImportResult, String, List<String>)>[
    (
      const PdfImportInvalidFile(PdfRejectReason.notPdf),
      'El archivo no es un PDF válido.',
      ['Elegir otro archivo'],
    ),
    (
      const PdfImportInvalidFile(PdfRejectReason.tooManyPages),
      'El PDF tiene más de 20 páginas. Elegí uno más corto.',
      ['Elegir otro archivo'],
    ),
    (
      const PdfImportInvalidFile(PdfRejectReason.encrypted),
      'El PDF tiene contraseña. Exportalo sin contraseña y elegilo de nuevo.',
      ['Elegir otro archivo'],
    ),
    (
      const PdfImportInvalidFile(PdfRejectReason.tooBig),
      'El archivo pesa más de 5 MB. Elegí uno más liviano.',
      ['Elegir otro archivo'],
    ),
    (
      const PdfImportInvalidFile(PdfRejectReason.unknown),
      'No pudimos usar este archivo. Probá con otro.',
      ['Elegir otro archivo'],
    ),
    (
      const PdfImportQuotaExhausted(scope: PdfQuotaScope.unknown),
      'Usaste todas las importaciones disponibles por ahora.',
      [],
    ),
    (
      const PdfImportTimeout(),
      'La lectura tardó demasiado. Probá de nuevo; si el PDF es largo, '
          'probá con menos páginas.',
      ['Reintentar', 'Elegir otro archivo'],
    ),
    (
      const PdfImportInternal(code: 'internal'),
      'No pudimos leer el plan. Probá de nuevo en un rato.',
      ['Reintentar'],
    ),
    (
      const PdfImportInvalidPlan(diagnostics: [], quota: null, model: 'm'),
      'Leímos el PDF pero no pudimos armar el plan. Este intento ya contó en '
          'tu cupo.',
      ['Elegir otro archivo'],
    ),
    (
      const PdfImportDisabled(),
      'Importar de PDF no está disponible para tu cuenta.',
      [],
    ),
    (
      const PdfImportStructuredOutputsDisabled(),
      'Importar de PDF no está disponible por un problema nuestro. No se '
          'descontó de tu cupo.',
      [],
    ),
    (
      const PdfImportNotTrainer(),
      'Solo los entrenadores pueden importar planes.',
      [],
    ),
    (
      const PdfImportUnauthenticated(),
      'Tu sesión se cerró. Volvé a iniciar sesión.',
      [],
    ),
  ];
  for (final (result, message, actions) in casos) {
    testWidgets('error ${result.runtimeType}: "$message"', (tester) async {
      final service = _FakeService();
      await _pump(tester, service);
      _pickReturns('plan.pdf', 1000);
      await _pickAndProcess(tester);
      service.complete(result);
      await tester.pumpAndSettle();

      final panel = find.byKey(const Key('pdf_import_error'));
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text(message)),
          findsOneWidget);
      for (final a in ['Reintentar', 'Elegir otro archivo']) {
        expect(
            find.text(a), actions.contains(a) ? findsOneWidget : findsNothing,
            reason: a);
      }
      // En la pantalla, no en un SnackBar.
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('cupo agotado de la semana dice cuándo se renueva',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    _pickReturns('plan.pdf', 1000);
    await _pickAndProcess(tester);
    // Lunes 00:00 ART = 03:00 UTC: un instante fijo, no depende del TZ del host.
    final resetsAt = DateTime.utc(2026, 10, 26, 3, 0);
    service.complete(
        PdfImportQuotaExhausted(scope: PdfQuotaScope.week, resetsAt: resetsAt));
    await tester.pumpAndSettle();

    expect(
        find.text('Usaste todas las importaciones de esta semana. Se renueva '
            'el 26/10 a las 00:00.'),
        findsOneWidget);
  });

  testWidgets('Reintentar vuelve a mandar el mismo archivo', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    _pickReturns('plan.pdf', 1000);
    await _pickAndProcess(tester);
    service.complete(const PdfImportInternal());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(service.calls, ['plan.pdf:ath-1', 'plan.pdf:ath-1']);
    service.complete(const PdfImportInternal());
    await tester.pumpAndSettle();
  });
}
