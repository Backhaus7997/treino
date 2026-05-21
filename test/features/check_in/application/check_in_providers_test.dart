import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/check_in/application/check_in_providers.dart';
import 'package:treino/features/check_in/data/check_in_repository.dart';
import 'package:treino/features/check_in/domain/check_in.dart';
import 'package:treino/features/workout/application/session_providers.dart';

class MockCheckInRepository extends Mock implements CheckInRepository {}

ProviderContainer _makeContainer({
  required MockCheckInRepository repo,
  String? uid,
}) {
  return ProviderContainer(
    overrides: [
      currentUidProvider.overrideWithValue(uid),
      checkInRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  late MockCheckInRepository repo;

  setUp(() {
    repo = MockCheckInRepository();
  });

  group('todayCheckInProvider', () {
    test('returns null when unauthenticated (null uid)', () async {
      final container = _makeContainer(repo: repo, uid: null);
      addTearDown(container.dispose);

      final result = await container.read(todayCheckInProvider.future);
      expect(result, isNull);

      // Should not call repo when unauthenticated
      verifyNever(() => repo.getTodayForUser(any()));
    });

    test('returns null when authed but no check-in today', () async {
      when(() => repo.getTodayForUser('u1')).thenAnswer((_) async => null);

      final container = _makeContainer(repo: repo, uid: 'u1');
      addTearDown(container.dispose);

      final result = await container.read(todayCheckInProvider.future);
      expect(result, isNull);
    });

    test('returns CheckIn when authed and check-in exists today', () async {
      final checkIn = CheckIn(
        uid: 'u1',
        date: CheckIn.dateKey(DateTime.now().toLocal()),
        checkedInAt: DateTime.now().toUtc(),
        gymId: 'gym1',
        gymName: 'Smart Fit',
      );

      when(() => repo.getTodayForUser('u1')).thenAnswer((_) async => checkIn);

      final container = _makeContainer(repo: repo, uid: 'u1');
      addTearDown(container.dispose);

      final result = await container.read(todayCheckInProvider.future);
      expect(result, isNotNull);
      expect(result!.uid, equals('u1'));
      expect(result.gymId, equals('gym1'));
    });
  });

  group('checkInNotifierProvider', () {
    test('confirm() creates check-in and invalidates todayCheckInProvider',
        () async {
      final checkIn = CheckIn(
        uid: 'u1',
        date: CheckIn.dateKey(DateTime.now().toLocal()),
        checkedInAt: DateTime.now().toUtc(),
        gymId: 'gym1',
        gymName: 'Smart Fit',
      );

      when(() => repo.getTodayForUser('u1')).thenAnswer((_) async => null);
      when(
        () => repo.createTodayCheckIn(
          'u1',
          inGym: any(named: 'inGym'),
          gymId: any(named: 'gymId'),
          gymName: any(named: 'gymName'),
        ),
      ).thenAnswer((_) async => checkIn);

      final container = _makeContainer(repo: repo, uid: 'u1');
      addTearDown(container.dispose);

      // Call confirm
      await container
          .read(checkInNotifierProvider.notifier)
          .confirm(gymId: 'gym1', gymName: 'Smart Fit');

      // Verify the repo was called with correct args
      verify(
        () => repo.createTodayCheckIn(
          'u1',
          inGym: any(named: 'inGym'),
          gymId: 'gym1',
          gymName: 'Smart Fit',
        ),
      ).called(1);
    });
  });
}
