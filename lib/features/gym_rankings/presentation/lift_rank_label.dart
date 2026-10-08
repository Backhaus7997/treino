import '../../../l10n/app_l10n.dart';
import '../domain/lift_rank.dart';

/// El nombre de un [LiftRank] en el idioma de la app.
///
/// Aparte del enum a propósito: `LiftRank` es dominio y no debe depender del
/// l10n, que es presentación.
extension LiftRankLabel on LiftRank {
  String label(AppL10n l10n) {
    switch (this) {
      case LiftRank.none:
        return l10n.liftRankNone;
      case LiftRank.bronze:
        return l10n.liftRankBronze;
      case LiftRank.silver:
        return l10n.liftRankSilver;
      case LiftRank.gold:
        return l10n.liftRankGold;
      case LiftRank.platinum:
        return l10n.liftRankPlatinum;
      case LiftRank.diamond:
        return l10n.liftRankDiamond;
      case LiftRank.champion:
        return l10n.liftRankChampion;
      case LiftRank.titan:
        return l10n.liftRankTitan;
      case LiftRank.olympian:
        return l10n.liftRankOlympian;
    }
  }
}
