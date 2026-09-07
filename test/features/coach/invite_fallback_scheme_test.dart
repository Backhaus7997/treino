import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/invite_capture.dart';

/// El rescate del link de invitación cuando iOS no lo entrega.
///
/// Un universal link NO dispara cuando se toca dentro del navegador embebido
/// de otra app —WhatsApp usa `SFSafariViewController`, y ahí iOS entrega la
/// URL al navegador, no a TREINO—. Verificado en un iPhone 16 real: la app
/// procesa el link perfecto cuando se lo pasás directo, y no lo recibe nunca
/// cuando el link se toca desde WhatsApp.
///
/// Quien cae en ese caso aterriza en `/abrir/alumno`. Desde ahí un link al
/// mismo dominio tampoco sirve: iOS ignora los universal links cuando la
/// navegación sale de una página del propio dominio. La única salida es un
/// esquema propio.
void main() {
  final raiz = Directory.current.path;

  group('Esquema treino:// registrado —', () {
    test('iOS lo declara en Info.plist', () {
      final plist = File('$raiz/ios/Runner/Info.plist').readAsStringSync();
      expect(
        plist.contains('<string>treino</string>'),
        isTrue,
        reason: 'sin el esquema en CFBundleURLSchemes, el botón de la página '
            'de fallback no abre nada',
      );
    });

    test('Android lo declara en el manifest', () {
      final manifest =
          File('$raiz/android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(
        manifest.contains('android:scheme="treino"'),
        isTrue,
        reason: 'el navegador interno de Android tiene el mismo problema que '
            'el de iOS',
      );
    });
  });

  group('Página de fallback —', () {
    for (final pagina in ['alumno', 'profe']) {
      test('$pagina.html ofrece abrir la app por el esquema propio', () {
        final html = File('$raiz/web/abrir/$pagina.html').readAsStringSync();
        expect(
          html.contains('treino://'),
          isTrue,
          reason: 'quien llega acá desde un navegador embebido TIENE la app: '
              'necesita un botón que la abra, no un texto que le diga que '
              'ya falló',
        );
        expect(
          html.contains('location.search'),
          isTrue,
          reason: 'el botón tiene que arrastrar la query original — sin '
              '`?to=invitacion&pf=X` abre la app pero pierde la invitación, '
              'que es exactamente el bug que vino a resolver',
        );
      });
    }
  });

  group('La captura no depende del esquema —', () {
    test('una invitación por treino:// se parsea igual que por https',
        () {
      const query = 'to=invitacion&pf=PF123';
      expect(
        trainerIdDeInvitacion(Uri.parse('treino:///abrir/alumno?$query')),
        'PF123',
      );
      expect(
        trainerIdDeInvitacion(
            Uri.parse('https://app.gettreino.com/abrir/alumno?$query')),
        'PF123',
      );
    });
  });
}
