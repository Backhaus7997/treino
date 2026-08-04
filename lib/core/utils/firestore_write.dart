import 'dart:async';

/// How long a Firestore write may stay pending before the UI is unblocked.
///
/// A Firestore write future resolves on SERVER ack. Offline (or on a dead
/// connection) it never completes — so any caller that `await`s it behind a
/// `_saving`/`_busy`/`_sending` spinner hangs forever with no error (QA H4).
/// The athlete side already bounds one write this way (QA-WKT-011,
/// `home_screen.dart`); this is the shared value for the trainer flows.
const kFirestoreWriteTimeout = Duration(seconds: 15);

extension FirestoreWriteTimeout<T> on Future<T> {
  /// Bounds this Firestore write with [kFirestoreWriteTimeout], throwing a
  /// [TimeoutException] if it does not ack in time.
  ///
  /// The write stays queued in Firestore's local cache and still syncs on
  /// reconnect — the bound only frees the UI to surface a retryable error
  /// instead of an infinite spinner. Callers MUST already handle a thrown
  /// write (reset the spinner, show feedback); this just makes the offline
  /// stall reach that handler.
  Future<T> get boundedWrite => timeout(kFirestoreWriteTimeout);
}
