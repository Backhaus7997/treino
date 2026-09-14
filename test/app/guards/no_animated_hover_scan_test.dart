import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — prohibición de `AnimatedContainer` que anime el
/// fondo **por hover** en el Coach Hub web.
///
/// POR QUÉ EXISTE. Un puntero es manipulación directa: el fondo tiene que estar
/// donde está el cursor, no llegando. Con 120 o 180 ms, barrer una lista deja
/// ESTELA — el item anterior sigue apagándose cuando el siguiente ya se
/// encendió, y se ven tres o cuatro prendidos a la vez. El PF lo reportó dos
/// veces con las mismas palabras: «parpadeo al pasar el cursor».
///
/// La primera vez (#1056) la respuesta fue bajar 180 a 120. Ciento veinte deja
/// una estela más corta, no ninguna, y volvió. La segunda (#1063) se puso
/// `Duration.zero` en la tabla, la list row y el item del sidebar — pero
/// quedaron NUEVE componentes más con el mismo defecto, incluidos los chips de
/// filtro, que están justo arriba de la tabla de Alumnos y el usuario los cruza
/// cada vez que va del buscador a la lista.
///
/// Tres rondas arreglando el mismo bug a mano es la señal de que faltaba un
/// guard, no otra corrección.
///
/// LA REGLA. Si lo que pinta un `AnimatedContainer` depende de `hovered`, su
/// `duration` tiene que poder ser `Duration.zero`. Las dos formas válidas:
///
/// ```dart
/// duration: Duration.zero,                                  // sólo hover
/// duration: selected ? AppMotion.resolve(...) : Duration.zero, // hover + selección
/// ```
///
/// La segunda es la que usa el item del sidebar desde #1063: el hover no anima,
/// pero el cambio de SELECCIÓN sí — ése pasa una vez, por una decisión del
/// usuario, y ahí el fundido dice que algo cambió.
///
/// LO QUE ESTE SCANNER **NO** PRUEBA. Que el hover se vea instantáneo. Un
/// scanner de texto jamás dice que algo FUNCIONA: dice que un patrón no está.
/// Que el fondo del hover se distinga del fondo de reposo lo prueba el guard de
/// perceptibilidad de `coach_hub_kit_tokens_test.dart`, y que el cross-fade no
/// duplique la pantalla lo prueba `alumnos_screen_test.dart`.
///
/// ALCANCE (deliberado):
///   ✓ El scope mirado va del `builder: (` que envuelve al `AnimatedContainer`
///     hasta el cierre del propio widget — así se caza el patrón
///     `final highlighted = states.hovered || states.pressed;` declarado antes.
///   ✓ Se ignoran los comentarios de línea, para que este mismo dartdoc no se
///     cuente como una infracción.
///   ✗ Un flag de hover que viaje por un parámetro desde otro archivo. Eso se
///     caza en review, igual que en los scanners de color y tipografía.
void main() {
  group('no_animated_hover_scan — el hover del Coach Hub no anima', () {
    /// Deuda congelada. Es CERO a propósito: este guard entra junto con la
    /// corrección de los nueve casos que quedaban, así que no hay nada
    /// legítimo que allowlistear. Si mañana aparece un caso real, va acá con
    /// su razón escrita — y el techo sube UNA vez, no cada vez.
    const allowlist = <String>{};
    const allowlistCeiling = 0;

    late List<String> offenders;
    late List<String> staleEntries;

    setUpAll(() {
      offenders = <String>[];
      final seen = <String>{};
      final dir = Directory('lib/features/coach_hub');

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final normalized = entity.path.replaceAll(r'\', '/');
        final libIndex = normalized.indexOf('lib/');
        if (libIndex == -1) continue;
        final relativePath = normalized.substring(libIndex + 4);

        final src = _stripLineComments(entity.readAsStringSync());
        var hit = false;

        for (final start in _occurrences(src, 'AnimatedContainer(')) {
          final open = start + 'AnimatedContainer'.length;
          final args = _balanced(src, open);
          if (args == null) continue;

          // Scope: desde el `builder: (` que lo envuelve (si lo hay) hasta el
          // cierre del widget. Ahí vive el `final highlighted = ...`.
          final builderAt = src.lastIndexOf('builder: (', start);
          final scope = builderAt == -1 ? args : src.substring(builderAt, open);
          if (!scope.contains('hovered') && !args.contains('hovered')) continue;

          final duration = _topLevelArg(args, 'duration');
          if (duration == null) continue;
          if (duration.contains('Duration.zero')) continue;

          hit = true;
          offenders.add(
            '$relativePath:${_lineOf(src, start)}  '
            'duration: ${duration.trim().replaceAll(RegExp(r'\s+'), ' ')}',
          );
        }

        if (hit) seen.add(relativePath);
      }

      offenders
        ..removeWhere((o) => allowlist.contains(o.split(':').first))
        ..sort();
      staleEntries = allowlist.where((p) => !seen.contains(p)).toList()..sort();
    });

    test('ningún AnimatedContainer anima el fondo por hover', () {
      expect(
        offenders,
        isEmpty,
        reason: 'Estos AnimatedContainer pintan según `hovered` y animan:\n'
            '${offenders.join('\n')}\n\n'
            'Un puntero es manipulación directa: el fondo va donde está el '
            'cursor, no llegando. Poné:\n'
            '  duration: Duration.zero,\n'
            'o, si el MISMO contenedor también cambia por selección:\n'
            '  duration: selected ? AppMotion.resolve(ctx, ...) : Duration.zero,\n\n'
            'El hover no anima; la selección sí.',
      );
    });

    test('la allowlist no creció vs el estado congelado (ratchet)', () {
      expect(
        allowlist.length,
        lessThanOrEqualTo(allowlistCeiling),
        reason: 'La allowlist tiene ${allowlist.length} entradas y el techo es '
            '$allowlistCeiling. SÓLO PUEDE ACHICARSE.',
      );
    });

    test('la allowlist no tiene entradas muertas', () {
      expect(
        staleEntries,
        isEmpty,
        reason: 'Ya no infringen la regla (o no existen) pero siguen en la '
            'allowlist:\n${staleEntries.join('\n')}',
      );
    });

    // CONTROL NEGATIVO. El verde de arriba no prueba que el scanner mire: un
    // scanner roto también da cero infracciones. Éste le da de comer un caso
    // que SÍ infringe y exige que lo cace.
    test('el scanner caza un caso plantado (control negativo)', () {
      const roto = '''
        builder: (ctx, states) {
          final highlighted = states.hovered || states.pressed;
          return AnimatedContainer(
            duration: AppMotion.resolve(ctx, AppMotion.micro),
            color: highlighted ? a : b,
          );
        }
      ''';
      expect(_infringe(roto), isTrue, reason: 'debería cazar el hover animado');

      const flatZero = '''
        builder: (ctx, states) {
          final highlighted = states.hovered;
          return AnimatedContainer(
            duration: Duration.zero,
            color: highlighted ? a : b,
          );
        }
      ''';
      expect(_infringe(flatZero), isFalse);

      const condicional = '''
        builder: (ctx, states) {
          final soft = states.hovered;
          return AnimatedContainer(
            duration: selected ? AppMotion.resolve(ctx, x) : Duration.zero,
            color: selected ? c : (soft ? a : b),
          );
        }
      ''';
      expect(_infringe(condicional), isFalse);

      // Sin hover de por medio, animar es legítimo — p. ej. la celda de la
      // matriz de notificaciones, que anima por el VALOR del checkbox.
      const sinHover = '''
        return AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.micro),
          color: value ? a : b,
        );
      ''';
      expect(_infringe(sinHover), isFalse);
    });
  });
}

/// Corre la misma lógica del scanner sobre un fragmento suelto.
bool _infringe(String source) {
  final src = _stripLineComments(source);
  for (final start in _occurrences(src, 'AnimatedContainer(')) {
    final open = start + 'AnimatedContainer'.length;
    final args = _balanced(src, open);
    if (args == null) continue;
    final builderAt = src.lastIndexOf('builder: (', start);
    final scope = builderAt == -1 ? args : src.substring(builderAt, open);
    if (!scope.contains('hovered') && !args.contains('hovered')) continue;
    final duration = _topLevelArg(args, 'duration');
    if (duration == null) continue;
    if (duration.contains('Duration.zero')) continue;
    return true;
  }
  return false;
}

/// Saca los comentarios `//` para que los dartdoc y las explicaciones no
/// cuenten como código.
String _stripLineComments(String src) => src.split('\n').map((l) {
      final i = l.indexOf('//');
      if (i == -1) return l;
      // No cortar dentro de un string ('https://...'): sólo si no hay comillas
      // impares antes del `//`.
      final antes = l.substring(0, i);
      final comillas =
          "'".allMatches(antes).length + '"'.allMatches(antes).length;
      return comillas.isEven ? antes : l;
    }).join('\n');

Iterable<int> _occurrences(String src, String needle) sync* {
  var i = src.indexOf(needle);
  while (i != -1) {
    yield i;
    i = src.indexOf(needle, i + 1);
  }
}

/// Texto entre los paréntesis balanceados que abren en [openParen].
String? _balanced(String src, int openParen) {
  var depth = 0;
  for (var i = openParen; i < src.length; i++) {
    final c = src[i];
    if (c == "'" || c == '"') {
      final quote = c;
      i++;
      while (i < src.length && src[i] != quote) {
        if (src[i] == r'\') i++;
        i++;
      }
      continue;
    }
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return src.substring(openParen + 1, i);
    }
  }
  return null;
}

/// Valor del argumento [name] en el nivel superior de [args].
String? _topLevelArg(String args, String name) {
  var depth = 0;
  for (var i = 0; i < args.length; i++) {
    final c = args[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      continue;
    }
    if (depth != 0) continue;
    if (!args.startsWith('$name:', i)) continue;
    final start = i + name.length + 1;
    var d = 0;
    for (var j = start; j < args.length; j++) {
      final k = args[j];
      if (k == '(' || k == '[' || k == '{') d++;
      if (k == ')' || k == ']' || k == '}') d--;
      if (k == ',' && d == 0) return args.substring(start, j);
    }
    return args.substring(start);
  }
  return null;
}

int _lineOf(String src, int index) =>
    '\n'.allMatches(src.substring(0, index)).length + 1;
