import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/exercise_providers.dart';
import '../domain/exercise.dart';
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
};

const _categoryEs = <String, String>{
  'compound': 'COMPUESTO',
  'isolation': 'AISLAMIENTO',
};

String _muscleEs(String raw) =>
    _muscleGroupEs[raw.toLowerCase()] ?? raw.toUpperCase();

String _categoryEsOf(String raw) =>
    _categoryEs[raw.toLowerCase()] ?? raw.toUpperCase();

/// ExerciseDetailScreen — ConsumerWidget that observes exerciseByIdProvider.
/// No Scaffold, AppBackground, or SafeArea — those are provided by
/// _ShellScaffold in router.dart (REQ-RDT-019).
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(exerciseId));

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
              onRetry: () => ref.invalidate(exerciseByIdProvider(exerciseId)),
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
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8),
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
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
    final hasVideo = exercise.videoUrl != null;
    final badgeText =
        '${_muscleEs(exercise.muscleGroup)} · ${_categoryEsOf(exercise.category)}';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HeroStrip(
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
              if (hasVideo) ...[
                const SizedBox(height: 20),
                const _VideoComingSoon(),
              ],
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

class _HeroStrip extends StatelessWidget {
  const _HeroStrip({
    required this.muscleGroup,
    required this.badgeText,
    required this.titleText,
  });

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
          // Convention: assets/muscles/{muscleGroup}.png. Missing asset →
          // errorBuilder paints the gradient so the screen never breaks.
          Image.asset(
            'assets/muscles/${muscleGroup.toLowerCase()}.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => gradient,
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

class _VideoComingSoon extends StatelessWidget {
  const _VideoComingSoon();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      'Video próximamente',
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
