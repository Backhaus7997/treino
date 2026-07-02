import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/domain/gym_suggestion.dart';

// T2.5 RED / T2.6 GREEN — gym-google-places Phase 2.
//
// Plain DTO (NOT freezed, per design #348) mapped from
// `suggestions[].placePrediction` in a Places Autocomplete (New) response.
void main() {
  group('GymSuggestion', () {
    test('constructs with placeId/primaryText/secondaryText', () {
      const suggestion = GymSuggestion(
        placeId: 'ChIJ_place_1',
        primaryText: 'SportClub Belgrano',
        secondaryText: 'Cabildo 1789, CABA',
      );

      expect(suggestion.placeId, 'ChIJ_place_1');
      expect(suggestion.primaryText, 'SportClub Belgrano');
      expect(suggestion.secondaryText, 'Cabildo 1789, CABA');
    });

    test('secondaryText is nullable (some predictions omit it)', () {
      const suggestion = GymSuggestion(
        placeId: 'ChIJ_place_2',
        primaryText: 'Gimnasio Local',
        secondaryText: null,
      );

      expect(suggestion.secondaryText, isNull);
    });

    test('equality is value-based', () {
      const a = GymSuggestion(
        placeId: 'ChIJ_place_1',
        primaryText: 'SportClub Belgrano',
        secondaryText: 'Cabildo 1789, CABA',
      );
      const b = GymSuggestion(
        placeId: 'ChIJ_place_1',
        primaryText: 'SportClub Belgrano',
        secondaryText: 'Cabildo 1789, CABA',
      );
      const c = GymSuggestion(
        placeId: 'ChIJ_place_other',
        primaryText: 'SportClub Belgrano',
        secondaryText: 'Cabildo 1789, CABA',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });
  });
}
