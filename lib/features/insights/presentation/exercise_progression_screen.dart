import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/presentation/widgets/exercise_progression_chart.dart';
import '../../workout/presentation/widgets/exercise_progression_section.dart';
import '../../workout/presentation/widgets/personal_records_list.dart';

/// Evolución por ejercicio del PROPIO atleta — el gráfico de progresión (peso
/// máximo / 1RM / volumen) más sus records personales, por ejercicio.
///
/// Hasta ahora [ExerciseProgressionSection] era 100% del coach: vivía embebida
/// en `athlete_detail_screen.dart` (mobile) y en el Coach Hub (web), y NO
/// existía ninguna pantalla del lado del alumno. El propio código lo dejaba
/// anotado: las filas de "Ejercicios frecuentes" NO navegaban a ningún lado
/// porque *"no athlete-side per-exercise progression destination exists today"*.
/// Ésta es esa pantalla, y esas filas ahora sí navegan acá.
///
/// Diferencia con los shells del coach: pasa `searchLabels`, así que la sección
/// renderiza un BUSCADOR y recorta la chip row a [kPickerChipCap]. El coach
/// mira a un alumno por vez y su lista es corta; el alumno acumula decenas de
/// ejercicios propios y el carrusel horizontal se vuelve incómodo.
///
/// La búsqueda corre SOBRE LOS EJERCICIOS QUE EL ATLETA REGISTRÓ, nunca sobre
/// el catálogo — que es exactamente lo que el ADR de `exercise-progression`
/// pide (prohíbe reusar `exercise_picker_sheet.dart`, que sí busca el catálogo,
/// porque un ejercicio que nunca entrenaste no tiene progresión que mostrar).
///
/// [uid] explícito — misma convención que el resto de las pantallas del hub.
class ExerciseProgressionScreen extends ConsumerWidget {
  const ExerciseProgressionScreen({
    super.key,
    required this.uid,
    this.initialExerciseId,
  });

  final String uid;

  /// Preselecciona un ejercicio — se usa al llegar desde "Ejercicios
  /// frecuentes" tocando una fila.
  final String? initialExerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.exerciseProgressionScreenTitle),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ExerciseProgressionSection(
                athleteId: uid,
                initialExerciseId: initialExerciseId,
                labels: ExerciseProgressionSectionLabels(
                  // null a propósito: el header de la pantalla ya dice
                  // "EVOLUCIÓN POR EJERCICIO". Repetirlo dentro de la sección
                  // sería el mismo título dos veces en pantalla.
                  sectionTitle: null,
                  loadingText: l10n.coachLoadingLabel,
                  emptyStateText: l10n.progressionEmpty,
                  // El alumno SÍ ve el error — a diferencia del shell del coach,
                  // que lo deja en null y no muestra nada.
                  exerciseListErrorText: l10n.insightsLoadError,
                  searchLabels: ExercisePickerSearchLabels(
                    hintText: l10n.progressionSearchHint,
                    noResultsText: l10n.progressionSearchNoResults,
                  ),
                  chartLabels: ExerciseProgressionChartLabels(
                    heaviestWeightLabel: l10n.progressionMetricPr,
                    oneRepMaxLabel: l10n.progressionMetricOneRepMax,
                    bestSetVolumeLabel: l10n.progressionMetricBestSetVolume,
                    bestSessionVolumeLabel: l10n.progressionMetricVolume,
                    volumeUnit: 'kg·reps',
                    weightUnit: 'kg',
                    frequencyLabel: (n) => l10n.progressionFrequency(n),
                    singlePointHint: l10n.progressionSinglePointHint,
                    emptyHint: l10n.progressionEmptyExercise,
                  ),
                  periodLabels: ChartPeriodLabels(
                    last30dLabel: l10n.progressionPeriodLast30Days,
                    thisWeekLabel: l10n.progressionPeriodThisWeek,
                    monthLabel: l10n.progressionPeriodMonth,
                  ),
                  localeName: l10n.localeName,
                  personalRecordsLabels: PersonalRecordsListLabels(
                    sectionTitle: l10n.personalRecordsSectionTitle,
                    heaviestWeightLabel: l10n.progressionMetricPr,
                    oneRepMaxLabel: l10n.progressionMetricOneRepMax,
                    bestSetVolumeLabel: l10n.progressionMetricBestSetVolume,
                    bestSessionVolumeLabel: l10n.progressionMetricVolume,
                    volumeUnit: 'kg·reps',
                    weightUnit: 'kg',
                    emptyText: l10n.progressionEmptyExercise,
                    localeName: l10n.localeName,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: () => _safePopOrInsights(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 24,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _safePopOrInsights(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home/insights');
  }
}
