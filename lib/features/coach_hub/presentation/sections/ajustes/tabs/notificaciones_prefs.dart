import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';

/// Canales de entrega de notificaciones del Coach Hub.
///
/// ESTADO REAL DE CADA CANAL (mantener sincronizado con `functions/`):
///
/// - `push`   — implementado (FCM). Las CFs mandan SIEMPRE, sin leer estas
///              preferencias todavía. Ese es el follow-up pendiente del canal.
/// - `email`  — implementado para los dos tipos que el outbox transaccional
///              cubre hoy: `nueva_solicitud` y `sesion_cancelada`. Esos dos SÍ
///              respetan el toggle: `enqueueMail` recibe el `prefKey` y
///              `sendQueuedMail` descarta el envío si el canal está apagado.
///              El resto de las filas no tienen envío por email.
/// - `whatsapp` — sin implementar. Queda como placeholder de roadmap y arranca
///              apagado en todas las filas, así no promete nada.
///
/// Las preferencias se persisten en `users/{uid}.notificationPrefs`, un campo
/// libremente escribible por el dueño del doc (`firestore.rules`, regla update
/// de `users`: solo pinea uid/role/email/createdAt/subscription/weightedLoad).
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

/// Tipos de aviso que el PF puede configurar.
///
/// REGLA: cada fila de esta lista tiene que corresponder a una notificación que
/// REALMENTE se dispara hacia el entrenador. Una fila sin Cloud Function detrás
/// es una promesa que el producto no cumple — el usuario apaga algo que nunca
/// estuvo prendido, o deja prendido algo que nunca va a llegar.
///
/// El mockup original (`notificaciones.png`) traía tres filas sin backend
/// alguno: `pago_recibido`, `alumno_inactivo` y `comida_pendiente`. Ninguna
/// tenía CF y se quitaron. Si alguna de esas features aterriza, se vuelven a
/// agregar JUNTO con su trigger, no antes.
///
/// Trazabilidad fila → Cloud Function (`functions/src/`):
///   nueva_solicitud    → notifications/notify-link-change.ts, rama `pending`
///   vinculo_finalizado → notifications/notify-link-change.ts, rama `terminated`
///   resena_nueva       → notifications/notify-review.ts
///   sesion_cancelada   → notifications/notify-appointment.ts, rama `cancelled`
///   mensaje_nuevo      → notifications/notify-chat-message.ts
const kNotifTypes = <NotifType>[
  NotifType('nueva_solicitud', 'ALUMNOS', 'Nueva solicitud de vinculación'),
  NotifType('vinculo_finalizado', 'ALUMNOS', 'Vínculo finalizado'),
  NotifType('resena_nueva', 'ALUMNOS', 'Reseña nueva'), // i18n: Fase W3
  NotifType('sesion_cancelada', 'AGENDA', 'Sesión cancelada'),
  NotifType('mensaje_nuevo', 'CHAT', 'Mensaje nuevo'),
];

/// Filas cuyo canal `email` tiene envío real detrás (outbox transaccional).
///
/// El valor tiene que coincidir con el `prefKey` que pasan los productores en
/// `functions/src/notifications/`. Si agregás un mail nuevo con `prefKey`,
/// sumá la clave acá también.
const kEmailBackedTypes = <String>{'nueva_solicitud', 'sesion_cancelada'};

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

  /// Defaults: push siempre on; email on SOLO donde hay envío real; whatsapp
  /// off en todo (sin canal implementado).
  ///
  /// El default anterior dejaba `mensaje_nuevo` con email en ON. Eso era una
  /// bomba de tiempo: el día que alguien conectara la matriz al backend, cada
  /// mensaje de chat se convertía en un mail. Volumen de chat por email =
  /// denuncias de spam = reputación de remitente quemada, que es lo único que
  /// no se recupera rápido. El chat se queda en push, a propósito.
  static bool _defaultFor(String typeKey, NotifChannel ch) {
    switch (ch) {
      case NotifChannel.push:
        return true;
      case NotifChannel.email:
        return kEmailBackedTypes.contains(typeKey);
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
