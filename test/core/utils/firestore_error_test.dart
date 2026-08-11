import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:treino/core/utils/firestore_error.dart';

void main() {
  group('isPermissionDenied', () {
    test('true for a FirebaseException with code permission-denied', () {
      expect(
        isPermissionDenied(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        isTrue,
      );
    });

    test('false for other FirebaseException codes (real failures)', () {
      expect(
        isPermissionDenied(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        isFalse,
      );
      expect(
        isPermissionDenied(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
          ),
        ),
        isFalse,
      );
    });

    test(
      'false for a non-Firebase error whose message says permission-denied',
      () {
        expect(isPermissionDenied(Exception('permission-denied')), isFalse);
      },
    );

    test('false for null', () {
      expect(isPermissionDenied(null), isFalse);
    });
  });
}
