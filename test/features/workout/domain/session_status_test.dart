import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/session_status.dart';

void main() {
  group('SessionStatus', () {
    test('SCENARIO-235: SessionStatus.fromJson("active") decodes correctly',
        () {
      final result = SessionStatusX.fromJson('active');

      expect(result, equals(SessionStatus.active));
    });

    test(
        'SCENARIO-236: SessionStatus.finished toJson encodes to lowercase wire',
        () {
      const status = SessionStatus.finished;

      final result = status.toJson();

      expect(result, equals('finished'));
    });

    test('SCENARIO-236b: SessionStatus.active toJson encodes to "active"', () {
      const status = SessionStatus.active;

      final result = status.toJson();

      expect(result, equals('active'));
    });

    test(
        'SCENARIO-235b: fromJson("finished") decodes to SessionStatus.finished',
        () {
      final result = SessionStatusX.fromJson('finished');

      expect(result, equals(SessionStatus.finished));
    });

    test('fromJson with unknown value throws ArgumentError', () {
      expect(
        () => SessionStatusX.fromJson('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
