// Fábricas de stubs para tests de application layer.
// Centralizadas acá para evitar duplicación entre archivos de test.

import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

// ── Session ──────────────────────────────────────────────────────────────────

Session makeSession({
  String id = 's1',
  String uid = 'u1',
  String routineId = 'r1',
  String routineName = 'Push Pull Legs',
  DateTime? startedAt,
  DateTime? finishedAt,
  double totalVolumeKg = 0.0,
  int durationMin = 0,
  SessionStatus status = SessionStatus.active,
  int dayNumber = 1,
  bool wasFullyCompleted = false,
  int weekNumber = 0,
}) =>
    Session(
      id: id,
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: startedAt ?? DateTime.utc(2026, 5, 18, 10, 0),
      finishedAt: finishedAt,
      totalVolumeKg: totalVolumeKg,
      durationMin: durationMin,
      status: status,
      dayNumber: dayNumber,
      wasFullyCompleted: wasFullyCompleted,
      weekNumber: weekNumber,
    );

// ── SetLog ───────────────────────────────────────────────────────────────────

SetLog makeSetLog({
  String id = 'sl1',
  String exerciseId = 'e1',
  String exerciseName = 'Press de banca',
  int setNumber = 1,
  int reps = 10,
  double weightKg = 60.0,
  int? rpe,
  DateTime? completedAt,
}) =>
    SetLog(
      id: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      rpe: rpe,
      completedAt: completedAt ?? DateTime.utc(2026, 5, 18, 10, 5),
    );

// ── RoutineSlot ───────────────────────────────────────────────────────────────

RoutineSlot makeSlot({
  String exerciseId = 'e1',
  String exerciseName = 'Press de banca',
  String muscleGroup = 'Pecho',
  int targetSets = 3,
  int targetRepsMin = 8,
  int targetRepsMax = 12,
  int restSeconds = 90,
  double? targetWeightKg = 60.0,
  String? notes,
  int? supersetGroup,
  List<List<SetSpec>>? weeklySets,
  int? durationSeconds,
}) =>
    RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      muscleGroup: muscleGroup,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      restSeconds: restSeconds,
      targetWeightKg: targetWeightKg,
      notes: notes,
      supersetGroup: supersetGroup,
      weeklySets: weeklySets ?? const [],
      durationSeconds: durationSeconds,
    );

// ── RoutineDay ────────────────────────────────────────────────────────────────

RoutineDay makeDay({
  int dayNumber = 1,
  String name = 'Push A',
  List<RoutineSlot>? slots,
  int? estimatedMinutes,
}) =>
    RoutineDay(
      dayNumber: dayNumber,
      name: name,
      slots: slots ??
          [
            makeSlot(exerciseId: 'e1', targetSets: 3),
            makeSlot(
                exerciseId: 'e2', exerciseName: 'Sentadilla', targetSets: 4),
          ],
      estimatedMinutes: estimatedMinutes,
    );

// ── Routine ───────────────────────────────────────────────────────────────────

Routine makeRoutine({
  String id = 'r1',
  String name = 'Push Pull Legs',
  String split = 'PPL',
  ExperienceLevel level = ExperienceLevel.intermediate,
  List<RoutineDay>? days,
  int? estimatedMinutesPerDay,
  String? imageUrl,
  int numWeeks = 1,
}) =>
    Routine(
      id: id,
      name: name,
      split: split,
      level: level,
      days: days ?? [makeDay()],
      estimatedMinutesPerDay: estimatedMinutesPerDay,
      imageUrl: imageUrl,
      numWeeks: numWeeks,
    );
