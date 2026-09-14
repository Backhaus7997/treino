// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/home/application/todays_routine_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routinesProvider;
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// ─── Factories ───────────────────────────────────────────────────────────────

RoutineSlot _slot() => const RoutineSlot(
      exerciseId: 'x',
      exerciseName: 'X',
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

RoutineDay _day(int n) =>
    RoutineDay(dayNumber: n, name: 'DÍA $n', slots: [_slot()]);

Routine _routine({
  String id = 'r1',
  int numDays = 5,
  int numWeeks = 1,
  RoutineSource source = RoutineSource.trainerAssigned,
}) =>
    Routine(
      id: id,
      name: 'R',
      level: ExperienceLevel.intermediate,
      days: List.generate(numDays, (i) => _day(i + 1)),
      source: source,
      numWeeks: numWeeks,
    );

Session _session({
  required String routineId,
  required int dayNumber,
  int weekNumber = 0,
  SessionStatus status = SessionStatus.finished,
  bool wasFullyCompleted = true,
  DateTime? startedAt,
}) =>
    Session(
      id: 's-$routineId-$dayNumber-$weekNumber',
      uid: 'u1',
      routineId: routineId,
      routineName: 'R',
      startedAt: startedAt ?? DateTime(2026, 6, 18, 10),
      finishedAt: status == SessionStatus.finished ? startedAt : null,
      status: status,
      wasFullyCompleted: wasFullyCompleted,
      dayNumber: dayNumber,
      weekNumber: weekNumber,
    );

// ─── Test harness ────────────────────────────────────────────────────────────

UserProfile _profile({String? activeRoutineId}) => UserProfile(
      uid: 'u1',
      email: 'u1@treino.app',
      displayName: 'U1',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: activeRoutineId,
    );

/// Keeps the profile stream subscribed and resolved BEFORE reading the
/// provider — Tier 0 reads `activeRoutineId` via a synchronous select, so
/// tests that rely on the marker must warm it up deterministically (mirrors
/// app runtime, where the profile loads long before the home card).
Future<void> _warmProfile(ProviderContainer c) async {
  c.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, __) {});
  await c.read(userProfileProvider.future);
}

ProviderContainer _container({
  List<Routine> assigned = const [],
  List<Routine> selfCreated = const [],
  List<Session> sessions = const [],
  String? activeRoutineId,
}) {
  final c = ProviderContainer(
    overrides: [
      currentUidProvider.overrideWith((ref) => 'u1'),
      assignedRoutinesProvider('u1').overrideWith((ref) async => assigned),
      userCreatedRoutinesProvider('u1')
          .overrideWith((ref) => Stream.value(selfCreated)),
      sessionsByUidProvider('u1').overrideWith((ref) async => sessions),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(_profile(activeRoutineId: activeRoutineId)),
      ),
      // Obligatorio desde "seguir sin copiar": con un marcador que no matchea
      // contra los planes, el provider resuelve el catálogo del sistema para
      // ver si el atleta está SIGUIENDO una plantilla. Sin este override esos
      // casos pegan contra Firestore de verdad y explotan.
      //
      // Vacío a propósito: los escenarios de este archivo son de planes, no de
      // catálogo. Los de catálogo viven en todays_routine_catalog_test.dart.
      routinesProvider.overrideWith((ref) async => const <Routine>[]),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('todaysRoutineProvider — priority', () {
    test('trainer-assigned plan wins over self-created routines', () async {
      final assigned = _routine(id: 'assigned-1');
      final self = _routine(id: 'self-1');
      final c = _container(assigned: [assigned], selfCreated: [self]);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNotNull);
      expect(today!.routine.id, equals('assigned-1'));
    });

    test('no assigned + single self-created → uses self-created', () async {
      final self = _routine(id: 'self-1');
      final c = _container(assigned: const [], selfCreated: [self]);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNotNull);
      expect(today!.routine.id, equals('self-1'));
    });

    test(
        'no assigned + MULTIPLE self-created + NO activeRoutineId → null '
        '(athlete needs to mark one as active)', () async {
      final self1 = _routine(id: 'self-1');
      final self2 = _routine(id: 'self-2');
      final c = _container(assigned: const [], selfCreated: [self1, self2]);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNull);
    });

    test(
        'no assigned + MULTIPLE self-created + activeRoutineId set → '
        'returns the active routine', () async {
      final self1 = _routine(id: 'self-1');
      final self2 = _routine(id: 'self-2');
      final c = _container(
        assigned: const [],
        selfCreated: [self1, self2],
        activeRoutineId: 'self-2',
      );

      // Pre-warm dependent autoDispose streams so activeRoutineProvider can
      // resolve when todaysRoutineProvider invokes ref.watch on it.
      c.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, __) {});
      c.listen<AsyncValue<List<Routine>>>(
          userCreatedRoutinesProvider('u1'), (_, __) {});
      await c.read(userProfileProvider.future);
      await c.read(userCreatedRoutinesProvider('u1').future);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNotNull);
      expect(today!.routine.id, equals('self-2'));
    });

    test(
        'multi self-created + activeRoutineId points to non-existent id → null '
        '(stale pointer, e.g. routine archived after being marked active)',
        () async {
      final self1 = _routine(id: 'self-1');
      final self2 = _routine(id: 'self-2');
      final c = _container(
        assigned: const [],
        selfCreated: [self1, self2],
        activeRoutineId: 'archived-routine-id',
      );

      c.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, __) {});
      c.listen<AsyncValue<List<Routine>>>(
          userCreatedRoutinesProvider('u1'), (_, __) {});
      await c.read(userProfileProvider.future);
      await c.read(userCreatedRoutinesProvider('u1').future);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNull);
    });

    // ── Tier 0 (workout redesign slice 1): explicit active marker wins ────
    // The unified list lets the athlete mark ANY routine active — coach
    // plans included — and the home card follows that choice.

    test(
        'Tier 0: trainer-assigned PRESENT + activeRoutineId on a self-created '
        'routine → the ACTIVE routine wins (marker beats the coach plan)',
        () async {
      final assigned = _routine(id: 'assigned-1');
      final self1 = _routine(id: 'self-1');
      final self2 = _routine(id: 'self-2');
      final c = _container(
        assigned: [assigned],
        selfCreated: [self1, self2],
        activeRoutineId: 'self-2',
      );
      await _warmProfile(c);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.routine.id, equals('self-2'),
          reason: 'slice 1: the explicit active marker drives the home card '
              'across the UNIFIED list — the coach plan no longer overrides '
              'the athlete\'s choice');
    });

    test(
        'Tier 0: activeRoutineId pointing at the trainer-assigned plan '
        'resolves it (coach plans are activatable)', () async {
      final assigned1 = _routine(id: 'assigned-1');
      final assigned2 = _routine(id: 'assigned-2');
      final self = _routine(id: 'self-1');
      final c = _container(
        assigned: [assigned1, assigned2],
        selfCreated: [self],
        activeRoutineId: 'assigned-2',
      );
      await _warmProfile(c);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.routine.id, equals('assigned-2'),
          reason: 'the marker can select an OLDER coach plan over the '
              'newest one — user choice beats recency');
    });

    test(
        'Tier 0 stale: activeRoutineId not in any list + assigned present → '
        'falls back to the legacy chain (assigned.first)', () async {
      final assigned = _routine(id: 'assigned-1');
      final self = _routine(id: 'self-1');
      final c = _container(
        assigned: [assigned],
        selfCreated: [self],
        activeRoutineId: 'archived-id',
      );
      await _warmProfile(c);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.routine.id, equals('assigned-1'),
          reason: 'a stale marker must not blank the card when the legacy '
              'chain can still resolve a routine');
    });

    test(
        'single self-created + activeRoutineId set elsewhere → '
        'still uses the single routine (auto-active wins)', () async {
      final self = _routine(id: 'self-only');
      final c = _container(
        assigned: const [],
        selfCreated: [self],
        activeRoutineId: 'something-else',
      );
      await _warmProfile(c);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.routine.id, equals('self-only'),
          reason: 'with a single routine the marker is irrelevant — '
              'tier 2 auto-activates before tier 3 runs');
    });

    test('empty uid → null (unauthenticated state)', () async {
      final c = ProviderContainer(
        overrides: [
          currentUidProvider.overrideWith((ref) => ''),
        ],
      );
      addTearDown(c.dispose);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNull);
    });

    test('routine with empty days → null (defensive)', () async {
      const empty = Routine(
        id: 'empty',
        name: 'E',
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.trainerAssigned,
      );
      final c = _container(assigned: [empty]);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNull);
    });
  });

  group('todaysRoutineProvider — day calculation (progress-based)', () {
    test('no prior session → Día 1, semana 0', () async {
      final r = _routine(numDays: 5);
      final c = _container(assigned: [r]);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(1));
      expect(today.weekNumber, equals(0));
      expect(today.day.dayNumber, equals(1));
    });

    test('last finished Día 3 of 5 → next is Día 4, same week', () async {
      final r = _routine(id: 'r1', numDays: 5);
      final c = _container(
        assigned: [r],
        sessions: [_session(routineId: 'r1', dayNumber: 3)],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(4));
      expect(today.weekNumber, equals(0));
    });

    test('last finished Día 5 of 5 → loops to Día 1', () async {
      final r = _routine(id: 'r1', numDays: 5);
      final c = _container(
        assigned: [r],
        sessions: [_session(routineId: 'r1', dayNumber: 5)],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(1));
      // numWeeks == 1 → week stays at 0 even on rollover.
      expect(today.weekNumber, equals(0));
    });

    test('skipped Día 2 → after Día 3, next is Día 4 (not the skipped Día 2)',
        () async {
      final r = _routine(id: 'r1', numDays: 5);
      final c = _container(
        assigned: [r],
        sessions: [
          // Most recent FINISHED is Día 3; Día 2 was never logged.
          _session(
              routineId: 'r1',
              dayNumber: 3,
              startedAt: DateTime(2026, 6, 18, 10)),
          _session(
              routineId: 'r1',
              dayNumber: 1,
              startedAt: DateTime(2026, 6, 16, 10)),
        ],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(4),
          reason: 'skipped days do not "come back" — progress always +1');
    });

    test('ignores sessions from OTHER routines', () async {
      final r = _routine(id: 'r1', numDays: 5);
      final c = _container(
        assigned: [r],
        sessions: [
          _session(routineId: 'other-routine', dayNumber: 4),
        ],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(1),
          reason: 'sessions for other routines must not influence next-day');
    });

    test('ignores ACTIVE (unfinished) sessions', () async {
      final r = _routine(id: 'r1', numDays: 5);
      final c = _container(
        assigned: [r],
        sessions: [
          _session(routineId: 'r1', dayNumber: 4, status: SessionStatus.active),
        ],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(1),
          reason: 'an open session is not "completed", does not advance');
    });
  });

  group('todaysRoutineProvider — periodization (numWeeks > 1)', () {
    test('Día N within the same week → week stays', () async {
      final r = _routine(id: 'r1', numDays: 5, numWeeks: 4);
      final c = _container(
        assigned: [r],
        sessions: [_session(routineId: 'r1', dayNumber: 3, weekNumber: 2)],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(4));
      expect(today.weekNumber, equals(2));
    });

    test('day rollover at end of week → week advances', () async {
      final r = _routine(id: 'r1', numDays: 5, numWeeks: 4);
      final c = _container(
        assigned: [r],
        sessions: [_session(routineId: 'r1', dayNumber: 5, weekNumber: 2)],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(1));
      expect(today.weekNumber, equals(3));
    });

    test('rollover at end of plan → both day AND week loop', () async {
      final r = _routine(id: 'r1', numDays: 5, numWeeks: 4);
      final c = _container(
        assigned: [r],
        sessions: [_session(routineId: 'r1', dayNumber: 5, weekNumber: 3)],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today!.dayNumber, equals(1));
      expect(today.weekNumber, equals(0),
          reason:
              'week loops back to 0 after the last week of a periodized plan');
    });
  });

  // A corrupt/legacy Firestore doc can carry an EXPLICIT `numWeeks: 0` — the
  // `?? 1` in the generated fromJson only covers an ABSENT field, so 0 reaches
  // the provider intact and `% 0` throws IntegerDivisionByZeroException.
  // Same criterion as derivePlanProgress and SessionNotifier._buildFresh.
  group('todaysRoutineProvider — corrupt numWeeks (<= 0)', () {
    test('numWeeks == 0 + day rollover → no crash, behaves like numWeeks == 1',
        () async {
      final r = _routine(id: 'r1', numDays: 5, numWeeks: 0);
      final c = _container(
        assigned: [r],
        sessions: [_session(routineId: 'r1', dayNumber: 5, weekNumber: 2)],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNotNull,
          reason: 'a corrupt numWeeks must not blow up the home card — '
              'the athlete keeps the "empezar en 1 tap" affordance');
      expect(today!.dayNumber, equals(1));
      expect(today.weekNumber, equals(0),
          reason: 'numWeeks <= 0 is normalized to 1, so the week loops to 0');
    });

    test('numWeeks == 0 without rollover → next day, week untouched', () async {
      final r = _routine(id: 'r1', numDays: 5, numWeeks: 0);
      final c = _container(
        assigned: [r],
        sessions: [_session(routineId: 'r1', dayNumber: 3, weekNumber: 2)],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNotNull);
      expect(today!.dayNumber, equals(4));
      expect(today.weekNumber, equals(2),
          reason: 'the guard only normalizes the modulo divisor — it must not '
              'reach into the non-rollover path');
    });

    test('negative numWeeks → no crash, week loops to 0 on rollover', () async {
      final r = _routine(id: 'r1', numDays: 5, numWeeks: -3);
      final c = _container(
        assigned: [r],
        sessions: [_session(routineId: 'r1', dayNumber: 5, weekNumber: 1)],
      );

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNotNull);
      expect(today!.dayNumber, equals(1));
      expect(today.weekNumber, equals(0));
    });
  });
}
