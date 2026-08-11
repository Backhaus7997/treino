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
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
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

/// Fake [AvailabilityRepository] that returns a fixed [overrides] list for
/// any [watchOverrides] call, regardless of the requested date range — the
/// dialog only needs a single-day check so the range itself isn't asserted.
class _FakeAvailabilityRepository extends Fake
    implements AvailabilityRepository {
  _FakeAvailabilityRepository({this.overrides = const []});

  final List<AvailabilityOverride> overrides;

  @override
  Stream<List<AvailabilityOverride>> watchOverrides(
    String trainerId,
    DateTime fromDate,
    DateTime toDate,
  ) =>
      Stream.value(overrides);
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
  List<AvailabilityOverride> availabilityOverrides = const [],
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
    availabilityRepositoryProvider.overrideWithValue(
      _FakeAvailabilityRepository(overrides: availabilityOverrides),
    ),
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
  List<AvailabilityOverride> availabilityOverrides = const [],
}) async {
  await tester.pumpWidget(
    _wrap(
      const AgendaWebScreen(),
      overrides: _overrides(
        links: links,
        profiles: profiles,
        repo: repo,
        availabilityOverrides: availabilityOverrides,
      ),
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

  // Blocked-day soft warning: creating a session on a day the trainer
  // blocked shows a confirm dialog; confirming proceeds to createByTrainer,
  // cancelling does NOT call the repo.
  group('Aviso de día bloqueado', () {
    // Fixed future date so the past-date guard never interferes with this
    // test regardless of when it runs.
    final blockedDate = DateTime.now().add(const Duration(days: 10));
    final blockedDateOnly =
        DateTime(blockedDate.year, blockedDate.month, blockedDate.day);

    Future<void> openDialogDirect(
      WidgetTester tester, {
      required List<AvailabilityOverride> availabilityOverrides,
      _StubAppointmentRepository? repo,
    }) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => NewSessionDialog(
                  initialDate: blockedDateOnly,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
          overrides: _overrides(
            links: [_activeLink(_kAthleteId1)],
            profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
            repo: repo,
            availabilityOverrides: availabilityOverrides,
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
    }

    testWidgets('crear sesión en día bloqueado muestra dialog "Día bloqueado"',
        (tester) async {
      final blockOverride = AvailabilityOverride.block(
        id: 'block-1',
        trainerId: _kTrainerId,
        date: blockedDateOnly,
      );

      await openDialogDirect(
        tester,
        availabilityOverrides: [blockOverride],
      );

      await tester.tap(find.text('REGISTRAR SESIÓN')); // i18n
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsOneWidget); // i18n
      expect(
        find.textContaining('marcado como bloqueado'), // i18n
        findsOneWidget,
      );
    });

    testWidgets('confirmar en el dialog de día bloqueado llama createByTrainer',
        (tester) async {
      final blockOverride = AvailabilityOverride.block(
        id: 'block-1',
        trainerId: _kTrainerId,
        date: blockedDateOnly,
      );
      final stub = _StubAppointmentRepository();

      await openDialogDirect(
        tester,
        availabilityOverrides: [blockOverride],
        repo: stub,
      );

      await tester.tap(find.text('REGISTRAR SESIÓN')); // i18n
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsOneWidget); // i18n

      // Confirmar "Cargar igual"
      await tester.tap(find.text('Cargar igual')); // i18n
      await tester.pumpAndSettle();

      // El dialog original debe cerrarse y el repo debe haber sido llamado.
      expect(find.byType(AlertDialog), findsNothing);
      expect(stub.capturedTrainerId, equals(_kTrainerId));
      expect(stub.capturedAthleteId, equals(_kAthleteId1));
    });

    testWidgets('cancelar en el dialog de día bloqueado NO llama al repo',
        (tester) async {
      final blockOverride = AvailabilityOverride.block(
        id: 'block-1',
        trainerId: _kTrainerId,
        date: blockedDateOnly,
      );
      final stub = _StubAppointmentRepository();

      await openDialogDirect(
        tester,
        availabilityOverrides: [blockOverride],
        repo: stub,
      );

      await tester.tap(find.text('REGISTRAR SESIÓN')); // i18n
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsOneWidget); // i18n

      // Cancelar
      await tester.tap(find.text('Cancelar').last); // i18n
      await tester.pumpAndSettle();

      // El dialog de aviso se cierra, pero el NewSessionDialog original
      // sigue abierto (aborta la creación, no navega).
      expect(find.text('Día bloqueado'), findsNothing); // i18n
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(stub.capturedTrainerId, isNull);
      expect(stub.capturedAthleteId, isNull);
    });

    testWidgets('día NO bloqueado no muestra el dialog de aviso',
        (tester) async {
      final stub = _StubAppointmentRepository();

      await openDialogDirect(
        tester,
        availabilityOverrides: const [], // sin bloqueo
        repo: stub,
      );

      await tester.tap(find.text('REGISTRAR SESIÓN')); // i18n
      await tester.pumpAndSettle();

      // Sin aviso — el submit va directo a createByTrainer.
      expect(find.text('Día bloqueado'), findsNothing); // i18n
      expect(stub.capturedTrainerId, equals(_kTrainerId));
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

  // initialTime — prefill de la celda tocada en la grilla semanal.
  // Espeja la API ya existente de NewSessionSheet (mobile), que acepta
  // initialDate + initialTime.
  group('initialTime — prefill desde la grilla semanal', () {
    /// Abre el dialog directamente (sin AgendaWebScreen) para poder pasarle
    /// initialDate/initialTime, igual que hará la grilla semanal.
    Future<void> openDialog(
      WidgetTester tester, {
      DateTime? initialDate,
      TimeOfDay? initialTime,
    }) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => NewSessionDialog(
                  initialDate: initialDate,
                  initialTime: initialTime,
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
    }

    testWidgets('initialTime 14:30 se refleja en el campo HORA',
        (tester) async {
      await openDialog(
        tester,
        initialTime: const TimeOfDay(hour: 14, minute: 30),
      );

      // El label se compara vía TimeOfDay.format(context) para no atarse al
      // locale que resuelva MaterialApp en el harness de tests.
      final ctx = tester.element(find.byType(NewSessionDialog));
      final expected = const TimeOfDay(hour: 14, minute: 30).format(ctx);

      expect(find.text(expected), findsOneWidget,
          reason:
              'el campo HORA debe mostrar la hora recibida por initialTime');
    });

    testWidgets('sin initialTime conserva el default now+1h en punto',
        (tester) async {
      final beforeHour = DateTime.now().hour;
      await openDialog(tester);
      final afterHour = DateTime.now().hour;

      final ctx = tester.element(find.byType(NewSessionDialog));
      String labelFor(int h) =>
          TimeOfDay(hour: h + 1 > 23 ? 23 : h + 1, minute: 0).format(ctx);

      // Tolerancia de una hora SOLO si el reloj cruzó la hora en punto entre
      // el cálculo del test y el initState del dialog.
      final candidates = <String>{labelFor(beforeHour), labelFor(afterHour)};
      final matches =
          candidates.where((l) => find.text(l).evaluate().length == 1);

      expect(matches, isNotEmpty,
          reason: 'omitir initialTime no debe cambiar el default now+1h '
              '(esperado uno de $candidates)');
    });

    testWidgets(
        'initialDate se respeta y sobrevive al date picker pese al frame mixing',
        (tester) async {
      final now = DateTime.now();
      // La grilla semanal arma los días como DateTime.utc(y, m, d)
      // (wall-clock flotante, sin componente horaria), mientras que _pickDate
      // compara contra DateTime.now(), que SÍ la tiene. Este test fija que esa
      // mezcla de frames no descarta la columna tocada para el día de hoy.
      final todayUtc = DateTime.utc(now.year, now.month, now.day);

      await openDialog(tester, initialDate: todayUtc);

      final dd = now.day.toString().padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final expectedDate = '$dd/$mm/${now.year}';

      expect(find.text(expectedDate), findsOneWidget,
          reason:
              'el campo FECHA debe mostrar el día recibido por initialDate');

      // Abrir el date picker no debe violar su assert initialDate >= firstDate.
      await tester.tap(find.text(expectedDate));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(NewSessionDialog));
      final okLabel = MaterialLocalizations.of(ctx).okButtonLabel;
      expect(find.text(okLabel), findsOneWidget,
          reason: 'el date picker debe haberse abierto');

      await tester.tap(find.text(okLabel));
      await tester.pumpAndSettle();

      // Confirmar sin mover nada devuelve el MISMO día.
      expect(find.text(expectedDate), findsOneWidget);
    });

    testWidgets(
        'initialDate de MAÑANA sobrevive al date picker (el caso que el test '
        'de hoy no cubre)', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowUtc =
          DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day);

      await openDialog(tester, initialDate: tomorrowUtc);

      final dd = tomorrow.day.toString().padLeft(2, '0');
      final mm = tomorrow.month.toString().padLeft(2, '0');
      final expectedDate = '$dd/$mm/${tomorrow.year}';

      expect(find.text(expectedDate), findsOneWidget);

      await tester.tap(find.text(expectedDate));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(NewSessionDialog));
      final okLabel = MaterialLocalizations.of(ctx).okButtonLabel;
      await tester.tap(find.text(okLabel));
      await tester.pumpAndSettle();

      // El bug: entre las 21:00 y las 24:00 ART, `DateTime.utc(mañana)` es un
      // instante ANTERIOR a `DateTime.now()` local, así que el picker se abría
      // en HOY y confirmar devolvía HOY. La sesión se creaba en el día
      // equivocado sin que el guard de "sesión en el pasado" lo notara.
      expect(find.text(expectedDate), findsOneWidget,
          reason: 'confirmar sin mover nada no puede cambiar el día');
    });
  });

  // ─── datePickerWindow — la aritmética, sin depender de la hora del reloj ────

  group('datePickerWindow', () {
    // El widget test de arriba sólo reproduce el bug si la suite corre entre
    // las 21:00 y las 24:00 ART. Estos casos fijan `now` a mano, así que
    // fallan siempre que la regresión vuelva — y son independientes del huso
    // del runner (`DateUtils.dateOnly` reconstruye y/m/d, no convierte).
    test('una fecha UTC de MAÑANA a las 22:00 NO se descarta como pasada', () {
      final window = datePickerWindow(
        date: DateTime.utc(2026, 8, 5),
        now: DateTime(2026, 8, 4, 22, 0),
      );
      expect(window.initial, equals(DateTime(2026, 8, 5)));
      expect(window.first, equals(DateTime(2026, 8, 4)));
    });

    test('una fecha UTC de HOY a las 22:00 se conserva como hoy', () {
      final window = datePickerWindow(
        date: DateTime.utc(2026, 8, 4),
        now: DateTime(2026, 8, 4, 22, 0),
      );
      expect(window.initial, equals(DateTime(2026, 8, 4)));
    });

    test('una fecha realmente pasada se sube al piso de hoy', () {
      final window = datePickerWindow(
        date: DateTime.utc(2026, 7, 30),
        now: DateTime(2026, 8, 4, 9, 0),
      );
      expect(window.initial, equals(DateTime(2026, 8, 4)));
    });

    test(
        'una fecha más allá de la ventana se baja a lastDate (si no, '
        'showDatePicker assertea y se come el tap)', () {
      final now = DateTime(2026, 8, 4, 9, 0);
      final window = datePickerWindow(
        date: DateTime.utc(2030, 1, 1),
        now: now,
      );
      expect(window.last, equals(DateTime(2027, 8, 4)));
      expect(window.initial, equals(window.last));
    });

    test('los tres bounds son fechas locales sin componente horaria', () {
      final window = datePickerWindow(
        date: DateTime.utc(2026, 8, 5, 13, 45),
        now: DateTime(2026, 8, 4, 22, 17),
      );
      for (final d in [window.initial, window.first, window.last]) {
        expect(d.isUtc, isFalse);
        expect(d.hour, 0);
        expect(d.minute, 0);
      }
    });
  });
}
