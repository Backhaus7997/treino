import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../profile/application/user_providers.dart';
import '../../feed/domain/gym_name.dart';
import '../application/routine_providers.dart';
import '../application/session_init.dart';
import '../application/session_providers.dart';
import '../application/session_state.dart';
import '../domain/routine.dart';
import '../domain/routine_slot.dart';
import '../domain/set_log.dart';
import 'widgets/set_entry_sheet.dart';

// ── Enum de estado por fila de ejercicio (file-scope, diseño §2.4.4) ──────────

enum ExerciseRowStatus { done, current, pending }

// ── Helpers de formato ────────────────────────────────────────────────────────

/// Formatea segundos totales como MM:SS (máx 99:59). Diseño §9.4.
String _formatMMSS(int totalSeconds) {
  final m = (totalSeconds ~/ 60).clamp(0, 99).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ── SessionPlayerScreen ───────────────────────────────────────────────────────

/// Pantalla del player de sesión activa. Acepta un [SessionInit] sellado que
/// despacha entre sesión nueva (FreshSession) y retomada (ResumeSession).
/// Diseño §2.1.
class SessionPlayerScreen extends ConsumerStatefulWidget {
  const SessionPlayerScreen({super.key, required this.init});

  final SessionInit init;

  @override
  ConsumerState<SessionPlayerScreen> createState() =>
      _SessionPlayerScreenState();
}

class _SessionPlayerScreenState extends ConsumerState<SessionPlayerScreen> {
  // ── Helpers ───────────────────────────────────────────────────────────────

  ExerciseRowStatus _statusFor(int index, SessionState state) {
    if (state.isExerciseDone(state.day.slots[index].exerciseId)) {
      return ExerciseRowStatus.done;
    }
    if (index == state.currentExerciseIndex) return ExerciseRowStatus.current;
    return ExerciseRowStatus.pending;
  }

  void _showAbandonConfirm() {
    showDialog<void>(
      context: context,
      builder: (_) => _AbandonConfirmDialog(
        onConfirm: _onAbandonConfirmed,
      ),
    );
  }

  Future<void> _onAbandonConfirmed() async {
    final notifier = ref.read(sessionNotifierProvider(widget.init).notifier);
    final sessionId =
        ref.read(sessionNotifierProvider(widget.init)).value?.session.id;
    await notifier.abandonSession();
    if (mounted && sessionId != null) {
      context.go('/workout/session-summary/$sessionId');
    }
  }

  Future<void> _finishSession() async {
    final notifier = ref.read(sessionNotifierProvider(widget.init).notifier);
    final sessionId =
        ref.read(sessionNotifierProvider(widget.init)).value?.session.id;
    await notifier.finishSession();
    if (mounted && sessionId != null) {
      context.go('/workout/session-summary/$sessionId');
    }
  }

  void _openSetEntry(RoutineSlot slot, SessionState state) {
    // Aplica defaults del último log del ejercicio (diseño §9.7).
    final lastLog =
        state.setLogs.where((l) => l.exerciseId == slot.exerciseId).lastOrNull;
    final effectiveSlot = lastLog != null
        ? RoutineSlot(
            exerciseId: slot.exerciseId,
            exerciseName: slot.exerciseName,
            muscleGroup: slot.muscleGroup,
            targetSets: slot.targetSets,
            targetRepsMin: lastLog.reps,
            targetRepsMax: lastLog.reps,
            restSeconds: slot.restSeconds,
            targetWeightKg: lastLog.weightKg,
            notes: slot.notes,
          )
        : slot;

    final setNumber = state.setsLoggedFor(slot.exerciseId) + 1;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SetEntrySheet(
        slot: effectiveSlot,
        setNumber: setNumber,
        onCheck: (reps, weightKg) {
          ref.read(sessionNotifierProvider(widget.init).notifier).logSet(
                SetLog(
                  id: '',
                  exerciseId: slot.exerciseId,
                  exerciseName: slot.exerciseName,
                  setNumber: setNumber,
                  reps: reps,
                  weightKg: weightKg,
                  completedAt: DateTime.now(),
                ),
              );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final sessionAsync = ref.watch(sessionNotifierProvider(widget.init));

    // Lookup de la rutina para el header (diseño §9.3).
    final routineId = switch (widget.init) {
      FreshSession(routineId: final rid) => rid,
      ResumeSession() => sessionAsync.value?.session.routineId,
    };
    final routineAsync = routineId != null
        ? ref.watch(routineByIdProvider(routineId))
        : const AsyncLoading<Routine?>();
    final routineSplit = routineAsync.valueOrNull?.split ?? '';

    return sessionAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos iniciar la sesión.',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (state) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, __) => _showAbandonConfirm(),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SessionHeader(
                routineSplit: routineSplit,
                dayNumber: state.day.dayNumber,
                onAbandon: _showAbandonConfirm,
                onBack: _showAbandonConfirm,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const SizedBox(height: 12),
                    const _AttendanceCard(),
                    const SizedBox(height: 14),
                    _SessionStatsCard(state: state),
                    const SizedBox(height: 20),
                    const _SectionLabel('EJERCICIOS'),
                    const SizedBox(height: 12),
                    ...state.day.slots.asMap().entries.expand((entry) {
                      final idx = entry.key;
                      final slot = entry.value;
                      final status = _statusFor(idx, state);
                      return [
                        _ExerciseListRow(
                          slot: slot,
                          status: status,
                          completedSets: state.setsLoggedFor(slot.exerciseId),
                          onTap: status != ExerciseRowStatus.done
                              ? () => _openSetEntry(slot, state)
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ];
                    }),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: _TerminarSessionButton(
                  enabled: state.isFullyCompleted,
                  onPressed: state.isFullyCompleted ? _finishSession : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SessionHeader ────────────────────────────────────────────────────────────

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.routineSplit,
    required this.dayNumber,
    required this.onAbandon,
    required this.onBack,
  });

  final String routineSplit;
  final int dayNumber;
  final VoidCallback onAbandon;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          // Botón back — mismo callback que ABANDONAR
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.bgCard,
              ),
              child:
                  Icon(TreinoIcon.back, color: palette.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${routineSplit.toUpperCase()} · DÍA $dayNumber',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: 1.4,
                color: palette.textPrimary,
              ),
            ),
          ),
          // Botón ABANDONAR — pill outlined rojo
          OutlinedButton(
            onPressed: onAbandon,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.highlight),
              foregroundColor: palette.highlight,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9999),
              ),
            ),
            child: Text(
              'ABANDONAR',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.0,
                color: palette.highlight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _AttendanceCard ───────────────────────────────────────────────────────────

// Placeholder: real check-in wired in Etapa 6.
class _AttendanceCard extends ConsumerWidget {
  const _AttendanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final gymId = profileAsync.valueOrNull?.gymId;
    final gymName = gymNameFromId(gymId);
    final now = DateTime.now().toLocal();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final timeStr = '$hh:$mm';

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(TreinoIcon.gym, color: palette.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asistencia marcada',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  gymName.isEmpty ? 'Sin gimnasio asignado' : gymName,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            timeStr,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Icon(TreinoIcon.checkCircleFill, color: palette.accent, size: 20),
        ],
      ),
    );
  }
}

// ── _SessionStatsCard ─────────────────────────────────────────────────────────

class _SessionStatsCard extends StatelessWidget {
  const _SessionStatsCard({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final total = state.day.slots.length;
    final completed = state.completedExerciseCount;
    final progress = total > 0 ? completed / total : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SESIÓN ACTIVA',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$completed / $total ejercicios · '
                  '${state.totalVolumeKg.toStringAsFixed(1)} kg vol.',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ),
              Text(
                _formatMMSS(state.elapsedSeconds),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 40,
                  color: palette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: palette.border,
            valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }
}

// ── _SectionLabel ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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
        color: palette.textMuted,
      ),
    );
  }
}

// ── _ExerciseListRow ──────────────────────────────────────────────────────────

class _ExerciseListRow extends StatelessWidget {
  const _ExerciseListRow({
    required this.slot,
    required this.status,
    required this.completedSets,
    required this.onTap,
  });

  final RoutineSlot slot;
  final ExerciseRowStatus status;
  final int completedSets;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    Widget leadingIcon;
    TextStyle nameStyle;
    Widget? trailingWidget;

    switch (status) {
      case ExerciseRowStatus.done:
        leadingIcon = Icon(
          TreinoIcon.checkCircleFill,
          color: palette.accent,
          size: 24,
        );
        nameStyle = GoogleFonts.barlow(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: palette.textMuted,
          decoration: TextDecoration.lineThrough,
          decorationColor: palette.textMuted,
        );
        trailingWidget = null;
      case ExerciseRowStatus.current:
        leadingIcon = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.accent, width: 2),
          ),
        );
        nameStyle = GoogleFonts.barlow(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: palette.textPrimary,
        );
        trailingWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text(
            'Ahora',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.8,
              color: palette.bg,
            ),
          ),
        );
      case ExerciseRowStatus.pending:
        leadingIcon = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.border, width: 2),
          ),
        );
        nameStyle = GoogleFonts.barlow(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: palette.textPrimary,
        );
        trailingWidget =
            Icon(TreinoIcon.chevronRight, color: palette.textMuted, size: 20);
    }

    final subtitle =
        '${slot.targetSets} × ${slot.targetRepsMin}–${slot.targetRepsMax} '
        '· ${slot.targetWeightKg != null ? '${slot.targetWeightKg} kg' : '– kg'}';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            leadingIcon,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.exerciseName, style: nameStyle),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingWidget != null) ...[
              const SizedBox(width: 8),
              trailingWidget,
            ],
          ],
        ),
      ),
    );
  }
}

// ── _TerminarSessionButton ────────────────────────────────────────────────────

class _TerminarSessionButton extends StatelessWidget {
  const _TerminarSessionButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final button = SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          disabledBackgroundColor: palette.bgCard,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        child: Text(
          'TERMINAR SESIÓN',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 1.0,
            color: enabled ? palette.bg : palette.textMuted,
          ),
        ),
      ),
    );

    if (!enabled) {
      return Opacity(opacity: 0.4, child: button);
    }
    return button;
  }
}

// ── _AbandonConfirmDialog ─────────────────────────────────────────────────────

class _AbandonConfirmDialog extends StatelessWidget {
  const _AbandonConfirmDialog({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Text(
        '¿Seguro que querés abandonar? Se va a guardar tu progreso hasta acá.',
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: palette.textPrimary,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.highlight,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: Text(
            'Abandonar',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: palette.bg,
            ),
          ),
        ),
      ],
    );
  }
}
