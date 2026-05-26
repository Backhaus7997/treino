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
  });

  final String rowName;
  final int sets;
  final int repsMin;
  final int repsMax;
  final double? weightKg;
  final int? restSec;
  final String? notes;
}

const _planSheet = 'Plan';
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
  final daysPerWeek =
      _asInt(map['dias por semana'] ?? map['días por semana']);
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
