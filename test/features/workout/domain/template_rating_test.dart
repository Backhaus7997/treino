import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/template_rating.dart';

void main() {
  group('TemplateRating', () {
    test('fromJson/toJson roundtrip with comment', () {
      final rating = TemplateRating.fromJson({
        'userId': 'user-1',
        'rating': 4,
        'comment': 'Muy buena progresión',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(2000),
      });

      expect(rating.userId, 'user-1');
      expect(rating.rating, 4);
      expect(rating.comment, 'Muy buena progresión');
      expect(rating.createdAt.millisecondsSinceEpoch, 1000);
      expect(rating.updatedAt.millisecondsSinceEpoch, 2000);

      final json = rating.toJson();
      expect(json['userId'], 'user-1');
      expect(json['rating'], 4);
      expect(json['comment'], 'Muy buena progresión');
      expect(json['createdAt'], isA<Timestamp>());
      expect(json['updatedAt'], isA<Timestamp>());
    });

    test('comment is optional and null survives the roundtrip', () {
      final rating = TemplateRating.fromJson({
        'userId': 'user-1',
        'rating': 5,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      });

      expect(rating.comment, isNull);
      // json_serializable emits the key with an explicit null — the normal
      // wire shape for nullable freezed fields (the rules accept it).
      expect(rating.toJson()['comment'], isNull);
    });
  });

  group('Routine rating aggregates (CF-only fields)', () {
    Routine routineFromJson(Map<String, Object?> extra) => Routine.fromJson({
          'id': 'r1',
          'name': 'Test Routine',
          'level': 'beginner',
          'days': <Object?>[],
          ...extra,
        });

    test('fromJson reads ratingAvg and ratingsCount', () {
      final routine = routineFromJson({'ratingAvg': 4.5, 'ratingsCount': 3});
      expect(routine.ratingAvg, 4.5);
      expect(routine.ratingsCount, 3);
    });

    test('fromJson coerces an integer ratingAvg to double', () {
      // Firestore stores a whole-number average (e.g. exactly 4) as an int.
      final routine = routineFromJson({'ratingAvg': 4, 'ratingsCount': 1});
      expect(routine.ratingAvg, 4.0);
    });

    test('fromJson defaults both aggregates to null when absent', () {
      final routine = routineFromJson({});
      expect(routine.ratingAvg, isNull);
      expect(routine.ratingsCount, isNull);
    });

    test('toJson NEVER emits the CF-only aggregate keys', () {
      // Regression lock for @JsonKey(includeToJson: false): if these keys
      // leaked into toJson(), every repo write built from toJson() would
      // carry them and trip the firestore.rules create/update guards.
      const routine = Routine(
        id: 'r1',
        name: 'Test Routine',
        level: ExperienceLevel.beginner,
        days: [],
        ratingAvg: 4.5,
        ratingsCount: 3,
      );

      final json = routine.toJson();
      expect(json.containsKey('ratingAvg'), isFalse);
      expect(json.containsKey('ratingsCount'), isFalse);
    });
  });
}
