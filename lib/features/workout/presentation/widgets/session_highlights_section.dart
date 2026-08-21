import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/exercise_progression_aggregator.dart'
    show roundToNearestHalfKg;
import '../../application/session_highlights.dart';
import '../../application/session_recognition.dart';
import '../../domain/exercise_progression.dart';

// NOTA l10n: los ARB los está tocando otra rama en vuelo, así que los strings
// NUEVOS de este archivo van como literales es-AR con TODO(l10n) — mismo
// criterio que tuvo el "N sets · X kg" de las barras que este cambio
// reemplaza. Los labels de tipo de récord y títulos reusan claves existentes.

/// [AD2] Mismo redondeo de display que `PersonalRecordsList._formatValue`:
/// el 1RM estimado (Epley, double pleno) se muestra al 0.5 kg más cercano;
/// el resto muestra su valor con a lo sumo un decimal.
String _formatRecordValue(double value, {required bool isOneRepMax}) {
  final display = isOneRepMax ? roundToNearestHalfKg(value) : value;
  return display % 1 == 0
      ? display.toStringAsFixed(0)
      : display.toStringAsFixed(1);
}

TextStyle _sectionTitleTextStyle(AppPalette palette) =>
    GoogleFonts.barlowCondensed(
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: palette.textPrimary,
      letterSpacing: 1.2,
    );

BoxDecoration _cardDecoration(AppPalette palette) => BoxDecoration(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: palette.border),
    );

// ── Recognition banner ────────────────────────────────────────────────────────

/// Pill de reconocimiento data-driven bajo el header del resumen: UNA frase
/// elegida por [deriveSessionRecognition] ("2 récords nuevos", "3ª sesión de
/// la semana", …). Con [SessionRecognitionKind.none] no renderiza nada.
class SessionRecognitionBanner extends StatelessWidget {
  const SessionRecognitionBanner({super.key, required this.recognition});

  final SessionRecognition recognition;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // TODO(l10n): literales es-AR — ARB owned por otra rama en vuelo.
    final (IconData? icon, String text) = switch (recognition.kind) {
      SessionRecognitionKind.records => (
          TreinoIcon.ranking,
          recognition.count == 1
              ? '1 RÉCORD NUEVO'
              : '${recognition.count} RÉCORDS NUEVOS',
        ),
      SessionRecognitionKind.firstWorkout => (
          TreinoIcon.sparkle,
          'PRIMER ENTRENO COMPLETADO',
        ),
      SessionRecognitionKind.bestMonthVolume => (
          TreinoIcon.starFill,
          'TU MEJOR VOLUMEN DEL MES',
        ),
      SessionRecognitionKind.nthSessionOfWeek => (
          TreinoIcon.streak,
          '${recognition.count}ª SESIÓN DE LA SEMANA',
        ),
      SessionRecognitionKind.none => (null, ''),
    };
    if (icon == null) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: palette.accent),
            const SizedBox(width: 8),
            // FittedBox scaleDown: con font scale grande la frase se achica en
            // vez de desbordar la pill (mismo blindaje #370 del resto).
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 1.2,
                    color: palette.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PRS DE LA SESIÓN ─────────────────────────────────────────────────────────

/// Sección "PRS DE LA SESIÓN" con los récords REALES logrados hoy (reemplaza
/// el stub "Próximamente"): una fila por récord con ejercicio, tipo, valor
/// nuevo y marca anterior. Sin récords muestra una línea digna acorde al
/// estado (con o sin historial) — jamás números inventados.
class SessionPrsSection extends StatelessWidget {
  const SessionPrsSection({super.key, required this.highlights});

  final SessionHighlights highlights;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final recordRows = <({String exerciseName, SessionExerciseRecord record})>[
      for (final exercise in highlights.exercises)
        for (final record in exercise.records)
          (exerciseName: exercise.exerciseName, record: record),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.workoutPrsSectionTitle,
          style: _sectionTitleTextStyle(palette),
        ),
        const SizedBox(height: 8),
        if (recordRows.isEmpty)
          Text(
            // TODO(l10n): literales es-AR — ARB owned por otra rama en vuelo.
            highlights.hasHistory
                ? 'Sin récords nuevos esta vez. La constancia también construye.'
                : 'Primer entreno: estas marcas son tu punto de partida.',
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _cardDecoration(palette),
            child: Column(
              children: [
                for (var i = 0; i < recordRows.length; i++) ...[
                  if (i > 0) Divider(color: palette.border, height: 18),
                  _SessionRecordRow(
                    exerciseName: recordRows[i].exerciseName,
                    record: recordRows[i].record,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _SessionRecordRow extends StatelessWidget {
  const _SessionRecordRow({required this.exerciseName, required this.record});

  final String exerciseName;
  final SessionExerciseRecord record;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final isOneRepMax = record.recordType == ProgressionRecordType.oneRepMax;

    // Mismos labels y unidades que PersonalRecordsList en el detalle de
    // ejercicio ('kg'/'kg·reps' hardcodeadas es el precedente de ese caller).
    final typeLabel = switch (record.recordType) {
      ProgressionRecordType.heaviestWeight => l10n.progressionMetricPr,
      ProgressionRecordType.oneRepMax => l10n.progressionMetricOneRepMax,
      ProgressionRecordType.bestSetVolume =>
        l10n.progressionMetricBestSetVolume,
      ProgressionRecordType.bestSessionVolume => l10n.progressionMetricVolume,
    };
    final unit = switch (record.recordType) {
      ProgressionRecordType.heaviestWeight ||
      ProgressionRecordType.oneRepMax =>
        'kg',
      ProgressionRecordType.bestSetVolume ||
      ProgressionRecordType.bestSessionVolume =>
        'kg·reps',
    };

    final newValue = _formatRecordValue(record.value, isOneRepMax: isOneRepMax);
    final previous =
        _formatRecordValue(record.previousBest, isOneRepMax: isOneRepMax);

    // El bloque de valores tiene ancho INTRÍNSECO, y un hijo no flexible de un
    // Row recibe ancho ILIMITADO: sin acotarlo el FittedBox nunca escala y la
    // fila desborda con font scale de accesibilidad grande (#370/#456). Por eso
    // el bloque necesita SÍ o SÍ un constraint acotado.
    //
    // Ahora, ese constraint tiene que ser un TOPE, no un reparto fijo de flex
    // (`Expanded 3:2`, que es lo que tenía este widget). Medido con las TTF
    // reales de Barlow, dPR 1.0:
    //
    //   · El reparto ASIGNA: el bloque se dimensiona a su ancho intrínseco pero
    //     el sobrante de su 2/5 queda a su DERECHA, así que nunca llegaba al
    //     borde de la card — y como cada fila tiene un valor de largo distinto,
    //     dos filas de la misma card quedaban desalineadas entre sí por ~50px.
    //     Borde derecho ragged. Con `Expanded` en el nombre + tope acá, el
    //     bloque queda pegado a la derecha y todas las filas alinean.
    //   · A font scale 1x el reparto no achicaba nada (el bloque mide 87px en
    //     el peor caso y 2/5 alcanzan de sobra hasta 320px de pantalla), pero a
    //     font scale de accesibilidad se queda sin aire y el FittedBox lo
    //     aplasta: a 390px de ancho el valor salía 37% más chico a 2x y 80% más
    //     chico a 3x de lo que corresponde. Con el tope escala recién a 3x.
    //
    // Mismo criterio que `_PersonalRecordRow` (PR #598). Diferencia con esa
    // fila: acá la izquierda es un nombre de ejercicio de largo arbitrario con
    // `maxLines: 1` + ellipsis, no un label corto y fijo. Elidir es su
    // comportamiento previsto, así que cederle ancho al bloque cuando el valor
    // es largo es el intercambio correcto.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exerciseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  typeLabel,
                  style: GoogleFonts.barlow(
                    fontSize: 11,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.7),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        newValue,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                  // "→ marca anterior" — mismo idioma visual que las stat cards
                  // del radar de Insights (valor actual grande, "→ prev" chico
                  // abajo).
                  Text(
                    '→ $previous $unit',
                    maxLines: 1,
                    style: GoogleFonts.barlow(
                      fontSize: 10,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── EJERCICIOS ───────────────────────────────────────────────────────────────

/// Sección "EJERCICIOS" del resumen: una fila por ejercicio con sets, mejor
/// set y badges (PR / 1ª VEZ). El de mayor volumen lleva estrella cuando hay
/// ≥2 ejercicios con volumen real (con 1 solo, "destacado" es trivial).
class SessionExercisesSection extends StatelessWidget {
  const SessionExercisesSection({super.key, required this.exercises});

  final List<SessionExerciseSummary> exercises;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    String? highlightedId;
    if (exercises.length >= 2) {
      SessionExerciseSummary? top;
      for (final exercise in exercises) {
        if (exercise.sessionVolumeKg <= 0) continue;
        if (top == null || exercise.sessionVolumeKg > top.sessionVolumeKg) {
          top = exercise;
        }
      }
      highlightedId = top?.exerciseId;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.routineDetailStatExercises,
          style: _sectionTitleTextStyle(palette),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(palette),
          child: Column(
            children: [
              for (var i = 0; i < exercises.length; i++) ...[
                if (i > 0) Divider(color: palette.border, height: 18),
                _SessionExerciseRow(
                  exercise: exercises[i],
                  isHighlighted: exercises[i].exerciseId == highlightedId,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionExerciseRow extends StatelessWidget {
  const _SessionExerciseRow({
    required this.exercise,
    required this.isHighlighted,
  });

  final SessionExerciseSummary exercise;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Mejor set: "80 kg × 5", o "12 reps" para bodyweight (#368: peso 0).
    // TODO(l10n): "sets"/"reps" literales — mismo pendiente que tenían las
    // barras de distribución que este cambio reemplazó.
    final bestSet = exercise.bestWeightKg > 0
        ? '${_formatRecordValue(exercise.bestWeightKg, isOneRepMax: false)} kg '
            '× ${exercise.bestSetReps}'
        : '${exercise.bestSetReps} reps';
    final stats = '${exercise.setCount} sets · $bestSet';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mismo razonamiento y mismo tope que _SessionRecordRow: los badges son
        // de ancho intrínseco y juntos superan el ancho útil en una pantalla
        // angosta aunque el nombre se elida a cero, así que necesitan un
        // constraint acotado para poder achicarse — pero un TOPE, no un reparto
        // fijo, para que a anchos normales se dibujen a tamaño natural.
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (isHighlighted) ...[
                Icon(TreinoIcon.starFill, size: 14, color: palette.accent),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  exercise.exerciseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (exercise.records.isNotEmpty || exercise.isFirstTime)
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth * 0.7),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (exercise.records.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _Badge(label: 'PR', color: palette.accent),
                        ],
                        if (exercise.isFirstTime) ...[
                          const SizedBox(width: 8),
                          // TODO(l10n): literal es-AR — ARB owned por otra rama.
                          _Badge(label: '1ª VEZ', color: palette.highlight),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          stats,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.barlow(fontSize: 12, color: palette.textMuted),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}
