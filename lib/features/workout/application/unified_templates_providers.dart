import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../domain/routine.dart';
import 'routine_providers.dart';

/// One entry of the unified PLANTILLAS grid. [fromCoach] marks templates
/// shared by the athlete's linked trainer — they render a "DE TU COACH"
/// badge and are pinned before the public catalog, mirroring how
/// `unifiedRoutinesProvider` pins coach plans in the RUTINAS list.
typedef TemplateEntry = ({Routine routine, bool fromCoach});

/// Coach-shared templates as OPTIONAL enrichment of the PLANTILLAS grid.
///
/// Same three gates the old `TrainerTemplatesSection` applied, with the same
/// `valueOrNull` semantics — while any gate is loading, errored, or simply
/// not met, the coach contributes nothing and the grid shows the catalog
/// alone (no spinner, no error): the coach rows pop in when the stream
/// resolves. A failure here must never take down the whole grid.
///
/// `autoDispose` + the PLANTILLAS page being kept alive across tab swipes
/// (see PlantillasTab) means the trainer-templates Firestore listener lives
/// exactly as long as `/workout` stays mounted and is released when the
/// athlete leaves the Entrenar tab route — the same lifetime the
/// widget-watched providers of the old always-mounted sections had.
final coachSharedTemplatesProvider = Provider.autoDispose<List<Routine>>(
  (ref) {
    final link = ref.watch(currentAthleteLinkProvider).valueOrNull;
    if (link == null) return const [];
    final trainerProfile =
        ref.watch(userPublicProfileProvider(link.trainerId)).valueOrNull;
    if (trainerProfile?.sharedTemplatesWithAthletes != true) return const [];
    return ref
            .watch(trainerTemplatesStreamProvider(link.trainerId))
            .valueOrNull ??
        const [];
  },
);

/// The unified PLANTILLAS grid source: coach-shared templates first, then the
/// public system catalog. Sources are disjoint by construction (`source ==
/// 'trainer-template'` vs `source == 'system'`), so plain concatenation
/// cannot duplicate.
///
/// Loading/error track the CATALOG only ([routinesProvider]) — the coach part
/// is enrichment (see [coachSharedTemplatesProvider]). Existing providers are
/// composed untouched: coach_hub consumes them and their signatures must not
/// change.
final unifiedTemplatesProvider =
    Provider.autoDispose<AsyncValue<List<TemplateEntry>>>((ref) {
  final catalog = ref.watch(routinesProvider);
  final coach = ref.watch(coachSharedTemplatesProvider);
  return catalog.whenData(
    (system) => [
      for (final r in coach) (routine: r, fromCoach: true),
      for (final r in system) (routine: r, fromCoach: false),
    ],
  );
});

/// [unifiedTemplatesProvider] filtered by [routinesLevelFilterProvider] —
/// the level pills apply to the WHOLE grid, coach templates included.
final filteredUnifiedTemplatesProvider =
    Provider.autoDispose<AsyncValue<List<TemplateEntry>>>((ref) {
  final entries = ref.watch(unifiedTemplatesProvider);
  final filter = ref.watch(routinesLevelFilterProvider);
  return entries.whenData(
    (list) => filter == null
        ? list
        : [
            for (final e in list)
              if (e.routine.level == filter) e,
          ],
  );
});
