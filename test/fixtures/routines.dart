import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

// ── Shared slot fixture ───────────────────────────────────────────────────────

/// A minimal slot with a single exercise — used to give a day at least one
/// slot so that [_isValid] in RoutineEditorScreen passes.
const kOneSlot = RoutineSlot(
  exerciseId: 'bench-press',
  exerciseName: 'Press de Banca',
  muscleGroup: 'chest',
  targetSets: 3,
  targetRepsMin: 8,
  targetRepsMax: 12,
  restSeconds: 60,
);

/// A minimal day containing [kOneSlot].
const kOneDay = RoutineDay(
  dayNumber: 1,
  name: 'Día 1',
  slots: [kOneSlot],
);

// ── T-RER-033: null-split fixture ─────────────────────────────────────────────

/// Routine created by an athlete in SelfCreating mode.
/// `split` is null — the form does not ask for it.
/// `level` defaults to [ExperienceLevel.beginner] (fixed default, ADR-RER-04).
///
/// Feeds T-RER-032 widget tests and null-split display-site tests (T-RER-011).
const routineWithoutSplit = Routine(
  id: 'r1',
  name: 'Mi rutina',
  split: null,
  level: ExperienceLevel.beginner,
  days: [kOneDay],
  source: RoutineSource.userCreated,
  visibility: RoutineVisibility.private,
);
