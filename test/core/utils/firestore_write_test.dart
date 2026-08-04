import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/firestore_write.dart';

void main() {
  group('boundedWrite', () {
    // testWidgets is used only for its fake clock: it lets the 15s .timeout
    // Timer be advanced without really waiting 15 seconds.
    testWidgets('throws TimeoutException when the write never acks',
        (tester) async {
      Object? caught;
      final never = Completer<void>();
      unawaited(never.future.boundedWrite.catchError((Object e) {
        caught = e;
      }));

      await tester.pump(const Duration(seconds: 16));

      expect(caught, isA<TimeoutException>());
    });

    testWidgets('passes a write that acks in time straight through',
        (tester) async {
      int? value;
      unawaited(Future.value(7).boundedWrite.then((v) => value = v));

      await tester.pump();

      expect(value, 7);
    });
  });
}
