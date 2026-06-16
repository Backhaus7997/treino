import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/data/excel_parser.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/plan_import_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/data/exercise_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';

// ---------------------------------------------------------------------------
// Gap tests for the coach_hub data/logic layer.
//
// These complement the existing suites under test/features/coach_hub/ and the
// test-plan-2026-06-16.md catalog (coach_hub-02, -05, -09, -11, -12, -16).
// They target regression-prone parser boundaries, the fuzzy-match scoring
// threshold, and repository metadata propagation. Source under
// lib/features/coach_hub/ was read to ensure each assertion reflects the
// ACTUAL (correct) behavior — not the buggy behavior, where any was found.
// ---------------------------------------------------------------------------

/// Mirrors the cell encoding used by the existing excel_parser_test helpers.
CellValue? _toCell(Object? v) {
  if (v == null) return null;
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(v);
  return TextCellValue(v.toString());
}

void _appendRow(Sheet sheet, List<Object?> values) {
  sheet.appendRow(values.map(_toCell).toList());
}

const _dayHeaders = [
  'Ejercicio',
  'Series',
  'Reps Min',
  'Reps Max',
  'Peso Kg',
  'Descanso Seg',
  'Notas',
];

/// Builds an in-memory .xlsx with a Plan sheet plus the given Día sheets.
/// [days] maps a day number to its data rows (each row is a list of cell
/// values in the order of [_dayHeaders]).
Uint8List _buildWorkbook({
  String name = 'Mi plan',
  Object daysPerWeek = 3,
  Object durationWeeks = 8,
  String level = 'intermedio',
  required Map<int, List<List<Object?>>> days,
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

  for (final entry in days.entries) {
    final sheet = excel['Día ${entry.key}'];
    _appendRow(sheet, _dayHeaders);
    for (final row in entry.value) {
      _appendRow(sheet, row);
    }
  }

  return Uint8List.fromList(excel.save()!);
}

List<RawParsedDay> _dayWith(List<String> names) => [
      RawParsedDay(
        dayNumber: 1,
        items: names
            .map((n) => RawParsedItem(
                  rowName: n,
                  sets: 4,
                  repsMin: 8,
                  repsMax: 10,
                ))
            .toList(),
      ),
    ];

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

Exercise _ex(String id, String name, String muscle) => Exercise(
      id: id,
      name: name,
      muscleGroup: muscle,
      category: 'compound',
    );

void main() {
  // -------------------------------------------------------------------------
  // coach_hub-02 (P1) — upper-boundary daysPerWeek=7 / durationWeeks=52.
  // The range guards are inclusive (1..7, 1..52); boundary values must NOT
  // trip them. Regression guard for off-by-one in the parser validation.
  // -------------------------------------------------------------------------
  test('coach_hub-02: accepts boundary daysPerWeek=7 and durationWeeks=52', () {
    final days = <int, List<List<Object?>>>{
      for (var d = 1; d <= 7; d++)
        d: [
          ['Sentadilla', 4, 8, 10, 60, 90, ''],
        ],
    };

    final result = parseExcelBytes(_buildWorkbook(
      daysPerWeek: 7,
      durationWeeks: 52,
      days: days,
    ));

    expect(result.daysPerWeek, 7);
    expect(result.durationWeeks, 52);
    expect(result.days, hasLength(7));
    expect(
      result.days.map((d) => d.dayNumber).toList(),
      [1, 2, 3, 4, 5, 6, 7],
    );
  });

  // -------------------------------------------------------------------------
  // coach_hub-05 (P1) — empty Reps Max defaults to Reps Min.
  // Source: RawParsedItem(repsMax: repsMax ?? repsMin). An empty cell parses
  // to null via _asInt, so repsMax must fall back to repsMin (not 0/throw).
  // -------------------------------------------------------------------------
  test('coach_hub-05: defaults repsMax to repsMin when Reps Max is empty', () {
    final result = parseExcelBytes(_buildWorkbook(
      daysPerWeek: 1,
      days: {
        1: [
          // Ejercicio, Series, Reps Min, Reps Max(empty), Peso, Descanso, Notas
          ['Sentadilla', 3, 8, '', 60, 90, ''],
        ],
      },
    ));

    final item = result.days.first.items.first;
    expect(item.repsMin, 8);
    expect(item.repsMax, 8, reason: 'empty Reps Max should fall back to Reps Min');
  });

  // -------------------------------------------------------------------------
  // coach_hub-09 (P2, high regression value) — day sheets are sorted by their
  // day number regardless of workbook insertion order. Sheets are inserted
  // out of order (3, 1, 2); parsed days must come back [1, 2, 3].
  // -------------------------------------------------------------------------
  test('coach_hub-09: sorts day sheets by number regardless of workbook order',
      () {
    // LinkedHashMap preserves insertion order → sheets created 3, 1, 2.
    final days = <int, List<List<Object?>>>{
      3: [
        ['Remo', 3, 10, 12, 40, 60, ''],
      ],
      1: [
        ['Sentadilla', 4, 8, 10, 60, 90, ''],
      ],
      2: [
        ['Press banca', 4, 8, 10, 50, 90, ''],
      ],
    };

    final result = parseExcelBytes(_buildWorkbook(daysPerWeek: 3, days: days));

    expect(
      result.days.map((d) => d.dayNumber).toList(),
      [1, 2, 3],
      reason: 'days must be sorted ascending by dayNumber',
    );
    expect(result.days.first.items.first.rowName, 'Sentadilla');
    expect(result.days.last.items.first.rowName, 'Remo');
  });

  // -------------------------------------------------------------------------
  // coach_hub-11 (P1) — fuzzy matching ignores tokens shorter than 3 chars.
  // Query 'el de barra' → tokens 'el'(2,skip), 'de'(2,skip), 'barra'(5).
  // Only 'barra' is scored; it is shared with catalog 'Remo con barra'
  // (score 1, threshold ceil(1/2)=1) → the item resolves to that exercise.
  // -------------------------------------------------------------------------
  test('coach_hub-11: skips tokens shorter than 3 chars in fuzzy matching', () {
    final catalog = [
      MatcherExercise(
          id: 'remo-con-barra', name: 'Remo con barra', muscleGroup: 'Espalda'),
    ];

    final result = matchExercises(_dayWith(['el de barra']), catalog);

    expect(result.unmatched, isEmpty);
    expect(result.days.first.items.first.exerciseId, 'remo-con-barra');
    expect(result.days.first.items.first.exerciseName, 'Remo con barra');
  });

  // -------------------------------------------------------------------------
  // coach_hub-12 (P0) — fuzzy score must be >= ceil(tokens/2) to accept.
  // Query 'Press banca inclinado' (3 long tokens) shares ZERO tokens with the
  // only catalog entry 'Sentadilla con barra' → best score 0 < ceil(3/2)=2 →
  // item goes to unmatched. Guards against over-matching on coincidence.
  // -------------------------------------------------------------------------
  test('coach_hub-12: requires fuzzy score >= ceil(tokens/2) to accept a match',
      () {
    final catalog = [
      MatcherExercise(
          id: 'sentadilla-con-barra',
          name: 'Sentadilla con barra',
          muscleGroup: 'Piernas'),
    ];

    final result =
        matchExercises(_dayWith(['Press banca inclinado']), catalog);

    expect(result.unmatched, hasLength(1));
    expect(result.unmatched.first.rowName, 'Press banca inclinado');
    final item = result.days.first.items.first;
    expect(item.exerciseId, isNull);
    expect(item.exerciseName, 'Press banca inclinado',
        reason: 'unmatched item keeps the raw rowName as exerciseName');
  });

  // -------------------------------------------------------------------------
  // coach_hub-16 (P0) — PlanImportRepository.parseAndMatch propagates Excel
  // metadata (name/daysPerWeek/durationWeeks/level) AND maps rows missing
  // from a partial catalog into `unmatched`, while matched rows carry their
  // exerciseId. Complements the existing repo tests (which use full or fully
  // disjoint catalogs) by asserting a partial-catalog split with metadata.
  // -------------------------------------------------------------------------
  test(
      'coach_hub-16: parseAndMatch preserves plan metadata and maps partial '
      'unmatched', () async {
    final exerciseRepo = _MockExerciseRepository();
    // Catalog covers only "Sentadilla con barra"; "Press banca" and
    // "Remo raro xyz" are absent → they land in unmatched.
    when(() => exerciseRepo.listAll()).thenAnswer((_) async => [
          _ex('sentadilla-con-barra', 'Sentadilla con barra', 'Piernas'),
        ]);
    final repo = PlanImportRepository(exerciseRepository: exerciseRepo);

    final bytes = _buildWorkbook(
      name: 'Plan Hipertrofia',
      daysPerWeek: 1,
      durationWeeks: 12,
      level: 'avanzado',
      days: {
        1: [
          ['Sentadilla con barra', 4, 8, 10, 60, 90, ''],
          ['Press banca', 4, 8, 10, 50, 90, ''],
          ['Remo raro xyz', 3, 10, 12, 40, 60, ''],
        ],
      },
    );

    final plan = await repo.parseAndMatch(bytes: bytes);

    // Metadata carried straight from the Excel.
    expect(plan.name, 'Plan Hipertrofia');
    expect(plan.daysPerWeek, 1);
    expect(plan.durationWeeks, 12);
    expect(plan.level, ExperienceLevel.advanced);

    // Partial-catalog split: one matched, two unmatched.
    final items = plan.days.single.items;
    expect(items, hasLength(3));
    expect(items.first.exerciseId, 'sentadilla-con-barra');
    expect(items.first.muscleGroup, 'Piernas');

    expect(plan.unmatched, hasLength(2));
    expect(
      plan.unmatched.map((u) => u.rowName).toSet(),
      {'Press banca', 'Remo raro xyz'},
    );
    // The unmatched rows have no exerciseId but keep their raw name.
    final unmatchedItems =
        items.where((i) => i.exerciseId == null).map((i) => i.exerciseName);
    expect(unmatchedItems.toSet(), {'Press banca', 'Remo raro xyz'});
  });
}
