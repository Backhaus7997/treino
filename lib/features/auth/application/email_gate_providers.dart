import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import 'auth_providers.dart';

/// Interruptor del gate del mail: `app_config/email_gate` con `{enabled: true}`.
///
/// Lo lee el redirect del router (`authRedirect`) como
/// `read(emailGateEnabledProvider).valueOrNull ?? false`. Documento ausente, en
/// `false`, sin sesión, o mientras no llegó ningún valor (cargando) ⇒ gate
/// APAGADO. Y un error en CUALQUIER momento también lo apaga (ver
/// [interruptorDesde]). Falla abierto a propósito: el código del mail es un
/// canal de comunicación (que el alumno lea cómo se paga), no un control de
/// acceso. Si Resend se queda sin cuota, el equipo apaga el gate desde la
/// consola de Firestore, sin deploy ni build nuevo.
///
/// Depende del uid y NO de un stream abierto de entrada: la regla de
/// `app_config` pide sesión. Un stream abierto con la sesión cerrada recibe
/// permission-denied, un `StreamProvider` que terminó en error no se vuelve a
/// suscribir solo, y el gate quedaría apagado toda esa corrida de la app aun
/// después de loguearse. Al depender del uid, el login reconstruye el provider
/// y abre el stream recién cuando ya hay sesión; sin uid emite `false` y listo.
final emailGateEnabledProvider = StreamProvider<bool>((ref) {
  final uid =
      ref.watch(authStateChangesProvider.select((a) => a.valueOrNull?.uid));
  if (uid == null) return Stream.value(false);

  final FirebaseFirestore firestore = ref.watch(firestoreProvider);
  return interruptorDesde(
    firestore
        .collection('app_config')
        .doc('email_gate')
        .snapshots()
        .map((snap) => snap.data()),
  );
});

/// Los datos del documento `app_config/email_gate` (`null` si no existe) como
/// el valor del interruptor: solo `enabled == true` (booleano) lo prende.
///
/// Un ERROR del stream se convierte en un `false`, venga cuando venga. No es un
/// detalle: Riverpod conserva el último valor cuando el stream pasa a error, y
/// Firestore cierra el listener después de un error (permission-denied, token
/// perdido). Sin esta conversión, un `true` seguido de un error quedaba como
/// `true` para siempre: el equipo apagaría el interruptor en la consola
/// durante una caída de Resend y el cambio nunca llegaría, con los usuarios
/// atrapados en la pantalla del código. Con ella, el interruptor siempre cae del
/// lado abierto.
Stream<bool> interruptorDesde(Stream<Map<String, dynamic>?> datos) {
  return datos.map((d) => d?['enabled'] == true).transform(
        StreamTransformer<bool, bool>.fromHandlers(
          handleError: (error, stackTrace, sink) => sink.add(false),
        ),
      );
}
