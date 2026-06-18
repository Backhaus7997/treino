// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/home/application/todays_routine_provider.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
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
      dayNumber: dayNumber,
      weekNumber: weekNumber,
    );

// ─── Test harness ────────────────────────────────────────────────────────────

ProviderContainer _container({
  List<Routine> assigned = const [],
  List<Routine> selfCreated = const [],
  List<Session> sessions = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      currentUidProvider.overrideWith((ref) => 'u1'),
      assignedRoutinesProvider('u1').overrideWith((ref) async => assigned),
      userCreatedRoutinesProvider('u1')
          .overrideWith((ref) => Stream.value(selfCreated)),
      sessionsByUidProvider('u1').overrideWith((ref) async => sessions),
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

    test('no assigned + MULTIPLE self-created → returns null (needs PR#2)',
        () async {
      final self1 = _routine(id: 'self-1');
      final self2 = _routine(id: 'self-2');
      final c = _container(assigned: const [], selfCreated: [self1, self2]);

      final today = await c.read(todaysRoutineProvider.future);
      expect(today, isNull);
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
          _session(
              routineId: 'r1', dayNumber: 4, status: SessionStatus.active),
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
          reason: 'week loops back to 0 after the last week of a periodized plan');
    });
  });
}
