// Shared read-only exercise block: exercise name heading + one row per set.
// Used by both the athlete's SessionDetailScreen and the trainer's
// coach-hub expansion. No provider reads, no edit/delete affordances
// (REQ-SETLOGS-006, REQ-SETLOGS-009).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/kg_format.dart';
import '../../domain/exercise_feedback.dart';
import '../../domain/set_log.dart';
import 'exercise_feedback_note.dart';

/// Displays one exercise group: name heading followed by a row per [SetLog].
/// API matches the old private `_ExerciseBlock` in session_detail_screen.dart.
///
/// #628 — también renderiza lo que el alumno REPORTÓ sobre este ejercicio,
/// pegado a la serie que lo originó. Se hizo acá, en el bloque COMPARTIDO,
/// y no en cada pantalla: este widget ya lo consumen las tres superficies que
/// muestran una sesión (el detalle del alumno, el athlete-detail mobile del PF
/// y el Coach Hub web), así que una sola implementación las cubre a las tres y
/// no puede haber una que muestre la molestia y otra que no.
class SessionExerciseBlock extends StatelessWidget {
  const SessionExerciseBlock({
    super.key,
    required this.exerciseName,
    required this.sets,
    this.feedback = const <ExerciseFeedback>[],
  });

  final String exerciseName;
  final List<SetLog> sets;

  /// Los reportes de ESTE ejercicio (#628). Ya vienen filtrados por
  /// `exerciseId` desde el llamador — el bloque sólo los ubica: los que traen
  /// `setNumber` van bajo su serie, y los que no, bajo el encabezado del
  /// ejercicio.
  ///
  /// Default vacío para que los call sites que todavía no los pasan sigan
  /// compilando y renderizando igual que antes.
  final List<ExerciseFeedback> feedback;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exerciseName,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: palette.textPrimary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          // Reportes sin serie: van arriba de las filas, porque hablan del
          // ejercicio entero y no de una serie en particular.
          ...feedback
              .where((f) => f.setNumber == null)
              .map((f) => ExerciseFeedbackNote(feedback: f)),
          ...sets.map(
            (log) => _SetRow(
              log: log,
              feedback: feedback
                  .where((f) => f.setNumber == log.setNumber)
                  .toList(growable: false),
            ),
          ),
          // Un reporte anclado a una serie que YA NO EXISTE (el alumno la
          // borró después de reportar) no puede desaparecer: sigue siendo lo
          // que la persona dijo que le pasó. Cae acá abajo en vez de perderse.
          ...feedback
              .where((f) =>
                  f.setNumber != null &&
                  !sets.any((s) => s.setNumber == f.setNumber))
              .map((f) => ExerciseFeedbackNote(feedback: f)),
        ],
      ),
    );
  }
}

// ── Agrupación por ejercicio ──────────────────────────────────────────────────

/// Un ejercicio listo para renderizar: las series que quedaron registradas y
/// los reportes que el alumno dejó sobre él.
class SessionExerciseGroup {
  const SessionExerciseGroup({
    required this.exerciseId,
    required this.exerciseName,
    required this.sets,
    required this.feedback,
  });

  final String exerciseId;
  final String exerciseName;
  final List<SetLog> sets;
  final List<ExerciseFeedback> feedback;
}

/// Arma los bloques de una sesión: primero los ejercicios CON series, en orden
/// de aparición, y después los que SÓLO tienen reportes.
///
/// #628 — la segunda pasada no es un caso de borde, es el agujero por el que
/// se caía la feature entera. Las tres superficies derivaban los bloques
/// EXCLUSIVAMENTE de los `SetLog`, así que un `exerciseId` con cero logs no
/// tenía grupo y su reporte no se renderizaba en ninguna parte. Se llega ahí
/// por tres caminos comunes: el alumno reporta sobre una serie PENDIENTE y
/// nunca la registra; reporta sobre un MIEMBRO de un superset que no es la
/// celda activa (`setNumber` en null y cero logs de ese miembro) — que es
/// justamente el caso con el que se vendió la feature —; o borra después la
/// única serie del ejercicio.
///
/// El nombre del bloque huérfano sale de [ExerciseFeedback.exerciseName], que
/// está denormalizado exactamente para esto: el PF lo ve sin resolver el
/// catálogo de ejercicios, así que la pasada extra no cuesta ninguna lectura.
///
/// Vive acá, al lado del widget compartido, y no en cada pantalla, por la
/// misma razón que [SessionExerciseBlock]: una sola implementación cubre a las
/// tres superficies y no puede haber una que muestre el reporte y otra que no.
List<SessionExerciseGroup> buildSessionExerciseGroups({
  required List<SetLog> sets,
  required List<ExerciseFeedback> feedback,
}) {
  // Map literal = LinkedHashMap en Dart: conserva el orden de aparición.
  final byExercise = <String, List<SetLog>>{};
  for (final log in sets) {
    byExercise.putIfAbsent(log.exerciseId, () => <SetLog>[]).add(log);
  }

  List<ExerciseFeedback> reportsOf(String exerciseId) =>
      feedback.where((f) => f.exerciseId == exerciseId).toList(growable: false);

  final groups = <SessionExerciseGroup>[
    for (final entry in byExercise.entries)
      SessionExerciseGroup(
        exerciseId: entry.key,
        exerciseName: entry.value.first.exerciseName,
        sets: entry.value,
        feedback: reportsOf(entry.key),
      ),
  ];

  // Los reportados sin series, en el orden en que llegaron los reportes.
  final orphans = <String, ExerciseFeedback>{};
  for (final f in feedback) {
    if (byExercise.containsKey(f.exerciseId)) continue;
    orphans.putIfAbsent(f.exerciseId, () => f);
  }
  for (final entry in orphans.entries) {
    groups.add(SessionExerciseGroup(
      exerciseId: entry.key,
      exerciseName: entry.value.exerciseName,
      sets: const <SetLog>[],
      feedback: reportsOf(entry.key),
    ));
  }

  return groups;
}

// ── Set row ───────────────────────────────────────────────────────────────────

class _SetRow extends StatelessWidget {
  const _SetRow(
      {required this.log, this.feedback = const <ExerciseFeedback>[]});

  final SetLog log;

  /// Lo que el alumno reportó sobre ESTA serie (#628).
  final List<ExerciseFeedback> feedback;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${log.setNumber}',
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${log.reps} reps',
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
              Text(
                '${formatWeightKg(log.weightKg)} kg',
                style: TextStyle(color: palette.textPrimary),
              ),
              // QA-WKT-007: no PR badge until real personal-record detection
              // exists. The Etapa-5 stub rendered on every set, showing false
              // PRs to the athlete and — via the coach-hub reuse — to the
              // trainer too.
            ],
          ),
          ...feedback.map((f) => ExerciseFeedbackNote(feedback: f)),
        ],
      ),
    );
  }
}
