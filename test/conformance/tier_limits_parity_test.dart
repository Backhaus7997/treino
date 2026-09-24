// tier_limits_parity_test.dart — las escaleras de límites por tier, escritas
// dos veces.
//
// ─── Por qué existe ─────────────────────────────────────────────────────────
//
// Dos tablas `Record<SubscriptionTier, number | null>` viven en DOS lenguajes:
//
//   • TypeScript — `functions/src/subscriptions/tier-config.ts`. Es la FUENTE
//     DE VERDAD: el servidor calcula el límite efectivo y lo hace cumplir
//     (reglas de Firestore + Cloud Functions).
//   • Dart — `lib/features/coach/domain/subscription_tier.dart`. Espejo a
//     mano, sólo para mostrar "N/límite" en la UI sin un round-trip.
//
// Dos tablas a mano en dos lenguajes divergen. No es una posibilidad, es
// cuestión de cuándo — el mismo razonamiento de `conformance/README.md`, y el
// mismo molde que `paywall_flag_parity_test.dart` usa para el Swift del
// reloj: un grep sobre el literal, feo y lo único que de veras cierra el
// agujero.
//
// Cubre las DOS escaleras que hoy tiene `tier-config.ts`:
//   • `TIER_WEIGHT_LIMITS` ↔ `kTierWeightLimits` (alumnos por tier). Hoy se
//     sincroniza a mano y sin guard — se suma acá de una.
//   • `TIER_CUSTOM_EXERCISE_LIMITS` ↔ `kTierCustomExerciseLimits` (ejercicios
//     propios por tier, docs/limite-ejercicios-pf.md PR3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';

/// Lee `export const <nombre>: Record<SubscriptionTier, number | null> = {...};`
/// del TypeScript y devuelve el mapa `tier -> límite`.
///
/// Devuelve `null` en los dos casos en que el guard quedaría ciego: el bloque
/// no está donde este test lo busca, o algún valor no es ni un número ni
/// `null`. Un guard que no encuentra lo que busca y pasa igual es peor que no
/// tenerlo.
Map<String, int?>? _limitesDelTypeScript(String fuente, String nombre) {
  final bloque = RegExp(
    'export const $nombre: Record<SubscriptionTier, number \\| null> = \\{'
    r'([^}]*)\};',
  ).firstMatch(fuente);
  if (bloque == null) return null;

  // Los comentarios salen primero: un número citado adentro de un comentario
  // no es un valor de la tabla.
  final cuerpo = bloque
      .group(1)!
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  final entradas = RegExp(r'(\w+)\s*:\s*(null|\d+)\s*,?').allMatches(cuerpo);
  final mapa = <String, int?>{};
  for (final e in entradas) {
    final clave = e.group(1)!;
    final valor = e.group(2)!;
    mapa[clave] = valor == 'null' ? null : int.parse(valor);
  }
  if (mapa.isEmpty) return null;

  const tiersEsperados = {'free', 'plan1', 'plan2', 'plan3'};
  if (!tiersEsperados.every(mapa.containsKey)) return null;

  return mapa;
}

Map<String, int?> _mapaDart(Map<SubscriptionTier, int?> mapa) => {
      for (final entry in mapa.entries) entry.key.toJson(): entry.value,
    };

void main() {
  final ts = File('functions/src/subscriptions/tier-config.ts');

  group('tier-config.ts existe donde este test lo busca', () {
    test('el archivo existe', () {
      expect(
        ts.existsSync(),
        isTrue,
        reason: 'no encontré ${ts.path} desde ${Directory.current}. '
            'Si se movió, movete este test con él en vez de borrarlo: sin '
            'esto, las tablas vuelven a poder divergir en silencio.',
      );
    });
  });

  group('TIER_WEIGHT_LIMITS: Dart y TypeScript dicen lo mismo', () {
    test('la tabla se puede leer del TypeScript', () {
      expect(
        _limitesDelTypeScript(ts.readAsStringSync(), 'TIER_WEIGHT_LIMITS'),
        isNotNull,
        reason: 'no pude leer '
            '`export const TIER_WEIGHT_LIMITS: Record<SubscriptionTier, '
            'number | null> = {...};` en ${ts.path}. Puede ser que cambió de '
            'forma (otro tipo, otro nombre) o que algún valor no es un '
            'número ni `null`. Arreglá el regex o el archivo — no borres el '
            'test.',
      );
    });

    test('EL TEST QUE IMPORTA: los dos valen lo mismo', () {
      final delTs =
          _limitesDelTypeScript(ts.readAsStringSync(), 'TIER_WEIGHT_LIMITS')!;
      final delDart = _mapaDart(kTierWeightLimits);

      expect(
        delDart,
        equals(delTs),
        reason: 'kTierWeightLimits (Dart) y TIER_WEIGHT_LIMITS (TypeScript) '
            'no coinciden:\n'
            '  Dart:       $delDart\n'
            '  TypeScript: $delTs\n\n'
            'El servidor es la autoridad; el Dart es sólo para mostrar '
            '"N/límite" sin round-trip. Si divergen, la UI miente sobre el '
            'límite real del alumno.',
      );
    });
  });

  group('TIER_CUSTOM_EXERCISE_LIMITS: Dart y TypeScript dicen lo mismo', () {
    test('la tabla se puede leer del TypeScript', () {
      expect(
        _limitesDelTypeScript(
          ts.readAsStringSync(),
          'TIER_CUSTOM_EXERCISE_LIMITS',
        ),
        isNotNull,
        reason: 'no pude leer '
            '`export const TIER_CUSTOM_EXERCISE_LIMITS: '
            'Record<SubscriptionTier, number | null> = {...};` en '
            '${ts.path}. Puede ser que cambió de forma (otro tipo, otro '
            'nombre) o que algún valor no es un número ni `null`. Arreglá el '
            'regex o el archivo — no borres el test.',
      );
    });

    test('EL TEST QUE IMPORTA: los dos valen lo mismo', () {
      final delTs = _limitesDelTypeScript(
        ts.readAsStringSync(),
        'TIER_CUSTOM_EXERCISE_LIMITS',
      )!;
      final delDart = _mapaDart(kTierCustomExerciseLimits);

      expect(
        delDart,
        equals(delTs),
        reason: 'kTierCustomExerciseLimits (Dart) y '
            'TIER_CUSTOM_EXERCISE_LIMITS (TypeScript) no coinciden:\n'
            '  Dart:       $delDart\n'
            '  TypeScript: $delTs\n\n'
            'El servidor es la autoridad (planLimits.customExercises + '
            'reglas); el Dart es sólo para mostrar "N/límite" sin '
            'round-trip. Si divergen, el gate del cliente bloquea (o deja '
            'pasar) en un número distinto del que hace cumplir el servidor.',
      );
    });
  });
}
