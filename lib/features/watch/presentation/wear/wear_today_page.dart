import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import 'wear_strings.dart';
import 'wear_view_models.dart';
import 'wear_widgets.dart';

/// El entreno de hoy y, más abajo, sus ejercicios.
///
/// **Réplica de `TodayPage` + `TodaysWorkoutView` + `DayExerciseList`** de
/// `ios/TreinoWatch Watch App/ContentView.swift`.
///
/// Los ejercicios van en el MISMO scroll y no en otra página: son el detalle de
/// lo que dice arriba, no otro tema. Deslizar hacia abajo los muestra.
///
/// Austera a propósito: el nombre del día es lo que el atleta necesita leer de
/// un vistazo entre series. El resto es contexto secundario.
class WearTodaySection extends StatelessWidget {
  const WearTodaySection({
    super.key,
    required this.state,
    required this.onStart,
  });

  final WearTodayState state;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // El `switch` exhaustivo sobre el sellado es medio punto del cambio: si
    // mañana se agrega un estado, esto no compila hasta que se decida qué
    // dibujar. Antes un estado nuevo se caía silenciosamente en el spinner.
    final WearTodaysWorkout w;
    switch (state) {
      case WearTodayLoading():
        return const WearLoading(text: WearStrings.loadingRoutine);

      case WearTodayFailed():
        return WearStatusMessage(
          icon: TreinoIcon.arrowRight,
          text: WearStrings.routineLoadFailed,
          tint: palette.warning,
        );

      case WearTodayEmpty():
        // NO es un error, así que no va teñido de warning: no hay nada roto,
        // sólo falta elegir plan.
        return const WearStatusMessage(
          icon: TreinoIcon.dumbbell,
          text: WearStrings.noActivePlan,
        );

      case WearTodayReady(:final workout):
        w = workout;
    }

    return Column(
      children: [
        // "HOY" en accent: es la marca de que esto es lo de ahora, no un plan
        // cualquiera. Igual que el verde de watchOS.
        Center(
            child: WearSectionTitle(WearStrings.today, color: palette.accent)),

        // El nombre del día se achica antes que cortarse: leer "Empuje super…"
        // de reojo no sirve de nada.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            w.dayName,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.05,
              color: palette.textPrimary,
            ),
          ),
        ),
        Text(
          w.routineName,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
        ),
        const SizedBox(height: 8),
        _Meta(workout: w),
        const SizedBox(height: 8),

        if (w.exercises.isEmpty)
          Text(
            WearStrings.noExercisesThisWeek,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
          )
        else ...[
          WearButton(label: WearStrings.start, onTap: onStart),
          const SizedBox(height: 18),
          _DayExerciseList(exercises: w.exercises),
        ],
      ],
    );
  }
}

/// Cantidad de ejercicios y, si el plan es periodizado, la semana.
class _Meta extends StatelessWidget {
  const _Meta({required this.workout});

  final WearTodaysWorkout workout;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(TreinoIcon.dumbbell, size: 12, color: palette.textMuted),
        const SizedBox(width: 8),
        Text(
          '${workout.exerciseCount}',
          style: GoogleFonts.barlow(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: palette.textMuted,
          ),
        ),
        // La semana SOLO en planes periodizados: en uno de una sola semana el
        // dato es ruido. Misma regla que watchOS.
        if (workout.showsWeek) ...[
          const SizedBox(width: 12),
          Text(
            '${WearStrings.weekAbbrev} ${workout.weekNumber + 1}/${workout.numWeeks}',
            style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Los ejercicios del día, en orden, con sus series.
///
/// Es sólo lectura: marcar se hace durante el entreno, no acá. Sirve para que el
/// atleta sepa qué le espera antes de darle a empezar.
class _DayExerciseList extends StatelessWidget {
  const _DayExerciseList({required this.exercises});

  final List<WearExercisePreview> exercises;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: WearSectionTitle(WearStrings.exercises)),
        const SizedBox(height: 8),
        for (var i = 0; i < exercises.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ancho fijo y alineado a la derecha: con dos dígitos los
                // nombres no se corren de lugar.
                SizedBox(
                  width: 14,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.barlow(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: palette.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercises[i].name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        exercises[i].setsLabel,
                        style: GoogleFonts.barlow(
                          fontSize: 10,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
