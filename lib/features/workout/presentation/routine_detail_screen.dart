import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
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

    return routineAsync.when(
      data: (routine) {
        if (routine == null) {
          return const _NotFoundState(label: 'Rutina no encontrada');
        }
        final dayIndex = selectedDayIndex.clamp(0, routine.days.length - 1);
        final day = routine.days.isEmpty ? null : routine.days[dayIndex];
        if (day == null) {
          return const _EmptyState(
              message: 'Esta rutina no tiene días configurados.');
        }
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
        onRetry: () => ref.invalidate(routineByIdProvider(widget.routineId)),
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
          child: _HeroStrip(imageUrl: routine.imageUrl),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 18),
              _DayChipBadge(
                text: '${routine.split.toUpperCase()} · DÍA ${day.dayNumber}',
              ),
              const SizedBox(height: 8),
              _DayTitle(text: day.name.toUpperCase()),
              const SizedBox(height: 14),
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
                ...day.slots.expand(
                  (slot) => [
                    ExerciseSlotRow(
                      slot: slot,
                      onTap: () => onSlotTap(slot),
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
  const _HeroStrip({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // imageUrl always null in Fase 2 — gradient placeholder only.
    return Container(
      height: 180,
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
            height: 180,
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
