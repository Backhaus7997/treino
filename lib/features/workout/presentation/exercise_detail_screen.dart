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

/// ExerciseDetailScreen — ConsumerWidget that observes exerciseByIdProvider.
/// No Scaffold, AppBackground, or SafeArea — those are provided by
/// _ShellScaffold in router.dart (REQ-RDT-019).
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(exerciseId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BackBar(),
        Expanded(
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
      ],
    );
  }
}

/// Persistent top-left back button. Always visible across loading / error /
/// not-found / data states so the user can never dead-end on a deep-linked
/// screen (REQ-RDT-020 strengthened).
class _BackBar extends StatelessWidget {
  const _BackBar();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _HeroPlaceholder()),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 18),
              _Breadcrumb(
                text:
                    '${exercise.muscleGroup.toUpperCase()} · ${exercise.category.toUpperCase()}',
              ),
              const SizedBox(height: 8),
              _ExerciseTitle(text: exercise.name.toUpperCase()),
              const SizedBox(height: 14),
              const _StatRow(
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
                ...instructions.asMap().entries.expand(
                      (e) => [
                        TechniqueInstructionItem(
                            index: e.key + 1, text: e.value),
                        const SizedBox(height: 12),
                      ],
                    ),
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

class _HeroPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 180,
      decoration: BoxDecoration(color: palette.espresso),
      alignment: Alignment.center,
      child: Icon(
        TreinoIcon.tabWorkout,
        size: 56,
        color: palette.textMuted.withValues(alpha: 0.5),
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
    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 1.4,
        color: palette.textMuted,
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
        fontSize: 32,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: tiles.map<Widget>((t) => Expanded(child: t)).toList(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 180, color: palette.espresso),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 12, width: 120, color: palette.bgCard),
              const SizedBox(height: 12),
              Container(height: 32, width: 200, color: palette.bgCard),
              const SizedBox(height: 14),
              Row(
                children: List.generate(
                  3,
                  (_) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(height: 40, color: palette.bgCard),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
