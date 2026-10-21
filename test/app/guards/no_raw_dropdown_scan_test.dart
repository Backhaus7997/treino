import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — prohibición del dropdown pelado de Material.
///
/// POR QUÉ EXISTE. «Crear ejercicio» abría el menú de `DropdownButton` tal
/// cual lo dibuja Material: una hoja blanca, rectangular, sin radios, con la
/// opción elegida resaltada en un mint plano y sin la tipografía ni los tokens
/// de Treino. Tapaba la pantalla entera. Cada pantalla que necesitaba elegir
/// un valor se había armado su propio `DropdownButton` envuelto en un
/// `Container` distinto —radios 10, 12 y 14, pesos 400 y 500, con y sin
/// chevron— y el menú, que ninguno podía estilar del todo, salía igual de
/// ajeno en todos.
///
/// LA REGLA. Para elegir un valor de una lista se usa `TreinoSelectField`
/// (o `showTreinoSelect` con un disparador propio), de
/// `lib/core/widgets/treino_select.dart`: hoja del kit en teléfono, menú
/// anclado en pantallas anchas.
///
/// EL ESTADO AL CONGELAR: los archivos de [allowlist], con [deudaCeiling]
/// ocurrencias. Es deuda con fecha de vencimiento —la migración va en el PR
/// siguiente de la misma cadena—, no licencia: el techo sólo baja.
///
/// QUÉ **NO** PROHÍBE, y por qué:
///   - `PopupMenuButton` / `TreinoPopupMenuButton`. Casi todos son menús de
///     ACCIONES (⋮ editar, duplicar, borrar), no selectores de valor, y ya
///     hablan el idioma del kit por `popupMenuTheme` (#1558). Un scanner de
///     texto no distingue un menú de acciones de un selector hecho con
///     `PopupMenuButton`; los dos que eran selectores se migran a mano.
///   - `DropdownMenuItem` suelto: sin un `DropdownButton` que lo dibuje no
///     abre nada.
///
/// LO QUE ESTE SCANNER **NO** PRUEBA. Que el selector se vea bien. Eso lo
/// prueba `test/core/widgets/treino_select_test.dart` en los dos temas.
void main() {
  group('no_raw_dropdown_scan — los selectores salen de TreinoSelectField', () {
    /// `DropdownButtonHideUnderline` cuenta: sólo existe para envolver un
    /// `DropdownButton`, y es la firma del patrón casero que esto reemplaza.
    /// El genérico es perezoso y acepta paréntesis: `DropdownButton<void
    /// Function(int)>(` y `DropdownButton<(int, String)>(` también cuentan.
    final patron = RegExp(
      r'\b(DropdownButtonFormField|DropdownButtonHideUnderline|DropdownButton'
      r'|DropdownMenuFormField|DropdownMenu)\s*(<[^;{}]*?>)?\(',
    );

    /// Registro de deuda, no licencia. Cada entrada se va con su migración.
    const allowlist = <String>{
      'features/coach/presentation/trainer_dashboard_tab.dart',
      'features/coach/presentation/widgets/new_session_sheet.dart',
      'features/coach_hub/presentation/widgets/treino_dropdown.dart',
      'features/profile/presentation/profile_edit_trainer_screen.dart',
      'features/workout/presentation/custom_exercise_editor_screen.dart',
      'features/workout/presentation/routine_editor_screen.dart',
    };
    const allowlistCeiling = 6;

    /// Techo de ocurrencias en `lib/`. Sólo baja.
    const deudaCeiling = 10;

    late List<String> offenders;
    late List<String> staleEntries;
    late int deudaTotal;

    setUpAll(() {
      offenders = <String>[];
      deudaTotal = 0;
      final seen = <String>{};

      for (final entity in Directory('lib').listSync(recursive: true)) {
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

    test('ningún archivo nuevo usa el dropdown de Material', () {
      expect(
        offenders,
        isEmpty,
        reason: 'Dropdowns de Material fuera del componente:\n'
            '${offenders.join('\n')}\n\n'
            'Usá el selector del kit:\n'
            '  TreinoSelectField<T>(\n'
            '    value: …,\n'
            '    sheetTitle: …,\n'
            '    options: [TreinoSelectOption(value: …, label: …)],\n'
            '    onChanged: …,\n'
            '  )\n'
            'o showTreinoSelect<T>(context, …) con un disparador propio.\n'
            'Ver lib/core/widgets/treino_select.dart.',
      );
    });

    test('la deuda total no creció (ratchet de ocurrencias)', () {
      expect(
        deudaTotal,
        lessThanOrEqualTo(deudaCeiling),
        reason: 'Hay $deudaTotal dropdowns de Material y el techo es '
            '$deudaCeiling. Bajalo al migrar; no lo subas.',
      );
    });

    test('la allowlist no creció vs el estado congelado (ratchet)', () {
      expect(allowlist.length, lessThanOrEqualTo(allowlistCeiling));
    });

    test('la allowlist no tiene entradas muertas', () {
      expect(
        staleEntries,
        isEmpty,
        reason: 'Estos archivos ya no usan dropdowns: sacalos de la '
            'allowlist y bajá allowlistCeiling.',
      );
    });

    // CONTROL NEGATIVO. El verde de arriba no prueba que el scanner mire: un
    // scanner roto también da cero infracciones.
    test('el scanner caza casos plantados (control negativo)', () {
      const infractores = [
        'child: DropdownButton<MuscleGroup?>(value: v, items: i)',
        'return DropdownButtonFormField<String>(initialValue: v)',
        'DropdownButtonFormField(items: i, onChanged: f)',
        'child: DropdownButtonHideUnderline(child: c)',
        'DropdownMenu<String>(dropdownMenuEntries: e)',
        'DropdownButton<Map<String, int>>(items: i)',
        'DropdownButton<void Function(int)>(items: i)',
        'DropdownButton<(int, String)>(items: i)',
        'DropdownMenuFormField<String>(dropdownMenuEntries: e)',
        'child: DropdownButton(items: i)',
      ];
      for (final caso in infractores) {
        expect(patron.hasMatch(caso), isTrue, reason: 'no cazó: $caso');
      }

      // Y NO marca al kit ni a lo que no abre un menú.
      const limpios = [
        'TreinoSelectField<String>(value: v, options: o)',
        'DropdownMenuItem<String>(value: v, child: c)',
        'final dropdownButton = 3;',
        'TreinoDropdownButtonTheme(x)',
      ];
      for (final caso in limpios) {
        expect(patron.hasMatch(caso), isFalse, reason: 'falso positivo: $caso');
      }
    });

    // CONTROL DEL CONTROL. Que el regex cace un string no prueba que el
    // recorrido de `lib/` lo vea: un `Directory` mal apuntado da cero
    // archivos y todo verde. Mientras quede deuda, el recorrido tiene que
    // haberla encontrado.
    test('el recorrido encontró los archivos congelados', () {
      expect(deudaTotal, greaterThan(0));
      expect(staleEntries, isEmpty);
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
