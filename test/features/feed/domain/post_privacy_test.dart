import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';

void main() {
  // SCENARIO-115: PostPrivacy fromJson round-trip
  group('PostPrivacy', () {
    test('SCENARIO-115a: fromJson returns .public for "public"', () {
      expect(PostPrivacyX.fromJson('public'), equals(PostPrivacy.public));
    });

    test('SCENARIO-115b: .public.toJson() returns "public"', () {
      expect(PostPrivacy.public.toJson(), equals('public'));
    });

    test('SCENARIO-115c: all three values round-trip', () {
      for (final value in PostPrivacy.values) {
        final wire = value.toJson();
        expect(PostPrivacyX.fromJson(wire), equals(value));
      }
    });

    test('SCENARIO-115d: fromJson returns .friends for "friends"', () {
      expect(PostPrivacyX.fromJson('friends'), equals(PostPrivacy.friends));
    });

    test('SCENARIO-115e: fromJson returns .gym for "gym"', () {
      expect(PostPrivacyX.fromJson('gym'), equals(PostPrivacy.gym));
    });

    test('SCENARIO-115f: unknown wire value throws ArgumentError', () {
      expect(
        () => PostPrivacyX.fromJson('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
