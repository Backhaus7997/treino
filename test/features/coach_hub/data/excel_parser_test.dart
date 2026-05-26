import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/excel_parser.dart';
import 'package:treino/features/coach_hub/data/template_builder.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

CellValue? _toCell(Object? v) {
  if (v == null) return null;
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(v);
  return TextCellValue(v.toString());
}

void _appendRow(Sheet sheet, List<Object?> values) {
  sheet.appendRow(values.map(_toCell).toList());
}

Uint8List _buildWorkbook({
  String name = 'Mi plan',
  Object daysPerWeek = 3,
  Object durationWeeks = 8,
  String level = 'intermedio',
  Map<int, List<List<Object?>>>? days,
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != 'Plan') {
    excel.rename(defaultSheet, 'Plan');
  }
  final plan = excel['Plan'];
  _appendRow(plan, ['Campo', 'Valor']);
  _appendRow(plan, ['Nombre', name]);
  _appendRow(plan, ['Días por semana', daysPerWeek]);
  _appendRow(plan, ['Duración semanas', durationWeeks]);
  _appendRow(plan, ['Nivel', level]);

  final dayMap = days ??
      {
        1: [
          ['Sentadilla', 4, 8, 10, 60, 90, ''],
        ],
        2: [
          ['Press banca', 4, 8, 10, 50, 90, ''],
        ],
        3: [
          ['Remo', 3, 10, 12, 40, 60, ''],
        ],
      };

  const dayHeaders = [
    'Ejercicio',
    'Series',
    'Reps Min',
    'Reps Max',
    'Peso Kg',
    'Descanso Seg',
    'Notas',
  ];
  for (final entry in dayMap.entries) {
    final sheet = excel['Día ${entry.key}'];
    _appendRow(sheet, dayHeaders);
    for (final row in entry.value) {
      _appendRow(sheet, row);
    }
  }
  return Uint8List.fromList(excel.save()!);
}

void main() {
  group('parseExcelBytes', () {
    test('parsea un plan válido', () {
      final result = parseExcelBytes(_buildWorkbook());
      expect(result.name, 'Mi plan');
      expect(result.daysPerWeek, 3);
      expect(result.durationWeeks, 8);
      expect(result.level, ExperienceLevel.intermediate);
      expect(result.days, hasLength(3));
      expect(result.days.first.items.first.rowName, 'Sentadilla');
    });

    test('falla si falta el nombre', () {
      expect(
        () => parseExcelBytes(_buildWorkbook(name: '')),
        throwsA(isA<ExcelParseException>()),
      );
    });

    test('falla si daysPerWeek está fuera de rango', () {
      expect(
        () => parseExcelBytes(_buildWorkbook(daysPerWeek: 8)),
        throwsA(isA<ExcelParseException>()),
      );
    });

    test('falla si nivel inválido', () {
      expect(
        () => parseExcelBytes(_buildWorkbook(level: 'experto')),
        throwsA(isA<ExcelParseException>()),
      );
    });

    test('falla si cantidad de hojas día no coincide con daysPerWeek', () {
      expect(
        () => parseExcelBytes(_buildWorkbook(
          daysPerWeek: 3,
          days: {
            1: [
              ['Sentadilla', 4, 8, 10, 60, 90, ''],
            ],
          },
        )),
        throwsA(isA<ExcelParseException>()),
      );
    });

    test('falla si reps max < reps min', () {
      expect(
        () => parseExcelBytes(_buildWorkbook(
          daysPerWeek: 1,
          days: {
            1: [
              ['Sentadilla', 4, 10, 8, 60, 90, ''],
            ],
          },
        )),
        throwsA(isA<ExcelParseException>()),
      );
    });

    test('falla si día sin ejercicios', () {
      expect(
        () => parseExcelBytes(_buildWorkbook(
          daysPerWeek: 1,
          days: {1: []},
        )),
        throwsA(isA<ExcelParseException>()),
      );
    });

    test('el template generado se puede parsear', () {
      final result = parseExcelBytes(buildPlanTemplateBytes());
      expect(result.daysPerWeek, 3);
      expect(result.days, hasLength(3));
      expect(result.days.first.items, hasLength(3));
    });
  });
}
