// Guard estructural: `USE_EMULATOR=true` tiene que mandar TODO al emulador.
//
// Cada entry point conectaba los emuladores a mano, y se desincronizaron:
// `main.dart` redirigía Firestore, Auth y Functions; `main_coach_hub.dart` sólo
// Firestore y Auth; ninguno Storage. Lo encontró la QA E2E del 2026-10-14: el
// Coach Hub "contra el emulador" llamaba a `acceptTrainerLink`,
// `reconcileMyCheckout` y `createPreapproval` de PRODUCCIÓN, y las subidas de
// archivos de las dos superficies iban al bucket real. Probar en local tocaba
// prod sin que nada lo dijera.
//
// La conexión vive ahora en UNA función, `conectarEmuladores()`, y estos tests
// fijan las tres cosas que la mantienen honesta:
//   1. la función redirige los cuatro servicios;
//   2. los dos entry points la usan, y ninguno conecta un emulador a mano;
//   3. ningún callable usa una región que la función no redirige — ni la
//      instancia default (`us-central1`).
//
// Es un scan y no un test que corra la app porque lo que se protege no se ve:
// una app que llama a producción y una que llama al emulador se ven idénticas
// hasta que algo escribe donde no debía. Mismo criterio que
// `analytics_consent_scan_test`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _emuladores = 'lib/core/firebase/emuladores.dart';
const _entryPoints = ['lib/main.dart', 'lib/main_coach_hub.dart'];

void main() {
  List<File> dartDeLib() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String norm(String path) => path.replaceAll(r'\', '/');

  test('conectarEmuladores() redirige los cuatro servicios', () {
    final src = File(_emuladores).readAsStringSync();
    for (final llamada in [
      'useFirestoreEmulator(',
      'useAuthEmulator(',
      'useFunctionsEmulator(',
      'useStorageEmulator(',
    ]) {
      expect(
        src,
        contains(llamada),
        reason: '$_emuladores no llama a $llamada: ese servicio sale a '
            'PRODUCCIÓN aunque la app corra con USE_EMULATOR=true',
      );
    }
  });

  test('Storage se conecta en el puerto que acepta el gate de videos', () {
    // `esUrlDeDescargaDelEmuladorDeStorage` acepta las URLs del emulador sólo
    // en `kPuertoEmuladorStorage`. Si `conectarEmuladores()` vuelve a un
    // literal y alguien lo cambia, la app sube a un puerto y el gate espera
    // otro: los videos del emulador dejan de reproducir sin que nada falle.
    final src = File(_emuladores).readAsStringSync();
    expect(
      RegExp(r"useStorageEmulator\(\s*'localhost',\s*kPuertoEmuladorStorage\s*\)")
          .hasMatch(src),
      isTrue,
      reason: '$_emuladores tiene que conectar Storage con '
          "useStorageEmulator('localhost', kPuertoEmuladorStorage)",
    );
  });

  test('los dos entry points usan conectarEmuladores() y no conectan a mano',
      () {
    final aMano = RegExp(r'use(Firestore|Auth|Functions|Storage)Emulator\(');
    for (final entry in _entryPoints) {
      final src = File(entry).readAsStringSync();
      expect(
        src,
        contains('conectarEmuladores()'),
        reason: '$entry no llama a conectarEmuladores(): en modo emulador '
            'quedaría hablando con producción',
      );
      expect(
        aMano.hasMatch(src),
        isFalse,
        reason: '$entry conecta un emulador a mano. Así se desincronizaron: '
            'agregalo en $_emuladores, que lo usan los dos',
      );
    }
  });

  // --- #1692: Auth en web volvía a PRODUCCIÓN después de recargar -----------
  //
  // `firebase_auth_web` restaura la sesión persistida por red dentro de
  // `Firebase.initializeApp`, antes de que `useAuthEmulator` pueda correr, y
  // desde ese request el emulador ya no se puede conectar (el plugin traga el
  // error). Se defiende en dos capas, y lo que se puede probar en la VM es QUÉ
  // se llama y EN QUÉ ORDEN: el borrado en el navegador (`dart:js_interop`) no
  // corre acá.
  //
  // Sin los comentarios: los dartdocs y los comentarios de los entry points
  // nombran `Firebase.initializeApp` y estas funciones a propósito.
  String sinComentarios(String src) =>
      src.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  test('los dos entry points borran la sesión de Auth ANTES de initializeApp',
      () {
    for (final entry in _entryPoints) {
      final src = sinComentarios(File(entry).readAsStringSync());
      final borrar = src.indexOf('limpiarSesionDeAuthParaEmulador()');
      final init = src.indexOf('Firebase.initializeApp(');
      expect(borrar, isNonNegative,
          reason: '$entry no llama a limpiarSesionDeAuthParaEmulador(): en '
              'web, con USE_EMULATOR, Auth restaura la sesión contra '
              'PRODUCCIÓN y el login manda la contraseña ahí (#1692)');
      expect(init, isNonNegative, reason: '$entry no inicializa Firebase');
      expect(
        borrar,
        lessThan(init),
        reason: '$entry borra la sesión DESPUÉS de Firebase.initializeApp: '
            'tarde, el plugin ya la restauró por red (#1692)',
      );
    }
  });

  test('el borrado y la conexión de emuladores corren sólo con USE_EMULATOR',
      () {
    // `kUsaEmuladores` es const: con el `if` pegado a la llamada, el compilador
    // la poda y un build normal no lleva nada de esto (ni el borrado de
    // IndexedDB, ni la verificación). Una llamada suelta corre siempre.
    for (final entry in _entryPoints) {
      final src = sinComentarios(File(entry).readAsStringSync());
      for (final llamada in [
        'limpiarSesionDeAuthParaEmulador',
        'conectarEmuladores',
      ]) {
        final guardada = RegExp(
          r'if\s*\(\s*kUsaEmuladores\s*\)\s*\{\s*await\s+'
          '$llamada'
          r'\(\)\s*;\s*\}',
        );
        expect(
          guardada.hasMatch(src),
          isTrue,
          reason: '$entry: $llamada() tiene que ir sola dentro de '
              'if (kUsaEmuladores) { … }. Si corre sin USE_EMULATOR, un '
              'build normal borra la sesión o toca los emuladores',
        );
        expect(
          RegExp('$llamada\\(').allMatches(src).length,
          1,
          reason: '$entry llama a $llamada() más de una vez: alguna puede '
              'estar fuera del if (kUsaEmuladores)',
        );
      }
    }
  });

  test('conectarEmuladores() verifica Auth DESPUÉS de useAuthEmulator', () {
    // `await useAuthEmulator(...)` vuelve bien aunque haya fallado: el plugin
    // web traga `auth/emulator-config-failed`. Sin esta verificación Auth se
    // queda en PRODUCCIÓN sin que nada lo diga.
    final src = sinComentarios(File(_emuladores).readAsStringSync());
    final inicio = src.indexOf('Future<void> conectarEmuladores()');
    expect(inicio, isNonNegative);
    final cuerpo = src.substring(inicio, src.indexOf('\n}', inicio));
    final conecta = cuerpo.indexOf('useAuthEmulator(');
    final verifica = cuerpo.indexOf('verificarAuthEnElEmulador(');
    expect(conecta, isNonNegative);
    expect(verifica, isNonNegative,
        reason: 'conectarEmuladores() no verifica que Auth quedó en el '
            'emulador (#1692)');
    expect(verifica, greaterThan(conecta));
  });

  test('el stub y la implementación web declaran la misma API', () {
    // `emuladores.dart` los elige con un conditional import: el analyzer y los
    // tests de la VM sólo ven el stub, así que una firma que diverge en el
    // archivo web rompería recién `flutter build web`.
    for (final archivo in [
      'lib/core/firebase/auth_emulador_stub.dart',
      'lib/core/firebase/auth_emulador_web.dart',
    ]) {
      final src = File(archivo).readAsStringSync();
      expect(src, contains('Future<void> borrarSesionPersistidaDeAuth()'),
          reason: archivo);
      expect(src,
          contains('void verificarAuthEnElEmulador(String host, int port)'),
          reason: archivo);
    }
    expect(
      File(_emuladores).readAsStringSync(),
      contains("if (dart.library.js_interop) 'auth_emulador_web.dart'"),
    );
  });

  test('todo callable usa la región que conectarEmuladores() redirige', () {
    final redirigida = RegExp(r"kFunctionsRegion\s*=\s*'([^']+)'")
        .firstMatch(File(_emuladores).readAsStringSync())
        ?.group(1);
    expect(redirigida, isNotNull,
        reason: '$_emuladores tiene que declarar kFunctionsRegion');

    // Regiones escritas en el código: literales en `region: '…'` y constantes
    // `…Region = '…'`. Si aparece otra, sus callables esquivan el redirect.
    final literal = RegExp(r"region:\s*'([^']+)'");
    final constante = RegExp(r"[rR]egion\s*=\s*'([^']+)'");
    // `FirebaseFunctions.instance` es `us-central1`, que el redirect no toca.
    final instanciaDefault = RegExp(r'FirebaseFunctions\.instance\b(?!For)');

    // Sin las líneas de comentario: el dartdoc de `emuladores.dart` explica
    // justamente que `FirebaseFunctions.instance` es `us-central1`, y un guard
    // que grita por un comentario termina ignorado.
    final comentario = RegExp(r'^\s*//.*$', multiLine: true);

    final ajenas = <String>[];
    for (final f in dartDeLib()) {
      final src = f.readAsStringSync().replaceAll(comentario, '');
      for (final m in [
        ...literal.allMatches(src),
        ...constante.allMatches(src)
      ]) {
        if (m.group(1) != redirigida)
          ajenas.add('${norm(f.path)}: ${m.group(1)}');
      }
      if (instanciaDefault.hasMatch(src)) {
        ajenas.add('${norm(f.path)}: FirebaseFunctions.instance (us-central1)');
      }
    }

    expect(
      ajenas,
      isEmpty,
      reason: 'estos callables usan una región que conectarEmuladores() no '
          'redirige ($redirigida), así que en modo emulador salen a '
          'PRODUCCIÓN: ${ajenas.join(", ")}',
    );
  });
}
