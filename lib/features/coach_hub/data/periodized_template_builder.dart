import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Genera el .xlsx template PERIODIZADO para que el PF lo descargue.
///
/// A diferencia del template simple (`buildPlanTemplateBytes`, una hoja por
/// día y la misma prescripción para todas las semanas), este formato lleva la
/// dimensión SEMANA: una sola hoja "Programa" donde cada fila es
/// `Semana + Día + Ejercicio + prescripción`. Así un mismo plan puede progresar
/// semana a semana (subir reps/series/peso) sin duplicar rutinas.
///
/// La app resuelve sola qué mostrarle al alumno según la semana en curso.
///
/// Convención de superserie: la columna "Bloque" agrupa ejercicios consecutivos
/// del mismo (Semana, Día). Misma letra en filas seguidas = superserie; vacío =
/// ejercicio suelto. Esto mapea 1:1 a `RoutineSlot.supersetGroup`.
Uint8List buildPeriodizedTemplateBytes() {
  final excel = Excel.createExcel();

  // El package crea "Sheet1" por defecto — la renombramos a Plan.
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != 'Plan') {
    excel.rename(defaultSheet, 'Plan');
  }

  // ── Hoja "Plan" — metadata del programa ────────────────────────────────────
  final plan = excel.sheets['Plan']!;
  _appendRow(plan, ['Campo', 'Valor']);
  _appendRow(plan, ['Nombre', 'Fuerza tren superior']);
  _appendRow(plan, ['Nivel', 'intermedio']);
  _appendRow(plan, ['Días por semana', 4]);
  _appendRow(plan, ['Duración semanas', 6]);
  plan.setColumnWidth(0, 22);
  plan.setColumnWidth(1, 24);
  _boldHeaderRow(plan, 2);

  // ── Hoja "Programa" — prescripción por semana/día ──────────────────────────
  const programaHeaders = [
    'Semana',
    'Día',
    'Orden',
    'Bloque',
    'Ejercicio',
    'Series',
    'Reps Min',
    'Reps Max',
    'Peso Kg',
    'Descanso Seg',
    'Notas',
  ];
  final programa = excel['Programa'];
  _appendRow(programa, programaHeaders);

  // Ejemplo: 2 semanas, 1 día, mostrando una superserie (Bloque A) + un
  // ejercicio suelto, y cómo la semana 2 progresa (más reps / más peso).
  // El PF reemplaza estas filas y copia el bloque para las semanas que falten.
  // Semana 1
  _appendRow(programa, [1, 1, 1, 'A', 'Press banca', 4, 6, 8, 50, 90, '']);
  _appendRow(programa, [1, 1, 2, 'A', 'Remo con barra', 4, 8, 10, 40, 90, '']);
  _appendRow(programa, [1, 1, 3, '', 'Press militar', 3, 8, 10, 30, 120, '']);
  // Semana 2 — misma estructura, progresión de reps/peso.
  _appendRow(programa, [2, 1, 1, 'A', 'Press banca', 4, 8, 10, 52, 90, '']);
  _appendRow(programa, [2, 1, 2, 'A', 'Remo con barra', 4, 10, 12, 42, 90, '']);
  _appendRow(programa, [2, 1, 3, '', 'Press militar', 3, 10, 12, 32, 120, '']);

  final widths = [8, 6, 7, 8, 28, 8, 10, 10, 9, 14, 30];
  for (var col = 0; col < widths.length; col++) {
    programa.setColumnWidth(col, widths[col].toDouble());
  }
  _boldHeaderRow(programa, programaHeaders.length);

  // ── Hoja "Instrucciones" ───────────────────────────────────────────────────
  final help = excel['Instrucciones'];
  _appendRow(help, ['Cómo cargar un plan periodizado']);
  _appendRow(help, ['']);
  _appendRow(help, [
    '1. Hoja "Plan": Nombre, Nivel (principiante / intermedio / avanzado), '
        'Días por semana (1–7) y Duración semanas (1–52).',
  ]);
  _appendRow(help, [
    '2. Hoja "Programa": una fila por ejercicio. Cada fila indica a qué '
        'SEMANA y DÍA pertenece.',
  ]);
  _appendRow(help, [
    '   Columnas: Semana · Día · Orden · Bloque · Ejercicio · Series · '
        'Reps Min · Reps Max · Peso Kg · Descanso Seg · Notas.',
  ]);
  _appendRow(help, [
    '3. Periodización: cargá la Semana 1 completa y copiá ese bloque de filas '
        'para la Semana 2, 3… cambiando el número de Semana',
  ]);
  _appendRow(help, [
    '   y ajustando lo que progrese (normalmente Series, Reps o Peso). El '
        'resto se mantiene igual.',
  ]);
  _appendRow(help, [
    '4. Bloque (superserie): misma letra (A, B…) en filas seguidas del mismo '
        'día = se ejecutan en superserie. Dejalo vacío para ejercicio suelto.',
  ]);
  _appendRow(help, [
    '5. Orden: define la secuencia dentro del día (1, 2, 3…).',
  ]);
  _appendRow(help, [
    '6. Series, Reps, Descanso y Semana/Día/Orden son números. Peso y Notas '
        'pueden quedar vacíos.',
  ]);
  _appendRow(help, [
    '7. El nombre del ejercicio se busca en el catálogo de TREINO. Si alguno '
        'no matchea, lo mapeás a mano al subir el archivo.',
  ]);
  _appendRow(help, [
    '8. No cambies los nombres de las hojas ("Plan", "Programa") ni de las '
        'columnas.',
  ]);
  help.setColumnWidth(0, 100);
  _boldHeaderRow(help, 1);

  final bytes = excel.save();
  if (bytes == null) {
    throw StateError('No se pudo generar el template periodizado.');
  }
  return Uint8List.fromList(bytes);
}

/// Aplica negrita a las primeras [colCount] celdas de la fila 0 (header).
void _boldHeaderRow(Sheet sheet, int colCount) {
  final headerStyle = CellStyle(bold: true);
  for (var col = 0; col < colCount; col++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
        .cellStyle = headerStyle;
  }
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
