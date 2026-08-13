import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/exercise_asset_image.dart';
import '../../../core/widgets/firebase_storage_video_player.dart'
    show VideoPlayOverlay;
import '../../../core/widgets/motion/treino_shimmer.dart';
import '../../../core/widgets/treino_icon.dart';
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

    // Stack so the hero photo extends edge-to-edge from the top of the safe
    // area while the back button floats over it. Non-data states still render
    // the back button on top so the user can always escape.
    return Stack(
      children: [
        Positioned.fill(
          child: exerciseAsync.when(
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
        ),
        Positioned(
          top: 0,
          left: 0,
          child: _BackBar(fallbackRoute: backFallbackRoute),
        ),
      ],
    );
  }
}

/// Persistent top-left back button. Always visible across loading / error /
/// not-found / data states so the user can never dead-end on a deep-linked
/// screen (REQ-RDT-020 strengthened). Floats over the hero photo with a
/// translucent chip so it stays legible on bright images.
class _BackBar extends StatelessWidget {
  const _BackBar({required this.fallbackRoute});

  /// Where to land when nothing can be popped — see
  /// [ExerciseDetailScreen.backFallbackRoute].
  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8),
      child: Material(
        color: palette.scrimDark.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: l10n.commonBack,
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(fallbackRoute),
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
    // in `assets/exercises/`, so the regular hero falls back to the green
    // gradient — which reads as broken for what's actually a personalized
    // plan. Swap to a compact header that skips the photo slot entirely.
    final isCustom = exercise.category.toLowerCase() == 'custom';

    // Video-first (pedido 2026-07-28): a playable URL puts the video in the
    // hero itself — photo as poster, tap to play. Absent/unplayable URLs keep
    // the photo hero, never an empty slot. Custom exercises keep the compact
    // header (no photo to posterize) and get the video as the first body
    // section instead, so trainers keep seeing their upload slot in every
    // state (including the "coming soon" placeholder).
    final videoUrl = exercise.videoUrl?.trim() ?? '';
    final heroVideoUrl = !isCustom &&
            (isFirebaseStorageVideo(videoUrl) ||
                parseYoutubeVideoId(videoUrl) != null)
        ? videoUrl
        : null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: isCustom
              ? _CompactHeader(
                  badgeText: badgeText,
                  titleText: exercise.name.toUpperCase(),
                )
              : heroVideoUrl != null
                  ? _VideoHeroStrip(
                      exerciseId: exercise.id,
                      muscleGroup: exercise.muscleGroup,
                      thumbnailUrl: exercise.thumbnailUrl,
                      badgeText: badgeText,
                      titleText: exercise.name.toUpperCase(),
                      videoUrl: heroVideoUrl,
                    )
                  : _HeroStrip(
                      exerciseId: exercise.id,
                      muscleGroup: exercise.muscleGroup,
                      thumbnailUrl: exercise.thumbnailUrl,
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
              if (isCustom) ...[
                const _SectionHeader(text: 'VIDEO'),
                const SizedBox(height: 12),
                // ExerciseVideoPlayer handles all states (null/invalid/valid)
                // internally — the slot always renders so trainers can see
                // there's a video surface even before URLs are populated.
                ExerciseVideoPlayer(videoUrl: exercise.videoUrl),
                const SizedBox(height: 20),
              ],
              const _SectionHeader(text: 'TÉCNICA'),
              const SizedBox(height: 12),
              if (instructions == null || instructions.isEmpty)
                const _EmptyState(
                  message: 'No hay instrucciones de técnica todavía',
                )
              else
                _TecnicaCard(instructions: instructions),
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
              ),
              onSelect: (p) => setState(() => _period = p),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatsCard(
          tiles: [
            StatTile(label: '1RM', value: _oneRepMaxValue(progression)),
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

/// Formats a kg / kg·reps value the same way the chart and the records list
/// do: whole numbers drop the decimals, fractional values keep one.
String _formatStatValue(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// 1RM tile: best Epley estimate within the active period, rounded to 0.5kg
/// at display only (AD2 — same convention as chart/records).
String? _oneRepMaxValue(ExerciseProgression? progression) {
  final series = progression?.oneRepMaxSeries;
  if (series == null || series.isEmpty) return null;
  var best = series.first.value;
  for (final point in series.skip(1)) {
    if (point.value > best) best = point.value;
  }
  return '${_formatStatValue(roundToNearestHalfKg(best))} kg';
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
            borderRadius: BorderRadius.circular(16),
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
              volumeUnit: 'kg·reps',
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
                volumeUnit: 'kg·reps',
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
        borderRadius: BorderRadius.circular(16),
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
        : '${_formatStatValue(entry.bestWeightKg)} kg × ${entry.bestSetReps}';

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
                '${_formatStatValue(entry.sessionVolume)} kg·reps',
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

/// Photo-less header for trainer-defined exercises. Sits flush at the top
/// with bg-color so the floating back button stays legible, then shows just
/// the breadcrumb badge and the exercise title. No image, no gradient,
/// no green fallback.
class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.badgeText, required this.titleText});

  final String badgeText;
  final String titleText;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      color: palette.bg,
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Breadcrumb(text: badgeText),
          const SizedBox(height: 10),
          _ExerciseTitle(text: titleText),
        ],
      ),
    );
  }
}

class _HeroStrip extends StatelessWidget {
  const _HeroStrip({
    required this.exerciseId,
    required this.muscleGroup,
    required this.badgeText,
    required this.titleText,
    this.thumbnailUrl,
  });

  final String exerciseId;
  final String muscleGroup;

  /// Foto real del ejercicio (frame de su video, #565). Presente → el hero
  /// muestra el ejercicio de verdad; ausente/falla → cascada de assets como
  /// siempre (pedido de producto 2026-07-24).
  final String? thumbnailUrl;
  final String badgeText;
  final String titleText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kHeroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Shared cascade (see ExerciseAssetImage): id variants under
          // `assets/exercises/` and `assets/muscles/`, then the muscle-group
          // bucket. In practice the muscle bucket is what paints — the bundled
          // PNGs predate the Drive catalogue (see
          // docs/video-catalog-audit/NUEVO-catalogo.json), so id matches are
          // the exception. Gradient is the last resort when even the muscle
          // is unknown.
          ExerciseAssetImage(
            exerciseId: exerciseId,
            muscleGroup: muscleGroup,
            thumbnailUrl: thumbnailUrl,
            fallback: const _HeroGradientFallback(),
          ),
          const _HeroTopScrim(),
          const _HeroBottomScrim(),
          _HeroTitleOverlay(badgeText: badgeText, titleText: titleText),
        ],
      ),
    );
  }
}

/// Fixed hero envelope shared by [_HeroStrip] and [_VideoHeroStrip] — every
/// video state (poster / loading / playing) keeps this exact height so the
/// layout never jumps.
const double _kHeroHeight = 320;

/// Last-resort hero paint when even the muscle group has no bundled asset.
class _HeroGradientFallback extends StatelessWidget {
  const _HeroGradientFallback();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent.withValues(alpha: 0.85),
            palette.bg,
          ],
        ),
      ),
    );
  }
}

/// Top scrim — keeps the floating back button legible on bright photos.
class _HeroTopScrim extends StatelessWidget {
  const _HeroTopScrim();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.scrimDark.withValues(alpha: 0.45),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom scrim — makes the badge + title overlay readable and softens the
/// seam between the photo/video and the body content.
class _HeroBottomScrim extends StatelessWidget {
  const _HeroBottomScrim();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              palette.bg.withValues(alpha: 0.95),
            ],
          ),
        ),
      ),
    );
  }
}

/// Badge + exercise title overlaid at the bottom-left of the hero.
class _HeroTitleOverlay extends StatelessWidget {
  const _HeroTitleOverlay({required this.badgeText, required this.titleText});

  final String badgeText;
  final String titleText;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 16,
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

/// Hero for catalogue exercises WITH a playable video (pedido 2026-07-28:
/// "el video arriba del todo, donde hoy está la foto"). Same [_kHeroHeight]
/// envelope as [_HeroStrip] in every state, with the photo (a frame of this
/// very video, #565) as poster. Playback NEVER starts on its own — only from
/// the user's tap.
///
///   * Firebase Storage URL → tap mounts the native inline player filling
///     the strip (cover, matching the poster's crop) and starts playback
///     once ready. While initialising the poster stays under the #545
///     loading treatment (shimmer sweep + accent spinner) so "loading" is
///     unmistakable. Tap toggles play/pause; scrims + title fade out during
///     playback and return on pause (same chrome-on-pause pattern as
///     [FirebaseStorageVideoPlayer]). Progress bar allows scrubbing.
///   * YouTube URL → tap opens the watch page in the in-app browser sheet —
///     inline embeds are rejected by YouTube on iOS WKWebView (see
///     exercise_video_player.dart).
///   * Init failure → poster returns with a muted caption; tapping retries.
class _VideoHeroStrip extends StatefulWidget {
  const _VideoHeroStrip({
    required this.exerciseId,
    required this.muscleGroup,
    required this.badgeText,
    required this.titleText,
    required this.videoUrl,
    this.thumbnailUrl,
  });

  final String exerciseId;
  final String muscleGroup;

  /// Poster del video — la foto real del ejercicio (frame de su video, #565).
  /// Ausente/falla → cascada de assets, igual que [_HeroStrip].
  final String? thumbnailUrl;
  final String badgeText;
  final String titleText;

  /// Already verified playable by the caller (Firebase Storage or YouTube) —
  /// anything else renders [_HeroStrip] instead.
  final String videoUrl;

  @override
  State<_VideoHeroStrip> createState() => _VideoHeroStripState();
}

class _VideoHeroStripState extends State<_VideoHeroStrip> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _initFailed = false;

  /// Last observed isPlaying. The controller notifies on every position tick,
  /// so [_onPlayerTick] only setStates when this flips (cero rebuilds
  /// innecesarios) — e.g. when the clip reaches its end and the chrome must
  /// come back without a tap.
  bool _wasPlaying = false;

  bool get _isPlaying => _controller?.value.isPlaying ?? false;

  @override
  void didUpdateWidget(covariant _VideoHeroStrip oldWidget) {
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
    final showChrome = !_isPlaying;

    return SizedBox(
      height: _kHeroHeight,
      width: double.infinity,
      child: Semantics(
        // hint (no label): badge + title descendants already fuse as the
        // node's label — an explicit label would duplicate them in VoiceOver.
        button: true,
        hint: _isPlaying ? 'Pausar video' : 'Reproducir video',
        child: GestureDetector(
          onTap: _onTap,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media layer: the poster until the player is ready (also the
              // backdrop while it initialises — loading never reads as a
              // black hole), then the video filling the strip with the same
              // cover crop as the poster frame.
              if (c == null)
                ExerciseAssetImage(
                  exerciseId: widget.exerciseId,
                  muscleGroup: widget.muscleGroup,
                  thumbnailUrl: widget.thumbnailUrl,
                  fallback: const _HeroGradientFallback(),
                )
              else
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                ),
              // Chrome (scrims + badge + title): visible on poster/pause,
              // fades out while playing so nothing covers the technique.
              AnimatedOpacity(
                opacity: showChrome ? 1 : 0,
                duration: AppMotion.fast,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const _HeroTopScrim(),
                    const _HeroBottomScrim(),
                    _HeroTitleOverlay(
                      badgeText: widget.badgeText,
                      titleText: widget.titleText,
                    ),
                  ],
                ),
              ),
              // #545 loading treatment over the poster: shimmer sweep +
              // accent spinner — unmistakably "loading", never a dead frame.
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
                opacity: showChrome && !_initializing ? 1 : 0,
                duration: AppMotion.fast,
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
                            color: palette.scrimDark.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            'No pudimos reproducir el video.',
                            style: GoogleFonts.barlow(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (c != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    c,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: palette.accent,
                      bufferedColor: Colors.white
                          .withValues(alpha: 0.35), // intentional: media
                      backgroundColor: Colors.white
                          .withValues(alpha: 0.15), // intentional: media
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
        borderRadius: BorderRadius.circular(9999),
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
        borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
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
            Container(height: 320, color: palette.espresso),
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
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(height: 12, width: 100, color: palette.bgCard),
                  const SizedBox(height: 12),
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: palette.bgCard,
                      borderRadius: BorderRadius.circular(20),
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
