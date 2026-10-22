import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — prohibición de `Excel.save()` en `lib/`.
///
/// POR QUÉ EXISTE. En el paquete `excel` (4.0.6), `save()` no es «serializar»:
/// en web llama a `SavingHelper.saveFile`, que crea un `<a download>` y le
/// hace click, con el nombre por defecto `FlutterExcel.xlsx`. La plantilla de
/// plan del Coach Hub usaba `save()` para obtener los bytes y después la
/// pantalla los descargaba como `treino-plantilla-plan.xlsx`: el entrenador
/// veía dos diálogos de guardar seguidos y se llevaba dos archivos.
///
/// LA REGLA. Para obtener los bytes se usa `encode()`, que devuelve lo mismo
/// sin efectos secundarios. La descarga la decide la pantalla, nunca el
/// paquete.
///
/// ALCANCE. Sólo mira los archivos que importan `package:excel`: `.save(` es
/// un nombre demasiado común (`canvas.save()`, repositorios) para prohibirlo
/// en todo `lib/`.
///
/// LO QUE ESTE SCANNER **NO** PRUEBA. Que la descarga funcione: un scanner de
/// texto sólo dice que un patrón no está. Un `Excel` recibido por parámetro en
/// un archivo que no importa el paquete se le escaparía.
void main() {
  group('no_excel_save_scan — los bytes del Excel salen de encode()', () {
    final patron = RegExp(r'\.save\(');
    final importaExcel = RegExp(r'''import\s+['"]package:excel/''');

    late List<String> offenders;
    late int archivosConExcel;

    setUpAll(() {
      offenders = <String>[];
      archivosConExcel = 0;

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final src = _sinComentarios(entity.readAsStringSync());
        if (!importaExcel.hasMatch(src)) continue;
        archivosConExcel++;

        final path = entity.path.replaceAll(r'\', '/');
        for (final h in patron.allMatches(src)) {
          offenders.add('$path:${_lineaDe(src, h.start)}');
        }
      }
      offenders.sort();
    });

    test('ningún archivo que usa el paquete excel llama a save()', () {
      expect(
        offenders,
        isEmpty,
        reason: 'Llamadas a save() en archivos que usan package:excel:\n'
            '${offenders.join('\n')}\n\n'
            'En web, Excel.save() descarga un «FlutterExcel.xlsx» además de '
            'devolver los bytes. Usá excel.encode().',
      );
    });

    // Si nadie importa el paquete el verde de arriba no significa nada: el
    // filtro de imports estaría roto o el paquete se fue.
    test('el scan encuentra los archivos que usan el paquete', () {
      expect(archivosConExcel, greaterThan(0));
    });

    // CONTROL NEGATIVO. Un scanner roto también da cero infracciones.
    test('el scanner caza casos plantados (control negativo)', () {
      const infractores = [
        'final bytes = excel.save();',
        "excel.save(fileName: 'x.xlsx');",
        'return book.save()!;',
      ];
      for (final caso in infractores) {
        expect(patron.hasMatch(caso), isTrue, reason: 'no cazó: $caso');
      }
      const limpios = [
        'final bytes = excel.encode();',
        'final saved = true;',
      ];
      for (final caso in limpios) {
        expect(patron.hasMatch(caso), isFalse, reason: 'falso positivo: $caso');
      }

      expect(
          importaExcel.hasMatch("import 'package:excel/excel.dart';"), isTrue);
      expect(importaExcel.hasMatch("import 'package:flutter/material.dart';"),
          isFalse);
    });
  });
}

/// Saca los comentarios de línea para que un dartdoc que NOMBRA `save()`
/// —como el del builder— no cuente como infracción.
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
