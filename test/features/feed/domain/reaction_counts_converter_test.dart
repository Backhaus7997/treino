import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/reaction_counts_converter.dart';
import 'package:treino/features/feed/domain/reaction_type.dart';

void main() {
  const converter = ReactionCountsConverter();

  group('ReactionCountsConverter', () {
    test('ignores legacy strong and unknown keys without throwing', () {
      expect(
        converter.fromJson({
          'strong': 2,
          'future_type': 99,
          'fire': 1,
        }),
        {
          ReactionType.fire: 1,
        },
      );
    });

    test('null input becomes an empty map', () {
      expect(converter.fromJson(null), isEmpty);
    });

    test('discards non-int values', () {
      expect(
        converter.fromJson({
          'like': '2',
          'fire': 1.5,
          'clap': null,
        }),
        isEmpty,
      );
    });

    test('writes enum keys back to wire strings', () {
      expect(
        converter.toJson({
          ReactionType.like: 3,
          ReactionType.clap: 4,
        }),
        {'like': 3, 'clap': 4},
      );
    });
  });
}
