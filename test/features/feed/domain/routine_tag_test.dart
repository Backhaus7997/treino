import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';

void main() {
  group('RoutineTag', () {
    test('SCENARIO-T05a: construct with routineId and routineName', () {
      const tag = RoutineTag(routineId: 'r1', routineName: 'Push Day');
      expect(tag.routineId, equals('r1'));
      expect(tag.routineName, equals('Push Day'));
    });

    test('SCENARIO-T05b: toJson produces nested map with expected keys', () {
      const tag = RoutineTag(routineId: 'r1', routineName: 'Push Day');
      final json = tag.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['routineId'], equals('r1'));
      expect(json['routineName'], equals('Push Day'));
    });

    test('SCENARIO-T05c: fromJson(toJson()) equals original', () {
      const tag = RoutineTag(routineId: 'r2', routineName: 'Leg Day');
      final roundTripped = RoutineTag.fromJson(tag.toJson());
      expect(roundTripped, equals(tag));
    });
  });
}
