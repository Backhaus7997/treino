import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/check_in/data/check_in_repository.dart';
import 'package:treino/features/check_in/domain/check_in.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late CheckInRepository repo;

  const uid = 'user-test-001';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = CheckInRepository(firestore: firestore);
  });

  group('getTodayForUser', () {
    test('SCENARIO-327: returns null when no check-in doc exists', () async {
      final result = await repo.getTodayForUser(uid);
      expect(result, isNull);
    });

    test('SCENARIO-328: returns existing CheckIn when doc exists', () async {
      final localDate = DateTime.now().toLocal();
      final docId = CheckIn.dateKey(localDate);
      final now = DateTime.utc(2026, 5, 15, 10, 0, 0);
      final ts = Timestamp.fromDate(now);

      await firestore
          .collection('users')
          .doc(uid)
          .collection('checkIns')
          .doc(docId)
          .set({
        'uid': uid,
        'date': docId,
        'checkedInAt': ts,
        'gymId': 'gym1',
        'gymName': 'Smart Fit',
      });

      final result = await repo.getTodayForUser(uid);
      expect(result, isNotNull);
      expect(result!.uid, equals(uid));
      expect(result.date, equals(docId));
      expect(result.gymId, equals('gym1'));
      expect(result.gymName, equals('Smart Fit'));
    });
  });

  group('createTodayCheckIn', () {
    test('SCENARIO-329: upserts doc with correct fields when inGym: true',
        () async {
      await repo.createTodayCheckIn(
        uid,
        inGym: true,
        gymId: 'gym1',
        gymName: 'Smart Fit',
      );

      final today = CheckIn.dateKey(DateTime.now().toLocal());
      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('checkIns')
          .doc(today)
          .get();

      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['uid'], equals(uid));
      expect(data['gymId'], equals('gym1'));
      expect(data['gymName'], equals('Smart Fit'));
    });

    test('creates doc with null gym fields when inGym: false', () async {
      final checkIn = await repo.createTodayCheckIn(
        uid,
        inGym: false,
      );

      expect(checkIn.gymId, isNull);
      expect(checkIn.gymName, isNull);
    });

    test('idempotency: second call returns existing doc without overwriting',
        () async {
      final first = await repo.createTodayCheckIn(
        uid,
        inGym: true,
        gymId: 'gym1',
        gymName: 'Smart Fit',
      );

      final second = await repo.createTodayCheckIn(
        uid,
        inGym: false, // different params — should NOT overwrite
      );

      // Both should return a CheckIn with the first call's data
      expect(first.gymId, equals('gym1'));
      expect(second.gymId, equals('gym1'));
      expect(second.gymName, equals('Smart Fit'));

      // Only one doc should exist
      final today = CheckIn.dateKey(DateTime.now().toLocal());
      final col = await firestore
          .collection('users')
          .doc(uid)
          .collection('checkIns')
          .get();
      expect(col.docs.where((d) => d.id == today).length, equals(1));
    });
  });
}
