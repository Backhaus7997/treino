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
import '../../../../../workout/application/routine_providers.dart';
import '../../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../../../workout/domain/routine.dart';
import '../../../widgets/empty_state/empty_state.dart';
import 'template_detail_dialog.dart';
import 'template_grid_card.dart';

/// Grid delegate compartido entre la grilla real y el skeleton de carga —
/// mismas proporciones para que el cross-fade loading→data no "salte".
const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 360,
  childAspectRatio: 1.6,
  crossAxisSpacing: AppSpacing.s12,
  mainAxisSpacing: AppSpacing.s12,
);

const _gridPadding = EdgeInsets.fromLTRB(16, 16, 16, 24);

/// Tab body for the "Templates Rutinas" tab of [BibliotecaWebScreen].
///
/// Watches [trainerTemplatesStreamProvider] (filtered to trainer-templates).
/// Layout: [TreinoStateSwitcher] con skeleton shimmer / empty-state honesto /
/// error tokenizado / GridView de [TemplateGridCard].
///
/// REQ-BIBW-09, REQ-BIBW-11.
/// SCENARIO-BIBW-09a, SCENARIO-BIBW-09b, SCENARIO-BIBW-09c, SCENARIO-BIBW-11b.
class TemplatesTab extends ConsumerWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider) ?? '';

    final templatesAsync = uid.isEmpty
        ? const AsyncValue<List<Routine>>.data([])
        : ref.watch(trainerTemplatesStreamProvider(uid));

    return TreinoStateSwitcher(
      childKey: ValueKey(_stateKey(templatesAsync)),
      child: templatesAsync.when(
        loading: () => const _TemplatesGridSkeleton(),
        error: (e, _) => const TreinoEmptyState(
          icon: TreinoIcon.errorState,
          title: 'Error al cargar plantillas', // i18n
        ),
        data: (templates) {
          if (templates.isEmpty) {
            return const TreinoEmptyState(
              icon: TreinoIcon.emptyState,
              title: 'Todavía no creaste plantillas', // i18n
            );
          }

          return GridView.builder(
            padding: _gridPadding,
            gridDelegate: _gridDelegate,
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final routine = templates[index];
              return TemplateGridCard(
                routine: routine,
                onTap: () => showTemplateDetailDialog(context, routine),
              );
            },
          );
        },
      ),
    );
  }
}

/// Discrimina el estado actual para [TreinoStateSwitcher]. Sin filtros en
/// esta tab, por lo que las keys son fijas: `loading`/`error`/`empty`/`data`.
String _stateKey(AsyncValue<List<Routine>> templatesAsync) {
  if (templatesAsync.hasError) return 'error';
  if (templatesAsync.isLoading && !templatesAsync.hasValue) return 'loading';
  final data = templatesAsync.value ?? const [];
  if (data.isEmpty) return 'empty';
  return 'data';
}

/// Skeleton de carga de la grilla de plantillas — mismo [_gridDelegate] que
/// la grilla real (para que el cross-fade no "salte") con cajas placeholder
/// envueltas en [TreinoShimmer].
class _TemplatesGridSkeleton extends StatelessWidget {
  const _TemplatesGridSkeleton();

  static const _placeholderCount = 4;

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
