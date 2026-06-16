import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/check_in/application/check_in_providers.dart';
import 'package:treino/features/check_in/data/check_in_repository.dart';
import 'package:treino/features/check_in/domain/check_in.dart';
import 'package:treino/features/profile_setup/domain/gym.dart';
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

  test(
    'confirm() with kNoGymId sentinel records a NOT-in-gym check-in',
    () async {
      final checkIn = CheckIn(
        uid: 'u1',
        date: CheckIn.dateKey(DateTime.now().toLocal()),
        checkedInAt: DateTime.now().toUtc(),
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

      await container
          .read(checkInNotifierProvider.notifier)
          .confirm(gymId: kNoGymId, gymName: null);

      // The sentinel must be treated as not-in-gym, with gym fields nulled out
      // so the stored record is not an inconsistent gym check-in.
      verify(
        () => repo.createTodayCheckIn(
          'u1',
          inGym: false,
          gymId: null,
          gymName: null,
        ),
      ).called(1);
    },
  );

  test('confirm() with a real gymId records an in-gym check-in', () async {
    final checkIn = CheckIn(
      uid: 'u1',
      date: CheckIn.dateKey(DateTime.now().toLocal()),
      checkedInAt: DateTime.now().toUtc(),
      gymId: 'smart-fit-palermo',
      gymName: 'SMART FIT',
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

    await container
        .read(checkInNotifierProvider.notifier)
        .confirm(gymId: 'smart-fit-palermo', gymName: 'SMART FIT');

    verify(
      () => repo.createTodayCheckIn(
        'u1',
        inGym: true,
        gymId: 'smart-fit-palermo',
        gymName: 'SMART FIT',
      ),
    ).called(1);
  });
}
