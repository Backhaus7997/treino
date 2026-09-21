// Guard estructural: la analítica no se puede volver a encender a la fuerza.
//
// Hasta el 2026-09-21 los dos entry points hacían
// `setAnalyticsCollectionEnabled(true)` fijo, mientras la Política de
// Privacidad le prometía al usuario poder revocar el consentimiento «en
// cualquier momento». El documento se acepta al crear la cuenta, así que era
// una promesa publicada sobre un control que no existía.
//
// El arreglo es una línea, y por eso mismo se revierte solo: cualquiera que
// debuggee analítica va a querer forzarla en `true` «un rato» y el rato se
// queda. Este test mira el código fuente porque el invariante no se puede
// observar corriendo la app: una app con la analítica prendida y una con el
// default prendido se ven idénticas.
//
// Mismo criterio que `no_hex_scan_test` y `storage_scripts_destination`:
// cuando la garantía vive en una línea que nadie mira, el test tiene que
// mirarla.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  List<File> dartDeLib() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('ningún archivo enciende la analítica con un literal', () {
    final literal = RegExp(
      r'setAnalyticsCollectionEnabled\(\s*(true|false)\s*\)',
    );

    final culpables = dartDeLib()
        .where((f) => literal.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();

    expect(
      culpables,
      isEmpty,
      reason: 'pasan un literal a setAnalyticsCollectionEnabled en vez del '
          'consentimiento del usuario. La Política promete que se puede '
          'revocar en cualquier momento, y un literal lo ignora: '
          '${culpables.join(", ")}',
    );
  });

  test('las DOS vistas de perfil llevan al interruptor', () {
    // `ProfileScreen` reparte por rol: el atleta ve `_AthleteProfile` y el
    // entrenador ve `TrainerProfileView`, que son dos arboles distintos. Poner
    // la entrada en uno solo deja a la mitad de los usuarios sin forma de
    // revocar en el telefono — y encima el tab de Privacidad del Coach Hub les
    // dice que «en el telefono se configura aparte», mandandolos a un lugar que
    // para ellos no existe. Lo encontro Codex en el PR #1205 (P1).
    //
    // Es un scan y no un widget test porque lo que se protege es que la RUTA
    // este alcanzable desde las dos vistas; montar `TrainerProfileView` pide
    // mockear perfil, auth y vinculos, y ese costo no compra mas garantia.
    for (final vista in [
      'lib/features/profile/profile_screen.dart',
      'lib/features/profile/trainer_profile_view.dart',
    ]) {
      expect(
        File(vista).readAsStringSync(),
        contains('/profile/settings/privacidad'),
        reason: '$vista no ofrece entrada a Privacidad: ese rol se queda sin '
            'poder apagar la analitica en el telefono',
      );
    }
  });

  test('los dos entry points la derivan de las preferencias', () {
    // Los dos, no uno: la Política es una sola y promete lo mismo a la app y
    // al Coach Hub. Que uno respete el interruptor y el otro no deja al
    // documento diciendo algo cierto sólo en la mitad del producto.
    for (final entry in ['lib/main.dart', 'lib/main_coach_hub.dart']) {
      final src = File(entry).readAsStringSync();

      expect(
        src.contains('setAnalyticsCollectionEnabled'),
        isTrue,
        reason: '$entry dejó de configurar la analítica. Si se movió a otro '
            'lado, actualizá este test Y confirmá que el nuevo lugar lea la '
            'preferencia.',
      );
      expect(
        src.contains('analyticsConsentFromPrefs'),
        isTrue,
        reason: '$entry configura la analítica sin leer el consentimiento '
            'guardado: el interruptor de Privacidad no tiene efecto ahí.',
      );
    }
  });
}
