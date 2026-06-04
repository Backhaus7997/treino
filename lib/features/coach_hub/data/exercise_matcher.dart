import '../domain/parsed_plan.dart';
import '../domain/periodized_preview.dart';
import 'excel_parser.dart';

/// Catálogo mínimo del lado matcher — sólo lo que necesita para mapear.
class MatcherExercise {
  MatcherExercise({
    required this.id,
    required this.name,
    this.muscleGroup,
    this.aliases = const <String>[],
  });

  final String id;
  final String name;
  final String? muscleGroup;

  /// Synonyms in Spanish or trainer jargon — every alias gets indexed
  /// alongside `name`, so "Sentadilla con barra" matches the same exercise
  /// as "Back Squat".
  final List<String> aliases;
}

class MatchResult {
  MatchResult({required this.days, required this.unmatched});
  final List<ParsedPlanDay> days;
  final List<ParsedPlanUnmatched> unmatched;
}

String normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp('[áàäâã]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _Index {
  _Index._(this.byName, this.byToken);
  final Map<String, MatcherExercise> byName;
  final Map<String, List<MatcherExercise>> byToken;

  factory _Index.build(List<MatcherExercise> exercises) {
    final byName = <String, MatcherExercise>{};
    final byToken = <String, List<MatcherExercise>>{};

    void indexLabel(String label, MatcherExercise ex) {
      final normalized = normalize(label);
      if (normalized.isEmpty) return;
      byName.putIfAbsent(normalized, () => ex);
      for (final token in normalized.split(' ')) {
        if (token.length < 3) continue;
        byToken.putIfAbsent(token, () => []).add(ex);
      }
    }

    for (final ex in exercises) {
      indexLabel(ex.name, ex);
      for (final alias in ex.aliases) {
        indexLabel(alias, ex);
      }
    }
    return _Index._(byName, byToken);
  }
}

MatcherExercise? _bestFuzzyMatch(String query, _Index index) {
  final tokens = query.split(' ').where((t) => t.length >= 3).toList();
  if (tokens.isEmpty) return null;

  final scores = <String, int>{};
  for (final token in tokens) {
    final cands = index.byToken[token] ?? const [];
    for (final ex in cands) {
      scores[ex.id] = (scores[ex.id] ?? 0) + 1;
    }
  }

  String? bestId;
  int bestScore = 0;
  scores.forEach((id, score) {
    if (score > bestScore) {
      bestScore = score;
      bestId = id;
    }
  });

  if (bestId == null || bestScore < (tokens.length / 2).ceil()) return null;

  for (final cands in index.byToken.values) {
    for (final ex in cands) {
      if (ex.id == bestId) return ex;
    }
  }
  return null;
}

MatchResult matchExercises(
  List<RawParsedDay> rawDays,
  List<MatcherExercise> exercises,
) {
  final index = _Index.build(exercises);
  final unmatched = <ParsedPlanUnmatched>[];
  final days = <ParsedPlanDay>[];

  for (final day in rawDays) {
    final items = <ParsedPlanItem>[];
    for (final item in day.items) {
      final key = normalize(item.rowName);
      MatcherExercise? exercise = index.byName[key];
      exercise ??= _bestFuzzyMatch(key, index);

      if (exercise == null) {
        unmatched.add(ParsedPlanUnmatched(
          dayNumber: day.dayNumber,
          rowName: item.rowName,
        ));
        items.add(ParsedPlanItem(
          rowName: item.rowName,
          sets: item.sets,
          repsMin: item.repsMin,
          repsMax: item.repsMax,
          weightKg: item.weightKg,
          restSec: item.restSec,
          notes: item.notes,
          exerciseId: null,
          exerciseName: item.rowName,
          muscleGroup: null,
        ));
      } else {
        items.add(ParsedPlanItem(
          rowName: item.rowName,
          sets: item.sets,
          repsMin: item.repsMin,
          repsMax: item.repsMax,
          weightKg: item.weightKg,
          restSec: item.restSec,
          notes: item.notes,
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          muscleGroup: exercise.muscleGroup,
        ));
      }
    }
    days.add(ParsedPlanDay(dayNumber: day.dayNumber, items: items));
  }

  return MatchResult(days: days, unmatched: unmatched);
}

/// Versión periodizada: matchea cada (semana, día, ejercicio) contra el
/// catálogo y conserva `order` + `block` (superserie). Construye el índice una
/// sola vez para todas las semanas. Mismo algoritmo de match exacto + fuzzy.
PeriodizedPreviewPlan matchPeriodized(
  RawParsedPeriodizedPlan raw,
  List<MatcherExercise> exercises,
) {
  final index = _Index.build(exercises);
  final unmatched = <PeriodizedUnmatched>[];
  final weeks = <PeriodizedPreviewWeek>[];

  for (final week in raw.weeks) {
    final days = <PeriodizedPreviewDay>[];
    for (final day in week.days) {
      final items = <PeriodizedPreviewItem>[];
      for (final item in day.items) {
        final key = normalize(item.rowName);
        MatcherExercise? exercise = index.byName[key];
        exercise ??= _bestFuzzyMatch(key, index);

        if (exercise == null) {
          unmatched.add(PeriodizedUnmatched(
            weekNumber: week.weekNumber,
            dayNumber: day.dayNumber,
            rowName: item.rowName,
          ));
        }
        items.add(PeriodizedPreviewItem(
          rowName: item.rowName,
          sets: item.sets,
          repsMin: item.repsMin,
          repsMax: item.repsMax,
          weightKg: item.weightKg,
          restSec: item.restSec,
          notes: item.notes,
          order: item.order,
          block: item.block,
          exerciseId: exercise?.id,
          exerciseName: exercise?.name ?? item.rowName,
          muscleGroup: exercise?.muscleGroup,
        ));
      }
      days.add(PeriodizedPreviewDay(dayNumber: day.dayNumber, items: items));
    }
    weeks.add(PeriodizedPreviewWeek(weekNumber: week.weekNumber, days: days));
  }

  return PeriodizedPreviewPlan(
    name: raw.name,
    daysPerWeek: raw.daysPerWeek,
    durationWeeks: raw.durationWeeks,
    level: raw.level,
    weeks: weeks,
    unmatched: unmatched,
  );
}
