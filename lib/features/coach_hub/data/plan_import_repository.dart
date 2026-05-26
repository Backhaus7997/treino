import 'dart:typed_data';

import '../../workout/data/exercise_repository.dart';
import '../domain/parsed_plan.dart';
import 'excel_parser.dart';
import 'exercise_matcher.dart';

class PlanImportException implements Exception {
  PlanImportException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => 'PlanImportException($code): $message';
}

/// Coordina el flujo de import client-side:
/// 1. Parsea el .xlsx en memoria con `parseExcelBytes`
/// 2. Lee el catálogo `exercises` desde Firestore
/// 3. Matchea cada fila contra el catálogo
/// 4. Devuelve un `ParsedPlan` listo para mostrar en el preview
///
/// La seguridad real está en Firestore rules — este repo solo hace UX.
class PlanImportRepository {
  PlanImportRepository({required ExerciseRepository exerciseRepository})
      : _exerciseRepository = exerciseRepository;

  final ExerciseRepository _exerciseRepository;

  Future<ParsedPlan> parseAndMatch({required Uint8List bytes}) async {
    final RawParsedPlan raw;
    try {
      raw = parseExcelBytes(bytes);
    } on ExcelParseException catch (e) {
      throw PlanImportException(e.message, code: 'parse-failed');
    } catch (e) {
      throw PlanImportException(
        'No pudimos leer el Excel.',
        code: 'parse-failed',
      );
    }

    final exercises = (await _exerciseRepository.listAll())
        .map((e) => MatcherExercise(
              id: e.id,
              name: e.name,
              muscleGroup: e.muscleGroup,
              aliases: e.aliases,
            ))
        .toList();

    final match = matchExercises(raw.days, exercises);

    return ParsedPlan(
      name: raw.name,
      daysPerWeek: raw.daysPerWeek,
      durationWeeks: raw.durationWeeks,
      level: raw.level,
      days: match.days,
      unmatched: match.unmatched,
    );
  }
}
