import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/data/plan_import_repository.dart';
import 'package:treino/features/coach_hub/data/template_builder.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/data/exercise_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

Exercise _ex(String id, String name, String muscle) => Exercise(
      id: id,
      name: name,
      muscleGroup: muscle,
      category: 'compound',
    );

Uint8List _buildValidXlsx() => buildPlanTemplateBytes();

Uint8List _buildXlsxMissingPlanSheet() {
  // Excel vacío con solo la sheet default → no tiene hoja "Plan",
  // fuerza el error del parser.
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != 'Día 1') {
    excel.rename(defaultSheet, 'Día 1');
  }
  return Uint8List.fromList(excel.save()!);
}

void main() {
  late _MockExerciseRepository exerciseRepo;
  late PlanImportRepository repo;

  setUp(() {
    exerciseRepo = _MockExerciseRepository();
    repo = PlanImportRepository(exerciseRepository: exerciseRepo);
  });

  test(
      'parseAndMatch: template default matchea contra catálogo y devuelve plan',
      () async {
    when(() => exerciseRepo.listAll()).thenAnswer((_) async => [
          _ex('sentadilla-barra', 'Sentadilla con barra', 'Piernas'),
          _ex('press-banca', 'Press banca', 'Pecho'),
          _ex('remo-barra', 'Remo con barra', 'Espalda'),
        ]);

    final plan = await repo.parseAndMatch(bytes: _buildValidXlsx());

    expect(plan.name, 'Mi plan');
    expect(plan.daysPerWeek, 3);
    expect(plan.durationWeeks, 8);
    expect(plan.level, ExperienceLevel.intermediate);
    expect(plan.days, hasLength(3));
    expect(plan.unmatched, isEmpty);
    expect(plan.days.first.items.first.exerciseId, 'sentadilla-barra');
    expect(plan.days.first.items.first.muscleGroup, 'Piernas');
  });

  test('parseAndMatch: ejercicios no catalogados van a unmatched', () async {
    // Catálogo completamente disjunto del template (que usa Sentadilla,
    // Press banca, Remo) → todos los items quedan unmatched.
    when(() => exerciseRepo.listAll()).thenAnswer((_) async => [
          _ex('curl-biceps', 'Curl bíceps con mancuerna', 'Bíceps'),
        ]);

    final plan = await repo.parseAndMatch(bytes: _buildValidXlsx());

    expect(plan.unmatched, isNotEmpty);
    expect(
      plan.unmatched.map((u) => u.dayNumber).toSet(),
      equals({1, 2, 3}),
    );
    for (final day in plan.days) {
      for (final item in day.items) {
        expect(item.exerciseId, isNull,
            reason: 'Item ${item.rowName} should be unmatched');
      }
    }
  });

  test('parseAndMatch: archivo sin hoja "Plan" → PlanImportException',
      () async {
    when(() => exerciseRepo.listAll()).thenAnswer((_) async => const []);

    expect(
      () => repo.parseAndMatch(bytes: _buildXlsxMissingPlanSheet()),
      throwsA(isA<PlanImportException>()),
    );
  });

  test('parseAndMatch: bytes corruptos → PlanImportException', () async {
    when(() => exerciseRepo.listAll()).thenAnswer((_) async => const []);

    expect(
      () => repo.parseAndMatch(bytes: Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsA(isA<PlanImportException>()),
    );
  });
}
