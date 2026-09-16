import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Espejo a mano de `NotificationKind` en
/// `functions/src/notifications/send-fcm.ts`, que es la **fuente de verdad**:
/// el backend es quien emite el `kind` que se persiste en el historial y acá
/// sólo se lee.
///
/// Las dos listas se mantienen a mano y no hay nada en ninguno de los dos
/// lenguajes que las ate, así que van a divergir. Ya pasó: `discomfort` y
/// `monthly-report` vivieron meses del lado TypeScript y no acá, y **no se
/// notó** porque hoy nada de la UI ramifica por este valor — un kind
/// desconocido cae en [unknown] por el `orElse` de [fromJson] y ninguna
/// pantalla cambia. El día que alguna empiece a ramificar, esa deriva
/// silenciosa se vuelve un bug de producto.
///
/// Lo que cierra el agujero es
/// `test/conformance/notification_kind_parity_test.dart`: lee el `.ts` y se
/// pone rojo apenas una de las dos listas se mueve sin la otra. Si agregás un
/// valor acá, agregalo allá — y si te olvidás, el test te avisa en vez de
/// dejarlo pasar.
///
/// [unknown] es el único valor sin contraparte en TypeScript, y es a
/// propósito: es el centinela del `orElse`, no un kind que el backend emita.
enum NotificationKind {
  appointment('appointment'),
  chatMessage('chat-message'),
  discomfort('discomfort'),
  friendAccepted('friend-accepted'),
  friendFollow('friend-follow'),
  friendRequest('friend-request'),
  linkChange('link-change'),
  monthlyReport('monthly-report'),
  overduePayment('overdue-payment'),
  reaction('reaction'),
  review('review'),
  sessionFinished('session-finished'),
  unknown('unknown');

  const NotificationKind(this.value);

  final String value;

  static NotificationKind fromJson(Object? value) => values.firstWhere(
        (kind) => kind.value == value,
        orElse: () => NotificationKind.unknown,
      );
}

class NotificationHistoryItem {
  const NotificationHistoryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.createdAt,
    this.actorUid,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final String deepLink;
  final DateTime createdAt;
  final String? actorUid;

  factory NotificationHistoryItem.fromJson(
    Map<String, Object?> json, {
    required String id,
  }) {
    final rawCreatedAt = json['createdAt'];
    return NotificationHistoryItem(
      id: id,
      kind: NotificationKind.fromJson(json['kind']),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      deepLink: json['deepLink'] as String? ?? '',
      createdAt: rawCreatedAt is Timestamp
          ? rawCreatedAt.toDate()
          : rawCreatedAt is DateTime
              ? rawCreatedAt
              : DateTime.fromMillisecondsSinceEpoch(0),
      actorUid: json['actorUid'] as String?,
    );
  }
}
