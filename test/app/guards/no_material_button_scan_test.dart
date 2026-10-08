import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — prohibición de botones Material crudos en el
/// Coach Hub web.
///
/// POR QUÉ EXISTE. El kit tenía `avatar`, `data_table`, `dialog`,
/// `empty_state`, `filter_chips`, `kpi_card`, `list_row`, `pager`,
/// `section_header`, `section_hero`, `skeleton` y `treino_dropdown` — y ningún
/// `button`. `TreinoButtonTokens` existía desde el principio pero suelto, sin
/// widget que lo encapsulara, así que cada pantalla se armó el suyo a mano.
///
/// EL ESTADO AL CONGELAR (medido sobre `211d4d77`): **156 botones Material
/// crudos en 43 archivos** — 56 `TextButton`, 41 `IconButton`, 28
/// `ElevatedButton`, 25 `OutlinedButton`, 4 `FilledButton`. Sólo en
/// `alumno_detail_screen.dart` convivían siete paddings distintos y seis
/// tamaños de ícono; el botón de confirmar era a veces `FilledButton` y a
/// veces `ElevatedButton`; el mismo ícono de eliminar aparecía en cuatro
/// tamaños; y de 59 botones apenas 6 acotaban su tap target.
///
/// La migración los llevó a CERO. Este guard es lo que impide que vuelvan.
///
/// LA REGLA. En `lib/features/coach_hub/` los botones salen de
/// `TreinoButton` / `TreinoIconButton`. La allowlist está VACÍA a propósito:
/// no hay ningún caso legítimo hoy, y si mañana aparece va con su razón
/// escrita y el techo sube UNA vez, no cada vez.
///
/// QUÉ **NO** PROHÍBE, y por qué:
///   - `_DialogActionButton` de `TreinoDialog`: no es Material crudo, es un
///     componente del kit sobre `TreinoInteractiveState`. Consolidarlo en
///     `TreinoButton` cambiaría la pinta de todos los diálogos de la app —de
///     link de texto a píldora rellena— y es una decisión de diseño, no de
///     higiene.
///   - El resto de la app fuera de `coach_hub`. Es la deuda que sigue: ver
///     `docs/handoff-botones-coach-hub.md`.
///
/// LO QUE ESTE SCANNER **NO** PRUEBA. Que los botones se vean bien. Un
/// scanner de texto jamás dice que algo FUNCIONA: dice que un patrón no está.
/// Que el botón mida lo que promete y que su hover se distinga lo prueban
/// `treino_button_test.dart` y el guard de perceptibilidad de
/// `coach_hub_kit_tokens_test.dart`.
void main() {
  group('no_material_button_scan — el Coach Hub usa el botón del kit', () {
    /// El look-behind evita que `TreinoIconButton(` cuente como `IconButton(`.
    /// Sin él este scanner reportaría infracciones sobre el propio kit — que
    /// es exactamente el error que cometió el primer conteo de esta migración.
    final patron = RegExp(
      r'(?<!Treino)\b(IconButton|OutlinedButton|TextButton|ElevatedButton'
      r'|FilledButton)(\.icon)?\(',
    );

    /// Registro de deuda, no licencia. Vacío: la migración terminó.
    const allowlist = <String>{};
    const allowlistCeiling = 0;

    /// Techo de ocurrencias en `lib/features/coach_hub/`. Sólo baja.
    const deudaCeiling = 0;

    late List<String> offenders;
    late List<String> staleEntries;
    late int deudaTotal;

    setUpAll(() {
      offenders = <String>[];
      deudaTotal = 0;
      final seen = <String>{};

      for (final entity
          in Directory('lib/features/coach_hub').listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final normalized = entity.path.replaceAll(r'\', '/');
        final libIndex = normalized.indexOf('lib/');
        if (libIndex == -1) continue;
        final relativePath = normalized.substring(libIndex + 4);

        final src = _sinComentarios(entity.readAsStringSync());
        final hits = patron.allMatches(src).toList();
        if (hits.isEmpty) continue;

        deudaTotal += hits.length;
        seen.add(relativePath);
        if (allowlist.contains(relativePath)) continue;
        for (final h in hits) {
          offenders.add('$relativePath:${_lineaDe(src, h.start)}  '
              '${h.group(0)}');
        }
      }

      offenders.sort();
      staleEntries = allowlist.where((p) => !seen.contains(p)).toList()..sort();
    });

    test('ningún archivo usa botones Material crudos', () {
      expect(
        offenders,
        isEmpty,
        reason: 'Botones Material crudos en coach_hub:\n'
            '${offenders.join('\n')}\n\n'
            'Usá el botón del kit:\n'
            '  TreinoButton(label: …, variant: …, size: …, onPressed: …)\n'
            '  TreinoIconButton(icon: …, tooltip: …, onPressed: …)\n\n'
            'Variantes: primary · secondary · secondaryAccent · ghost · '
            'ghostAccent · danger\n'
            'Tamaños: xs (24, sólo en fila de tabla) · sm (32) · md (40)\n\n'
            'Ver docs/handoff-botones-coach-hub.md para elegir.',
      );
    });

    test('la deuda total sigue en cero (ratchet de ocurrencias)', () {
      expect(
        deudaTotal,
        lessThanOrEqualTo(deudaCeiling),
        reason: 'Hay $deudaTotal botones Material crudos y el techo es '
            '$deudaCeiling. Se llegó a cero migrando 156; no los devuelvas '
            'subiendo el número.',
      );
    });

    test('la allowlist no creció vs el estado congelado (ratchet)', () {
      expect(allowlist.length, lessThanOrEqualTo(allowlistCeiling));
    });

    test('la allowlist no tiene entradas muertas', () {
      expect(staleEntries, isEmpty);
    });

    // CONTROL NEGATIVO. El verde de arriba no prueba que el scanner mire: un
    // scanner roto también da cero infracciones.
    test('el scanner caza casos plantados (control negativo)', () {
      const infractores = [
        'child: TextButton(onPressed: x, child: y)',
        'IconButton(icon: i, onPressed: x)',
        'ElevatedButton.icon(icon: i, label: l, onPressed: x)',
        'return OutlinedButton(onPressed: x, child: y);',
        'FilledButton(onPressed: x, child: y)',
      ];
      for (final caso in infractores) {
        expect(patron.hasMatch(caso), isTrue, reason: 'no cazó: $caso');
      }

      // Y NO marca al kit ni a lo que no es un botón. El primero es el que
      // importa: `TreinoIconButton(` CONTIENE `IconButton(`, y sin el
      // look-behind este guard reportaría como infracción cada llamada al
      // componente que él mismo exige usar.
      const limpios = [
        'TreinoIconButton(icon: i, tooltip: t, onPressed: x)',
        'TreinoButton(label: l, onPressed: x)',
        'MyIconButtonThing(x)',
        'final iconButton = 3;',
      ];
      for (final caso in limpios) {
        expect(patron.hasMatch(caso), isFalse, reason: 'falso positivo: $caso');
      }
    });
  });
}

/// Saca los comentarios de línea para que un dartdoc que NOMBRA los widgets
/// prohibidos —como el de este mismo archivo— no cuente como infracción.
String _sinComentarios(String src) => src.split('\n').map((l) {
      final i = l.indexOf('//');
      if (i == -1) return l;
      final antes = l.substring(0, i);
      final comillas =
          "'".allMatches(antes).length + '"'.allMatches(antes).length;
      return comillas.isEven ? antes : l;
    }).join('\n');

int _lineaDe(String src, int index) =>
    '\n'.allMatches(src.substring(0, index)).length + 1;
