import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'periodized_excel_parser.dart';

/// Cantidades de la plantilla descargable. El parser NO depende de ellas.
const int kTemplateDays = 7;
const int kTemplateRowsPerDay = 10;
const int kTemplateWeeks = 6;

/// Columnas de la hoja `Programa`: A = N°, B = ejercicio, C = DESCANSOS y
/// desde la D las semanas.
const double kProgramNumberWidth = 6;
const double kProgramExerciseWidth = 44;
const double kProgramRestWidth = 12;
const double kProgramWeekWidth = 14;

/// Genera el `.xlsx` de la plantilla periodizada que baja el PF desde el
/// Coach Hub: hoja `Programa` (7 bloques de día × 10 renglones vacíos, 6
/// semanas) y hoja `Instrucciones` con ejemplos GENÉRICOS de notación.
Uint8List buildPeriodizedTemplateBytes() {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != kProgramSheet) {
    excel.rename(defaultSheet, kProgramSheet);
  }
  final sheet = excel[kProgramSheet];

  sheet.setColumnWidth(0, kProgramNumberWidth);
  sheet.setColumnWidth(1, kProgramExerciseWidth);
  sheet.setColumnWidth(2, kProgramRestWidth);
  for (var w = 0; w < kTemplateWeeks; w++) {
    sheet.setColumnWidth(3 + w, kProgramWeekWidth);
  }

  final headerStyle = CellStyle(bold: true);
  var row = 0;
  for (var day = 1; day <= kTemplateDays; day++) {
    _put(sheet, 0, row, 'N°', headerStyle);
    _put(sheet, 1, row, 'DÍA $day', headerStyle);
    _put(sheet, 2, row, 'DESCANSOS', headerStyle);
    // Las etiquetas SEMANA van sólo en el encabezado del DÍA 1: el parser fija
    // las columnas con el primer encabezado.
    if (day == 1) {
      for (var w = 1; w <= kTemplateWeeks; w++) {
        _put(sheet, 2 + w, row, 'SEMANA $w', headerStyle);
      }
    }
    row += 1 + kTemplateRowsPerDay;
  }

  _buildInstructions(excel);

  final bytes = excel.save();
  if (bytes == null) {
    throw StateError('No se pudo generar la plantilla.');
  }
  return Uint8List.fromList(bytes);
}

void _put(Sheet sheet, int col, int row, String value, [CellStyle? style]) {
  final cell =
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
  cell.value = TextCellValue(value);
  if (style != null) cell.cellStyle = style;
}

/// Ejemplos genéricos: NUNCA ejercicios reales de un entrenador.
void _buildInstructions(Excel excel) {
  final sheet = excel[kInstructionsSheet];
  sheet.setColumnWidth(0, 34);
  sheet.setColumnWidth(1, 90);
  final bold = CellStyle(bold: true);

  var r = 0;
  void title(String text) {
    _put(sheet, 0, r, text, bold);
    r += 1;
  }

  void pair(String left, String right) {
    _put(sheet, 0, r, left);
    _put(sheet, 1, r, right);
    r += 1;
  }

  title('Cómo completar la hoja "Programa"');
  pair('Un bloque por día',
      'Cada bloque empieza con "DÍA N" y "DESCANSOS". Hasta 7 días y 16 semanas.');
  pair('Renglones',
      'Se carga un renglón sólo si tiene nombre de ejercicio. Los vacíos se ignoran.');
  pair('N°', 'Numerá los ejercicios de trabajo. Sin número = calentamiento.');
  pair('Superserie', 'EJERCICIO A + EJERCICIO B en el mismo renglón.');
  pair(
      'DESCANSOS',
      '90 = 90 s, 1\' = 60 s, 1\'30 = 90 s, 90\'\' = 90 s. Vacío = 60 s. '
          'En una superserie es el descanso al terminar todo el grupo.');
  r += 1;

  title('Notación de las celdas SEMANA');
  pair('Ejemplo', 'Qué significa');
  pair('3x8', '3 series de 8 repeticiones');
  pair('3xmax', '3 series al fallo');
  pair('8\'', '1 serie de 8 minutos');
  pair('3x8\'', '3 series de 8 minutos');
  pair('6m', '1 serie de 6 metros');
  pair('4x20m', '4 series de 20 metros');
  pair(
      '3x10 c/pierna',
      '3 series de 10; "c/pierna" queda como nota '
          '(también c/brazo y c/lado)');
  r += 1;

  title('Superseries: un valor por ejercicio, separados por "+"');
  pair('EJERCICIO A + EJERCICIO B   |   3x10+12',
      'Si sólo el primero trae series, valen para todos: 3x10 y 3x12.');
  pair('EJERCICIO A + EJERCICIO B   |   3x10+4x12',
      'Cada uno conserva su propio conteo.');
  pair('EJERCICIO A + EJERCICIO B   |   8\'+3x20',
      'Un tiempo o una distancia sin conteo es 1 serie.');
  pair('EJERCICIO A + EJERCICIO B + EJERCICIO C   |   3x4+2+6m',
      'Tres valores para tres ejercicios.');
  r += 1;

  title('Celda de semana vacía');
  pair('(vacía)',
      'El ejercicio va igual esa semana, sin repeticiones; completalas después en la app.');
}
