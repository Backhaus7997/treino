import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';

/// Canales de entrega de notificaciones del Coach Hub.
///
/// IMPORTANTE (honestidad de scope W3.2): hoy SOLO `push` tiene backend (FCM),
/// y las Cloud Functions todavía NO leen estas preferencias (siempre mandan).
/// `email` y `whatsapp` no tienen envío implementado. Esta pantalla PERSISTE
/// las preferencias en `users/{uid}.notificationPrefs`; que las CFs las
/// respeten + los canales email/whatsapp son follow-ups de `functions/`.
enum NotifChannel { email, push, whatsapp }

extension NotifChannelX on NotifChannel {
  String get label => switch (this) {
        NotifChannel.email => 'EMAIL', // i18n: Fase W3
        NotifChannel.push => 'PUSH', // i18n: Fase W3
        NotifChannel.whatsapp => 'WHATSAPP', // i18n: Fase W3
      };
}

/// Un tipo de aviso (fila de la matriz), con su grupo y etiqueta.
class NotifType {
  const NotifType(this.key, this.group, this.label);

  final String key;
  final String group; // PAGOS / ALUMNOS / CHAT
  final String label;
}

/// Tipos de aviso del mockup `notificaciones.png`, en orden.
const kNotifTypes = <NotifType>[
  NotifType('pago_recibido', 'PAGOS', 'Pago recibido'), // i18n: Fase W3
  NotifType('nueva_solicitud', 'ALUMNOS', 'Nueva solicitud (Discovery)'),
  NotifType('alumno_inactivo', 'ALUMNOS', 'Alumno inactivo'),
  NotifType('comida_pendiente', 'ALUMNOS', 'Comida pendiente de revisar'),
  NotifType('mensaje_nuevo', 'CHAT', 'Mensaje nuevo'),
];

/// Preferencias de notificación: matriz `tipo -> canal -> bool`.
///
/// Inmutable; `toggle` devuelve una copia. `fromFirestore` completa los huecos
/// con los defaults para que la UI siempre tenga las 5 filas × 3 canales.
class NotifPrefs {
  const NotifPrefs(this._matrix);

  final Map<String, Map<NotifChannel, bool>> _matrix;

  bool isOn(String typeKey, NotifChannel ch) =>
      _matrix[typeKey]?[ch] ?? _defaultFor(typeKey, ch);

  NotifPrefs toggle(String typeKey, NotifChannel ch, bool value) {
    final copy = {
      for (final t in kNotifTypes)
        t.key: {
          for (final c in NotifChannel.values) c: isOn(t.key, c),
        },
    };
    copy[typeKey]![ch] = value;
    return NotifPrefs(copy);
  }

  Map<String, dynamic> toFirestore() => {
        for (final t in kNotifTypes)
          t.key: {
            for (final c in NotifChannel.values) c.name: isOn(t.key, c),
          },
      };

  factory NotifPrefs.fromFirestore(Map<String, dynamic>? raw) {
    return NotifPrefs({
      for (final t in kNotifTypes)
        t.key: {
          for (final c in NotifChannel.values)
            c: ((raw?[t.key] as Map?)?[c.name] as bool?) ??
                _defaultFor(t.key, c),
        },
    });
  }

  /// Defaults sensatos: push siempre on; email on para pago y chat; whatsapp
  /// off (todavía sin canal real).
  static bool _defaultFor(String typeKey, NotifChannel ch) {
    switch (ch) {
      case NotifChannel.push:
        return true;
      case NotifChannel.email:
        return typeKey == 'pago_recibido' || typeKey == 'mensaje_nuevo';
      case NotifChannel.whatsapp:
        return false;
    }
  }
}

/// Stream de las preferencias del PF logueado, leídas del campo crudo
/// `users/{uid}.notificationPrefs` (no pasa por `UserProfile` para no tocar el
/// modelo). Nuevo provider de W3.2 (plan: `webNotificationPreferencesProvider`).
final webNotificationPreferencesProvider = StreamProvider<NotifPrefs>((ref) {
  final uid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
  if (uid == null) {
    return Stream<NotifPrefs>.value(NotifPrefs.fromFirestore(null));
  }
  final fs = ref.watch(firestoreProvider);
  return fs.collection('users').doc(uid).snapshots().map(
        (snap) => NotifPrefs.fromFirestore(
          snap.data()?['notificationPrefs'] as Map<String, dynamic>?,
        ),
      );
});
