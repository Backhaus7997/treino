import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/routine_providers.dart';
import '../domain/routine.dart';
import '../domain/routine_day.dart';
import '../domain/routine_slot.dart';
import 'widgets/exercise_slot_row.dart';
import 'widgets/stat_tile.dart';

/// RoutineDetailScreen — ConsumerStatefulWidget that observes routineByIdProvider.
/// selectedDayIndex is local state (ADR-RD-3).
/// No Scaffold, AppBackground, or SafeArea — provided by _ShellScaffold (REQ-RDT-011).
class RoutineDetailScreen extends ConsumerStatefulWidget {
  const RoutineDetailScreen({super.key, required this.routineId});

  final String routineId;

  @override
  ConsumerState<RoutineDetailScreen> createState() =>
      _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen> {
  int selectedDayIndex = 0;

  @override
  Widget build(BuildContext context) {
    final routineAsync = ref.watch(routineByIdProvider(widget.routineId));

    // Stack so the hero image can extend edge-to-edge from the top of the
    // safe area while the back button floats over it. Non-data states still
    // render the back button on top so the user can always escape.
    return Stack(
      children: [
        Positioned.fill(
          child: routineAsync.when(
            data: (routine) {
              if (routine == null) {
                return const _NotFoundState(label: 'Rutina no encontrada');
              }
              // `clamp(0, length - 1)` throws when length == 0 — empty-check
              // BEFORE clamping.
              if (routine.days.isEmpty) {
                return const _EmptyState(
                    message: 'Esta rutina no tiene días configurados.');
              }
              final dayIndex =
                  selectedDayIndex.clamp(0, routine.days.length - 1);
              final day = routine.days[dayIndex];
              return _RoutineDetailContent(
                routine: routine,
                day: day,
                selectedDayIndex: dayIndex,
                onSelectDay: (i) => setState(() => selectedDayIndex = i),
                onSlotTap: (slot) =>
                    context.push('/workout/exercise/${slot.exerciseId}'),
              );
            },
            loading: () => const _RoutineLoadingSkeleton(),
            error: (_, __) => _ErrorState(
              message: 'No pudimos cargar la rutina.',
              onRetry: () =>
                  ref.invalidate(routineByIdProvider(widget.routineId)),
            ),
          ),
        ),
        const Positioned(top: 0, left: 0, child: _BackBar()),
      ],
    );
  }
}

/// Persistent top-left back button. Always visible so the user can never
/// dead-end on a deep-linked screen — even in loading, error, or not-found
/// states (REQ-RDT-016 strengthened). Now floats over the hero image with a
/// translucent chip so it stays legible on bright photos.
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

class _RoutineDetailContent extends StatelessWidget {
  const _RoutineDetailContent({
    required this.routine,
    required this.day,
    required this.selectedDayIndex,
    required this.onSelectDay,
    required this.onSlotTap,
  });

  final Routine routine;
  final RoutineDay day;
  final int selectedDayIndex;
  final ValueChanged<int> onSelectDay;
  final ValueChanged<RoutineSlot> onSlotTap;

  int _totalSets(RoutineDay d) =>
      d.slots.fold(0, (sum, s) => sum + s.targetSets);

  String? _minutesValue(RoutineDay d) =>
      d.estimatedMinutes != null ? '${d.estimatedMinutes}' : null;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HeroStrip(
            routineId: routine.id,
            badgeText: '${routine.split.toUpperCase()} · DÍA ${day.dayNumber}',
            titleText: day.name.toUpperCase(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 20),
              _StatRow(
                tiles: [
                  StatTile(
                    label: 'EJERCICIOS',
                    value: '${day.slots.length}',
                  ),
                  StatTile(
                    label: 'SETS',
                    value: '${_totalSets(day)}',
                  ),
                  StatTile(
                    label: 'MINUTOS',
                    value: _minutesValue(day),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (routine.days.length > 1) ...[
                _DaySelector(
                  days: routine.days,
                  selectedIndex: selectedDayIndex,
                  onSelect: onSelectDay,
                ),
                const SizedBox(height: 20),
              ],
              const _SectionHeader(text: 'EJERCICIOS'),
              const SizedBox(height: 12),
              if (day.slots.isEmpty)
                const _EmptyState(message: 'No hay ejercicios en este día')
              else
                ...day.slots.asMap().entries.expand(
                      (entry) => [
                        ExerciseSlotRow(
                          slot: entry.value,
                          index: entry.key + 1,
                          onTap: () => onSlotTap(entry.value),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
              const SizedBox(height: 20),
              const _DisabledCTABar(),
              const SizedBox(height: 18),
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
    required this.routineId,
    required this.badgeText,
    required this.titleText,
  });

  final String routineId;
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
          // Convention: assets/routines/{routine.id}.png. Missing asset →
          // errorBuilder paints the gradient so the screen never breaks.
          Image.asset(
            'assets/routines/$routineId.png',
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
          // Badge + day title overlaid at the bottom-left of the hero.
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DayChipBadge(text: badgeText),
                const SizedBox(height: 8),
                _DayTitle(text: titleText),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayChipBadge extends StatelessWidget {
  const _DayChipBadge({required this.text});

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

class _DayTitle extends StatelessWidget {
  const _DayTitle({required this.text});

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

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<RoutineDay> days;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(days.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                'DÍA ${days[i].dayNumber}',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: i == selectedIndex ? palette.bg : palette.textMuted,
                ),
              ),
              selected: i == selectedIndex,
              onSelected: (_) => onSelect(i),
              selectedColor: palette.accent,
              backgroundColor: palette.bgCard,
              side: BorderSide(color: palette.border),
              showCheckmark: false,
            ),
          );
        }),
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

class _DisabledCTABar extends StatelessWidget {
  const _DisabledCTABar();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: 0.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.border),
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: Text(
                  'EDITAR',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 1.0,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  disabledBackgroundColor:
                      palette.accent.withValues(alpha: 1.0),
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: Text(
                  'EMPEZAR',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 1.0,
                    color: palette.bg,
                  ),
                ),
              ),
            ),
          ],
        ),
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
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: palette.textPrimary,
        ),
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

class _RoutineLoadingSkeleton extends StatelessWidget {
  const _RoutineLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 320,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.accent.withValues(alpha: 0.3),
                  palette.bg,
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 12, width: 100, color: palette.bgCard),
                const SizedBox(height: 8),
                Container(height: 36, width: 180, color: palette.bgCard),
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
                const SizedBox(height: 18),
                ...List.generate(
                  4,
                  (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      height: 76,
                      decoration: BoxDecoration(
                        color: palette.bgCard,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
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
