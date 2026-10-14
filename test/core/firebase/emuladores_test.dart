// `esUrlDeDescargaDelEmuladorDeStorage` abre los gates de "¿esto es Storage?"
// a las URLs del emulador. Estos tests fijan que los abre SÓLO en modo
// emulador y SÓLO para la forma exacta de esas URLs: sin `USE_EMULATOR` no
// cambia nada, y con `USE_EMULATOR` un host, puerto, esquema o path distinto
// sigue afuera.
//
// `flutter test` corre sin `USE_EMULATOR`, así que el default de estos tests
// es justamente el de un build normal. El modo emulador se prende con
// `debugUsaEmuladoresOverride`, que cada test vuelve a `null`.
//
// El corte de release se traba pasando `release: true`, porque bajo
// `flutter test` común `kReleaseMode` es `false`. Que el default de ese
// parámetro sea `kReleaseMode` se ve corriendo este archivo con
// `--dart-define=dart.vm.product=true`: los tests que aceptan la URL se ponen
// rojos (medido), que es lo que tiene que pasar en release.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/firebase/emuladores.dart';

const _delEmulador = 'http://localhost:9199/v0/b/treino-dev.firebasestorage.app'
    '/o/customExerciseVideos%2Fuid%2Fclip.mp4?alt=media&token=t';

bool _acepta(String url) => esUrlDeDescargaDelEmuladorDeStorage(Uri.parse(url));

void _modoEmulador(bool valor) {
  debugUsaEmuladoresOverride = valor;
  addTearDown(() => debugUsaEmuladoresOverride = null);
}

void main() {
  group('sin USE_EMULATOR (el build de todos los días)', () {
    test('la URL del emulador NO cuenta como de Storage', () {
      expect(kUsaEmuladores, isFalse,
          reason: 'flutter test corre sin --dart-define=USE_EMULATOR');
      expect(_acepta(_delEmulador), isFalse);
    });

    test('con el override en false, tampoco', () {
      _modoEmulador(false);
      expect(_acepta(_delEmulador), isFalse);
    });
  });

  group('con USE_EMULATOR', () {
    test('acepta los tres hosts con los que el emulador arma sus URLs', () {
      _modoEmulador(true);
      for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
        expect(
          _acepta(_delEmulador.replaceFirst('localhost', host)),
          isTrue,
          reason: host,
        );
      }
    });

    test('en release no acepta nada, ni con el override prendido', () {
      _modoEmulador(true);
      expect(
        esUrlDeDescargaDelEmuladorDeStorage(Uri.parse(_delEmulador),
            release: true),
        isFalse,
      );
    });

    test('un escape que no es UTF-8 da false, no una excepción', () {
      // En modo emulador le llega todo lo que el PF tipea en el editor; si
      // tirara, la pantalla se pone roja en cada tecla.
      _modoEmulador(true);
      expect(_acepta('http://localhost:9199/v0/b/bkt/o/%FF'), isFalse);
      expect(_acepta('https://example.com/%FF'), isFalse);
    });

    test('rechaza cualquier otro host, aunque se parezca', () {
      _modoEmulador(true);
      for (final url in [
        'http://evil.test:9199/v0/b/bkt/o/x.mp4',
        'http://localhost.attacker.test:9199/v0/b/bkt/o/x.mp4',
        // userinfo: el host real es attacker.test.
        'http://localhost:9199@attacker.test/v0/b/bkt/o/x.mp4',
        'http://192.168.0.10:9199/v0/b/bkt/o/x.mp4',
      ]) {
        expect(_acepta(url), isFalse, reason: url);
      }
    });

    test('rechaza otro puerto o ninguno', () {
      _modoEmulador(true);
      expect(_acepta(_delEmulador.replaceFirst(':9199', ':8080')), isFalse);
      expect(_acepta(_delEmulador.replaceFirst(':9199', '')), isFalse);
    });

    test('rechaza https: el emulador sólo habla http', () {
      _modoEmulador(true);
      expect(_acepta(_delEmulador.replaceFirst('http:', 'https:')), isFalse);
    });

    test('rechaza un path que no es /v0/b/<bucket>/o/<objeto>', () {
      _modoEmulador(true);
      for (final url in [
        'http://localhost:9199/x.mp4',
        'http://localhost:9199/v0/b/bkt/o',
        'http://localhost:9199/v1/b/bkt/o/x.mp4',
        'http://localhost:9199/v0/x/bkt/o/x.mp4',
        'http://localhost:9199/v0/b/bkt/x/x.mp4',
      ]) {
        expect(_acepta(url), isFalse, reason: url);
      }
    });
  });
}
