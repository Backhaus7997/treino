import '../../workout/domain/set_log.dart';

/// The 3 "main lifts" tracked for per-gym rankings. Only barbell-canonical
/// variants count so PRs are apples-to-apples across athletes — a dumbbell
/// or Multipower weight is not comparable to a barbell 1RM. See design
/// `sdd/rankings/design` — Family membership.
enum MainLift { squat, bench, deadlift }

/// Curated map of catalog exercise ids (see
/// `docs/video-catalog-audit/NUEVO-catalogo.json`) that count toward each
/// [MainLift] family. Deadlift includes BOTH conventional and sumo — a
/// competition-legal variant of the same lift — so a PR is the max of the
/// two. Assistance variants (rumano/stiff-leg) and non-barbell equipment
/// (dumbbell/Multipower/machine/hack) are intentionally excluded.
const kMainLiftFamilies = <MainLift, Set<String>>{
  MainLift.squat: {'squat-barra'},
  MainLift.bench: {'bench-press-barra'},
  MainLift.deadlift: {'deadlift-barra', 'sumo-deadlift-barra'},
};

/// Returns the max `weightKg` among [logs] whose `exerciseId` belongs to
/// [lift]'s family, or `null` when none match (no PR to report for that
/// lift in this set of logs).
double? familyMaxWeight(MainLift lift, List<SetLog> logs) {
  final familyIds = kMainLiftFamilies[lift] ?? const <String>{};
  double? max;
  for (final log in logs) {
    if (!familyIds.contains(log.exerciseId)) continue;
    if (max == null || log.weightKg > max) {
      max = log.weightKg;
    }
  }
  return max;
}
