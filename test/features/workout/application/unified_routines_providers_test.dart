// Tests for unifiedRoutinesProvider — unified routines list + lazy adoption
// of the active routine (workout-area redesign slice 1, 2026-07-27).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/unified_routines_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';

class _MockUserRepository extends Mock implements UserRepository {}

// ── Fixtures ─────────────────────────────────────────────────────────────────

Routine _own(String id) => Routine(
      id: id,
      name: 'Own $id',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.userCreated,
      createdBy: 'u1',
    );

Routine _coach(String id) => Routine(
      id: id,
      name: 'Coach $id',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerAssigned,
      assignedBy: 'trainer-1',
      assignedTo: 'u1',
    );

UserProfile _profile({String? activeRoutineId}) => UserProfile(
      uid: 'u1',
      email: 'u1@treino.app',
      displayName: 'U1',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: activeRoutineId,
    );

ProviderContainer _container({
  List<Routine> assigned = const [],
  List<Routine> own = const [],
  Stream<UserProfile?>? profileStream,
  String? activeRoutineId,
  required UserRepository userRepo,
}) {
  final c = ProviderContainer(
    overrides: [
      assignedRoutinesProvider('u1').overrideWith((ref) async => assigned),
      userCreatedRoutinesProvider('u1')
          .overrideWith((ref) => Stream.value(own)),
      userProfileProvider.overrideWith(
        (ref) =>
            profileStream ??
            Stream.value(_profile(activeRoutineId: activeRoutineId)),
      ),
      userRepositoryProvider.overrideWithValue(userRepo),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Keeps the profile stream subscribed and resolved before reading the
/// unified provider — mirrors app runtime where the profile loads first.
Future<void> _warmProfile(ProviderContainer c) async {
  c.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, __) {});
  await c.read(userProfileProvider.future);
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  late _MockUserRepository userRepo;

  setUp(() {
    userRepo = _MockUserRepository();
    when(() => userRepo.update(any(), any())).thenAnswer((_) async {});
  });

  group('unifiedRoutinesProvider — composition', () {
    test('coach plans pinned first, then own routines, orders preserved',
        () async {
      final c = _container(
        assigned: [_coach('p1'), _coach('p2')],
        own: [_own('r1'), _own('r2')],
        activeRoutineId: 'p1',
        userRepo: userRepo,
      );
      await _warmProfile(c);

      final entries = await c.read(unifiedRoutinesProvider('u1').future);

      expect(entries.map((e) => e.routine.id), ['p1', 'p2', 'r1', 'r2']);
      expect(entries.map((e) => e.fromCoach), [true, true, false, false]);
    });

    test('empty uid → empty list, no reads, no writes', () async {
      final c = _container(userRepo: userRepo);
      final entries = await c.read(unifiedRoutinesProvider('').future);
      expect(entries, isEmpty);
      verifyNever(() => userRepo.update(any(), any()));
    });
  });

  group('unifiedRoutinesProvider — lazy adoption', () {
    test(
        'profile loaded + NO activeRoutineId + non-empty list → adopts the '
        'HEAD (coach plan first)', () async {
      final c = _container(
        assigned: [_coach('p1')],
        own: [_own('r1')],
        userRepo: userRepo,
      );
      await _warmProfile(c);

      await c.read(unifiedRoutinesProvider('u1').future);

      verify(() => userRepo.update('u1', {'activeRoutineId': 'p1'})).called(1);
    });

    test('no coach plan → adopts the newest own routine (list head)', () async {
      final c = _container(
        own: [_own('r1'), _own('r2')],
        userRepo: userRepo,
      );
      await _warmProfile(c);

      await c.read(unifiedRoutinesProvider('u1').future);

      verify(() => userRepo.update('u1', {'activeRoutineId': 'r1'})).called(1);
    });

    test('activeRoutineId already set → NO write (marker never stolen)',
        () async {
      final c = _container(
        assigned: [_coach('p1')],
        own: [_own('r1')],
        activeRoutineId: 'r1',
        userRepo: userRepo,
      );
      await _warmProfile(c);

      await c.read(unifiedRoutinesProvider('u1').future);

      verifyNever(() => userRepo.update(any(), any()));
    });

    test(
        'STALE activeRoutineId (not in the unified list) → NO re-adoption '
        '(strict-null trigger)', () async {
      final c = _container(
        assigned: [_coach('p1')],
        own: [_own('r1')],
        activeRoutineId: 'archived-id',
        userRepo: userRepo,
      );
      await _warmProfile(c);

      await c.read(unifiedRoutinesProvider('u1').future);

      verifyNever(() => userRepo.update(any(), any()));
    });

    test('empty list → NO adoption', () async {
      final c = _container(userRepo: userRepo);
      await _warmProfile(c);

      final entries = await c.read(unifiedRoutinesProvider('u1').future);

      expect(entries, isEmpty);
      verifyNever(() => userRepo.update(any(), any()));
    });

    test(
        'profile still loading → NO adoption (cannot distinguish null field '
        'from unloaded profile)', () async {
      final c = _container(
        assigned: [_coach('p1')],
        profileStream: const Stream.empty(),
        userRepo: userRepo,
      );

      final entries = await c.read(unifiedRoutinesProvider('u1').future);

      expect(entries, hasLength(1));
      verifyNever(() => userRepo.update(any(), any()));
    });

    test(
        'idempotent: after the profile re-emits WITH the adopted id, the '
        'recomputation does not write again', () async {
      final profileController = StreamController<UserProfile?>.broadcast();
      final c = _container(
        assigned: [_coach('p1')],
        profileStream: profileController.stream,
        userRepo: userRepo,
      );
      addTearDown(profileController.close);
      c.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, __) {});
      c.listen<AsyncValue<List<UnifiedRoutineEntry>>>(
          unifiedRoutinesProvider('u1'), (_, __) {});

      // 1st emission: no active routine → adoption writes p1.
      profileController.add(_profile());
      await c.read(userProfileProvider.future);
      await c.read(unifiedRoutinesProvider('u1').future);
      verify(() => userRepo.update('u1', {'activeRoutineId': 'p1'})).called(1);

      // 2nd emission: marker now set (simulates the Firestore echo of the
      // adoption write) → select changes → provider recomputes → no write.
      profileController.add(_profile(activeRoutineId: 'p1'));
      await Future<void>.delayed(Duration.zero);
      await c.read(unifiedRoutinesProvider('u1').future);
      verifyNever(() => userRepo.update(any(), any()));
    });

    test('adoption write failure is swallowed — the list still resolves',
        () async {
      when(() => userRepo.update(any(), any())).thenThrow(Exception('offline'));
      final c = _container(
        assigned: [_coach('p1')],
        own: [_own('r1')],
        userRepo: userRepo,
      );
      await _warmProfile(c);

      final entries = await c.read(unifiedRoutinesProvider('u1').future);

      expect(entries.map((e) => e.routine.id), ['p1', 'r1']);
    });
  });
}
