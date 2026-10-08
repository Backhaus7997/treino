import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/notifications/application/notification_router.dart';

/// Forma real del deep link de chat, la que arma `notify-chat-message.ts`.
String chatDeepLink({String chatId = 'chat-1', String sender = 'uid-pf'}) =>
    '/coach/chat/$chatId?other=$sender';

void main() {
  group('shouldSuppressForegroundNotification', () {
    test('en otra pantalla: se notifica', () {
      expect(
        shouldSuppressForegroundNotification(
          currentLocation: '/home',
          deepLink: chatDeepLink(),
        ),
        isFalse,
      );
    });

    test('en el MISMO chat al que apunta el link: no se notifica', () {
      expect(
        shouldSuppressForegroundNotification(
          currentLocation: chatDeepLink(),
          deepLink: chatDeepLink(),
        ),
        isTrue,
      );
    });

    test('en OTRO chat: se notifica', () {
      expect(
        shouldSuppressForegroundNotification(
          currentLocation: chatDeepLink(chatId: 'chat-2'),
          deepLink: chatDeepLink(chatId: 'chat-1'),
        ),
        isFalse,
      );
    });

    test('mismo chat con query distinta: igual se suprime (se compara el path)',
        () {
      expect(
        shouldSuppressForegroundNotification(
          currentLocation: '/coach/chat/chat-1',
          deepLink: chatDeepLink(chatId: 'chat-1'),
        ),
        isTrue,
      );
    });

    test('en el centro de notificaciones: no se notifica NINGUNA', () {
      for (final link in [
        chatDeepLink(),
        '/feed/post/p1',
        '/coach',
        null,
      ]) {
        expect(
          shouldSuppressForegroundNotification(
            currentLocation: kCentroDeNotificaciones,
            deepLink: link,
          ),
          isTrue,
          reason: 'deepLink $link debería suprimirse en el centro',
        );
      }
    });

    test('el centro de notificaciones matchea por path, no por prefijo', () {
      // `/feed/notifications-algo` NO es el centro.
      expect(
        shouldSuppressForegroundNotification(
          currentLocation: '/feed/notificationes-viejas',
          deepLink: chatDeepLink(),
        ),
        isFalse,
      );
    });

    group('falla ABIERTA — ante la duda, se notifica', () {
      test('location nula', () {
        expect(
          shouldSuppressForegroundNotification(
            currentLocation: null,
            deepLink: chatDeepLink(),
          ),
          isFalse,
        );
      });

      test('location vacía', () {
        expect(
          shouldSuppressForegroundNotification(
            currentLocation: '',
            deepLink: chatDeepLink(),
          ),
          isFalse,
        );
      });

      test('deepLink nulo estando fuera del centro', () {
        expect(
          shouldSuppressForegroundNotification(
            currentLocation: '/home',
            deepLink: null,
          ),
          isFalse,
        );
      });
    });

    group('NO se generaliza a "mismo path ⇒ suprimir"', () {
      test('parado en /coach, un cambio de vínculo (deepLink /coach) SÍ avisa',
          () {
        // Es el caso que hace que la regla amplia sea peligrosa: `/coach` es
        // una tab entera. Estar ahí no es haber visto que un alumno te aceptó.
        expect(
          shouldSuppressForegroundNotification(
            currentLocation: '/coach',
            deepLink: '/coach',
          ),
          isFalse,
        );
      });

      test('parado en un post, una reacción a ESE post SÍ avisa', () {
        expect(
          shouldSuppressForegroundNotification(
            currentLocation: '/feed/post/p1',
            deepLink: '/feed/post/p1',
          ),
          isFalse,
        );
      });
    });
  });
}
