import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/reaction_type.dart';

void main() {
  group('ReactionType', () {
    test('round-trips every supported wire value', () {
      for (final type in ReactionType.values) {
        expect(ReactionTypeX.fromJson(type.toJson()), type);
      }
    });

    test('rejects an unknown wire value', () {
      expect(
        () => ReactionTypeX.fromJson('future_type'),
        throwsArgumentError,
      );
    });
  });
}
