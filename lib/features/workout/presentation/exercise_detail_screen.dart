import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/exercise_providers.dart';
import '../domain/exercise.dart';
import 'widgets/exercise_video_player.dart';
import 'widgets/stat_tile.dart';
import 'widgets/technique_instruction_item.dart';

// Display-name maps. Data from Firestore is stored in English (e.g. 'chest',
// 'compound') so the UI translates to Spanish at render time. Unknown values
// fall back to the original string upper-cased so we never crash.
const _muscleGroupEs = <String, String>{
  'chest': 'PECHO',
  'back': 'ESPALDA',
  'shoulders': 'HOMBROS',
  'quads': 'CUÁDRICEPS',
  'hamstrings': 'ISQUIOS',
  'glutes': 'GLÚTEOS',
  'calves': 'PANTORRILLAS',
  'biceps': 'BÍCEPS',
  'triceps': 'TRÍCEPS',
  'core': 'CORE',
  'cardio': 'CARDIO',
  'fullbody': 'CUERPO COMPLETO',
};

const _categoryEs = <String, String>{
  'compound': 'COMPUESTO',
  'isolation': 'AISLAMIENTO',
};

String _muscleEs(String raw) =>
    _muscleGroupEs[raw.toLowerCase()] ?? raw.toUpperCase();

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
  });

  final String exerciseId;

  /// Trainer uid that owns the routine the slot belongs to. When non-null
  /// and the public catalogue lookup misses, the provider tries
  /// `users/{ownerId}/customExercises/{exerciseId}`.
  final String? ownerId;

  /// Display name from the slot. Used by [slotExerciseProvider]'s tier-2
  /// fallback (name / alias match) when the slot's `exerciseId` drifted
  /// from the current catalogue. Optional — when omitted, only strict ID
  /// + custom-exercise fallbacks run.
  final String? exerciseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseAsync = ref.watch(
      slotExerciseProvider((
        exerciseId: exerciseId,
        ownerId: ownerId,
        exerciseName: exerciseName,
      )),
    );

    // Stack so the hero photo extends edge-to-edge from the top of the safe
    // area while the back button floats over it. Non-data states still render
    // the back button on top so the user can always escape.
    return Stack(
      children: [
        Positioned.fill(
          child: exerciseAsync.when(
            data: (exercise) => exercise == null
                ? const _NotFoundState(label: 'Ejercicio no encontrado')
                : _ExerciseDetailContent(exercise: exercise),
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
        const Positioned(top: 0, left: 0, child: _BackBar()),
      ],
    );
  }
}

/// Persistent top-left back button. Always visible across loading / error /
/// not-found / data states so the user can never dead-end on a deep-linked
/// screen (REQ-RDT-020 strengthened). Floats over the hero photo with a
/// translucent chip so it stays legible on bright images.
class _BackBar extends StatelessWidget {
  const _BackBar();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8),
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: l10n.commonBack,
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/workout'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Happy-path content
// ---------------------------------------------------------------------------

class _ExerciseDetailContent extends StatelessWidget {
  const _ExerciseDetailContent({required this.exercise});

  final Exercise exercise;

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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: isCustom
              ? _CompactHeader(
                  badgeText: badgeText,
                  titleText: exercise.name.toUpperCase(),
                )
              : _HeroStrip(
                  exerciseId: exercise.id,
                  muscleGroup: exercise.muscleGroup,
                  badgeText: badgeText,
                  titleText: exercise.name.toUpperCase(),
                ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 20),
              const _StatsCard(
                tiles: [
                  StatTile(label: '1RM', value: null),
                  StatTile(label: 'SESIONES', value: null),
                  StatTile(label: 'PROGRESO', value: null),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionHeader(text: 'VIDEO'),
              const SizedBox(height: 12),
              // ExerciseVideoPlayer handles all states (null/invalid/valid)
              // internally — we always render the slot so trainers can see
              // there's a video surface even before URLs are populated.
              ExerciseVideoPlayer(videoUrl: exercise.videoUrl),
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
              const _SectionHeader(text: 'HISTORIAL'),
              const SizedBox(height: 12),
              const _HistoryEmptyState(),
              const SizedBox(height: 20),
            ]),
          ),
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
  });

  final String exerciseId;
  final String muscleGroup;
  final String badgeText;
  final String titleText;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final gradient = Container(
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

    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Convention: assets/exercises/{exerciseId}.png. Cascade for the 25
          // hand-curated assets vs the 415-exercise catalogue + the 10
          // muscle-group fallback assets:
          //   1. strict exercise id (e.g. `bench-press-barbell`)
          //   2. strip suffix       (`bench-press-barbell` → `bench-press`)
          //   3. strip prefix       (`barbell-back-squat`  → `back-squat`)
          //   4. muscle group       (`assets/muscles/{muscleGroup}.png`)
          //   5. gradient (last resort, paints when even the muscle is unknown)
          _ExerciseHeroAsset(
            exerciseId: exerciseId,
            muscleGroup: muscleGroup,
            fallback: gradient,
          ),
          // Top scrim — keeps the floating back button legible on bright photos.
          Positioned(
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
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Bottom scrim — makes the badge + title overlay readable and
          // softens the seam between the photo and the body content.
          Positioned(
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
          ),
          // Badge + exercise title overlaid at the bottom-left of the hero.
          Positioned(
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
          ),
        ],
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
    return SingleChildScrollView(
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
    );
  }
}

/// Cascading hero image lookup. For each id variant (strict, strip-suffix,
/// strip-prefix), tries BOTH `assets/exercises/` and `assets/muscles/`
/// before falling back to the muscle-group bucket. This lets the
/// `assets/muscles/` folder host movement-pattern assets (e.g.
/// `squat.png` for any squat variant) alongside the strict muscle-group
/// silhouettes (e.g. `quads.png`).
///
/// Order for `exerciseId: 'squat-barbell'`, `muscleGroup: 'quads'`:
///   1. `assets/exercises/squat-barbell.png`
///   2. `assets/exercises/squat.png`                 (strip suffix)
///   3. `assets/exercises/barbell.png`               (strip prefix)
///   4. `assets/muscles/squat-barbell.png`
///   5. `assets/muscles/squat.png`                   (strip suffix) ← hit
///   6. `assets/muscles/barbell.png`                 (strip prefix)
///   7. `assets/muscles/quads.png`                   (muscle bucket)
///   8. [fallback]
///
/// The chain is built once into a list of candidate paths so the rendered
/// widget tree is flat (one `Image.asset` with a nested `errorBuilder`
/// chain), avoiding rebuilds when the lookup walks down the list.
class _ExerciseHeroAsset extends StatelessWidget {
  const _ExerciseHeroAsset({
    required this.exerciseId,
    required this.muscleGroup,
    required this.fallback,
  });

  final String exerciseId;
  final String muscleGroup;
  final Widget fallback;

  /// Generates the id-derived slugs to probe in priority order:
  /// strict, strip-suffix, strip-prefix. Skips duplicates.
  List<String> _idSlugs() {
    final out = <String>[exerciseId];
    final last = exerciseId.lastIndexOf('-');
    if (last > 0) out.add(exerciseId.substring(0, last));
    final first = exerciseId.indexOf('-');
    if (first > 0 && first != last) out.add(exerciseId.substring(first + 1));
    return out;
  }

  /// All candidate asset paths in priority order — see class docs.
  List<String> _candidates() {
    final slugs = _idSlugs();
    final out = <String>[
      for (final s in slugs) 'assets/exercises/$s.png',
      for (final s in slugs) 'assets/muscles/$s.png',
    ];
    if (muscleGroup.isNotEmpty) {
      out.add('assets/muscles/$muscleGroup.png');
    }
    return out;
  }

  Widget _tryAt(int index, List<String> paths) {
    if (index >= paths.length) return fallback;
    return Image.asset(
      paths[index],
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _tryAt(index + 1, paths),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _tryAt(0, _candidates());
  }
}
