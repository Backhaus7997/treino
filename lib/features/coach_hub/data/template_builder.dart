import 'dart:typed_data';

import 'package:excel/excel.dart';

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
    _appendRow(sheet, dayHeaders);
    _appendRow(sheet, ['Sentadilla con barra', 4, 8, 10, 60, 90, '']);
    _appendRow(sheet, ['Press banca', 4, 8, 10, 50, 90, '']);
    _appendRow(sheet, ['Remo con barra', 3, 10, 12, 40, 60, '']);
  }

  final bytes = excel.save();
  if (bytes == null) {
    throw StateError('No se pudo generar el template.');
  }
  return Uint8List.fromList(bytes);
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
