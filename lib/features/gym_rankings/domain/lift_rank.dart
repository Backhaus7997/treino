import '../../profile/domain/user_public_profile.dart';
import 'ranking_dimension.dart';

/// Rango de levantamiento de un atleta en sentadilla, banca o peso muerto: lo
/// que la pestaña Rankings dibuja como insignia.
///
/// Se llama "rango" y no "tier" ni "nivel" a propósito. `tier` ya es el plan
/// del PF (`SubscriptionTier`), y `AGENTS.md` §4 deja fuera Levels / XP: esto no
/// es progresión por puntos, se DERIVA del mayor peso levantado, escalado por
/// peso corporal.
///
/// El cliente no calcula nada. La fórmula y los umbrales viven en
/// `functions/src/ranking-ranks.ts`, que escribe el entero 0..8 en
/// `userPublicProfiles/{uid}`; acá sólo se mapea ese entero a una insignia.
///
/// El orden de los valores ES el entero guardado: `none` = 0 … `olympian` = 8.
/// No reordenar ni insertar en el medio sin migrar los docs.
enum LiftRank {
  none,
  bronze,
  silver,
  gold,
  platinum,
  diamond,
  champion,
  titan,
  olympian;

  /// El rango que corresponde al entero guardado, o `null` si no hay dato.
  ///
  /// `null` y los valores fuera de 0..8 son "sin dato", NO `none`: `none` (0)
  /// significa que el atleta tiene datos pero todavía no llega a Bronce, y
  /// mostrarlo con un valor corrupto sería inventarle un estado.
  static LiftRank? fromValue(int? value) {
    if (value == null || value < 0 || value >= LiftRank.values.length) {
      return null;
    }
    return LiftRank.values[value];
  }

  /// Cantidad de discos por lado que lleva la barra de la insignia: el rango
  /// mismo (Bronce 1 … Olímpico 8, `none` ninguno).
  int get plates => index;

  /// Nombre del SVG en `assets/ranking_ranks/`, sin extensión. Coincide con el
  /// de `tool/build_lift_rank_badges.dart`; un test lo verifica.
  String get assetName => this == LiftRank.none ? 'unranked' : name;

  String get assetPath => 'assets/ranking_ranks/$assetName.svg';
}

/// El rango de [profile] en [dimension], o `null` cuando no hay dato o la
/// dimensión no es un levantamiento (rachas y volumen no tienen rango).
LiftRank? liftRankFor(RankingDimension dimension, UserPublicProfile profile) {
  switch (dimension) {
    case RankingDimension.squat:
      return LiftRank.fromValue(profile.squatRank);
    case RankingDimension.bench:
      return LiftRank.fromValue(profile.benchRank);
    case RankingDimension.deadlift:
      return LiftRank.fromValue(profile.deadliftRank);
    case RankingDimension.streak:
    case RankingDimension.volume:
      return null;
  }
}

/// `true` para las tres dimensiones que tienen rango.
bool dimensionHasLiftRank(RankingDimension dimension) =>
    dimension == RankingDimension.squat ||
    dimension == RankingDimension.bench ||
    dimension == RankingDimension.deadlift;
