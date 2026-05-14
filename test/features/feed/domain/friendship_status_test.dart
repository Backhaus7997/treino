import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';

void main() {
  // SCENARIO-117: FriendshipStatus fromJson round-trip
  group('FriendshipStatus', () {
    test('SCENARIO-117a: fromJson returns .pending for "pending"', () {
      expect(
        FriendshipStatusX.fromJson('pending'),
        equals(FriendshipStatus.pending),
      );
    });

    test('SCENARIO-117b: .accepted.toJson() returns "accepted"', () {
      expect(FriendshipStatus.accepted.toJson(), equals('accepted'));
    });

    test('SCENARIO-117c: both values round-trip', () {
      for (final value in FriendshipStatus.values) {
        final wire = value.toJson();
        expect(FriendshipStatusX.fromJson(wire), equals(value));
      }
    });

    test('SCENARIO-117d: unknown wire value throws ArgumentError', () {
      expect(
        () => FriendshipStatusX.fromJson('blocked'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
