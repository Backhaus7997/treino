// Blocked-day soft warning tests for NewSessionSheet (mobile).
//
// Mirrors the fake/override idiom used by
// test/features/coach_hub/presentation/sections/agenda/new_session_dialog_test.dart
// (web sibling of this sheet) for AvailabilityRepository, and the mocktail
// Mock idiom from test/features/coach_hub/pagos/widgets/marcar_pagado_test.dart
// for AppointmentRepository.
//
// Covers:
//  1. Single, blocked day → confirm dialog; confirm → createByTrainer called;
//     cancel → NOT called.
//  2. Single, non-blocked day → no dialog, createByTrainer called directly.
//  3. Recurring with some blocked dates → warning dialog with right count;
//     confirm → createRecurringByTrainer called with the FULL set (blocked
//     dates not skipped); cancel → not called.
//  4. Fail-open (regression test for the try/catch guards in
//     new_session_sheet.dart's _isDateBlocked / _blockedDatesAmongCandidates):
//     watchOverrides errors → creation still proceeds WITHOUT the warning
//     dialog. This test MUST fail if either try/catch is removed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/widgets/new_session_sheet.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-nss';
const _kAthleteId1 = 'athlete-uid-nss1';

// ─── Mocks / Fakes ───────────────────────────────────────────────────────────

/// Mocktail mock for [AppointmentRepository] — asserts createByTrainer /
/// createRecurringByTrainer calls. Mirrors _MockPaymentRepo in
/// marcar_pagado_test.dart.
class _MockAppointmentRepository extends Mock
    implements AppointmentRepository {}

/// Fake [AvailabilityRepository] that returns a fixed [overrides] list for
/// any [watchOverrides] call, or — when [shouldThrow] is set — a stream that
/// errors instead. Mirrors _FakeAvailabilityRepository in
/// new_session_dialog_test.dart (web sibling).
class _FakeAvailabilityRepository extends Fake
    implements AvailabilityRepository {
  _FakeAvailabilityRepository({
    this.overrides = const [],
    this.shouldThrow = false,
  });

  final List<AvailabilityOverride> overrides;
  final bool shouldThrow;

  @override
  Stream<List<AvailabilityOverride>> watchOverrides(
    String trainerId,
    DateTime fromDate,
    DateTime toDate,
  ) {
    if (shouldThrow) {
      return Stream.error(Exception('permission-denied'));
    }
    return Stream.value(overrides);
  }
}

/// Availability repo whose `watchOverrides` stays PENDING until [gate]
/// completes. Lets a test hold the submit inside the blocked-day async read —
/// the window that M7 left unguarded — while it fires a second tap.
class _GatedAvailabilityRepository extends Fake
    implements AvailabilityRepository {
  _GatedAvailabilityRepository({required this.gate});

  final Completer<void> gate;

  @override
  Stream<List<AvailabilityOverride>> watchOverrides(
    String trainerId,
    DateTime fromDate,
    DateTime toDate,
  ) {
    return Stream.fromFuture(
      gate.future.then((_) => const <AvailabilityOverride>[]),
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

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

Appointment _fakeAppointment({
  required String trainerId,
  required String athleteId,
  required String athleteDisplayName,
  required DateTime startsAt,
  required int durationMin,
}) =>
    Appointment(
      id: 'new-appt',
      trainerId: trainerId,
      athleteId: athleteId,
      athleteDisplayName: athleteDisplayName,
      startsAt: startsAt,
      durationMin: durationMin,
      status: AppointmentStatus.confirmed,
    );

// ─── Test wrap helper ─────────────────────────────────────────────────────────

/// Wraps [NewSessionSheet] in ProviderScope + MaterialApp, mirroring the
/// l10n + theme setup used by marcar_pagado_test.dart and the web dialog test.
Widget _wrap({
  DateTime? initialDate,
  required List<Override> overrides,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: NewSessionSheet(initialDate: initialDate),
        ),
      ),
    );

/// Sizes the test viewport tall enough that the whole scrollable sheet
/// (including the bottom submit button) is laid out on-screen, so taps hit.
/// Mirrors the payment/filter-sheet tests' `physicalSize` idiom.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<Override> _overrides({
  List<TrainerLink> links = const [],
  Map<String, UserPublicProfile> profiles = const {},
  _MockAppointmentRepository? appointmentRepo,
  AvailabilityRepository? availabilityRepo,
}) {
  return [
    currentUidProvider.overrideWithValue(_kTrainerId),
    trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
    if (appointmentRepo != null)
      appointmentRepositoryProvider.overrideWithValue(appointmentRepo),
    availabilityRepositoryProvider.overrideWithValue(
      availabilityRepo ?? _FakeAvailabilityRepository(),
    ),
    for (final entry in profiles.entries)
      userPublicProfileProvider(entry.key).overrideWith(
        (ref) => Stream.value(entry.value),
      ),
  ];
}

/// Selects the (only) active athlete in the dropdown. The sheet requires an
/// athlete before the submit button becomes enabled.
Future<void> _selectAthlete(WidgetTester tester, String displayName) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(displayName).last);
  await tester.pumpAndSettle();
}

void main() {
  // A fixed future date so the past-date guard in _submitSingle /
  // _submitRecurring never interferes, regardless of when the suite runs.
  final targetDate = DateTime.now().add(const Duration(days: 10));
  final targetDateOnly =
      DateTime(targetDate.year, targetDate.month, targetDate.day);

  late _MockAppointmentRepository mockAppointmentRepo;

  setUpAll(() {
    registerFallbackValue(DateTime.utc(2026, 1, 1));
    registerFallbackValue(<int>{});
  });

  setUp(() {
    mockAppointmentRepo = _MockAppointmentRepository();
    when(
      () => mockAppointmentRepo.createByTrainer(
        trainerId: any(named: 'trainerId'),
        athleteId: any(named: 'athleteId'),
        athleteDisplayName: any(named: 'athleteDisplayName'),
        startsAt: any(named: 'startsAt'),
        durationMin: any(named: 'durationMin'),
        noteBefore: any(named: 'noteBefore'),
      ),
    ).thenAnswer((invocation) async => _fakeAppointment(
          trainerId: invocation.namedArguments[#trainerId] as String,
          athleteId: invocation.namedArguments[#athleteId] as String,
          athleteDisplayName:
              invocation.namedArguments[#athleteDisplayName] as String,
          startsAt: invocation.namedArguments[#startsAt] as DateTime,
          durationMin: invocation.namedArguments[#durationMin] as int,
        ));
    when(
      () => mockAppointmentRepo.createRecurringByTrainer(
        trainerId: any(named: 'trainerId'),
        athleteId: any(named: 'athleteId'),
        athleteDisplayName: any(named: 'athleteDisplayName'),
        weekdays: any(named: 'weekdays'),
        startHour: any(named: 'startHour'),
        startMinute: any(named: 'startMinute'),
        durationMin: any(named: 'durationMin'),
        fromDate: any(named: 'fromDate'),
        untilDate: any(named: 'untilDate'),
        noteBefore: any(named: 'noteBefore'),
      ),
    ).thenAnswer((_) async => 1);
  });

  // ── SCENARIO 1: single, blocked day ─────────────────────────────────────
  group('Single — día bloqueado', () {
    testWidgets(
        'muestra el dialog "Día bloqueado"; confirmar llama '
        'createByTrainer', (tester) async {
      _useTallViewport(tester);
      final blockOverride = AvailabilityOverride.block(
        id: 'block-1',
        trainerId: _kTrainerId,
        date: targetDateOnly,
      );

      await tester.pumpWidget(_wrap(
        initialDate: targetDateOnly,
        overrides: _overrides(
          links: [_activeLink(_kAthleteId1)],
          profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
          appointmentRepo: mockAppointmentRepo,
          availabilityRepo:
              _FakeAvailabilityRepository(overrides: [blockOverride]),
        ),
      ));
      await tester.pumpAndSettle();

      await _selectAthlete(tester, 'Carlos Pérez');

      await tester.tap(find.text('REGISTRAR SESIÓN'));
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsOneWidget);
      expect(
        find.textContaining('marcado como bloqueado'),
        findsOneWidget,
      );

      // Confirm "Cargar igual" → proceeds to createByTrainer.
      await tester.tap(find.text('Cargar igual'));
      await tester.pumpAndSettle();

      verify(
        () => mockAppointmentRepo.createByTrainer(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId1,
          athleteDisplayName: 'Carlos Pérez',
          startsAt: any(named: 'startsAt'),
          durationMin: any(named: 'durationMin'),
          noteBefore: any(named: 'noteBefore'),
        ),
      ).called(1);
    });

    testWidgets('cancelar en el dialog NO llama a createByTrainer',
        (tester) async {
      _useTallViewport(tester);
      final blockOverride = AvailabilityOverride.block(
        id: 'block-1',
        trainerId: _kTrainerId,
        date: targetDateOnly,
      );

      await tester.pumpWidget(_wrap(
        initialDate: targetDateOnly,
        overrides: _overrides(
          links: [_activeLink(_kAthleteId1)],
          profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
          appointmentRepo: mockAppointmentRepo,
          availabilityRepo:
              _FakeAvailabilityRepository(overrides: [blockOverride]),
        ),
      ));
      await tester.pumpAndSettle();

      await _selectAthlete(tester, 'Carlos Pérez');

      await tester.tap(find.text('REGISTRAR SESIÓN'));
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsOneWidget);

      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsNothing);
      verifyNever(
        () => mockAppointmentRepo.createByTrainer(
          trainerId: any(named: 'trainerId'),
          athleteId: any(named: 'athleteId'),
          athleteDisplayName: any(named: 'athleteDisplayName'),
          startsAt: any(named: 'startsAt'),
          durationMin: any(named: 'durationMin'),
          noteBefore: any(named: 'noteBefore'),
        ),
      );
    });
  });

  // ── SCENARIO 2: single, non-blocked day ─────────────────────────────────
  group('Single — día NO bloqueado', () {
    testWidgets('no muestra dialog; createByTrainer se llama directo',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrap(
        initialDate: targetDateOnly,
        overrides: _overrides(
          links: [_activeLink(_kAthleteId1)],
          profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
          appointmentRepo: mockAppointmentRepo,
          availabilityRepo: _FakeAvailabilityRepository(overrides: const []),
        ),
      ));
      await tester.pumpAndSettle();

      await _selectAthlete(tester, 'Carlos Pérez');

      await tester.tap(find.text('REGISTRAR SESIÓN'));
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsNothing);
      verify(
        () => mockAppointmentRepo.createByTrainer(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId1,
          athleteDisplayName: 'Carlos Pérez',
          startsAt: any(named: 'startsAt'),
          durationMin: any(named: 'durationMin'),
          noteBefore: any(named: 'noteBefore'),
        ),
      ).called(1);
    });
  });

  // ── SCENARIO 4: fail-open regression test ───────────────────────────────
  //
  // This is the regression test for Fix 1 (the try/catch guards added to
  // _isDateBlocked / _blockedDatesAmongCandidates in new_session_sheet.dart).
  // Without the try/catch, watchOverrides' error propagates out of the
  // async onPressed handler uncaught — the tap silently does nothing (no
  // dialog, no repo call, no snackbar). Verified manually: temporarily
  // removing the try/catch from _isDateBlocked makes this test fail with
  // "createByTrainer was not called" (see report).
  group('Fail-open — watchOverrides lanza error', () {
    testWidgets(
        'single: creación procede SIN el dialog de aviso cuando el repo '
        'de disponibilidad falla', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrap(
        initialDate: targetDateOnly,
        overrides: _overrides(
          links: [_activeLink(_kAthleteId1)],
          profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
          appointmentRepo: mockAppointmentRepo,
          availabilityRepo: _FakeAvailabilityRepository(shouldThrow: true),
        ),
      ));
      await tester.pumpAndSettle();

      await _selectAthlete(tester, 'Carlos Pérez');

      await tester.tap(find.text('REGISTRAR SESIÓN'));
      await tester.pumpAndSettle();

      // No blocked-day warning — the check degraded to "not blocked".
      expect(find.text('Día bloqueado'), findsNothing);

      // Creation still proceeded.
      verify(
        () => mockAppointmentRepo.createByTrainer(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId1,
          athleteDisplayName: 'Carlos Pérez',
          startsAt: any(named: 'startsAt'),
          durationMin: any(named: 'durationMin'),
          noteBefore: any(named: 'noteBefore'),
        ),
      ).called(1);
    });
  });

  // ── SCENARIO 3: recurring with some blocked dates ───────────────────────
  //
  // Toggle "Se repite", pick a single weekday, and block the FIRST future
  // occurrence of that weekday within the default 4-week window. The recurring
  // warning must show the blocked count (1), and confirming must call
  // createRecurringByTrainer with the FULL weekday set (blocked dates are NOT
  // skipped — the trainer decides).
  group('Recurring — fechas bloqueadas', () {
    // Pick a weekday whose chip label is UNIQUE (L/J/V/S/D — the two "M"s,
    // weekdays 2 and 3, are ambiguous by text finder), and whose first future
    // occurrence lands strictly after today (so the default 09:00 time can't
    // filter it out as "past"). Any of these hits within 7 days.
    ({int weekday, String label, DateTime firstOccurrence}) pickWeekday() {
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      const candidates = [
        (weekday: 4, label: 'J'),
        (weekday: 5, label: 'V'),
        (weekday: 6, label: 'S'),
        (weekday: 7, label: 'D'),
        (weekday: 1, label: 'L'),
      ];
      for (final c in candidates) {
        // First occurrence strictly after today.
        var d = todayOnly.add(const Duration(days: 1));
        for (var i = 0; i < 7; i++) {
          if (d.weekday == c.weekday) break;
          d = d.add(const Duration(days: 1));
        }
        return (weekday: c.weekday, label: c.label, firstOccurrence: d);
      }
      throw StateError('unreachable');
    }

    Future<void> setUpRecurring(
      WidgetTester tester, {
      required _FakeAvailabilityRepository availabilityRepo,
      required String weekdayLabel,
    }) async {
      await tester.pumpWidget(_wrap(
        overrides: _overrides(
          links: [_activeLink(_kAthleteId1)],
          profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
          appointmentRepo: mockAppointmentRepo,
          availabilityRepo: availabilityRepo,
        ),
      ));
      await tester.pumpAndSettle();

      // Switch to recurring mode.
      await tester.tap(find.text('Se repite'));
      await tester.pumpAndSettle();

      await _selectAthlete(tester, 'Carlos Pérez');

      // Select the (unique-label) weekday chip.
      await tester.tap(find.text(weekdayLabel));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'muestra el aviso con el conteo y confirmar llama '
        'createRecurringByTrainer con TODAS las fechas', (tester) async {
      _useTallViewport(tester);
      final picked = pickWeekday();
      final blockOverride = AvailabilityOverride.block(
        id: 'block-rec-1',
        trainerId: _kTrainerId,
        date: picked.firstOccurrence,
      );

      await setUpRecurring(
        tester,
        availabilityRepo:
            _FakeAvailabilityRepository(overrides: [blockOverride]),
        weekdayLabel: picked.label,
      );

      await tester.tap(find.text('REGISTRAR SERIE'));
      await tester.pumpAndSettle();

      // Recurring warning dialog with the blocked count (exactly 1 blocked
      // occurrence — only the first occurrence of the chosen weekday is
      // blocked).
      expect(find.text('Día bloqueado'), findsOneWidget);
      expect(find.textContaining('1 de las fechas'), findsOneWidget);

      await tester.tap(find.text('Cargar igual'));
      await tester.pumpAndSettle();

      // createRecurringByTrainer called with the FULL selected weekday set —
      // blocked dates are not removed from the request.
      final captured = verify(
        () => mockAppointmentRepo.createRecurringByTrainer(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId1,
          athleteDisplayName: 'Carlos Pérez',
          weekdays: captureAny(named: 'weekdays'),
          startHour: any(named: 'startHour'),
          startMinute: any(named: 'startMinute'),
          durationMin: any(named: 'durationMin'),
          fromDate: any(named: 'fromDate'),
          untilDate: any(named: 'untilDate'),
          noteBefore: any(named: 'noteBefore'),
        ),
      ).captured;
      expect(captured.single, equals({picked.weekday}));
    });

    testWidgets('cancelar en el aviso NO llama a createRecurringByTrainer',
        (tester) async {
      _useTallViewport(tester);
      final picked = pickWeekday();
      final blockOverride = AvailabilityOverride.block(
        id: 'block-rec-1',
        trainerId: _kTrainerId,
        date: picked.firstOccurrence,
      );

      await setUpRecurring(
        tester,
        availabilityRepo:
            _FakeAvailabilityRepository(overrides: [blockOverride]),
        weekdayLabel: picked.label,
      );

      await tester.tap(find.text('REGISTRAR SERIE'));
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsOneWidget);

      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();

      expect(find.text('Día bloqueado'), findsNothing);
      verifyNever(
        () => mockAppointmentRepo.createRecurringByTrainer(
          trainerId: any(named: 'trainerId'),
          athleteId: any(named: 'athleteId'),
          athleteDisplayName: any(named: 'athleteDisplayName'),
          weekdays: any(named: 'weekdays'),
          startHour: any(named: 'startHour'),
          startMinute: any(named: 'startMinute'),
          durationMin: any(named: 'durationMin'),
          fromDate: any(named: 'fromDate'),
          untilDate: any(named: 'untilDate'),
          noteBefore: any(named: 'noteBefore'),
        ),
      );
    });

    testWidgets(
        'fail-open: si watchOverrides falla, la serie se crea SIN aviso',
        (tester) async {
      _useTallViewport(tester);
      final picked = pickWeekday();

      // Throwing availability repo from the start — the recurring blocked-dates
      // check (_blockedDatesAmongCandidates) must fail-open to "none blocked".
      await setUpRecurring(
        tester,
        availabilityRepo: _FakeAvailabilityRepository(shouldThrow: true),
        weekdayLabel: picked.label,
      );

      await tester.tap(find.text('REGISTRAR SERIE'));
      await tester.pumpAndSettle();

      // No warning — the blocked-dates check degraded to "none blocked".
      expect(find.text('Día bloqueado'), findsNothing);
      verify(
        () => mockAppointmentRepo.createRecurringByTrainer(
          trainerId: _kTrainerId,
          athleteId: _kAthleteId1,
          athleteDisplayName: 'Carlos Pérez',
          weekdays: any(named: 'weekdays'),
          startHour: any(named: 'startHour'),
          startMinute: any(named: 'startMinute'),
          durationMin: any(named: 'durationMin'),
          fromDate: any(named: 'fromDate'),
          untilDate: any(named: 'untilDate'),
          noteBefore: any(named: 'noteBefore'),
        ),
      ).called(1);
    });
  });

  // ── M7: doble tap no duplica ─────────────────────────────────────────────
  //
  // #607 insertó el chequeo async de días bloqueados ARRIBA del
  // `setState(_saving=true)`, dejando una ventana en la que un segundo tap
  // corría el submit de nuevo → sesión/serie duplicada en Firestore. El fake
  // gateado sostiene el submit dentro de esa ventana mientras se dispara el
  // segundo tap.
  group('Doble tap (M7)', () {
    testWidgets('single: dos taps rápidos crean la sesión UNA sola vez',
        (tester) async {
      _useTallViewport(tester);
      final gate = Completer<void>();

      await tester.pumpWidget(_wrap(
        initialDate: targetDateOnly,
        overrides: _overrides(
          links: [_activeLink(_kAthleteId1)],
          profiles: {_kAthleteId1: _pub(_kAthleteId1, 'Carlos Pérez')},
          appointmentRepo: mockAppointmentRepo,
          availabilityRepo: _GatedAvailabilityRepository(gate: gate),
        ),
      ));
      await tester.pumpAndSettle();
      await _selectAthlete(tester, 'Carlos Pérez');

      // Tap 1: entra a _submitSingle, setea _saving=true y queda esperando el
      // chequeo de días bloqueados (gateado).
      await tester.tap(find.text('REGISTRAR SESIÓN'));
      await tester.pump();
      // Tap 2 en la ventana que M7 dejaba sin proteger.
      await tester.tap(find.text('REGISTRAR SESIÓN'), warnIfMissed: false);
      await tester.pump();

      // Liberar el gate → el único submit vivo continúa hasta createByTrainer.
      gate.complete();
      await tester.pumpAndSettle();

      verify(
        () => mockAppointmentRepo.createByTrainer(
          trainerId: any(named: 'trainerId'),
          athleteId: any(named: 'athleteId'),
          athleteDisplayName: any(named: 'athleteDisplayName'),
          startsAt: any(named: 'startsAt'),
          durationMin: any(named: 'durationMin'),
          noteBefore: any(named: 'noteBefore'),
        ),
      ).called(1);
    });
  });
}
