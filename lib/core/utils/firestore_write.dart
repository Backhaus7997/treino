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
  ///
  /// DO NOT apply this blindly. Three rules, each learned the hard way:
  ///
  /// 1. EVERY call-site of the method must already catch a thrown write.
  ///    Repositories are shared across the trainer, athlete and Coach Hub
  ///    surfaces, so one unguarded caller is enough to turn a bounded write
  ///    into an uncaught async error — on mobile that reaches
  ///    `runZonedGuarded` in main.dart and is recorded as a Crashlytics FATAL.
  ///    Bounding an unguarded write is a REGRESSION, not a fix.
  ///
  /// 2. Do NOT bound a write whose failure path destroys something the write
  ///    still references. A timeout does NOT cancel the write — it may sync
  ///    later. `ChatRepository.sendMessage` is the live example: its media
  ///    caller deletes the uploaded file on error, which after a timeout would
  ///    leave a message pointing at deleted media once the write lands.
  ///
  /// 3. `runTransaction` already bounds itself (30s by default) and does not
  ///    queue offline, so it is not part of the infinite-hang problem.
  ///    Firebase Storage uploads have their own progress/cancel semantics —
  ///    they are not Firestore writes and must not be bounded with this.
  Future<T> get boundedWrite => timeout(kFirestoreWriteTimeout);
}
