// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../app/theme/app_motion.dart';
import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../../../workout/domain/equipment_type.dart';
import '../../../../../workout/domain/exercise.dart';
import '../../../../../workout/domain/muscle_group.dart';
import '../../../shell/responsive.dart' as rsp;
import '../../../widgets/empty_state/empty_state.dart';
import '../providers/biblioteca_providers.dart';
import 'biblioteca_filter_chips.dart';
import 'exercise_detail_dialog.dart';
import 'exercise_detail_panel.dart';
import 'exercise_grid_card.dart';

const double _filterColumnWidth = 232;

/// Piso de la sección para las tres columnas.
///
/// 232 de filtros + 40 de gutters + 420 de panel + 836 de grilla: cuatro
/// cards de al menos 200 y tres gutters de 12. Total: 1528 px lógicos.
const double kBibliotecaThreeColumnMinWidth = 1528;

/// Delegate adaptativo del tramo compact, compartido con su skeleton.
const _adaptiveGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 260,
  childAspectRatio: 0.82,
  crossAxisSpacing: AppSpacing.s12,
  mainAxisSpacing: AppSpacing.s12,
);

/// Los tramos desktop mantienen exactamente cuatro columnas.
const _desktopGridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 4,
  childAspectRatio: 0.82,
  crossAxisSpacing: AppSpacing.s12,
  mainAxisSpacing: AppSpacing.s12,
);

const _gridPadding = EdgeInsets.fromLTRB(16, 0, 16, 24);

/// Tab body de "Ejercicios" con tres tramos responsivos.
///
/// El gate desktop usa el viewport del ADR-CHW-004. Dentro de desktop, el
/// [LayoutBuilder] mide el ancho real de la sección —no el viewport— porque el
/// sidebar puede ocupar 72 o 240 px sin cambiar `MediaQuery`.
class EjerciciosTab extends ConsumerWidget {
  const EjerciciosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(bibliotecaExercisesProvider);
    final query = ref.watch(bibliotecaQueryProvider);
    final muscles = ref.watch(bibliotecaMuscleFilterProvider);
    final equipment = ref.watch(bibliotecaEquipmentFilterProvider);
    final selected = ref.watch(bibliotecaSelectedExerciseProvider);
    final filterSignature = _filterSignature(query, muscles, equipment);
    final isDesktop = rsp.viewportFor(MediaQuery.sizeOf(context).width) ==
        rsp.Viewport.desktop;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showSideFilters = isDesktop;
        final showDetailPanel = isDesktop &&
            constraints.maxWidth >= kBibliotecaThreeColumnMinWidth;

        void openExercise(Exercise exercise) {
          final ownerId = resolveOwnerId(ref, exercise.category);
          if (showDetailPanel) {
            ref.read(bibliotecaSelectedExerciseProvider.notifier).state = (
              exerciseId: exercise.id,
              ownerId: ownerId,
              exerciseName: exercise.name,
            );
            return;
          }
          showExerciseDetailDialog(
            context,
            exerciseId: exercise.id,
            ownerId: ownerId,
            exerciseName: exercise.name,
          );
        }

        final results = _ExerciseResults(
          exercisesAsync: exercisesAsync,
          filterSignature: filterSignature,
          fixedFourColumns: showSideFilters,
          onQueryChanged: (value) {
            ref.read(bibliotecaQueryProvider.notifier).state = value;
          },
          onExerciseTap: openExercise,
        );

        if (!showSideFilters) {
          return Column(
            children: [
              _SearchField(onChanged: results.onQueryChanged),
              TreinoFadeSlideIn(
                delay: AppMotion.stagger(1),
                child: const BibliotecaFilterChips(),
              ),
              Expanded(child: results),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('biblioteca_filter_column'),
              width: _filterColumnWidth,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s18,
                AppSpacing.s18,
                AppSpacing.s18,
                AppSpacing.s20,
              ),
              child: TreinoFadeSlideIn(
                delay: AppMotion.stagger(1),
                child: const BibliotecaFilterChips(vertical: true),
              ),
            ),
            const SizedBox(width: AppSpacing.s20),
            Expanded(
              child: Column(
                children: [
                  _SearchField(onChanged: results.onQueryChanged),
                  Expanded(child: results),
                ],
              ),
            ),
            if (showDetailPanel && selected != null) ...[
              const SizedBox(width: AppSpacing.s20),
              ExerciseDetailPanel(
                key: const Key('biblioteca_detail_panel'),
                exerciseId: selected.exerciseId,
                ownerId: selected.ownerId,
                exerciseName: selected.exerciseName,
                onClose: () {
                  ref
                      .read(bibliotecaSelectedExerciseProvider.notifier)
                      .state = null;
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s18,
        AppSpacing.s18,
        AppSpacing.s18,
        AppSpacing.s8,
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Buscar ejercicios...', // i18n
          hintStyle: TextStyle(
            fontFamily: AppFonts.barlow,
            color: palette.textMuted,
          ),
          prefixIcon: Icon(
            TreinoIcon.search,
            color: palette.textMuted,
            size: 20,
          ),
          filled: true,
          fillColor: palette.bgCard,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: palette.accent, width: 1.5),
          ),
        ),
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          color: palette.textPrimary,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _ExerciseResults extends StatelessWidget {
  const _ExerciseResults({
    required this.exercisesAsync,
    required this.filterSignature,
    required this.fixedFourColumns,
    required this.onQueryChanged,
    required this.onExerciseTap,
  });

  final AsyncValue<List<Exercise>> exercisesAsync;
  final String filterSignature;
  final bool fixedFourColumns;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Exercise> onExerciseTap;

  SliverGridDelegate get gridDelegate =>
      fixedFourColumns ? _desktopGridDelegate : _adaptiveGridDelegate;

  @override
  Widget build(BuildContext context) {
    return TreinoStateSwitcher(
      childKey: ValueKey(_stateKey(exercisesAsync, filterSignature)),
      child: exercisesAsync.when(
        loading: () => _ExercisesGridSkeleton(gridDelegate: gridDelegate),
        error: (e, _) => const TreinoEmptyState(
          icon: TreinoIcon.errorState,
          title: 'Error al cargar ejercicios.', // i18n
          description: 'Volvé a intentar en unos segundos.', // i18n
        ),
        data: (exercises) {
          if (exercises.isEmpty) {
            return const TreinoEmptyState(
              icon: TreinoIcon.emptyState,
              title: 'No se encontraron ejercicios', // i18n
              description:
                  'Probá con otra búsqueda o ajustá los filtros.', // i18n
            );
          }
          return GridView.builder(
            key: const Key('biblioteca_exercise_grid'),
            padding: _gridPadding,
            gridDelegate: gridDelegate,
            itemCount: exercises.length,
            itemBuilder: (context, index) {
              final exercise = exercises[index];
              return ExerciseGridCard(
                exercise: exercise,
                onTap: () => onExerciseTap(exercise),
              );
            },
          );
        },
      ),
    );
  }
}

String _filterSignature(
  String query,
  Set<MuscleGroup> muscles,
  Set<EquipmentType> equipment,
) {
  final muscleKey = (muscles.map((m) => m.name).toList()..sort()).join(',');
  final equipmentKey = (equipment.map((e) => e.name).toList()..sort()).join(
    ',',
  );
  return '$query|$muscleKey|$equipmentKey';
}

String _stateKey(
  AsyncValue<List<Exercise>> exercisesAsync,
  String filterSignature,
) {
  if (exercisesAsync.hasError) return 'error';
  if (exercisesAsync.isLoading && !exercisesAsync.hasValue) return 'loading';
  final data = exercisesAsync.value ?? const [];
  if (data.isEmpty) return 'empty';
  return 'data_$filterSignature';
}

class _ExercisesGridSkeleton extends StatelessWidget {
  const _ExercisesGridSkeleton({required this.gridDelegate});

  static const _placeholderCount = 8;
  final SliverGridDelegate gridDelegate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoShimmer(
      child: GridView.builder(
        padding: _gridPadding,
        gridDelegate: gridDelegate,
        itemCount: _placeholderCount,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}
