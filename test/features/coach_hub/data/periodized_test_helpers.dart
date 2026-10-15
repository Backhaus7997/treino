import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:treino/features/coach_hub/data/periodized_excel_parser.dart';

CellValue? _toCell(Object? v) {
  if (v == null) return null;
  if (v is CellValue) return v;
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(v);
  return TextCellValue(v.toString());
}

/// Arma un .xlsx con una hoja `Programa` a partir de una grilla de filas.
/// Cada fila es una lista de celdas desde la columna A.
Uint8List programa(
  List<List<Object?>> rows, {
  String sheetName = kProgramSheet,
  List<String> extraSheets = const [],
}) {
  final excel = Excel.createExcel();
  final def = excel.getDefaultSheet();
  if (def != null && def != sheetName) excel.rename(def, sheetName);
  final sheet = excel[sheetName];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final v = _toCell(rows[r][c]);
      if (v == null) continue;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value = v;
    }
  }
  for (final name in extraSheets) {
    excel[name];
  }
  return Uint8List.fromList(excel.save()!);
}

/// Encabezado del DÍA 1 con [weeks] semanas.
List<Object?> header1({int weeks = 3}) => [
      'N°',
      'DÍA 1',
      'DESCANSOS',
      for (var w = 1; w <= weeks; w++) 'SEMANA $w',
    ];

List<Object?> header(int day) => ['N°', 'DÍA $day', 'DESCANSOS'];

/// Escribe celdas en una plantilla ya construida (fila/columna base 0).
/// Enteros como número, el resto como texto; conserva los estilos.
Uint8List fillTemplate(Uint8List template, Map<(int, int), Object> cells) {
  final excel = Excel.decodeBytes(template);
  final sheet = excel[kProgramSheet];
  cells.forEach((rc, v) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: rc.$2, rowIndex: rc.$1))
        .value = v is int ? IntCellValue(v) : TextCellValue(v.toString());
  });
  return Uint8List.fromList(excel.save()!);
}
