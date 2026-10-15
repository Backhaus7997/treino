import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/periodized_excel_parser.dart';
import 'package:treino/features/coach_hub/data/periodized_template_builder.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';

import 'periodized_test_helpers.dart';

CellStyle? _style(Sheet s, int col, int row) => s
    .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
    .cellStyle;

/// Alineación horizontal de una celda leída DIRECTO del XML del .xlsx.
///
/// `Excel.decodeBytes` no devuelve la alineación horizontal que el mismo
/// paquete escribe (siempre lee `Left`), así que decodificar y comparar daría
/// un falso rojo sobre un archivo bien armado: se verifica en el XML.
String? _alignmentOf(String ref) => _xfOf(ref)
    ?.let((xf) => RegExp(r'horizontal="(\w+)"').firstMatch(xf)?.group(1));

/// `numFmtId` del estilo de una celda, leído del XML (49 = Texto, `@`).
String? _numFmtOf(String ref) => _xfOf(ref)
    ?.let((xf) => RegExp(r'numFmtId="(\d+)"').firstMatch(xf)?.group(1));

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

String? _xfOf(String ref) {
  final zip = ZipDecoder().decodeBytes(buildPeriodizedTemplateBytes());
  String read(String name) =>
      utf8.decode(zip.findFile(name)!.content as List<int>);
  final sheetXml = read('xl/worksheets/sheet1.xml');
  final cell = RegExp('<c r="$ref"[^>]*?s="(\\d+)"').firstMatch(sheetXml);
  if (cell == null) return null;
  final xfs = RegExp(r'<cellXfs[^>]*>(.*?)</cellXfs>', dotAll: true)
      .firstMatch(read('xl/styles.xml'))!
      .group(1)!;
  final xf = RegExp(r'<xf\b.*?(?:/>|</xf>)', dotAll: true)
      .allMatches(xfs)
      .elementAt(int.parse(cell.group(1)!))
      .group(0)!;
  return xf;
}

String _ref(int col, int row) => '${columnLetter(col)}${row + 1}';

void main() {
  final book = Excel.decodeBytes(buildPeriodizedTemplateBytes());
  final sheet = book[kProgramSheet];

  group('estilo de la plantilla', () {
    test('el encabezado de cada día es una banda negra con texto blanco', () {
      for (var day = 0; day < kTemplateDays; day++) {
        final row = day * (1 + kTemplateRowsPerDay);
        // Desde N° hasta la última semana, también donde no hay texto.
        for (var col = 0; col <= 2 + kTemplateWeeks; col++) {
          final st = _style(sheet, col, row);
          expect(st, isNotNull, reason: 'fila ${row + 1} col $col sin estilo');
          expect(st!.backgroundColor, ExcelColor.black,
              reason: 'fila ${row + 1} col $col');
          expect(st.fontColor, ExcelColor.white);
          expect(st.isBold, isTrue);
        }
      }
    });

    test(
        'DÍA N, DESCANSOS y SEMANA van en negrita; DESCANSOS y SEMANA '
        'centrados', () {
      expect(_style(sheet, 1, 0)!.isBold, isTrue); // DÍA 1
      expect(_style(sheet, 2, 0)!.isBold, isTrue); // DESCANSOS
      expect(_alignmentOf(_ref(2, 0)), 'center');
      for (var w = 0; w < kTemplateWeeks; w++) {
        final st = _style(sheet, 3 + w, 0)!;
        expect(st.isBold, isTrue);
        expect(_alignmentOf(_ref(3 + w, 0)), 'center');
      }
    });

    test('las celdas de descanso y de semana de los renglones van centradas',
        () {
      for (var r = 1; r <= kTemplateRowsPerDay; r++) {
        for (var col = 2; col <= 2 + kTemplateWeeks; col++) {
          expect(_alignmentOf(_ref(col, r)), 'center',
              reason: 'fila ${r + 1} col $col');
        }
      }
      // El renglón del segundo bloque también.
      const second = 1 + kTemplateRowsPerDay + 1;
      expect(_alignmentOf(_ref(3, second)), 'center');
    });

    test(
        'las celdas de descanso y de semana van con formato Texto (@) para '
        'que Excel no las convierta en fecha u hora', () {
      for (var day = 0; day < kTemplateDays; day++) {
        final base = day * (1 + kTemplateRowsPerDay);
        for (var r = 1; r <= kTemplateRowsPerDay; r++) {
          for (var col = 2; col <= 2 + kTemplateWeeks; col++) {
            expect(_numFmtOf(_ref(col, base + r)), '49',
                reason: 'fila ${base + r + 1} col $col');
          }
        }
      }
    });

    test('la columna del ejercicio es ancha', () {
      expect(sheet.getColumnWidth(1), kProgramExerciseWidth);
      expect(kProgramExerciseWidth, greaterThan(kProgramWeekWidth * 2));
    });

    test('la plantilla estilada sigue pasando por el parser (round-trip)', () {
      final empty = parsePeriodizedExcel(buildPeriodizedTemplateBytes());
      // Sin ejercicios cargados: único error, "no hay ningún ejercicio".
      expect(
          empty.errors.map((e) => e.code), [ImportDiagnosticCode.noExercises]);

      final filled = parsePeriodizedExcel(fillTemplate(
        buildPeriodizedTemplateBytes(),
        {
          (1, 0): 1,
          (1, 1): 'Ejercicio A',
          (1, 2): 90,
          for (var w = 0; w < kTemplateWeeks; w++) (1, 3 + w): '3x${8 + w}',
        },
      ));
      expect(filled.errors, isEmpty);
      expect(filled.plan!.numWeeks, kTemplateWeeks);
      expect(filled.plan!.days.first.rows.single.restSeconds, 90);
    });
  });
}
