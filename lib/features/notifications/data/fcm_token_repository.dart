import 'package:cloud_firestore/cloud_firestore.dart';

/// Repository for managing FCM token storage on `users/{uid}`.
///
/// Tokens are stored as a camelCase array field `fcmTokens: List<String>`
/// on the existing `users/{uid}` document. No new collections are created.
///
/// ADR-PN-001: field name is `fcmTokens` (camelCase).
/// ADR-PN-002: writes use `arrayUnion` (save) and `arrayRemove` (remove).
/// REQ-PN-DATA-001, REQ-PN-DATA-002, REQ-PN-DATA-003.
class FcmTokenRepository {
  FcmTokenRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _users =>
      _firestore.collection('users');

  /// Saves [token] to `users/[uid].fcmTokens` using `arrayUnion`.
  ///
  /// Idempotent — duplicate tokens are not added.
  /// Creates the `fcmTokens` field if absent on the document.
  /// REQ-PN-DATA-001, REQ-PN-DATA-002, SCENARIO-619, 620, 621.
  Future<void> saveToken(String uid, String token) async {
    await _users.doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]), // ADR-PN-001, ADR-PN-002
      },
      SetOptions(merge: true),
    );
  }

  /// Removes [token] from `users/[uid].fcmTokens` using `arrayRemove`.
  ///
  /// No-op when the token is not in the array.
  /// Swallows not-found errors so logout cleanup never crashes the app.
  /// REQ-PN-DATA-003, SCENARIO-622, 623.
  Future<void> removeToken(String uid, String token) async {
    try {
      await _users.doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]), // ADR-PN-001, ADR-PN-002
      });
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return;
      rethrow;
    }
  }
}
