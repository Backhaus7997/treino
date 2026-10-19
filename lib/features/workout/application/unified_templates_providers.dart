import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../domain/routine.dart';
import 'routine_providers.dart';
import 'template_preferences_providers.dart';
import '../domain/template_affinity.dart';
import '../domain/template_search.dart';

/// Where a PLANTILLAS grid entry comes from — drives its badge and its
/// position in the grid.
enum TemplateOrigin {
  /// Shared by the athlete's own linked trainer → "DE TU COACH", pinned first.
  coach,

  /// Published to the community catalogue by any trainer → "ENTRENADOR".
  community,

  /// The TREINO system catalogue → no badge.
  system,
}

/// One entry of the unified PLANTILLAS grid.
typedef TemplateEntry = ({Routine routine, TemplateOrigin origin});

extension TemplateEntryX on TemplateEntry {
  /// Kept so existing call sites (and tests) keep reading naturally now that
  /// the grid has three origins instead of a coach/not-coach boolean.
  bool get fromCoach => origin == TemplateOrigin.coach;
}

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

/// Community-published templates as OPTIONAL enrichment of the grid, same
/// contract as [coachSharedTemplatesProvider]: while the query is loading or
/// failed, the community contributes nothing and the rest of the grid renders
/// alone.
final communityTemplatesProvider = Provider.autoDispose<List<Routine>>((ref) {
  return ref.watch(publishedTemplatesProvider).valueOrNull ?? const [];
});

/// The unified PLANTILLAS grid source: the linked coach's templates first,
/// then community-published templates from any trainer, then the public
/// system catalog.
///
/// Loading/error track the CATALOG only ([routinesProvider]) — coach and
/// community are enrichment. Existing providers are composed untouched:
/// coach_hub consumes them and their signatures must not change.
///
/// Coach and community DO overlap (the linked coach's own published
/// templates match both queries), so entries are deduped by routine id with
/// the coach origin winning — an athlete seeing their own coach's template
/// should read "DE TU COACH", not the generic community badge. System is
/// disjoint from both by `source`.
final unifiedTemplatesProvider =
    Provider.autoDispose<AsyncValue<List<TemplateEntry>>>((ref) {
  final catalog = ref.watch(routinesProvider);
  final coach = ref.watch(coachSharedTemplatesProvider);
  final community = ref.watch(communityTemplatesProvider);
  return catalog.whenData((system) {
    final seen = <String>{for (final r in coach) r.id};
    return [
      for (final r in coach) (routine: r, origin: TemplateOrigin.coach),
      for (final r in community)
        if (seen.add(r.id)) (routine: r, origin: TemplateOrigin.community),
      for (final r in system) (routine: r, origin: TemplateOrigin.system),
    ];
  });
});

/// El atleta levantó el filtro duro de días/minutos ("ver todas") para esta
/// vista (#1561). El estado vive acá y no en el widget.
///
/// Mira las preferencias a propósito: si el atleta las edita, el provider se
/// recrea y vuelve a `false` — una respuesta nueva merece su filtro nuevo, no
/// el "ver todas" de la anterior. `autoDispose`: dura lo que la pestaña.
final templatesPreferenceFilterLiftedProvider =
    StateProvider.autoDispose<bool>((ref) {
  ref.watch(athleteTemplatePreferencesProvider);
  return false;
});

/// True si hay un filtro duro de días/minutos EN EFECTO: el atleta respondió
/// alguno y no lo levantó con "ver todas".
final templatesPreferenceFilterActiveProvider = Provider.autoDispose<bool>((
  ref,
) {
  final prefs = ref.watch(athleteTemplatePreferencesProvider);
  return TemplateAffinity.hasHardFilters(prefs) &&
      !ref.watch(templatesPreferenceFilterLiftedProvider);
});

/// [unifiedTemplatesProvider] filtrado por la pill de nivel
/// ([routinesLevelFilterProvider], a TODA la grilla, coach incluido) Y por el
/// filtro duro de días/minutos del mini-onboarding (#1561, ver
/// [TemplateAffinity.matchesHardFilters]) mientras no se haya levantado.
final filteredUnifiedTemplatesProvider =
    Provider.autoDispose<AsyncValue<List<TemplateEntry>>>((ref) {
  final entries = ref.watch(unifiedTemplatesProvider);
  final filter = ref.watch(routinesLevelFilterProvider);
  final hardFilter = ref.watch(templatesPreferenceFilterActiveProvider);
  final preferences = ref.watch(athleteTemplatePreferencesProvider);
  if (filter == null && !hardFilter) return entries;
  return entries.whenData(
    (list) => [
      for (final e in list)
        if ((filter == null || e.routine.level == filter) &&
            (!hardFilter ||
                TemplateAffinity.matchesHardFilters(e.routine, preferences)))
          e,
    ],
  );
});

/// [filteredUnifiedTemplatesProvider] ORDENADO por afinidad con lo que el
/// atleta respondió en el mini-onboarding (#635 PR#3).
///
/// Ordena, no filtra: el filtro duro de días/minutos ya se aplicó en
/// [filteredUnifiedTemplatesProvider] (#1561); acá objetivo y zonas sólo
/// reordenan lo que sobrevivió — ver el dartdoc de [TemplateAffinity].
///
/// Es un provider derivado y no una cuenta en el `build` a propósito:
/// `PlantillasTab` es `AutomaticKeepAliveClientMixin`, así que rankear en el
/// build recalcularía el puntaje de todo el catálogo en cada rebuild de la
/// pestaña.
///
/// El orden es ESTABLE: ante puntajes iguales conserva el de
/// [unifiedTemplatesProvider], que ya pone coach > comunidad > sistema. Sin
/// eso, dos plantillas empatadas podrían intercambiarse entre rebuilds y la
/// grilla bailaría sola. `List.sort` no garantiza estabilidad en Dart, así que
/// el desempate va explícito por posición original.
final rankedUnifiedTemplatesProvider =
    Provider.autoDispose<AsyncValue<List<TemplateEntry>>>((ref) {
  final entries = ref.watch(filteredUnifiedTemplatesProvider);
  final preferences = ref.watch(athleteTemplatePreferencesProvider);
  if (preferences.isEmpty) return entries;
  return entries.whenData((list) {
    final scored = [
      for (var i = 0; i < list.length; i++)
        (
          entry: list[i],
          score: TemplateAffinity.score(list[i].routine, preferences),
          position: i,
        ),
    ]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.position.compareTo(b.position);
      });
    return [for (final s in scored) s.entry];
  });
});

/// Texto de búsqueda de EXPLORAR (#1412), ya con debounce aplicado: el campo
/// de la pestaña escribe acá recién cuando el atleta dejó de tipear.
///
/// `autoDispose` y la pestaña `keepAlive` van de la mano: el valor vive lo
/// que vive la pestaña, y el campo de texto (que se crea vacío al montarse)
/// nunca queda desincronizado de lo que el provider recuerda.
final templatesSearchQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');

/// [rankedUnifiedTemplatesProvider] filtrado Y REORDENADO por relevancia
/// según el texto de búsqueda.
///
/// Parte de la lista que ya respeta la pill de nivel y el orden por afinidad.
/// Con consulta, [TemplateSearch.filter] descarta lo que no matchea (o matchea
/// muy débil) y ordena por relevancia — nombre > ejercicio > músculo por
/// participación > objetivo/nivel —; el orden por afinidad queda sólo como
/// desempate entre puntajes iguales. Sin consulta devuelve la lista rankeada
/// tal cual.
final searchedUnifiedTemplatesProvider =
    Provider.autoDispose<AsyncValue<List<TemplateEntry>>>((ref) {
  final entries = ref.watch(rankedUnifiedTemplatesProvider);
  final query = ref.watch(templatesSearchQueryProvider);
  if (TemplateSearch.isBlank(query)) return entries;
  return entries.whenData(
    (list) => TemplateSearch.filter(list, query, (e) => e.routine),
  );
});
