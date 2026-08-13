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

    test('SCENARIO-115d: fromJson returns .followers for "friends"', () {
      expect(PostPrivacyX.fromJson('friends'), equals(PostPrivacy.followers));
    });

    // SCENARIO-810 / LD-05 — EL INVARIANTE QUE SOSTIENE TODO EL RENAME.
    //
    // El símbolo Dart pasa de `friends` a `followers`, pero el valor que viaja
    // a Firestore SIGUE SIENDO 'friends'. Si esto cambiara, los posts ya
    // escritos quedarían con un tier que el cliente no sabe leer Y las rules
    // dejarían de matchear (`resource.data.privacy == 'friends'`), o sea que un
    // rename cosmético se convertiría en una migración de datos silenciosa
    // sobre todos los posts existentes. Este test es la única cosa que impide
    // que alguien "prolije" el @JsonValue.
    test('SCENARIO-810: .followers.toJson() sigue siendo "friends"', () {
      expect(PostPrivacy.followers.toJson(), equals('friends'));
    });

    test('SCENARIO-810: ningún valor de wire cambió con el rename', () {
      expect(
        PostPrivacy.values.map((v) => v.toJson()).toSet(),
        equals({'friends', 'gym', 'public'}),
      );
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
