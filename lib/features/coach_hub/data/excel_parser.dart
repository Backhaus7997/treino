import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../profile/domain/experience_level.dart';

class ExcelParseException implements Exception {
  ExcelParseException(this.message);
  final String message;
  @override
  String toString() => 'ExcelParseException: $message';
}

/// Datos crudos del Excel sin matchear contra `exercises`.
/// El matcher consume esto y devuelve `ParsedPlan`.
class RawParsedPlan {
  RawParsedPlan({
    required this.name,
    required this.daysPerWeek,
    required this.durationWeeks,
    required this.level,
    required this.days,
  });

  final String name;
  final int daysPerWeek;
  final int durationWeeks;
  final ExperienceLevel level;
  final List<RawParsedDay> days;
}

class RawParsedDay {
  RawParsedDay({required this.dayNumber, required this.items});
  final int dayNumber;
  final List<RawParsedItem> items;
}

class RawParsedItem {
  RawParsedItem({
    required this.rowName,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    this.weightKg,
    this.restSec,
    this.notes,
    this.order,
    this.block,
  });

  final String rowName;
  final int sets;
  final int repsMin;
  final int repsMax;
  final double? weightKg;
  final int? restSec;
  final String? notes;

  // Solo el formato periodizado (hoja "Programa") los usa. En el formato
  // simple (hoja "Día N") quedan null: el orden lo da la posición de la fila
  // y no hay columna de superserie.
  final int? order;

  /// Letra de superserie tal cual viene del Excel ("A", "B"…); null = suelto.
  /// El matcher la convierte luego a `RoutineSlot.supersetGroup` (int?).
  final String? block;
}

/// Plan periodizado: en lugar de una hoja por día con la misma prescripción
/// para todas las semanas, lleva la dimensión SEMANA. Una sola hoja "Programa"
/// donde cada fila es `Semana + Día + Ejercicio + prescripción`, así un mismo
/// plan progresa semana a semana sin duplicar rutinas.
class RawParsedPeriodizedPlan {
  RawParsedPeriodizedPlan({
    required this.name,
    required this.daysPerWeek,
    required this.durationWeeks,
    required this.level,
    required this.weeks,
  });

  final String name;
  final int daysPerWeek;
  final int durationWeeks;
  final ExperienceLevel level;
  final List<RawParsedWeek> weeks;
}

class RawParsedWeek {
  RawParsedWeek({required this.weekNumber, required this.days});
  final int weekNumber;
  final List<RawParsedDay> days;
}

const _planSheet = 'Plan';
const _programaSheet = 'Programa';
final _daySheetRegex = RegExp(r'^D[ií]a\s*(\d+)$', caseSensitive: false);

const _levelEsToWire = {
  'principiante': ExperienceLevel.beginner,
  'intermedio': ExperienceLevel.intermediate,
  'avanzado': ExperienceLevel.advanced,
};

String _asString(dynamic v) {
  if (v == null) return '';
  if (v is Data) return _asString(v.value);
  return v.toString().trim();
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is Data) return _asInt(v.value);
  if (v is int) return v;
  if (v is double) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return int.tryParse(s) ?? double.tryParse(s)?.toInt();
}

double? _asNumber(dynamic v) {
  if (v == null) return null;
  if (v is Data) return _asNumber(v.value);
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

dynamic _cell(Sheet sheet, int col, int row) {
  if (row < 0 || row > sheet.maxRows) return null;
  if (col < 0 || col > sheet.maxColumns) return null;
  final data = sheet.cell(CellIndex.indexByColumnRow(
    columnIndex: col,
    rowIndex: row,
  ));
  return data.value;
}

RawParsedPlan _parsePlanSheet(Sheet sheet) {
  final map = <String, dynamic>{};
  for (var row = 1; row <= 20 && row <= sheet.maxRows; row++) {
    final key = _asString(_cell(sheet, 0, row)).toLowerCase();
    if (key.isEmpty) continue;
    map[key] = _cell(sheet, 1, row);
  }

  final name = _asString(map['nombre'] ?? map['nombre del plan'] ?? '');
  final daysPerWeek = _asInt(map['dias por semana'] ?? map['días por semana']);
  final durationWeeks = _asInt(map['duracion semanas'] ??
      map['duración semanas'] ??
      map['duracion (semanas)']);
  final levelEs = _asString(map['nivel']).toLowerCase();

  if (name.isEmpty) {
    throw ExcelParseException('Falta "Nombre" en la hoja Plan.');
  }
  if (daysPerWeek == null || daysPerWeek < 1 || daysPerWeek > 7) {
    throw ExcelParseException(
      'Días por semana debe ser un número entre 1 y 7.',
    );
  }
  if (durationWeeks == null || durationWeeks < 1 || durationWeeks > 52) {
    throw ExcelParseException(
      'Duración semanas debe ser un número entre 1 y 52.',
    );
  }
  final level = _levelEsToWire[levelEs];
  if (level == null) {
    throw ExcelParseException(
      'Nivel debe ser: principiante, intermedio o avanzado.',
    );
  }

  return RawParsedPlan(
    name: name,
    daysPerWeek: daysPerWeek,
    durationWeeks: durationWeeks,
    level: level,
    days: const [],
  );
}

RawParsedDay _parseDaySheet(Sheet sheet, int dayNumber) {
  final items = <RawParsedItem>[];
  final maxRow = sheet.maxRows;

  for (var row = 1; row <= maxRow; row++) {
    final name = _asString(_cell(sheet, 0, row));
    if (name.isEmpty) continue;

    final sets = _asInt(_cell(sheet, 1, row));
    final repsMin = _asInt(_cell(sheet, 2, row));
    final repsMax = _asInt(_cell(sheet, 3, row));
    final weightKg = _asNumber(_cell(sheet, 4, row));
    final restSec = _asInt(_cell(sheet, 5, row));
    final notes = _asString(_cell(sheet, 6, row));

    if (sets == null || sets < 1) {
      throw ExcelParseException(
        'Día $dayNumber, fila ${row + 1}: faltan series.',
      );
    }
    if (repsMin == null || repsMin < 1) {
      throw ExcelParseException(
        'Día $dayNumber, fila ${row + 1}: faltan reps mínimas.',
      );
    }
    if (repsMax != null && repsMax < repsMin) {
      throw ExcelParseException(
        'Día $dayNumber, fila ${row + 1}: reps máximas < reps mínimas.',
      );
    }

    items.add(RawParsedItem(
      rowName: name,
      sets: sets,
      repsMin: repsMin,
      repsMax: repsMax ?? repsMin,
      weightKg: weightKg,
      restSec: restSec,
      notes: notes.isEmpty ? null : notes,
    ));
  }

  if (items.isEmpty) {
    throw ExcelParseException('Día $dayNumber: sin ejercicios.');
  }

  return RawParsedDay(dayNumber: dayNumber, items: items);
}

/// True si el workbook trae el formato PERIODIZADO (hoja "Programa"). Se usa en
/// el upload para decidir qué parser/preview disparar. Si el archivo no decodea,
/// devuelve false y el flujo simple emite el error correspondiente.
bool isPeriodizedWorkbook(Uint8List bytes) {
  try {
    return Excel.decodeBytes(bytes).sheets.containsKey(_programaSheet);
  } catch (_) {
    return false;
  }
}

RawParsedPlan parseExcelBytes(Uint8List bytes) {
  Excel workbook;
  try {
    workbook = Excel.decodeBytes(bytes);
  } catch (_) {
    throw ExcelParseException('El archivo no es un Excel válido.');
  }

  final planSheet = workbook.sheets[_planSheet];
  if (planSheet == null) {
    throw ExcelParseException('Falta la hoja "Plan".');
  }

  final plan = _parsePlanSheet(planSheet);

  final days = <RawParsedDay>[];
  for (final entry in workbook.sheets.entries) {
    final match = _daySheetRegex.firstMatch(entry.key);
    if (match == null) continue;
    final dayNumber = int.parse(match.group(1)!);
    days.add(_parseDaySheet(entry.value, dayNumber));
  }

  if (days.isEmpty) {
    throw ExcelParseException(
      'No se encontraron hojas de días (Día 1, Día 2, etc.).',
    );
  }
  if (days.length != plan.daysPerWeek) {
    throw ExcelParseException(
      'Hojas de día (${days.length}) no coinciden con "Días por '
      'semana" (${plan.daysPerWeek}).',
    );
  }

  days.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

  return RawParsedPlan(
    name: plan.name,
    daysPerWeek: plan.daysPerWeek,
    durationWeeks: plan.durationWeeks,
    level: plan.level,
    days: days,
  );
}

/// Parsea el formato PERIODIZADO: hoja "Plan" (metadata) + hoja "Programa"
/// (una fila por ejercicio, con columna Semana). Lector tonto: agrupa por
/// Semana → Día y ordena por la columna Orden. No exige que estén todas las
/// semanas cargadas — el PF puede dejar el template con un ejemplo y expandirlo.
RawParsedPeriodizedPlan parsePeriodizedExcelBytes(Uint8List bytes) {
  Excel workbook;
  try {
    workbook = Excel.decodeBytes(bytes);
  } catch (_) {
    throw ExcelParseException('El archivo no es un Excel válido.');
  }

  final planSheet = workbook.sheets[_planSheet];
  if (planSheet == null) {
    throw ExcelParseException('Falta la hoja "Plan".');
  }
  final meta = _parsePlanSheet(planSheet);

  final programa = workbook.sheets[_programaSheet];
  if (programa == null) {
    throw ExcelParseException('Falta la hoja "Programa".');
  }

  // Columnas: 0 Semana · 1 Día · 2 Orden · 3 Bloque · 4 Ejercicio · 5 Series ·
  // 6 Reps Min · 7 Reps Max · 8 Peso Kg · 9 Descanso Seg · 10 Notas.
  final byWeek = <int, Map<int, List<RawParsedItem>>>{};
  final maxRow = programa.maxRows;
  for (var row = 1; row <= maxRow; row++) {
    final name = _asString(_cell(programa, 4, row));
    if (name.isEmpty) continue; // fila vacía → se ignora

    final week = _asInt(_cell(programa, 0, row));
    final day = _asInt(_cell(programa, 1, row));
    final order = _asInt(_cell(programa, 2, row));
    final block = _asString(_cell(programa, 3, row));
    final sets = _asInt(_cell(programa, 5, row));
    final repsMin = _asInt(_cell(programa, 6, row));
    final repsMax = _asInt(_cell(programa, 7, row));
    final weightKg = _asNumber(_cell(programa, 8, row));
    final restSec = _asInt(_cell(programa, 9, row));
    final notes = _asString(_cell(programa, 10, row));

    final where = 'Programa, fila ${row + 1}';
    if (week == null || week < 1 || week > meta.durationWeeks) {
      throw ExcelParseException(
        '$where: "Semana" debe estar entre 1 y ${meta.durationWeeks}.',
      );
    }
    if (day == null || day < 1 || day > meta.daysPerWeek) {
      throw ExcelParseException(
        '$where: "Día" debe estar entre 1 y ${meta.daysPerWeek}.',
      );
    }
    if (sets == null || sets < 1) {
      throw ExcelParseException('$where: faltan series.');
    }
    if (repsMin == null || repsMin < 1) {
      throw ExcelParseException('$where: faltan reps mínimas.');
    }
    if (repsMax != null && repsMax < repsMin) {
      throw ExcelParseException('$where: reps máximas < reps mínimas.');
    }

    byWeek
        .putIfAbsent(week, () => <int, List<RawParsedItem>>{})
        .putIfAbsent(day, () => <RawParsedItem>[])
        .add(RawParsedItem(
          rowName: name,
          sets: sets,
          repsMin: repsMin,
          repsMax: repsMax ?? repsMin,
          weightKg: weightKg,
          restSec: restSec,
          notes: notes.isEmpty ? null : notes,
          order: order,
          block: block.isEmpty ? null : block,
        ));
  }

  if (byWeek.isEmpty) {
    throw ExcelParseException('La hoja "Programa" no tiene ejercicios.');
  }

  final weeks = <RawParsedWeek>[];
  for (final w in byWeek.keys.toList()..sort()) {
    final daysMap = byWeek[w]!;
    final days = <RawParsedDay>[];
    for (final d in daysMap.keys.toList()..sort()) {
      final items = daysMap[d]!
        ..sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));
      days.add(RawParsedDay(dayNumber: d, items: items));
    }
    weeks.add(RawParsedWeek(weekNumber: w, days: days));
  }

  return RawParsedPeriodizedPlan(
    name: meta.name,
    daysPerWeek: meta.daysPerWeek,
    durationWeeks: meta.durationWeeks,
    level: meta.level,
    weeks: weeks,
  );
}
