import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Single source of truth for Excel column widths.
/// SCENARIOs 727-729 assert these values verbatim.
/// ADR-CXP-001: keep here, import in tests.
const Map<String, double> kColumnWidthsDay = {
  'Ejercicio': 28,
  'Series': 10,
  'Reps Min': 12,
  'Reps Max': 12,
  'Peso Kg': 12,
  'Descanso Seg': 16,
  'Notas': 22,
};

const Map<String, double> kColumnWidthsPlan = {
  'Campo': 22,
  'Valor': 20,
};

/// Genera el .xlsx template para que el PF lo descargue desde el browser.
/// Mismo formato que espera `parseExcelBytes`.
Uint8List buildPlanTemplateBytes() {
  final excel = Excel.createExcel();

  // El package crea una sheet default "Sheet1" — la renombramos a Plan.
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != 'Plan') {
    excel.rename(defaultSheet, 'Plan');
  }
  final plan = excel.sheets['Plan']!;

  // Plan sheet column widths (ADR-CXP-001, SCENARIO-729).
  plan.setColumnWidth(0, kColumnWidthsPlan['Campo']!);
  plan.setColumnWidth(1, kColumnWidthsPlan['Valor']!);

  _appendRow(plan, ['Campo', 'Valor']);
  _appendRow(plan, ['Nombre', 'Mi plan']);
  _appendRow(plan, ['Días por semana', 3]);
  _appendRow(plan, ['Duración semanas', 8]);
  _appendRow(plan, ['Nivel', 'intermedio']);

  const dayHeaders = [
    'Ejercicio',
    'Series',
    'Reps Min',
    'Reps Max',
    'Peso Kg',
    'Descanso Seg',
    'Notas',
  ];

  for (var day = 1; day <= 3; day++) {
    final sheet = excel['Día $day'];

    // Day sheet column widths (ADR-CXP-001, SCENARIO-727/728).
    var colIndex = 0;
    for (final width in kColumnWidthsDay.values) {
      sheet.setColumnWidth(colIndex, width);
      colIndex++;
    }

    _appendRow(sheet, dayHeaders);
    _appendRow(sheet, ['Sentadilla con barra', 4, 8, 10, 60, 90, '']);
    _appendRow(sheet, ['Press banca', 4, 8, 10, 50, 90, '']);
    _appendRow(sheet, ['Remo con barra', 3, 10, 12, 40, 60, '']);
  }

  // Instrucciones sheet appended after all day sheets (ADR-CXP-002, SCENARIO-730..732).
  _buildInstruccionesSheet(excel);

  final bytes = excel.save();
  if (bytes == null) {
    throw StateError('No se pudo generar el template.');
  }
  return Uint8List.fromList(bytes);
}

/// Appends the static guide sheet "Instrucciones" to [excel].
///
/// Content is locked per ADR-CXP-012. Cell positions follow the spec:
/// A1 heading, A3/B3 column meanings header, A4..A11/B4..B11 column rows,
/// A13..A16 valid Nivel values, A18..H19 example header, A20..H20 example row,
/// A22 guide paragraph.
///
/// No i18n marker needed — Excel content is data, not Dart UI (Hard Constraint #6).
// ignore: prefer_expression_function_bodies
void _buildInstruccionesSheet(Excel excel) {
  final sheet = excel['Instrucciones'];

  // A1 — heading
  _setCell(sheet, 0, 0, 'Instrucciones de uso');

  // A3/B3 — column meanings header (row index 2)
  _setCell(sheet, 0, 2, 'Columna');
  _setCell(sheet, 1, 2, 'Descripción');

  // A4..A11 / B4..B11 — column descriptions (row indices 3..10)
  const columnNames = [
    'Ejercicio',
    'Series',
    'Reps Min',
    'Reps Max',
    'Peso Kg',
    'Descanso Seg',
    'Notas',
    'Nivel',
  ];
  const columnDescriptions = [
    'Nombre del ejercicio. Si lo tipeás como aparece en la app, lo matcheamos automático.',
    'Cantidad de series objetivo (número entero).',
    'Repeticiones mínimas por serie (entero).',
    'Repeticiones máximas por serie (entero). Si dejás vacío usa Reps Min.',
    'Peso objetivo en kilogramos (puede ser decimal).',
    'Descanso entre series en segundos.',
    'Texto libre — técnica, tempo, RPE, lo que quieras.',
    'Nivel del plan (principiante, intermedio o avanzado). Solo en la hoja Plan.',
  ];
  for (var i = 0; i < columnNames.length; i++) {
    _setCell(sheet, 0, 3 + i, columnNames[i]);
    _setCell(sheet, 1, 3 + i, columnDescriptions[i]);
  }

  // A13 — valid Nivel heading (row index 12)
  _setCell(sheet, 0, 12, 'Valores válidos para Nivel:');

  // A14..A16 — valid Nivel values (row indices 13..15)
  _setCell(sheet, 0, 13, 'principiante');
  _setCell(sheet, 0, 14, 'intermedio');
  _setCell(sheet, 0, 15, 'avanzado');

  // A18 — example heading (row index 17)
  _setCell(sheet, 0, 17, 'Ejemplo:');

  // A19..H19 — example row headers (row index 18)
  const exampleHeaders = [
    'Ejercicio',
    'Series',
    'Reps Min',
    'Reps Max',
    'Peso Kg',
    'Descanso Seg',
    'Notas',
    'Nivel',
  ];
  for (var i = 0; i < exampleHeaders.length; i++) {
    _setCell(sheet, i, 18, exampleHeaders[i]);
  }

  // A20..H20 — example row data (row index 19)
  _setCell(sheet, 0, 19, 'Sentadilla con barra');
  _setCell(sheet, 1, 19, '4');
  _setCell(sheet, 2, 19, '8');
  _setCell(sheet, 3, 19, '10');
  _setCell(sheet, 4, 19, '60');
  _setCell(sheet, 5, 19, '90');
  _setCell(sheet, 6, 19, 'Calentar bien');
  _setCell(sheet, 7, 19, 'intermedio');

  // A22 — guide paragraph (row index 21)
  _setCell(
    sheet,
    0,
    21,
    'Completá una hoja por día (Día 1, Día 2, …). El Nivel va en la hoja "Plan", '
    'fila "Nivel". Si un ejercicio no matchea, lo asignás manualmente desde la preview.',
  );
}

/// Sets a text cell at (col, row) on [sheet].
void _setCell(Sheet sheet, int col, int row, String value) {
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      .value = TextCellValue(value);
}

void _appendRow(Sheet sheet, List<Object?> values) {
  sheet.appendRow(values.map<CellValue?>(_toCellValue).toList());
}

CellValue? _toCellValue(Object? v) {
  if (v == null) return null;
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(v);
  if (v is bool) return BoolCellValue(v);
  return TextCellValue(v.toString());
}
