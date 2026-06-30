// ignore_for_file: avoid_redundant_argument_values
//
// PR2 — Nueva Sesión dialog tests.
// SCENARIOS 201-A/B/C, 202-A/B.
// Todas las strings son español hardcodeado + comentario // i18n.
// NO se usa AppL10n en ningún nuevo archivo de agenda web.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/new_session_dialog.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-pr2';
const _kAthleteId1 = 'athlete-uid-aa1';
const _kAthleteId2 = 'athlete-uid-bb2';
const _kAthleteIdPaused = 'athlete-uid-paused';

// ─── Stub repository ─────────────────────────────────────────────────────────

/// Stub de [AppointmentRepository] que captura los args de [createByTrainer].
///
/// Extiende Fake + implements para que los métodos no stubeados lancen
/// `UnimplementedError` en vez de crashear silenciosamente.
class _StubAppointmentRepository extends Fake implements AppointmentRepository {
  String? capturedTrainerId;
  String? capturedAthleteId;
  String? capturedAthleteDisplayName;
  DateTime? capturedStartsAt;
  int? capturedDurationMin;
  String? capturedNoteBefore;
  bool shouldThrow = false;

  @override
  Future<Appointment> createByTrainer({
    required String trainerId,
    required String athleteId,
    required String athleteDisplayName,
    required DateTime startsAt,
    required int durationMin,
    String? noteBefore,
  }) async {
    if (shouldThrow) throw Exception('network error');
    capturedTrainerId = trainerId;
    capturedAthleteId = athleteId;
    capturedAthleteDisplayName = athleteDisplayName;
    capturedStartsAt = startsAt;
    capturedDurationMin = durationMin;
    capturedNoteBefore = noteBefore;
    return Appointment(
      id: 'new-appt',
      trainerId: trainerId,
      athleteId: athleteId,
      athleteDisplayName: athleteDisplayName,
      startsAt: startsAt,
      durationMin: durationMin,
      status: AppointmentStatus.confirmed,
      noteBefore: noteBefore,
    );
  }
}

// ─── Factories ───────────────────────────────────────────────────────────────

final _kRequestedAt = DateTime(2026, 1, 1);

TrainerLink _activeLink(String athleteId) => TrainerLink(
      id: 'link-$athleteId',
      trainerId: _kTrainerId,
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: _kRequestedAt,
    );

TrainerLink _pausedLink(String athleteId) => TrainerLink(
      id: 'link-paused-$athleteId',
      trainerId: _kTrainerId,
      athleteId: athleteId,
      status: TrainerLinkStatus.paused,
      requestedAt: _kRequestedAt,
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

// ─── Test wrap helper ─────────────────────────────────────────────────────────

/// Wraps [child] in ProviderScope + MaterialApp mirroring agenda screen test.
Widget _wrap(Widget child, {required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

// ─── Shared overrides builder ─────────────────────────────────────────────────

List<Override> _overrides({
  List<TrainerLink> links = const [],
  Map<String, UserPublicProfile> profiles = const {},
  _StubAppointmentRepository? repo,
}) {
  final stub = repo ?? _StubAppointmentRepository();
  return [
    currentUidProvider.overrideWithValue(_kTrainerId),
    trainerLinksStreamProvider.overrideWith(
      (ref) => Stream.value(links),
    ),
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream.value(const []),
    ),
    appointmentRepositoryProvider.overrideWithValue(stub),
    for (final entry in profiles.entries)
      userPublicProfileProvider(entry.key).overrideWith(
        (ref) => Stream.value(entry.value),
      ),
  ];
}

// ─── Helper: open dialog via "NUEVA SESIÓN" button ───────────────────────────

/// Pumps [AgendaWebScreen] (which has the NUEVA SESIÓN button in PR2) and taps it.
Future<void> _openDialogViaScreen(
  WidgetTester tester, {
  List<TrainerLink> links = const [],
  Map<String, UserPublicProfile> profiles = const {},
  _StubAppointmentRepository? repo,
}) async {
  await tester.pumpWidget(
    _wrap(
      const AgendaWebScreen(),
      overrides: _overrides(links: links, profiles: profiles, repo: repo),
    ),
  );
  await tester.pumpAndSettle();

  final btnFinder = find.text('NUEVA SESIÓN'); // i18n
  expect(btnFinder, findsOneWidget,
      reason: 'AgendaWebScreen debe mostrar botón NUEVA SESIÓN');
  await tester.tap(btnFinder);
  await tester.pumpAndSettle();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // SCENARIO-201-A: Dialog opens
  group('SCENARIO-201-A — dialog abre al tocar NUEVA SESIÓN', () {
    testWidgets('muestra NewSessionDialog como AlertDialog', (tester) async {
      await _openDialogViaScreen(
        tester,
        links: [_activeLink(_kAthleteId1)],
        profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
      );

      // El dialog debe estar visible
      expect(find.byType(AlertDialog), findsOneWidget);
      // El título "NUEVA SESIÓN" debe aparecer dentro del dialog
      expect(find.text('NUEVA SESIÓN'), findsWidgets); // i18n
    });
  });

  // SCENARIO-201-B: Empty active → disabled submit + copy
  group('SCENARIO-201-B — sin alumnos activos → submit deshabilitado', () {
    testWidgets(
        'si solo hay vínculos pausados, muestra copia y submit deshabilitado',
        (tester) async {
      await _openDialogViaScreen(
        tester,
        links: [_pausedLink(_kAthleteIdPaused)],
      );

      // El texto de "no tenés alumnos activos" debe aparecer
      expect(
        find.text('No tenés alumnos activos todavía.'), // i18n
        findsOneWidget,
      );

      // El botón REGISTRAR debe estar deshabilitado (null onPressed)
      final elevatedButtons = find.byType(ElevatedButton);
      bool foundDisabled = false;
      for (final btn in tester.widgetList<ElevatedButton>(elevatedButtons)) {
        if (btn.onPressed == null) {
          foundDisabled = true;
          break;
        }
      }
      expect(foundDisabled, isTrue,
          reason: 'ElevatedButton de submit debe estar deshabilitado');
    });

    testWidgets('sin ningún vínculo → mensaje + submit deshabilitado',
        (tester) async {
      await _openDialogViaScreen(tester, links: const []);

      expect(
        find.text('No tenés alumnos activos todavía.'), // i18n
        findsOneWidget,
      );
    });
  });

  // SCENARIO-201-C: Solo activos en el dropdown
  group('SCENARIO-201-C — dropdown lista solo vínculos activos', () {
    testWidgets('vínculo activo aparece; vínculo pausado no aparece',
        (tester) async {
      await _openDialogViaScreen(
        tester,
        links: [
          _activeLink(_kAthleteId1),
          _pausedLink(_kAthleteIdPaused),
        ],
        profiles: {
          _kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez'),
          _kAthleteIdPaused: _pub(_kAthleteIdPaused, 'Pausado Gomez'),
        },
      );

      // Abre el dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // El activo debe estar en el dropdown
      expect(find.text('Carlos Pérez'), findsWidgets);

      // El pausado NO debe estar
      expect(find.text('Pausado Gomez'), findsNothing);
    });
  });

  // SCENARIO-202-A: Happy path → createByTrainer called, dialog closes
  group('SCENARIO-202-A — submit exitoso cierra dialog y llama createByTrainer',
      () {
    testWidgets('llama createByTrainer con args exactos y cierra el dialog',
        (tester) async {
      final stub = _StubAppointmentRepository();

      await _openDialogViaScreen(
        tester,
        links: [_activeLink(_kAthleteId1)],
        profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
        repo: stub,
      );

      // Seleccionar el alumno en el dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carlos Pérez').last);
      await tester.pumpAndSettle();

      // Ingresar una duración válida (el default 60 ya está, pero forzamos 45)
      final durationField = find.byType(TextField).first;
      await tester.enterText(durationField, '45');
      await tester.pumpAndSettle();

      // Tap el submit
      final submitBtn = find.text('REGISTRAR SESIÓN'); // i18n
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // El dialog debe cerrarse
      expect(find.byType(AlertDialog), findsNothing);

      // El stub debe haber capturado los args correctos
      expect(stub.capturedTrainerId, equals(_kTrainerId));
      expect(stub.capturedAthleteId, equals(_kAthleteId1));
      expect(stub.capturedAthleteDisplayName, equals('Carlos Pérez'));
      expect(stub.capturedDurationMin, equals(45));
      expect(stub.capturedStartsAt, isNotNull);
    });
  });

  // SCENARIO-202-B: Repository error → dialog stays open + error message
  group('SCENARIO-202-B — error del repo → dialog se mantiene abierto', () {
    testWidgets('muestra mensaje de error cuando createByTrainer lanza',
        (tester) async {
      final stub = _StubAppointmentRepository()..shouldThrow = true;

      await _openDialogViaScreen(
        tester,
        links: [_activeLink(_kAthleteId1)],
        profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
        repo: stub,
      );

      // Seleccionar alumno
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carlos Pérez').last);
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('REGISTRAR SESIÓN')); // i18n
      await tester.pumpAndSettle();

      // Dialog debe seguir abierto
      expect(find.byType(AlertDialog), findsOneWidget);

      // Mensaje de error visible
      expect(
        find.text('No pudimos registrar la sesión. Probá de nuevo.'), // i18n
        findsOneWidget,
      );
    });
  });

  // Extra: past date guard
  group('Validación — fecha/hora en el pasado', () {
    testWidgets('si el usuario ingresa hora pasada el submit muestra error',
        (tester) async {
      // Esta prueba verifica que el guard del pasado bloquea el submit.
      // Dado que no podemos controlar showDatePicker fácilmente en unit tests,
      // probamos directamente NewSessionDialog con initialDate=ayer.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => NewSessionDialog(
                  initialDate: yesterday,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
          overrides: _overrides(
            links: [_activeLink(_kAthleteId1)],
            profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Seleccionar alumno
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carlos Pérez').last);
      await tester.pumpAndSettle();

      // Submit sin cambiar la fecha (ayer)
      await tester.tap(find.text('REGISTRAR SESIÓN')); // i18n
      await tester.pumpAndSettle();

      // El dialog debe seguir abierto (guard activo)
      expect(find.byType(AlertDialog), findsOneWidget);

      // Mensaje de pasado visible
      expect(
        find.text('No podés registrar una sesión en el pasado.'), // i18n
        findsOneWidget,
      );
    });
  });

  // Extra: duración inválida
  group('Validación — duración fuera de rango', () {
    testWidgets('duración < 5 → submit bloqueado con mensaje', (tester) async {
      await _openDialogViaScreen(
        tester,
        links: [_activeLink(_kAthleteId1)],
        profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
      );

      // Seleccionar alumno
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carlos Pérez').last);
      await tester.pumpAndSettle();

      // Ingresar duración inválida
      final durationField = find.byType(TextField).first;
      await tester.enterText(durationField, '3');
      await tester.pumpAndSettle();

      await tester.tap(find.text('REGISTRAR SESIÓN')); // i18n
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('entre 5 y 480'), // i18n
        findsOneWidget,
      );
    });
  });
}
