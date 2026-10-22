// El JSON que devuelve `parsePlanPdf` se vuelve a validar en el cliente con
// los mismos topes del contrato. Cada violación es un diagnóstico, nunca un
// throw. Fixtures en test/fixtures/pdf_plan/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_routine_mapper.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan_json.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/pdf_plan/$name.json').readAsStringSync())
        as Map<String, Object?>;

/// El fixture válido con UNA cosa cambiada.
Map<String, Object?> _valid(void Function(Map<String, dynamic> j) mutate) {
  final j = _fixture('valido') as Map<String, dynamic>;
  mutate(j);
  return j;
}

/// Día 1 (Torso A), renglón 1, ejercicio 1 del fixture válido.
Map<String, dynamic> _press(Map<String, dynamic> j) =>
    (j['days'][1]['rows'][0]['exercises'] as List).first
        as Map<String, dynamic>;

Map<String, dynamic> _pressSet(Map<String, dynamic> j) =>
    _press(j)['weeks'][0][1] as Map<String, dynamic>;

Map<String, dynamic> _set({
  String type = 'normal',
  Object? weightKg,
  Object? reps,
  Object? repsMin,
  Object? repsMax,
}) =>
    {
      'type': type,
      'weightKg': weightKg,
      'reps': reps,
      'repsMin': repsMin,
      'repsMax': repsMax,
      'durationSeconds': null,
      'distanceMeters': null,
    };

/// Rechazado por UN solo error, con ese código.
void _rejects(PeriodizedParseResult r, ImportDiagnosticCode code) {
  expect(r.canImport, isFalse);
  expect(r.errors.map((e) => e.code), [code], reason: '${r.diagnostics}');
}

void main() {
  group('fixtures válidos', () {
    test('plan válido: semanas, días ordenados, series, nota y candidato', () {
      final r = periodizedPlanFromJson(_fixture('valido'));
      expect(r.errors, isEmpty, reason: '${r.diagnostics}');
      expect(r.canImport, isTrue);

      final plan = r.plan!;
      expect(plan.numWeeks, 2);
      expect(plan.days.map((d) => d.dayNumber), [1, 2]);
      expect(plan.days.first.headerRow, isNull);

      final press = plan.days.first.rows.single.exercises.single;
      expect(press.component, 0);
      expect(press.rawName, 'Press banca plano con barra');
      expect(press.note, 'RIR 2, tempo 3-0-1');
      expect(press.sourceText, 'Press banca 4x8-10 @60kg RIR2');
      expect(press.candidateExerciseId, 'bench-press');
      expect(press.candidateConfidence, 0.9);
      expect(press.weeks, const [
        [
          SetSpec(type: SetType.warmup, weightKg: 40, reps: 10),
          SetSpec(weightKg: 60, repsMin: 8, repsMax: 10),
        ],
        [
          SetSpec(weightKg: 62.5, repsMin: 8, repsMax: 10),
          SetSpec(type: SetType.failure, weightKg: 50),
        ],
      ]);

      // El PDF no tiene filas: la posición es el ordinal en el día.
      final pierna = plan.days.last.rows;
      expect(pierna.map((row) => row.position), [1, 2]);
      expect(pierna.map((row) => row.restSeconds), [120, 60]);
    });

    test('semana vacía: una serie sin valores marcada como vacía', () {
      final r = periodizedPlanFromJson(_fixture('valido'));
      final plancha = r.plan!.days.last.rows.last.exercises.single;
      expect(plancha.weeks, const [
        [SetSpec(durationSeconds: 45)],
        [SetSpec()],
      ]);
      expect(plancha.emptyWeeks, {1});
    });

    test('los avisos del extractor son warnings con su página', () {
      final r = periodizedPlanFromJson(_fixture('valido'));
      final w = r.warnings.single;
      expect(w.code, ImportDiagnosticCode.extractorWarning);
      expect(w.page, 2);
      expect(w.location, 'página 2');
      expect(w.rawValue, 'ambiguous_reps');
    });

    test('el plan leído pasa por el mapper con pesos y rangos', () {
      final plan = periodizedPlanFromJson(_fixture('valido')).plan!;
      final catalog = MatcherExercise(id: 'x', name: 'x');
      final routine = mapPeriodizedPlanToRoutine(
        plan,
        {for (final k in unresolvedKeys(plan, const {})) k: catalog},
        routineId: 'r',
        routineName: 'n',
        level: ExperienceLevel.beginner,
      );
      final press = routine.days.first.slots.single;
      expect(press.repMode, RepMode.range);
      expect(press.targetWeightKg, 40);
      expect(press.weeklySets[1].first,
          const SetSpec(weightKg: 62.5, repsMin: 8, repsMax: 10));
    });

    test('superserie: componentes ordenados y base 0', () {
      final r = periodizedPlanFromJson(_fixture('superserie'));
      expect(r.errors, isEmpty, reason: '${r.diagnostics}');
      final row = r.plan!.days.single.rows.single;
      expect(row.isSuperset, isTrue);
      expect(row.exercises.map((e) => e.component), [0, 1]);
      expect(row.exercises.map((e) => e.rawName), [
        'Curl de bíceps con mancuernas',
        'Extensión de tríceps en polea',
      ]);
    });

    test('calentamiento: renglón sin N°, descanso 0 y duración', () {
      final r = periodizedPlanFromJson(_fixture('calentamiento'));
      expect(r.errors, isEmpty, reason: '${r.diagnostics}');
      final rows = r.plan!.days.single.rows;
      expect(rows.first.isWarmup, isTrue);
      expect(rows.first.restSeconds, 0);
      expect(rows.first.exercises.single.weeks.single.single,
          const SetSpec(type: SetType.warmup, durationSeconds: 300));
      expect(rows.last.isWarmup, isFalse);
    });

    test('descanso ausente: 60 s, como la celda vacía del Excel', () {
      final r = periodizedPlanFromJson(
          _valid((j) => j['days'][1]['rows'][0]['restSeconds'] = null));
      expect(r.canImport, isTrue);
      expect(r.plan!.days.first.rows.single.restSeconds, 60);
    });
  });

  group('topes del contrato', () {
    test('numWeeks 0 o 17: tooManyWeeks y sin plan', () {
      for (final n in [0, 17]) {
        final r = periodizedPlanFromJson(_valid((j) => j['numWeeks'] = n));
        _rejects(r, ImportDiagnosticCode.tooManyWeeks);
        expect(r.plan, isNull);
      }
    });

    test('sin numWeeks o con otro tipo: malformedPlan', () {
      for (final v in [null, '4', 2.5]) {
        final r = periodizedPlanFromJson(_valid((j) => j['numWeeks'] = v));
        _rejects(r, ImportDiagnosticCode.malformedPlan);
      }
    });

    test('más de 7 días: tooManyDays', () {
      final r = periodizedPlanFromJson(_valid((j) {
        final days = j['days'] as List;
        final template = jsonEncode(days.first);
        days.clear();
        for (var d = 1; d <= 8; d++) {
          days.add(jsonDecode(template)..['dayNumber'] = d);
        }
      }));
      // El día 8 además está fuera de rango.
      expect(r.canImport, isFalse);
      expect(r.errors.map((e) => e.code).toSet(), {
        ImportDiagnosticCode.tooManyDays,
        ImportDiagnosticCode.invalidDayNumber,
      });
    });

    test('dayNumber fuera de 1–7: invalidDayNumber', () {
      for (final n in [0, 8]) {
        final r = periodizedPlanFromJson(
            _valid((j) => j['days'][0]['dayNumber'] = n));
        _rejects(r, ImportDiagnosticCode.invalidDayNumber);
      }
    });

    test('día repetido: duplicatedDay', () {
      final r =
          periodizedPlanFromJson(_valid((j) => j['days'][0]['dayNumber'] = 1));
      _rejects(r, ImportDiagnosticCode.duplicatedDay);
    });

    test('descanso fuera de 0–600: invalidRest', () {
      for (final s in [-1, 601]) {
        final r = periodizedPlanFromJson(
            _valid((j) => j['days'][1]['rows'][0]['restSeconds'] = s));
        _rejects(r, ImportDiagnosticCode.invalidRest);
      }
    });

    test('N° menor a 1: invalidNumber', () {
      final r = periodizedPlanFromJson(
          _valid((j) => j['days'][1]['rows'][0]['number'] = 0));
      _rejects(r, ImportDiagnosticCode.invalidNumber);
    });

    test('reps fijas Y rango en la misma serie: invalidReps', () {
      final r = periodizedPlanFromJson(_valid((j) => _pressSet(j)['reps'] = 8));
      _rejects(r, ImportDiagnosticCode.invalidReps);
    });

    test('rango a medias: invalidReps', () {
      final r =
          periodizedPlanFromJson(_valid((j) => _pressSet(j)['repsMax'] = null));
      _rejects(r, ImportDiagnosticCode.invalidReps);
    });

    test('mínimo mayor que el máximo: invalidReps', () {
      final r =
          periodizedPlanFromJson(_valid((j) => _pressSet(j)['repsMin'] = 12));
      _rejects(r, ImportDiagnosticCode.invalidReps);
    });

    test('reps fuera de 1–999 o no enteras: invalidReps', () {
      for (final v in [0, 1000, '8', 8.5]) {
        final r = periodizedPlanFromJson(_valid((j) {
          _press(j)['weeks'][0][0] = _set(reps: v);
        }));
        _rejects(r, ImportDiagnosticCode.invalidReps);
      }
    });

    test('peso fuera de 0–500 kg: invalidWeight', () {
      for (final v in [-5, 500.5, 'sesenta']) {
        final r =
            periodizedPlanFromJson(_valid((j) => _pressSet(j)['weightKg'] = v));
        _rejects(r, ImportDiagnosticCode.invalidWeight);
      }
    });

    test('500 kg justo es válido', () {
      final r =
          periodizedPlanFromJson(_valid((j) => _pressSet(j)['weightKg'] = 500));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
    });

    test('weeks.length distinto de numWeeks: weekCountMismatch', () {
      final r = periodizedPlanFromJson(
          _valid((j) => (_press(j)['weeks'] as List).removeLast()));
      _rejects(r, ImportDiagnosticCode.weekCountMismatch);
    });

    test('type que no es un SetType: invalidSetType', () {
      final r = periodizedPlanFromJson(
          _valid((j) => _pressSet(j)['type'] = 'superset'));
      _rejects(r, ImportDiagnosticCode.invalidSetType);
    });

    test('superserie mal numerada: invalidComponent', () {
      final j = _fixture('superserie') as Map<String, dynamic>;
      j['days'][0]['rows'][0]['exercises'][0]['component'] = 1;
      _rejects(
          periodizedPlanFromJson(j), ImportDiagnosticCode.invalidComponent);
    });

    test('ejercicio sin nombre: emptyExerciseComponent', () {
      final r =
          periodizedPlanFromJson(_valid((j) => _press(j)['rawName'] = '  '));
      _rejects(r, ImportDiagnosticCode.emptyExerciseComponent);
    });

    test('duración o distancia no positivas: invalidNumber', () {
      final r = periodizedPlanFromJson(_valid((j) {
        _pressSet(j)
          ..['repsMin'] = null
          ..['repsMax'] = null
          ..['durationSeconds'] = 0;
      }));
      _rejects(r, ImportDiagnosticCode.invalidNumber);
    });

    test('sin ejercicios: noExercises', () {
      final r = periodizedPlanFromJson(_valid((j) {
        for (final d in j['days'] as List) {
          d['rows'] = [];
        }
      }));
      _rejects(r, ImportDiagnosticCode.noExercises);
    });

    test('un renglón con error queda afuera, el resto del plan sigue', () {
      final r = periodizedPlanFromJson(
          _valid((j) => j['days'][0]['rows'][0]['restSeconds'] = 601));
      expect(r.canImport, isFalse);
      expect(r.plan!.days.last.rows.map((row) => row.position), [2]);
      expect(r.errors.single.message, startsWith('Día 2, renglón 1'));
    });
  });

  group('campos opcionales', () {
    test('confianza fuera de 0–1: se descarta el candidato con aviso', () {
      final r = periodizedPlanFromJson(
          _valid((j) => _press(j)['candidateConfidence'] = 1.5));
      expect(r.canImport, isTrue);
      expect(
          r.plan!.days.first.rows.single.exercises.single.candidateExerciseId,
          isNull);
      expect(r.warnings.map((w) => w.code),
          contains(ImportDiagnosticCode.invalidOptionalField));
    });

    test('sourceText de más de 300 caracteres se recorta', () {
      final r = periodizedPlanFromJson(
          _valid((j) => _press(j)['sourceText'] = 'x' * 400));
      expect(r.plan!.days.first.rows.single.exercises.single.sourceText!.length,
          kMaxSourceTextLength);
    });
  });
}
