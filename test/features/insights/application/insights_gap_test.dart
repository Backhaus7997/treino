import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

Exercise _ex({
  required String id,
  required String muscleGroup,
  String name = 'Exercise',
}) =>
    Exercise(
      id: id,
      name: name,
      muscleGroup: muscleGroup,
      category: 'compound',
    );

// Mirrors `_mondayOfWeek` inside insights_providers.dart. The provider reads
// DateTime.now() directly (no clock injection — see SCENARIO-401 note), so all
// week-relative seed data MUST be built relative to now() exactly as the
// provider computes it.
DateTime _mondayOfThisWeek() {
  final now = DateTime.now().toLocal();
  return DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - DateTime.monday));
}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  group('weeklyInsightsProvider — GAP coverage', () {
    // insights-20 (P0, logic): the week window is [Mon 00:00, next-Mon 00:00).
    // weekStart is inclusive, weekEndExclusive is exclusive, and anything
    // before weekStart (even by 1ms) is out. Regression-prone date math.
    test(
        'insights-20: buckets sessions strictly inside [Mon 00:00, next-Mon 00:00)',
        () async {
      final repo = MockSessionRepository();
      final monday = _mondayOfThisWeek();
      // Inside: exactly Monday 00:00 and Sunday 23:59:59.999.
      final atWeekStart = monday;
      final atWeekEndBoundary =
          monday.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      // Outside: 1ms before weekStart, and next Monday 00:00 (exclusive end).
      final justBeforeStart = monday.subtract(const Duration(milliseconds: 1));
      final nextMonday = monday.add(const Duration(days: 7));

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's-start',
              startedAt: atWeekStart,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
            makeSession(
              id: 's-end',
              startedAt: atWeekEndBoundary,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
            makeSession(
              id: 's-before',
              startedAt: justBeforeStart,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
            makeSession(
              id: 's-next',
              startedAt: nextMonday,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
          ]);
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => const <SetLog>[]);

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
        routineByIdProvider('r1').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      // Only the Monday-00:00 and the Sunday-23:59 sessions are inside.
      expect(result!.sessionsCount, 2);
      // daysTrained: index 0 = Monday, index 6 = Sunday.
      expect(result.daysTrained[0], isTrue);
      expect(result.daysTrained[6], isTrue);
      for (var i = 1; i < 6; i++) {
        expect(result.daysTrained[i], isFalse);
      }
      // The out-of-window sessions must NOT trigger setLog reads.
      verifyNever(() => repo.listSetLogs(uid: 'u1', sessionId: 's-before'));
      verifyNever(() => repo.listSetLogs(uid: 'u1', sessionId: 's-next'));
    });

    // insights-22 (P1, logic): every SetLog row counts as exactly one set.
    // setNumber is metadata, never a dedupe key or a weight.
    test('insights-22: each SetLog counts as one set regardless of setNumber',
        () async {
      final repo = MockSessionRepository();
      final now = DateTime.now();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: now,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
          ]);
      // 3 chest logs with arbitrary/duplicate setNumber values (1, 1, 7).
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
          .thenAnswer((_) async => [
                makeSetLog(id: 'l1', exerciseId: 'e-chest', setNumber: 1),
                makeSetLog(id: 'l2', exerciseId: 'e-chest', setNumber: 1),
                makeSetLog(id: 'l3', exerciseId: 'e-chest', setNumber: 7),
              ]);

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith(
            (ref) async => [_ex(id: 'e-chest', muscleGroup: 'chest')]),
        routineByIdProvider('r1').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      // 3 rows → 3 sets, even though setNumber repeats and skips.
      expect(result!.setsByGroup[MuscleGroupDisplay.pecho], 3);
    });

    // insights-27 (P1, logic): targetByGroup derives ONLY from the most-recent
    // session's routine (allSessions is DESC by startedAt; mostRecent = first).
    // The older session's routine must NOT contribute to targets.
    test('insights-27: targetByGroup uses the most-recent session routine only',
        () async {
      final repo = MockSessionRepository();
      final monday = _mondayOfThisWeek();
      final newer = monday.add(const Duration(days: 3, hours: 10));
      final older = monday.add(const Duration(days: 1, hours: 10));

      // listByUid contract: DESC by startedAt → newest first.
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's-new',
              startedAt: newer,
              status: SessionStatus.finished,
              routineId: 'rNew',
            ),
            makeSession(
              id: 's-old',
              startedAt: older,
              status: SessionStatus.finished,
              routineId: 'rOld',
            ),
          ]);
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => const <SetLog>[]);

      final newRoutine = makeRoutine(
        id: 'rNew',
        days: [
          makeDay(slots: [
            makeSlot(exerciseId: 'e-chest', muscleGroup: 'chest', targetSets: 4),
          ]),
        ],
      );
      final oldRoutine = makeRoutine(
        id: 'rOld',
        days: [
          makeDay(slots: [
            makeSlot(exerciseId: 'e-back', muscleGroup: 'back', targetSets: 9),
          ]),
        ],
      );

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
        routineByIdProvider('rNew').overrideWith((ref) async => newRoutine),
        routineByIdProvider('rOld').overrideWith((ref) async => oldRoutine),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      // Targets come from rNew only.
      expect(result!.targetByGroup[MuscleGroupDisplay.pecho], 4);
      // rOld's back target (9) must NOT leak in.
      expect(result.targetByGroup.containsKey(MuscleGroupDisplay.espalda),
          isFalse);
    });

    // insights-35 (P1, data): setLog reads are fanned out per session
    // (Future.wait) and merged across all week sessions.
    test('insights-35: aggregates setLogs across multiple sessions', () async {
      final repo = MockSessionRepository();
      final monday = _mondayOfThisWeek();
      final dayA = monday.add(const Duration(hours: 10));
      final dayB = monday.add(const Duration(days: 1, hours: 10));

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 'sA',
              startedAt: dayA,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
            makeSession(
              id: 'sB',
              startedAt: dayB,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
          ]);
      // Session A: 2 chest sets. Session B: 3 back sets.
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 'sA'))
          .thenAnswer((_) async => [
                makeSetLog(id: 'a1', exerciseId: 'e-chest', setNumber: 1),
                makeSetLog(id: 'a2', exerciseId: 'e-chest', setNumber: 2),
              ]);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 'sB'))
          .thenAnswer((_) async => [
                makeSetLog(id: 'b1', exerciseId: 'e-back', setNumber: 1),
                makeSetLog(id: 'b2', exerciseId: 'e-back', setNumber: 2),
                makeSetLog(id: 'b3', exerciseId: 'e-back', setNumber: 3),
              ]);

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => [
              _ex(id: 'e-chest', muscleGroup: 'chest'),
              _ex(id: 'e-back', muscleGroup: 'back'),
            ]),
        routineByIdProvider('r1').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.setsByGroup[MuscleGroupDisplay.pecho], 2);
      expect(result.setsByGroup[MuscleGroupDisplay.espalda], 3);
      // One read per session subcollection.
      verify(() => repo.listSetLogs(uid: 'u1', sessionId: 'sA')).called(1);
      verify(() => repo.listSetLogs(uid: 'u1', sessionId: 'sB')).called(1);
    });

    // insights-37 (P0, data): a repository failure must surface as an
    // AsyncError (the screen renders the 'No pudimos cargar tus insights.'
    // state), never as null or a partial result.
    test('insights-37: surfaces AsyncError when the repository throws',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1'))
          .thenThrow(Exception('firestore offline'));

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      ]);
      addTearDown(container.dispose);

      await expectLater(
        container.read(weeklyInsightsProvider.future),
        throwsA(isA<Exception>()),
      );
    });

    // insights-40 (P0, data): the provider must query the repository strictly
    // with the signed-in uid — both listByUid and listSetLogs. Confirms the
    // per-user data-scoping / isolation invariant.
    test('insights-40: reads only the signed-in uid sessions and setLogs',
        () async {
      final repo = MockSessionRepository();
      final now = DateTime.now();
      when(() => repo.listByUid(any())).thenAnswer((invocation) async {
        final uid = invocation.positionalArguments.first as String;
        // Only uid 'A' has data; any other uid would return empty.
        if (uid != 'A') return const [];
        return [
          makeSession(
            id: 's1',
            uid: 'A',
            startedAt: now,
            status: SessionStatus.finished,
            routineId: 'r1',
          ),
        ];
      });
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => [
            makeSetLog(id: 'l1', exerciseId: 'e-chest', setNumber: 1),
          ]);

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('A'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith(
            (ref) async => [_ex(id: 'e-chest', muscleGroup: 'chest')]),
        routineByIdProvider('r1').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.setsByGroup[MuscleGroupDisplay.pecho], 1);

      // Repo queried strictly with uid 'A' — never with any other uid.
      verify(() => repo.listByUid('A')).called(1);
      verifyNever(() => repo.listByUid(any(that: isNot('A'))));
      verify(() => repo.listSetLogs(uid: 'A', sessionId: 's1')).called(1);
      verifyNever(() => repo.listSetLogs(
            uid: any(named: 'uid', that: isNot('A')),
            sessionId: any(named: 'sessionId'),
          ));
    });
  });
}
