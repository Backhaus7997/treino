import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Registra el token de push DEL RELOJ, para que el servidor pueda despertarlo.
///
/// ## Por qué un campo propio y no `fcmTokens`
///
/// `sendFcm` de las Cloud Functions manda a **todos** los tokens del usuario.
/// Si el reloj guardara el suyo en el mismo array, cada aviso pensado para la
/// muñeca le llegaría también al teléfono como notificación fantasma — y al
/// revés, los avisos sociales del teléfono despertarían la app del reloj.
///
/// Son audiencias distintas, así que van en campos distintos. El costo es una
/// función de envío propia; la alternativa era ensuciar las notificaciones que
/// ya funcionan.
///
/// ## Por qué el reloj necesita push si ya tiene Firestore
///
/// Un listener de Firestore existe sólo mientras hay proceso vivo. Con la app
/// cerrada no hay nadie escuchando, por más internet que tenga el reloj: hace
/// falta algo que despierte el proceso DESDE AFUERA. La Data Layer puede, pero
/// exige emparejamiento con ese teléfono. El push no exige nada más que red.
class WearPushRegistration {
  WearPushRegistration({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  /// El campo donde viven los tokens de relojes. Lo lee la Cloud Function.
  static const String field = 'wearFcmTokens';

  /// Deja registrado el token de este reloj para [uid].
  ///
  /// Nunca tira. Quedarse sin push es una degradación —el reloj sigue andando
  /// entero, sólo que hay que abrirlo a mano— y no justifica tumbar el arranque.
  Future<void> register(String uid) async {
    if (uid.isEmpty) return;
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[wear-push] sin token todavía');
        return;
      }

      // `arrayUnion` y no `set`: el atleta puede tener más de un reloj, y
      // pisar el array dejaría al otro sin poder despertarse.
      await _firestore.collection('users').doc(uid).set(
        {
          field: FieldValue.arrayUnion([token]),
        },
        SetOptions(merge: true),
      );
      debugPrint('[wear-push] token registrado (${token.length} caracteres)');
    } catch (e) {
      debugPrint('[wear-push] no se pudo registrar el token — $e');
    }
  }
}
