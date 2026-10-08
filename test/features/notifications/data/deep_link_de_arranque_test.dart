// El deep link de la notificación LOCAL que abrió la app (plan del PF §5.2).
//
// El callback de `init` —`onDidReceiveNotificationResponse`— sólo corre con la
// app VIVA. Tocar un aviso local con la app cerrada la ARRANCA, ese callback no
// se dispara nunca, y el tap se perdía entero: el usuario aterrizaba en la
// pantalla de inicio en vez de donde el aviso prometía. Y es el caso más
// común, no el raro — una notificación se toca justamente cuando no estabas
// usando la app.
//
// `getInitialMessage()` de FCM cubría sólo la mitad: la de los avisos de
// background que dibuja el SDK nativo. Las locales no tenían equivalente.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/notifications/data/local_notifications_service.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

NotificationResponse _respuesta(String? payload) => NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: payload,
    );

void main() {
  late _MockPlugin plugin;
  late LocalNotificationsService service;

  setUp(() {
    plugin = _MockPlugin();
    service = LocalNotificationsService(plugin: plugin);
  });

  void arranque(NotificationAppLaunchDetails? detalles) {
    when(() => plugin.getNotificationAppLaunchDetails())
        .thenAnswer((_) async => detalles);
  }

  test('devuelve el payload cuando la app la abrió una notificación', () async {
    arranque(NotificationAppLaunchDetails(
      true,
      notificationResponse: _respuesta('/coach/athlete/a1/session/s1'),
    ));

    expect(
      await service.deepLinkDeArranque(),
      '/coach/athlete/a1/session/s1',
    );
  });

  // El control negativo del de arriba. Sin éste, un método que devolviera el
  // payload SIEMPRE —sin mirar `didNotificationLaunchApp`— pasaría aquel test
  // igual de bien, y en producción mandaría al usuario a un aviso viejo cada
  // vez que abre la app a mano.
  test('devuelve null en un arranque normal, aunque haya payload viejo',
      () async {
    arranque(NotificationAppLaunchDetails(
      false,
      notificationResponse: _respuesta('/coach/athlete/a1/session/viejo'),
    ));

    expect(await service.deepLinkDeArranque(), isNull);
  });

  test('devuelve null si la plataforma no informa nada', () async {
    arranque(null);

    expect(await service.deepLinkDeArranque(), isNull);
  });

  // Un fallo del canal nativo tiene que dejar el arranque como estaba ANTES de
  // que este método existiera —o sea, normal— y no tumbar la app en el primer
  // frame por un deep link que es una mejora, no un requisito.
  test('un fallo del canal nativo devuelve null y no propaga', () async {
    when(() => plugin.getNotificationAppLaunchDetails())
        .thenThrow(Exception('MissingPluginException'));

    expect(await service.deepLinkDeArranque(), isNull);
  });
}
