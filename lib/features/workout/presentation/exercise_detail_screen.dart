import 'package:flutter/material.dart';
import 'package:treino/core/utils/kg_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/exercise_asset_image.dart';
import '../../../core/widgets/treino_collapsing_top_bar.dart';
import '../../../core/widgets/firebase_storage_video_player.dart'
    show VideoPlayOverlay;
import '../../../core/widgets/motion/treino_shimmer.dart';
import '../../../l10n/app_l10n.dart';
import '../../insights/domain/chart_period.dart';
import '../application/exercise_progression_aggregator.dart';
import '../application/exercise_progression_providers.dart';
import '../application/exercise_providers.dart';
import '../application/session_providers.dart' show currentUidProvider;
import '../domain/exercise.dart';
import '../domain/exercise_progression.dart';
import '../domain/muscle_group.dart';
import 'widgets/exercise_progression_chart.dart';
import 'widgets/exercise_progression_section.dart'
    show ChartPeriodLabels, ChartPeriodSelector;
import 'widgets/exercise_video_player.dart';
import 'widgets/personal_records_list.dart';
import 'widgets/stat_tile.dart';
import 'widgets/technique_instruction_item.dart';
import '../../paywall/application/athlete_entitlement_provider.dart';
import '../../paywall/presentation/free_plan_limit_sheet.dart';

// Display-name maps. Data from Firestore is stored in English (e.g. 'chest',
// 'compound') so the UI translates to Spanish at render time. Unknown values
// fall back to the original string upper-cased so we never crash.
const _categoryEs = <String, String>{
  'compound': 'COMPUESTO',
  'isolation': 'AISLAMIENTO',
};

// Canonical taxonomy label (Pecho, Isquiotibiales, …), upper-cased for the
// detail header. Resolves canonical keys AND legacy Spanish labels; unknown
// values fall back to their upper-cased raw text.
String _muscleEs(String raw) => muscleGroupLabel(raw).toUpperCase();

String _categoryEsOf(String raw) =>
    _categoryEs[raw.toLowerCase()] ?? raw.toUpperCase();

/// ExerciseDetailScreen — ConsumerWidget that observes slotExerciseProvider
/// (which falls back to the trainer's customExercises subcollection when
/// `ownerId` is supplied and the id isn't in the public catalogue).
/// No Scaffold, AppBackground, or SafeArea — those are provided by
/// _ShellScaffold in router.dart (REQ-RDT-019).
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exerciseId,
    this.ownerId,
    this.exerciseName,
    this.athleteId,
    this.backFallbackRoute = '/workout',
  });

  final String exerciseId;

  /// Whose personal stats/history the screen shows (1RM, sesiones, progreso,
  /// récords, historial). The coach read-only route passes the athlete being
  /// inspected so a PF NEVER sees their own numbers inside an athlete's
  /// context; null — every athlete-side entry point — resolves to the
  /// signed-in user.
  final String? athleteId;

  /// Trainer uid that owns the routine the slot belongs to. When non-null
  /// and the public catalogue lookup misses, the provider tries
  /// `users/{ownerId}/customExercises/{exerciseId}`.
  final String? ownerId;

  /// Display name from the slot. Used by [slotExerciseProvider]'s tier-2
  /// fallback (name / alias match) when the slot's `exerciseId` drifted
  /// from the current catalogue. Optional — when omitted, only strict ID
  /// + custom-exercise fallbacks run.
  final String? exerciseName;

  /// Where the back button lands when there is nothing to pop (deep-link or
  /// OS state restoration). Defaults to the athlete's `/workout` tab. The
  /// coach read-only context — reached OUT of the shell from a plan detail —
  /// passes `/coach/athlete/:id` so a restored PF isn't dumped on the
  /// athlete's Entrenar tab (issue #410, same class as the RoutineDetailScreen
  /// back fallback).
  final String backFallbackRoute;

  /// Abre el detalle con un push IMPERATIVO y su propio Scaffold host, para
  /// los lugares fuera del shell donde la ruta de go_router no sirve (el
  /// player de sesión, el picker de ejercicios del PF): ahí monta el detalle
  /// sin `_ShellScaffold` → pantalla negra.
  ///
  /// El host es el mismo que `_immersiveEdgeToEdge` del router: el degradé
  /// del tema ([AppBackground]) corre también detrás de la status bar, y
  /// [TreinoCollapsingTopBar] reserva ese inset él solo. Con un `SafeArea`
  /// entero sobre un `bg` liso quedaba una franja del alto de la status bar
  /// arriba de todo (#1559).
  static Future<void> push(
    BuildContext context, {
    required String exerciseId,
    String? ownerId,
    String? exerciseName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Colors.transparent,
          body: AppBackground(
            child: SafeArea(
              top: false,
              child: ExerciseDetailScreen(
                exerciseId: exerciseId,
                ownerId: ownerId,
                exerciseName: exerciseName,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseAsync = ref.watch(
      slotExerciseProvider((
        exerciseId: exerciseId,
        ownerId: ownerId,
        exerciseName: exerciseName,
      )),
    );
    final statsUid = athleteId ?? ref.watch(currentUidProvider) ?? '';

    final exercise = exerciseAsync.valueOrNull;

    // La barra superior aparece al scrollear (#1559): en offset 0 sólo flota la
    // flecha sobre el fondo del tema, arriba del encabezado. Nada va debajo de
    // la status bar ni de la flecha: la media vive más abajo, en su tarjeta
    // (feedback en device 2026-10-21: el video quedaba tapado). Los estados
    // sin datos también la llevan, para que el usuario nunca quede sin salida.
    return TreinoCollapsingTopBar(
      title: exercise?.name,
      // El encabezado arranca bajo la barra y mide ~120.
      collapseOffset: 120,
      onBack: () =>
          context.canPop() ? context.pop() : context.go(backFallbackRoute),
      body: exerciseAsync.when(
        data: (exercise) => exercise == null
            ? const _NotFoundState(label: 'Ejercicio no encontrado')
            : _ExerciseDetailContent(
                exercise: exercise,
                statsUid: statsUid,
                // The SLOT's id, not the resolved [Exercise.id]: the
                // player logs `slot.exerciseId` into setLogs, so when the
                // slot id drifted from the catalogue and the provider
                // resolved by name-fallback, the athlete's history still
                // lives under the slot id.
                statsExerciseId: exerciseId,
              ),
        loading: () => const _ExerciseLoadingSkeleton(),
        error: (_, __) => _ErrorState(
          message: 'No pudimos cargar el ejercicio.',
          onRetry: () => ref.invalidate(
            slotExerciseProvider((
              exerciseId: exerciseId,
              ownerId: ownerId,
              exerciseName: exerciseName,
            )),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Happy-path content
// ---------------------------------------------------------------------------

class _ExerciseDetailContent extends StatelessWidget {
  const _ExerciseDetailContent({
    required this.exercise,
    required this.statsUid,
    required this.statsExerciseId,
  });

  final Exercise exercise;

  /// Athlete whose personal data feeds the stats/records/history blocks —
  /// see [ExerciseDetailScreen.athleteId].
  final String statsUid;

  /// The slot's exerciseId — the id the player writes into setLogs (see the
  /// call site in [ExerciseDetailScreen.build]).
  final String statsExerciseId;

  @override
  Widget build(BuildContext context) {
    final instructions = exercise.techniqueInstructions;
    final badgeText =
        '${_muscleEs(exercise.muscleGroup)} · ${_categoryEsOf(exercise.category)}';

    // Trainer-defined exercises (category == 'custom') don't have an asset
    // in `assets/exercises/`: no photo card for them (the green fallback reads
    // as broken for a personalized plan), and their VIDEO section keeps the
    // trainer's upload slot in every state, including "coming soon".
    final isCustom = exercise.category.toLowerCase() == 'custom';

    // Orden pedido en device (2026-10-21): encabezado → TÉCNICA → VIDEO →
    // PROGRESIÓN → HISTORIAL. El video ya no es un hero de borde a borde: con
    // la status bar y la flecha encima quedaba tapado mientras se
    // reproducía. Ahora va en su tarjeta, con su relación de aspecto real y
    // nada encima. Sólo Firebase Storage y YouTube son reproducibles; una URL
    // ausente o irreproducible deja la foto, nunca un hueco.
    final videoUrl = exercise.videoUrl?.trim() ?? '';
    final playableVideoUrl = !isCustom &&
            (isFirebaseStorageVideo(videoUrl) ||
                parseYoutubeVideoId(videoUrl) != null)
        ? videoUrl
        : null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _ExerciseHeader(
            badgeText: badgeText,
            titleText: exercise.name.toUpperCase(),
          ),
        ),
        SliverPadding(
          // Bottom inset clears the shell's floating nav bar (extendBody:true).
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.paddingOf(context).bottom),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 20),
              const _SectionHeader(text: 'TÉCNICA'),
              const SizedBox(height: 12),
              if (instructions == null || instructions.isEmpty)
                const _EmptyState(
                  message: 'No hay instrucciones de técnica todavía',
                )
              else
                _TecnicaCard(instructions: instructions),
              const SizedBox(height: 20),
              if (playableVideoUrl != null) ...[
                const _SectionHeader(text: 'VIDEO'),
                const SizedBox(height: 12),
                _ExerciseVideoCard(
                  exerciseId: exercise.id,
                  muscleGroup: exercise.muscleGroup,
                  thumbnailUrl: exercise.thumbnailUrl,
                  videoUrl: playableVideoUrl,
                ),
              ] else if (isCustom) ...[
                const _SectionHeader(text: 'VIDEO'),
                const SizedBox(height: 12),
                // ExerciseVideoPlayer handles all states (null/invalid/valid)
                // internally — the slot always renders so trainers can see
                // there's a video surface even before URLs are populated.
                ExerciseVideoPlayer(videoUrl: exercise.videoUrl),
              ] else
                _ExercisePhotoCard(
                  exerciseId: exercise.id,
                  muscleGroup: exercise.muscleGroup,
                  thumbnailUrl: exercise.thumbnailUrl,
                ),
              const SizedBox(height: 20),
              _PersonalStatsBlock(
                athleteUid: statsUid,
                exerciseId: statsExerciseId,
              ),
              const SizedBox(height: 20),
              const _SectionHeader(text: 'HISTORIAL'),
              const SizedBox(height: 12),
              _HistorySection(
                athleteUid: statsUid,
                exerciseId: statsExerciseId,
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Period-scoped personal block: header + selector, stats card, chart, records
// ---------------------------------------------------------------------------

/// Owns the [ChartPeriod] selection and the single
/// [exerciseProgressionProvider] watch, so switching periods rebuilds ONLY
/// this subtree — the hero/TÉCNICA above and HISTORIAL below don't care
/// about the period (ref.watch del provider más chico posible).
class _PersonalStatsBlock extends ConsumerStatefulWidget {
  const _PersonalStatsBlock({
    required this.athleteUid,
    required this.exerciseId,
  });

  final String athleteUid;
  final String exerciseId;

  @override
  ConsumerState<_PersonalStatsBlock> createState() =>
      _PersonalStatsBlockState();
}

class _PersonalStatsBlockState extends ConsumerState<_PersonalStatsBlock> {
  /// [AD7] Governs stats card, chart and records — all read the same
  /// period-scoped aggregation. HISTORIAL deliberately does NOT follow it
  /// (see [exerciseSessionHistoryProvider]).
  ChartPeriod _period = ChartPeriod.defaultPeriod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final progressionAsync = ref.watch(exerciseProgressionProvider((
      athleteUid: widget.athleteUid,
      exerciseId: widget.exerciseId,
      period: _period,
    )));
    // Loading/error → null → the tiles keep their "—" placeholder (the card
    // must never crash nor block the rest of the screen).
    final progression = progressionAsync.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionHeader(text: 'PROGRESIÓN'),
            const Spacer(),
            ChartPeriodSelector(
              selected: _period,
              labels: ChartPeriodLabels(
                last30dLabel: l10n.progressionPeriodLast30Days,
                thisWeekLabel: l10n.progressionPeriodThisWeek,
                monthLabel: l10n.progressionPeriodMonth,
                last3mLabel: l10n.progressionPeriodLast3Months,
                last1yLabel: l10n.progressionPeriodLast1Year,
              ),
              onSelect: (p) => setState(() => _period = p),
              lockedPeriods: ref.watch(lockedChartPeriodsProvider),
              onLockedTap: (_) => showFreePlanLimitSheet(
                context,
                limit: FreePlanLimit.chartHistory,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatsCard(
          tiles: [
            StatTile(
                label: '1RM',
                value: _oneRepMaxValue(
                    progression, AppL10n.of(context).localeName)),
            StatTile(
              label: 'SESIONES',
              value: progression == null
                  ? null
                  : '${progression.frequencySessionCount}',
            ),
            StatTile(label: 'PROGRESO', value: _progressValue(progression)),
          ],
        ),
        const SizedBox(height: 12),
        _ProgressionChartBlock(progressionAsync: progressionAsync),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Personal stats derivations (display-side)
// ---------------------------------------------------------------------------

/// Formats a kg value the same way the chart and the records list do: whole
/// numbers drop the decimals, fractional values keep one — with the locale's
/// separator («112,5» in es).
String _formatStatValue(double value, String localeName) =>
    formatNumberDisplay(value, localeName);

/// 1RM tile: best Epley estimate within the active period, rounded to 0.5kg
/// at display only (AD2 — same convention as chart/records).
String? _oneRepMaxValue(ExerciseProgression? progression, String localeName) {
  final series = progression?.oneRepMaxSeries;
  if (series == null || series.isEmpty) return null;
  var best = series.first.value;
  for (final point in series.skip(1)) {
    if (point.value > best) best = point.value;
  }
  return '${_formatStatValue(roundToNearestHalfKg(best), localeName)} kg';
}

/// PROGRESO tile criterion: % delta first→last session over the period's 1RM
/// series — the estimated-strength metric, deliberately the same series the
/// 1RM tile reads so the card stays internally coherent (session volume is
/// confounded by set count; heaviest weight moves in coarse plate jumps).
/// Needs ≥2 points inside the period; otherwise "—".
String? _progressValue(ExerciseProgression? progression) {
  final series = progression?.oneRepMaxSeries;
  if (series == null || series.length < 2) return null;
  final first = series.first.value;
  if (first <= 0) return null;
  final pct = ((series.last.value - first) / first * 100).round();
  return pct > 0 ? '+$pct%' : '$pct%';
}

// ---------------------------------------------------------------------------
// Progression chart + personal records block
// ---------------------------------------------------------------------------

/// Chart + records for the active period. Loading keeps a card-sized shimmer
/// so the sections below don't jump when the data lands; error degrades to a
/// muted one-liner (the rest of the screen must stay usable).
class _ProgressionChartBlock extends StatelessWidget {
  const _ProgressionChartBlock({required this.progressionAsync});

  final AsyncValue<ExerciseProgression> progressionAsync;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return progressionAsync.when(
      loading: () => TreinoShimmer(
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      error: (_, __) =>
          const _EmptyState(message: 'No pudimos cargar la progresión.'),
      data: (progression) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExerciseProgressionChart(
            progression: progression,
            labels: ExerciseProgressionChartLabels(
              heaviestWeightLabel: l10n.progressionMetricPr,
              oneRepMaxLabel: l10n.progressionMetricOneRepMax,
              bestSetVolumeLabel: l10n.progressionMetricBestSetVolume,
              bestSessionVolumeLabel: l10n.progressionMetricVolume,
              volumeUnit: 'kg',
              weightUnit: 'kg',
              frequencyLabel: (n) => l10n.progressionFrequencyPeriod(n),
              singlePointHint: l10n.progressionSinglePointHint,
              emptyHint: l10n.progressionEmptyExercise,
            ),
            localeName: l10n.localeName,
          ),
          // Empty records would repeat the chart's empty hint right below it —
          // render the list only when there is something to celebrate.
          if (progression.personalRecords.isNotEmpty) ...[
            const SizedBox(height: 14),
            PersonalRecordsList(
              records: progression.personalRecords,
              labels: PersonalRecordsListLabels(
                sectionTitle: l10n.personalRecordsSectionTitle,
                heaviestWeightLabel: l10n.progressionMetricPr,
                oneRepMaxLabel: l10n.progressionMetricOneRepMax,
                bestSetVolumeLabel: l10n.progressionMetricBestSetVolume,
                bestSessionVolumeLabel: l10n.progressionMetricVolume,
                volumeUnit: 'kg',
                weightUnit: 'kg',
                emptyText: l10n.progressionEmptyExercise,
                localeName: l10n.localeName,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HISTORIAL — real per-session history
// ---------------------------------------------------------------------------

/// e.g. '10 mar 2026' — same date convention as PersonalRecordsList.
String _historyDate(DateTime dt, String localeName) =>
    intl.DateFormat('d MMM yyyy', localeName).format(dt);

class _HistorySection extends ConsumerWidget {
  const _HistorySection({
    required this.athleteUid,
    required this.exerciseId,
  });

  final String athleteUid;
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final historyAsync = ref.watch(exerciseSessionHistoryProvider(
        (athleteUid: athleteUid, exerciseId: exerciseId)));

    return historyAsync.when(
      loading: () => Text(
        l10n.coachLoadingLabel,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.textMuted,
        ),
      ),
      error: (_, __) =>
          const _EmptyState(message: 'No pudimos cargar el historial.'),
      data: (entries) => entries.isEmpty
          ? const _HistoryEmptyState()
          : _HistoryList(entries: entries, localeName: l10n.localeName),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.entries, required this.localeName});

  final List<ExerciseSessionHistoryEntry> entries;
  final String localeName;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(color: palette.border, height: 18),
            _HistoryRow(entry: entries[i], localeName: localeName),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.localeName});

  final ExerciseSessionHistoryEntry entry;
  final String localeName;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // #368: bodyweight-only session → best set is reps-only, no volume line.
    final isBodyweight = entry.bestWeightKg <= 0;
    final bestSet = isBodyweight
        ? '${entry.bestSetReps} reps'
        : '${_formatStatValue(entry.bestWeightKg, AppL10n.of(context).localeName)} kg × ${entry.bestSetReps}';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _historyDate(entry.date, localeName),
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.setCount == 1 ? '1 serie' : '${entry.setCount} series',
                style: GoogleFonts.barlow(
                  fontSize: 11,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              bestSet,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.accent,
              ),
            ),
            if (entry.sessionVolume > 0) ...[
              const SizedBox(height: 2),
              Text(
                '${formatVolumeKg(entry.sessionVolume, AppL10n.of(context).localeName)} kg',
                style: GoogleFonts.barlow(
                  fontSize: 11,
                  color: palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

/// Encabezado de todos los ejercicios: chip «grupo · tipo» y el nombre grande,
/// arriba de todo y DEBAJO de la flecha (reserva el alto de la barra y de la
/// status bar). Sin fondo propio: el degradé del tema corre por detrás, igual
/// que en el resto de la app, así no aparece una franja lisa arriba.
class _ExerciseHeader extends StatelessWidget {
  const _ExerciseHeader({required this.badgeText, required this.titleText});

  final String badgeText;
  final String titleText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        TreinoTopBarMetrics.reservedHeightOf(context) + 12,
        20,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Breadcrumb(text: badgeText),
          const SizedBox(height: 8),
          _ExerciseTitle(text: titleText),
        ],
      ),
    );
  }
}

/// Relación de aspecto de la tarjeta mientras no se conoce la del video
/// (poster, carga, falla) y de la foto de los ejercicios sin video.
const double _kMediaAspectRatio = 16 / 9;

/// Tope de alto de la tarjeta de video, como fracción del alto de pantalla:
/// un video vertical a todo el ancho ocuparía más de una pantalla entera.
const double _kVideoMaxHeightFraction = 0.6;

/// Marco común de la media: esquinas redondeadas, fondo y borde de tarjeta
/// como TÉCNICA. El borde va como `foregroundDecoration` (1 px sobre el
/// canto), así la foto/video llega hasta la curva sin un hueco.
class _MediaFrame extends StatelessWidget {
  const _MediaFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radius = BorderRadius.circular(AppRadius.lg);
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: palette.border),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(color: palette.bgCard, child: child),
      ),
    );
  }
}

/// Foto del ejercicio cuando no hay video reproducible: la misma cascada de
/// siempre (frame del video #565 → assets por id → grupo muscular) y, si ni
/// el grupo tiene asset, el placeholder.
class _ExercisePhotoCard extends StatelessWidget {
  const _ExercisePhotoCard({
    required this.exerciseId,
    required this.muscleGroup,
    this.thumbnailUrl,
  });

  final String exerciseId;
  final String muscleGroup;
  final String? thumbnailUrl;

  @override
  Widget build(BuildContext context) {
    return _MediaFrame(
      child: AspectRatio(
        aspectRatio: _kMediaAspectRatio,
        child: ExerciseAssetImage(
          exerciseId: exerciseId,
          muscleGroup: muscleGroup,
          thumbnailUrl: thumbnailUrl,
          fallback: const _MediaFallback(),
        ),
      ),
    );
  }
}

/// Placeholder de la media cuando ni el grupo muscular tiene asset.
class _MediaFallback extends StatelessWidget {
  const _MediaFallback();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DecoratedBox(
      key: const Key('exercise-media-fallback'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent.withValues(alpha: 0.35),
            palette.bgCard,
          ],
        ),
      ),
    );
  }
}

/// Video del ejercicio en su tarjeta, debajo de TÉCNICA (pedido en device
/// 2026-10-21). La foto (un frame de este mismo video, #565) hace de poster.
/// La reproducción NUNCA arranca sola: sólo con el toque del usuario.
///
///   * Firebase Storage → el toque monta el player nativo y arranca cuando
///     está listo. Mientras inicializa, el poster queda bajo el tratamiento
///     de carga del #545 (shimmer + spinner de acento). Ya inicializado, la
///     tarjeta toma la relación de aspecto REAL del video (con tope de alto
///     para los verticales) y el video se ve entero, sin recorte. Tocar
///     pausa/reanuda. La barra de progreso va DEBAJO del video, no encima.
///   * YouTube → el toque abre la página del video en el navegador in-app:
///     YouTube rechaza los embeds inline en WKWebView de iOS (ver
///     exercise_video_player.dart).
///   * Falla de init → vuelve el poster con un aviso; tocar reintenta.
///
/// Mientras reproduce no hay nada encima del video: ni status bar, ni
/// flecha, ni degradés, ni el botón de play (se desvanece).
class _ExerciseVideoCard extends StatefulWidget {
  const _ExerciseVideoCard({
    required this.exerciseId,
    required this.muscleGroup,
    required this.videoUrl,
    this.thumbnailUrl,
  });

  final String exerciseId;
  final String muscleGroup;

  /// Poster del video — la foto real del ejercicio (frame de su video, #565).
  /// Ausente/falla → cascada de assets, igual que [_ExercisePhotoCard].
  final String? thumbnailUrl;

  /// Already verified playable by the caller (Firebase Storage or YouTube) —
  /// anything else renders [_ExercisePhotoCard] instead.
  final String videoUrl;

  @override
  State<_ExerciseVideoCard> createState() => _ExerciseVideoCardState();
}

class _ExerciseVideoCardState extends State<_ExerciseVideoCard> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _initFailed = false;

  /// Last observed isPlaying. The controller notifies on every position tick,
  /// so [_onPlayerTick] only setStates when this flips (cero rebuilds
  /// innecesarios) — e.g. when the clip reaches its end and the play button
  /// must come back without a tap.
  bool _wasPlaying = false;

  bool get _isPlaying => _controller?.value.isPlaying ?? false;

  @override
  void didUpdateWidget(covariant _ExerciseVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeController();
      _initializing = false;
      _initFailed = false;
      _wasPlaying = false;
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  /// removeListener BEFORE dispose: the controller's own dispose only clears
  /// listeners at the very end, after async platform round-trips — an
  /// in-flight position tick can still notify in that gap and would reach a
  /// setState on an unmounted State (e.g. play → back immediately).
  void _disposeController() {
    _controller?.removeListener(_onPlayerTick);
    _controller?.dispose();
    _controller = null;
  }

  void _onPlayerTick() {
    if (!mounted) return;
    final playing = _controller?.value.isPlaying ?? false;
    if (playing == _wasPlaying) return;
    setState(() => _wasPlaying = playing);
  }

  /// Lazy init on the user's tap — the poster costs zero bandwidth until the
  /// athlete actually wants the video.
  Future<void> _startPlayback() async {
    setState(() {
      _initializing = true;
      _initFailed = false;
    });
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initFailed = true;
      });
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    c.addListener(_onPlayerTick);
    setState(() {
      _controller = c;
      _initializing = false;
    });
    // The tap that got us here IS the play intent (tap-to-play, not
    // autoplay). Outside the try: a play() failure must never dispose a
    // controller the build is already rendering.
    await c.play();
  }

  void _onTap() {
    final youtubeId = parseYoutubeVideoId(widget.videoUrl);
    if (youtubeId != null) {
      openYoutubeWatchPage(context, youtubeId);
      return;
    }
    final c = _controller;
    if (c != null) {
      setState(() => c.value.isPlaying ? c.pause() : c.play());
      return;
    }
    if (!_initializing) _startPlayback();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final c = _controller;
    final videoRatio = c?.value.aspectRatio ?? 0;
    final ratio = c != null && videoRatio > 0 ? videoRatio : _kMediaAspectRatio;
    final maxHeight =
        MediaQuery.sizeOf(context).height * _kVideoMaxHeightFraction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Align afloja el ancho: un video vertical queda centrado y más
        // angosto en vez de estirarse a todo el ancho.
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: AspectRatio(
              key: const Key('exercise-video-card'),
              aspectRatio: ratio,
              child: _MediaFrame(
                child: Semantics(
                  button: true,
                  label: 'Video del ejercicio',
                  hint: _isPlaying ? 'Pausar video' : 'Reproducir video',
                  child: GestureDetector(
                    onTap: _onTap,
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Media: el poster hasta que el player está listo
                        // (también de fondo mientras inicializa, así la carga
                        // nunca es un agujero negro); después, el video entero
                        // en una caja de su misma relación de aspecto.
                        if (c == null)
                          ExerciseAssetImage(
                            exerciseId: widget.exerciseId,
                            muscleGroup: widget.muscleGroup,
                            thumbnailUrl: widget.thumbnailUrl,
                            fallback: const _MediaFallback(),
                          )
                        else
                          VideoPlayer(c),
                        // #545: shimmer + spinner de acento sobre el poster —
                        // inconfundiblemente "cargando", nunca un frame muerto.
                        if (_initializing)
                          TreinoShimmer(
                            child: ColoredBox(
                              color: palette.scrimDark.withValues(alpha: 0.55),
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.6,
                                    color: palette.accent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        AnimatedOpacity(
                          opacity: !_isPlaying && !_initializing ? 1 : 0,
                          duration: AppMotion.resolve(context, AppMotion.fast),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const VideoPlayOverlay(),
                                if (_initFailed) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: palette.scrimDark
                                          .withValues(alpha: 0.55),
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.full),
                                    ),
                                    child: Text(
                                      'No pudimos reproducir el video.',
                                      style: GoogleFonts.barlow(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                        // intentional: texto sobre scrim de
                                        // media, oscuro en las dos paletas.
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (c != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              padding: EdgeInsets.zero,
              colors: VideoProgressColors(
                playedColor: palette.accent,
                bufferedColor: palette.accent.withValues(alpha: 0.35),
                backgroundColor: palette.border,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        text,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 1.4,
          color: palette.accent,
        ),
      ),
    );
  }
}

class _ExerciseTitle extends StatelessWidget {
  const _ExerciseTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 36,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: tiles.map<Widget>((t) => Expanded(child: t)).toList(),
      ),
    );
  }
}

class _TecnicaCard extends StatelessWidget {
  const _TecnicaCard({required this.instructions});

  final List<String> instructions;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < instructions.length; i++) ...[
            TechniqueInstructionItem(index: i + 1, text: instructions[i]),
            if (i < instructions.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        letterSpacing: 1.4,
        color: palette.textPrimary,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      message,
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        color: palette.textMuted,
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      'Aún no entrenaste este ejercicio',
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        color: palette.textMuted,
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Reintentar',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: palette.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseLoadingSkeleton extends StatelessWidget {
  const _ExerciseLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoShimmer(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mismo encabezado que el contenido: arranca bajo la barra.
            SizedBox(
                height: TreinoTopBarMetrics.reservedHeightOf(context) + 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 22, width: 160, color: palette.bgCard),
                  const SizedBox(height: 8),
                  Container(height: 36, width: 240, color: palette.bgCard),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: palette.bgCard,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(height: 12, width: 100, color: palette.bgCard),
                  const SizedBox(height: 12),
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: palette.bgCard,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
