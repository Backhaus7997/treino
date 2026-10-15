import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_excel_parser.dart';
import 'package:treino/features/coach_hub/data/periodized_routine_mapper.dart';
import 'package:treino/features/coach_hub/data/periodized_template_builder.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

/// Escribe celdas en la plantilla ya construida (por fila/columna base 0).
Uint8List _fill(Uint8List template, Map<(int, int), Object> cells) {
  final excel = Excel.decodeBytes(template);
  final sheet = excel[kProgramSheet];
  cells.forEach((rc, v) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: rc.$2, rowIndex: rc.$1))
        .value = v is int ? IntCellValue(v) : TextCellValue(v.toString());
  });
  return Uint8List.fromList(excel.save()!);
}

List<MatcherExercise> _catalog() => [
      MatcherExercise(id: 'a', name: 'Ejercicio A', muscleGroup: 'legs'),
      MatcherExercise(id: 'b', name: 'Ejercicio B', muscleGroup: 'core'),
      MatcherExercise(id: 'c', name: 'Ejercicio C', muscleGroup: 'chest'),
      MatcherExercise(id: 't', name: 'Trote', muscleGroup: 'cardio'),
      MatcherExercise(id: 'ab', name: 'Abdominal', muscleGroup: 'core'),
    ];

void main() {
  group('plantilla descargable', () {
    final template = buildPeriodizedTemplateBytes();
    final book = Excel.decodeBytes(template);

    test('hojas Programa e Instrucciones, y nada del formato viejo', () {
      expect(book.sheets.keys.toList(), [kProgramSheet, kInstructionsSheet]);
    });

    test(
        'Programa: encabezado del DÍA 1 con 6 semanas y 7 bloques de 10 '
        'renglones', () {
      final s = book[kProgramSheet];
      String at(int r, int c) => s
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value
          .toString();
      expect(
        [for (var c = 0; c < 9; c++) at(0, c)],
        ['N°', 'DÍA 1', 'DESCANSOS', for (var w = 1; w <= 6; w++) 'SEMANA $w'],
      );
      for (var d = 1; d <= 7; d++) {
        final row = (d - 1) * 11;
        expect(at(row, 0), 'N°');
        expect(at(row, 1), 'DÍA $d');
        expect(at(row, 2), 'DESCANSOS');
        if (d > 1) expect(at(row, 3), 'null'); // sin SEMANA repetida
      }
      expect(at(11 * 7 - 1, 1), 'null');
    });

    test('Instrucciones: notación genérica, sin ejercicios cargados', () {
      final s = book[kInstructionsSheet];
      final all = s.rows
          .expand((r) => r)
          .map((d) => d?.value?.toString() ?? '')
          .join('\n');
      expect(all, contains('3xmax'));
      expect(all, contains('c/pierna'));
      expect(all, contains('EJERCICIO A + EJERCICIO B'));
      expect(all.toLowerCase(), isNot(contains('sentadilla')));
    });

    test(
        'la plantilla vacía se lee: 7 días, 1 semana (las 6 columnas vacías no '
        'cuentan) y sólo el error de "sin ejercicios"', () {
      final r = parsePeriodizedExcel(template);
      expect(r.plan!.numWeeks, 1);
      expect(r.plan!.days.map((d) => d.dayNumber), [1, 2, 3, 4, 5, 6, 7]);
      expect(r.errors.map((d) => d.code), [ImportDiagnosticCode.noExercises]);
    });
  });

  group('round-trip plantilla → parser → matcher → Routine', () {
    late Routine routine;
    late PeriodizedParseResult parsed;
    late PeriodizedMatchResult match;

    setUp(() {
      final cells = <(int, int), Object>{
        // DÍA 1: calentamiento (superserie), superserie de 3 con distancia y
        // un renglón común con calificador y una semana vacía.
        (1, 1): 'Trote + Abdominal',
        (1, 3): "8'+3x20",
        (1, 4): "8'+3x24",
        (1, 5): "9'+3x24",
        (1, 6): "9'+3x28",
        (1, 7): "10'+3x28",
        (1, 8): "10'+3x30",
        (2, 0): 1,
        (2, 1): 'Ejercicio A + Ejercicio B + Ejercicio C',
        (2, 2): 90,
        for (var w = 0; w < 6; w++) (2, 3 + w): '3x${4 + w}+2+6m',
        (3, 0): 2,
        (3, 1): 'Ejercicio B',
        (3, 3): '3x10 c/pierna',
        (3, 4): '3xmax',
        // (3, 5) vacía a propósito.
        (3, 6): '4x8',
        (3, 7): '4x8',
        (3, 8): '4x8',
        // DÍA 2: una fila de duración pura.
        (12, 0): 1,
        (12, 1): 'Trote',
        (12, 2): "1'30''",
        for (var w = 0; w < 6; w++) (12, 3 + w): "${20 + w}'",
      };
      parsed =
          parsePeriodizedExcel(_fill(buildPeriodizedTemplateBytes(), cells));
      expect(parsed.errors, isEmpty, reason: '${parsed.diagnostics}');
      match = matchPeriodizedPlan(parsed.plan!, _catalog());
      expect(match.needsReview, isEmpty);
      routine = mapPeriodizedPlanToRoutine(
        parsed.plan!,
        match.autoAssigned,
        routineId: 'r1',
        routineName: 'Plan importado',
        level: ExperienceLevel.intermediate,
      );
    });

    test('estructura general', () {
      expect(routine.numWeeks, 6);
      expect(routine.days.map((d) => d.dayNumber), [1, 2]);
      expect(routine.days[0].slots, hasLength(6));
      expect(routine.days[1].slots, hasLength(1));
      // Los 5 bloques de la plantilla sin ejercicios quedan en el borrador
      // pero no son días de la Routine.
      expect(parsed.plan!.days, hasLength(7));
    });

    test(
        'calentamiento: warmup, duración + reps, superserie sin descanso '
        'entre sí', () {
      final trote = routine.days[0].slots[0];
      final abdominal = routine.days[0].slots[1];
      expect(trote.exerciseId, 't');
      expect(abdominal.exerciseId, 'ab');
      expect(trote.supersetGroup, isNotNull);
      expect(trote.supersetGroup, abdominal.supersetGroup);
      expect(trote.restSeconds, 0);
      expect(abdominal.restSeconds, 60); // descanso vacío = 60, en el último
      expect(trote.effectiveExerciseMode, ExerciseMode.duration);
      expect(trote.weeklySets[0],
          [const SetSpec(type: SetType.warmup, durationSeconds: 480)]);
      expect(trote.weeklySets[5],
          [const SetSpec(type: SetType.warmup, durationSeconds: 600)]);
      expect(trote.durationSeconds, 480);
      expect(abdominal.effectiveExerciseMode, ExerciseMode.reps);
      expect(abdominal.weeklySets[0],
          List.filled(3, const SetSpec(type: SetType.warmup, reps: 20)));
      expect(abdominal.weeklySets[5].first.reps, 30);
    });

    test('superserie de 3: grupo común, descanso en el último, modos', () {
      final slots = routine.days[0].slots.sublist(2, 5);
      expect(slots.map((s) => s.exerciseId), ['a', 'b', 'c']);
      final group = slots.first.supersetGroup;
      expect(group, isNotNull);
      expect(slots.every((s) => s.supersetGroup == group), isTrue);
      expect(slots.map((s) => s.restSeconds), [0, 0, 90]);
      // Grupo distinto al del calentamiento.
      expect(group, isNot(routine.days[0].slots.first.supersetGroup));
      expect(slots[0].effectiveExerciseMode, ExerciseMode.reps);
      expect(slots[2].effectiveExerciseMode, ExerciseMode.distance);
      expect(slots[2].weeklySets[3],
          List.filled(3, const SetSpec(distanceMeters: 6)));
      // Legacy = semana 1.
      expect(slots[0].targetSets, 3);
      expect(slots[0].targetReps, [4, 4, 4]);
      expect(slots[0].targetRepsMin, 4);
      expect(slots[0].sets, slots[0].weeklySets.first);
      expect(slots[0].weeklySets[5].first.reps, 9);
      expect(slots[0].activeWeeks, isEmpty);
      expect(slots[2].exerciseMode, ExerciseMode.distance);
    });

    test('renglón común: sin superserie, nota, fallo y semana vacía', () {
      final b = routine.days[0].slots[5];
      expect(b.exerciseId, 'b');
      expect(b.supersetGroup, isNull);
      expect(b.restSeconds, 60);
      expect(b.notes, 'c/pierna');
      expect(b.weeklySets[0], List.filled(3, const SetSpec(reps: 10)));
      expect(b.weeklySets[1],
          List.filled(3, const SetSpec(type: SetType.failure)));
      expect(b.weeklySets[2], [const SetSpec()]); // semana vacía: sin reps
      expect(b.weeklySets[3], List.filled(4, const SetSpec(reps: 8)));
      expect(b.activeWeeks, isEmpty); // el slot no se saca de ninguna semana
      expect(b.targetReps, [10, 10, 10]);
    });

    test('Routine completa: weeklySets 0-based, una por columna', () {
      for (final slot in routine.days.expand((d) => d.slots)) {
        expect(slot.weeklySets, hasLength(6));
        expect(slot.activeWeeks, isEmpty);
      }
    });

    test('día 2: duración con descanso 1\'30\'\'', () {
      final s = routine.days[1].slots.single;
      expect(s.supersetGroup, isNull);
      expect(s.restSeconds, 90);
      expect(s.effectiveExerciseMode, ExerciseMode.duration);
      expect(s.weeklySets[2], [const SetSpec(durationSeconds: 22 * 60)]);
    });

    test('diagnósticos esperados: nota por calificador y semana sin reps', () {
      final codes = parsed.warnings.map((d) => d.code).toSet();
      expect(codes, contains(ImportDiagnosticCode.qualifierSavedAsNote));
      expect(codes, contains(ImportDiagnosticCode.missingReps));
      final missing = parsed.warnings
          .singleWhere((d) => d.code == ImportDiagnosticCode.missingReps);
      expect(missing.cellRef, 'Programa!F4');
    });
  });
}
