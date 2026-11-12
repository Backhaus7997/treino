// #1692: en web, con `USE_EMULATOR=true`, Auth volvía a PRODUCCIÓN después de
// recargar con una sesión persistida, y el siguiente login mandaba la
// contraseña a `identitytoolkit.googleapis.com`.
//
// Se defiende en dos capas, y estos tests fijan lo que se puede probar en la VM:
//   1. `exigirAuthEnElEmulador`: la decisión de "Auth quedó en el emulador, sí
//      o no", que frena la app si no. Pura, sin navegador ni Firebase.
//   2. `limpiarSesionDeAuthParaEmulador`: que la prevención corra SÓLO en modo
//      emulador.
//
// Lo que NO se prueba acá, porque necesita un navegador: el borrado real de
// IndexedDB y la lectura de `auth.emulatorConfig` (`auth_emulador_web.dart`,
// `dart:js_interop`). Eso se confirma a mano; los pasos están en el PR.
//
// El orden de las llamadas en los entry points, y que la verificación siga
// dentro de `conectarEmuladores()`, los fija
// `test/app/guards/emuladores_scan_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/firebase/auth_emulador_guard.dart';
import 'package:treino/core/firebase/emuladores.dart';

const _host = 'localhost';
const _puerto = kPuertoEmuladorAuth;

void _modoEmulador(bool valor) {
  debugUsaEmuladoresOverride = valor;
  addTearDown(() => debugUsaEmuladoresOverride = null);
}

void main() {
  group('exigirAuthEnElEmulador', () {
    test('Auth en el emulador esperado: no tira', () {
      expect(
        () => exigirAuthEnElEmulador(
          configurado: (host: _host, port: _puerto),
          host: _host,
          port: _puerto,
        ),
        returnsNormally,
      );
    });

    test('Auth sin emulador (producción): tira y lo dice', () {
      // Es el caso del #1692: `useAuthEmulator` vuelve bien y Auth sigue en
      // producción, o sea `emulatorConfig == null`.
      expect(
        () => exigirAuthEnElEmulador(
          configurado: null,
          host: _host,
          port: _puerto,
        ),
        throwsA(
          isA<AuthFueraDelEmuladorError>()
              .having((e) => e.mensaje, 'mensaje', contains('PRODUCCIÓN')),
        ),
      );
    });

    test('Auth en otro host: tira', () {
      expect(
        () => exigirAuthEnElEmulador(
          configurado: (host: '192.168.0.10', port: _puerto),
          host: _host,
          port: _puerto,
        ),
        throwsA(isA<AuthFueraDelEmuladorError>()),
      );
    });

    test('Auth en otro puerto: tira', () {
      expect(
        () => exigirAuthEnElEmulador(
          configurado: (host: _host, port: 9098),
          host: _host,
          port: _puerto,
        ),
        throwsA(isA<AuthFueraDelEmuladorError>()),
      );
    });

    test('Auth sin puerto: tira (no es el emulador esperado)', () {
      expect(
        () => exigirAuthEnElEmulador(
          configurado: (host: _host, port: null),
          host: _host,
          port: _puerto,
        ),
        throwsA(isA<AuthFueraDelEmuladorError>()),
      );
    });

    test('es un Error y no una Exception: no hay nada que atrapar', () {
      // Un `catch (Exception)` de alguna capa de arriba no la puede tragar.
      expect(AuthFueraDelEmuladorError('x'), isA<Error>());
      expect(AuthFueraDelEmuladorError('x'), isNot(isA<Exception>()));
    });
  });

  group('limpiarSesionDeAuthParaEmulador', () {
    test('sin USE_EMULATOR (el build de todos los días) no borra nada',
        () async {
      expect(kUsaEmuladores, isFalse,
          reason: 'flutter test corre sin --dart-define=USE_EMULATOR');
      var borrados = 0;
      await limpiarSesionDeAuthParaEmulador(borrar: () async => borrados++);
      expect(borrados, 0);
    });

    test('con el override en false, tampoco', () async {
      _modoEmulador(false);
      var borrados = 0;
      await limpiarSesionDeAuthParaEmulador(borrar: () async => borrados++);
      expect(borrados, 0);
    });

    test('con USE_EMULATOR borra, una sola vez', () async {
      _modoEmulador(true);
      var borrados = 0;
      await limpiarSesionDeAuthParaEmulador(borrar: () async => borrados++);
      expect(borrados, 1);
    });

    test('con USE_EMULATOR, si no pudo borrar la app frena: no se la traga',
        () async {
      // Seguir con la sesión sin borrar es dejar que el SDK la restaure contra
      // producción.
      _modoEmulador(true);
      await expectLater(
        limpiarSesionDeAuthParaEmulador(
          borrar: () async => throw AuthFueraDelEmuladorError('no pude'),
        ),
        throwsA(isA<AuthFueraDelEmuladorError>()),
      );
    });

    test('esperar la llamada es esperar el borrado (va antes de initializeApp)',
        () async {
      _modoEmulador(true);
      final pasos = <String>[];
      await limpiarSesionDeAuthParaEmulador(borrar: () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        pasos.add('borrado');
      });
      pasos.add('initializeApp');
      expect(pasos, ['borrado', 'initializeApp']);
    });

    test('el default (fuera de web) es un no-op que no tira', () async {
      // En la VM el conditional import resuelve al stub: no hay navegador.
      _modoEmulador(true);
      await expectLater(limpiarSesionDeAuthParaEmulador(), completes);
    });
  });
}
