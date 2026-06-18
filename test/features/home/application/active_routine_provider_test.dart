// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/home/application/active_routine_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';

RoutineSlot _slot() => const RoutineSlot(
      exerciseId: 'x',
      exerciseName: 'X',
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

Routine _routine({required String id}) => Routine(
      id: id,
      name: id.toUpperCase(),
      level: ExperienceLevel.intermediate,
      days: [
        RoutineDay(dayNumber: 1, name: 'D1', slots: [_slot()])
      ],
      source: RoutineSource.userCreated,
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
  String uid = 'u1',
  List<Routine> selfCreated = const [],
  String? activeRoutineId,
  bool profileNull = false,
}) {
  final c = ProviderContainer(
    overrides: [
      currentUidProvider.overrideWith((ref) => uid),
      userCreatedRoutinesProvider(uid)
          .overrideWith((ref) => Stream.value(selfCreated)),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(
          profileNull ? null : _profile(activeRoutineId: activeRoutineId),
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('activeRoutineProvider', () {
    test('uid empty → null (unauthenticated)', () async {
      final c = _container(uid: '');
      expect(c.read(activeRoutineProvider), isNull);
    });

    test('profile null → null', () async {
      final c = _container(profileNull: true);
      // Drain async to settle the stream-backed profile.
      await c.read(userProfileProvider.future);
      expect(c.read(activeRoutineProvider), isNull);
    });

    test('activeRoutineId null → null', () async {
      final c = _container(
        selfCreated: [_routine(id: 'r1'), _routine(id: 'r2')],
        activeRoutineId: null,
      );
      await c.read(userProfileProvider.future);
      expect(c.read(activeRoutineProvider), isNull);
    });

    test('activeRoutineId empty string → null', () async {
      final c = _container(
        selfCreated: [_routine(id: 'r1')],
        activeRoutineId: '',
      );
      await c.read(userProfileProvider.future);
      expect(c.read(activeRoutineProvider), isNull);
    });

    test('activeRoutineId matches a routine → returns that routine', () async {
      final r1 = _routine(id: 'r1');
      final r2 = _routine(id: 'r2');
      final c = _container(
        selfCreated: [r1, r2],
        activeRoutineId: 'r2',
      );
      // Pre-subscribe to the autoDispose streams so they resolve before
      // activeRoutineProvider reads .valueOrNull.
      c.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, __) {});
      c.listen<AsyncValue<List<Routine>>>(
          userCreatedRoutinesProvider('u1'), (_, __) {});
      await c.read(userProfileProvider.future);
      await c.read(userCreatedRoutinesProvider('u1').future);
      final active = c.read(activeRoutineProvider);
      expect(active, isNotNull);
      expect(active!.id, equals('r2'));
    });

    test(
        'activeRoutineId does not match any routine → null '
        '(stale pointer, e.g. routine was archived after being marked)',
        () async {
      final c = _container(
        selfCreated: [_routine(id: 'r1')],
        activeRoutineId: 'archived-id',
      );
      c.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, __) {});
      c.listen<AsyncValue<List<Routine>>>(
          userCreatedRoutinesProvider('u1'), (_, __) {});
      await c.read(userProfileProvider.future);
      await c.read(userCreatedRoutinesProvider('u1').future);
      expect(c.read(activeRoutineProvider), isNull);
    });
  });
}
