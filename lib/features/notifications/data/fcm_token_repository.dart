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
  ///
  /// ─── Por qué `update` y no `set(merge)` ───────────────────────────────────
  ///
  /// Si `users/{uid}` todavía no existe, no se escribe nada. Pasa en el alta
  /// por mail: `fcmLifecycleProvider` guarda el token apenas existe la cuenta
  /// de Auth, antes de que el registro cree el perfil.
  ///
  /// Con `set(merge)` ese caso era peor que inútil. El servidor lo rechaza
  /// siempre —el create de `users/{uid}` exige `uid`, `email` y `role`—, pero
  /// el SDK aplica la escritura en el teléfono AL INSTANTE y, hasta que llega
  /// el rechazo, muestra un `users/{uid}` con SÓLO `fcmTokens`. El registro lo
  /// leía como perfil, `UserProfile.fromJson` reventaba y el rollback borraba
  /// la cuenta recién creada: «Hubo un problema creando tu perfil» (medido en
  /// un emulador Android, 2026-10-13). `update` sobre un doc inexistente no
  /// aparece en la vista local: sólo falla.
  ///
  /// OJO con CÓMO falla, que no es igual en todos lados. Contra producción
  /// vuelve `permission-denied` —las reglas de update corren antes de que el
  /// servidor note que el doc no existe; medido el mismo día—, y eso lo ataja
  /// y loguea `FcmService.init`, igual que antes con el `set(merge)`. El
  /// `not-found` de acá abajo es lo que tira `fake_cloud_firestore`: se
  /// silencia porque no hay nada que reportar, no porque sea lo que pasa en
  /// el teléfono.
  ///
  /// El token no se pierde: `FcmService.init` vuelve a correr al próximo
  /// arranque y cuando `PermissionGate` concede el permiso.
  Future<void> saveToken(String uid, String token) async {
    try {
      await _users.doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]), // ADR-PN-001, ADR-PN-002
      });
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return;
      rethrow;
    }
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
