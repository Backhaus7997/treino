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
