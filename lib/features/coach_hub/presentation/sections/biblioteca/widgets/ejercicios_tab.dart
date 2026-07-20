// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../../../workout/domain/equipment_type.dart';
import '../../../../../workout/domain/exercise.dart';
import '../../../../../workout/domain/muscle_group.dart';
import '../../../widgets/empty_state/empty_state.dart';
import '../providers/biblioteca_providers.dart';
import 'biblioteca_filter_chips.dart';
import 'exercise_detail_dialog.dart';
import 'exercise_grid_card.dart';

/// Grid delegate compartido entre la grilla real y el skeleton de carga —
/// mismas proporciones para que el cross-fade loading→data no "salte".
const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 260,
  childAspectRatio: 0.82,
  crossAxisSpacing: 12,
  mainAxisSpacing: 12,
);

const _gridPadding = EdgeInsets.fromLTRB(16, 0, 16, 24);

/// Tab body for the "Ejercicios" tab of [BibliotecaWebScreen].
///
/// Layout: search field → [BibliotecaFilterChips] → Expanded state-switched
/// grid ([TreinoStateSwitcher] con skeleton shimmer / error / empty / data).
///
/// REQ-BIBW-03, REQ-BIBW-04, REQ-BIBW-05, REQ-BIBW-06, REQ-BIBW-11.
/// SCENARIO-BIBW-03a, SCENARIO-BIBW-03b, SCENARIO-BIBW-11a.
class EjerciciosTab extends ConsumerWidget {
  const EjerciciosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final exercisesAsync = ref.watch(bibliotecaExercisesProvider);
    final query = ref.watch(bibliotecaQueryProvider);
    final muscles = ref.watch(bibliotecaMuscleFilterProvider);
    final equipment = ref.watch(bibliotecaEquipmentFilterProvider);
    final filterSignature = _filterSignature(query, muscles, equipment);

    return Column(
      children: [
        // ── Search field ───────────────────────────────────────────────────
        Padding(
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
            onChanged: (v) {
              ref.read(bibliotecaQueryProvider.notifier).state = v;
            },
          ),
        ),
        // ── Filter chips ───────────────────────────────────────────────────
        const BibliotecaFilterChips(),
        // ── Exercise grid (loading/error/empty/data) ──────────────────────
        Expanded(
          child: TreinoStateSwitcher(
            childKey: ValueKey(_stateKey(exercisesAsync, filterSignature)),
            child: exercisesAsync.when(
              loading: () => const _ExercisesGridSkeleton(),
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
                  padding: _gridPadding,
                  gridDelegate: _gridDelegate,
                  itemCount: exercises.length,
                  itemBuilder: (context, index) {
                    final exercise = exercises[index];
                    return ExerciseGridCard(
                      exercise: exercise,
                      onTap: () {
                        showExerciseDetailDialog(
                          context,
                          exerciseId: exercise.id,
                          ownerId: resolveOwnerId(ref, exercise.category),
                          exerciseName: exercise.name,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Firma estable de la combinación de filtros activos — se usa como parte de
/// la key del branch `data` del [TreinoStateSwitcher] para que cambiar de
/// búsqueda/músculo/equipamiento dispare un cross-fade entre resultados en
/// vez de un swap seco.
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

/// Discrimina el estado actual para [TreinoStateSwitcher]. `loading`/`error`/
/// `empty` son keys fijas (no re-animan entre sí al cambiar filtros); `data`
/// incluye [filterSignature] para que resultados distintos crossfadeen.
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

/// Skeleton de carga de la grilla de ejercicios — mismo [_gridDelegate] que
/// la grilla real (para que el cross-fade no "salte") con cajas placeholder
/// envueltas en [TreinoShimmer].
class _ExercisesGridSkeleton extends StatelessWidget {
  const _ExercisesGridSkeleton();

  static const _placeholderCount = 8;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoShimmer(
      child: GridView.builder(
        padding: _gridPadding,
        gridDelegate: _gridDelegate,
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
