import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../profile/application/user_providers.dart'
    show userProfileProvider;
import '../../../profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import '../../../profile/domain/user_public_profile.dart';
import '../../domain/lift_rank.dart';
import '../../domain/ranking_dimension.dart';
import '../lift_rank_label.dart';
import 'lift_rank_badge.dart';

/// Cuántos rangos con insignia hay (Bronce … Olímpico). Es el "8" de "Rango 3
/// de 8"; un test lo ata a la cantidad de valores del enum.
const kLiftRankTotal = 8;

/// Qué le pasa al atleta con su rango en un levantamiento. Separado del widget
/// para poder probar la decisión sin pintar nada.
enum LiftRankStripState {
  /// Tiene rango de Bronce para arriba.
  ranked,

  /// Tiene datos pero todavía no llega a Bronce.
  belowFirstRank,

  /// Nunca registró este levantamiento.
  noLift,

  /// Registró el levantamiento pero no cargó su peso corporal: sin peso no hay
  /// rango, porque la escala depende de él.
  noBodyWeight,

  /// Tiene levantamiento y peso, pero el servidor todavía no calculó el rango
  /// (se recalcula al terminar cada entrenamiento).
  pending,
}

/// Decide el estado de la franja a partir de los tres datos que lo determinan.
///
/// El orden importa: sin levantamiento no hay nada que rankear aunque falte el
/// peso, y sólo cuando el levantamiento existe se pregunta por el peso corporal.
/// Si están los dos y el rango sigue en `null`, no es culpa del atleta: es que
/// el recompute todavía no corrió, y pedirle que cargue un peso que ya cargó
/// sería mandarlo a arreglar algo que no está roto.
LiftRankStripState liftRankStripState({
  required LiftRank? rank,
  required num? bestKg,
  required double? bodyWeightKg,
}) {
  if (rank != null) {
    return rank == LiftRank.none
        ? LiftRankStripState.belowFirstRank
        : LiftRankStripState.ranked;
  }
  if (bestKg == null) return LiftRankStripState.noLift;
  if (bodyWeightKg == null) return LiftRankStripState.noBodyWeight;
  return LiftRankStripState.pending;
}

/// La franja "Tu rango" de las pestañas de levantamientos de Rankings.
///
/// El tablero muestra sólo el top 20 del gym, así que sin esta franja casi nadie
/// vería su propia insignia. Toma los datos del atleta logueado, no de la lista.
class LiftRankStrip extends ConsumerWidget {
  const LiftRankStrip({
    super.key,
    required this.myUid,
    required this.dimension,
    required this.liftLabel,
  });

  final String myUid;

  /// Una de las tres dimensiones de levantamiento.
  final RankingDimension dimension;

  /// Nombre del levantamiento ya en mayúsculas (SENTADILLA, BANCA…).
  final String liftLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);

    // `select` a un record de primitivos: la franja sólo se reconstruye cuando
    // cambia algo que ella muestra, no con cada contador del perfil público.
    final mine = ref.watch(
      userPublicProfileProvider(myUid)
          .select((async) => _mine(dimension, async.valueOrNull)),
    );
    final bodyWeightKg = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.bodyWeightKg),
    );

    final state = liftRankStripState(
      rank: mine.rank,
      bestKg: mine.bestKg,
      bodyWeightKg: bodyWeightKg,
    );
    final rank = mine.rank ?? LiftRank.none;

    final hint = switch (state) {
      LiftRankStripState.ranked => l10n.liftRankStripPosition(
          rank.index,
          kLiftRankTotal,
        ),
      LiftRankStripState.belowFirstRank => l10n.liftRankStripBelowBronze,
      LiftRankStripState.noLift => l10n.liftRankStripNoLift,
      LiftRankStripState.noBodyWeight => l10n.liftRankStripNoBodyWeight,
      LiftRankStripState.pending => l10n.liftRankStripPending,
    };
    final showName = state == LiftRankStripState.ranked ||
        state == LiftRankStripState.belowFirstRank;

    final hintText = Text(
      hint,
      key: const Key('rankings_my_rank_hint'),
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w400,
        fontSize: AppTextSize.bodyDense,
        // `accentText`, no `accent`: el acento como TINTA tiene su propio token
        // porque el menta puro sobre blanco no llega al contraste (AGENTS §2).
        color: state == LiftRankStripState.noBodyWeight
            ? palette.accentText
            : palette.textMuted,
      ),
    );

    final strip = Container(
      key: const Key('rankings_my_rank_strip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          LiftRankBadge(
            key: const Key('rankings_my_rank_badge'),
            rank: rank,
            size: LiftRankBadge.featuredSize,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.liftRankStripTitle(liftLabel),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.caption,
                    letterSpacing: 1.4,
                    color: palette.textMuted,
                  ),
                ),
                if (showName)
                  Text(
                    rank.label(l10n).toUpperCase(),
                    key: const Key('rankings_my_rank_name'),
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTextSize.titleLarge,
                      color: palette.textPrimary,
                    ),
                  ),
                hintText,
              ],
            ),
          ),
        ],
      ),
    );

    if (state != LiftRankStripState.noBodyWeight) return strip;

    // Sin peso corporal no hay rango: la franja entera lleva a cargarlo.
    return Semantics(
      container: true,
      button: true,
      label: l10n.liftRankStripNoBodyWeight,
      child: TreinoTappable(
        onTap: () => context.push('/profile/edit-personal'),
        child: strip,
      ),
    );
  }
}

/// Lo que la franja necesita saber de [profile] en [dimension]: el rango y el
/// mejor peso. Con perfil `null` (todavía cargando, o sin doc) no sabe nada.
({LiftRank? rank, num? bestKg}) _mine(
  RankingDimension dimension,
  UserPublicProfile? profile,
) {
  if (profile == null) return (rank: null, bestKg: null);
  return (
    rank: liftRankFor(dimension, profile),
    bestKg: _bestKg(dimension, profile),
  );
}

/// El mejor peso del atleta en [dimension], o `null` si nunca lo registró.
num? _bestKg(RankingDimension dimension, UserPublicProfile profile) {
  switch (dimension) {
    case RankingDimension.squat:
      return profile.bestSquatKg;
    case RankingDimension.bench:
      return profile.bestBenchKg;
    case RankingDimension.deadlift:
      return profile.bestDeadliftKg;
    case RankingDimension.streak:
    case RankingDimension.volume:
      return null;
  }
}
