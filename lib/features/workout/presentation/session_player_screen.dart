import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../../feed/domain/gym_name.dart';
import '../application/exercise_providers.dart';
import '../application/routine_providers.dart';
import '../application/session_init.dart';
import '../application/session_notifier.dart';
import '../application/session_providers.dart';
import '../application/session_state.dart';
import '../domain/routine.dart';
import '../domain/routine_slot.dart';
import '../domain/set_enums.dart';
import '../domain/set_log.dart';
import '../domain/set_spec.dart';
import 'widgets/set_entry_sheet.dart';

// ── Helpers de formato ────────────────────────────────────────────────────────

/// Formatea segundos totales como MM:SS (máx 99:59). Diseño §9.4.
String _formatMMSS(int totalSeconds) {
  final m = (totalSeconds ~/ 60).clamp(0, 99).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _formatWeight(double w) =>
    w == w.truncateToDouble() ? w.toInt().toString() : w.toString();

// ── Block gating helpers (top-level, testable) ────────────────────────────────

/// The gating state of a block (standalone exercise or superset group).
enum BlockStatus {
  /// All sets in this block are logged.
  completed,

  /// This is the first non-completed block — fully interactive.
  current,

  /// This block comes after the current one — locked, dimmed, not interactive.
  future,
}

/// A block is either a standalone slot or a list of slots that belong to the
/// same superset group.
typedef BlockInfo = ({List<RoutineSlot> slots, bool isSuperset});

/// Splits the day's slots into ordered blocks (standalone or superset groups).
/// A lone slot tagged with a supersetGroup falls back to standalone.
List<BlockInfo> buildBlocks(List<RoutineSlot> slots) {
  final blocks = <BlockInfo>[];
  var i = 0;
  while (i < slots.length) {
    final group = slots[i].supersetGroup;
    if (group != null) {
      var scan = i;
      final members = <RoutineSlot>[];
      while (scan < slots.length && slots[scan].supersetGroup == group) {
        members.add(slots[scan]);
        scan++;
      }
      if (members.length >= 2) {
        blocks.add((slots: members, isSuperset: true));
        i = scan;
        continue;
      }
    }
    blocks.add((slots: [slots[i]], isSuperset: false));
    i++;
  }
  return blocks;
}

/// Returns true if a standalone block (single slot) is fully completed.
/// [week] is the 0-based active week (from [SessionState.activeWeek]).
/// Single-week sessions pass 0; effectiveSetsForWeek(0) falls back to
/// effectiveSets semantics. (REQ-PERIOD-040)
bool isStandaloneBlockComplete(
    RoutineSlot slot, List<SetLog> allLogs, int week) {
  final logged = allLogs.where((l) => l.exerciseId == slot.exerciseId).length;
  return logged >= slot.effectiveSetsForWeek(week).length;
}

/// Returns true if a superset block (round-robin) is fully completed.
/// Complete = every member has effectiveSetsForWeek(week).length logs.
bool isSupersetBlockComplete(
    List<RoutineSlot> members, List<SetLog> allLogs, int week) {
  return members.every((slot) {
    final logged = allLogs.where((l) => l.exerciseId == slot.exerciseId).length;
    return logged >= slot.effectiveSetsForWeek(week).length;
  });
}

/// Determines the [BlockStatus] for each block given the current logs.
/// The "current" block is the first non-completed one.
/// [week] threads through to the slot-complete helpers. (REQ-PERIOD-040)
List<BlockStatus> computeBlockStatuses(
    List<BlockInfo> blocks, List<SetLog> allLogs, int week) {
  var foundCurrent = false;
  return blocks.map((block) {
    final complete = block.isSuperset
        ? isSupersetBlockComplete(block.slots, allLogs, week)
        : isStandaloneBlockComplete(block.slots.first, allLogs, week);
    if (complete) return BlockStatus.completed;
    if (!foundCurrent) {
      foundCurrent = true;
      return BlockStatus.current;
    }
    return BlockStatus.future;
  }).toList();
}

/// Planned reps to log for a SetSpec.
/// For range sets we use repsMax (the top of the range).
/// For single sets we use reps.
/// Document: rep-range logging uses repsMax to represent "aimed for the top".
int plannedRepsForSpec(SetSpec spec, ExerciseMode mode) {
  if (mode == ExerciseMode.duration) return 0;
  if (spec.reps != null) return spec.reps!;
  if (spec.repsMax != null) return spec.repsMax!;
  if (spec.repsMin != null) return spec.repsMin!;
  return 0;
}

/// Human-readable display for planned reps (e.g. "10" or "8–12").
/// Failure sets ([SetType.failure]) display "Al fallo" regardless of mode.
String repsDisplayText(SetSpec spec, ExerciseMode mode) {
  if (spec.type == SetType.failure) return 'Al fallo';
  if (mode == ExerciseMode.duration) {
    final secs = spec.durationSeconds ?? 0;
    return _formatMMSS(secs);
  }
  if (spec.reps != null) return '${spec.reps} reps';
  final min = spec.repsMin;
  final max = spec.repsMax;
  if (min != null && max != null && min != max) return '$min–$max reps';
  if (max != null) return '$max reps';
  if (min != null) return '$min reps';
  return '0 reps';
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
  // Marca que evita que el PopScope dispare el dialog de abandono cuando la
  // salida es intencional (TERMINAR o ABANDONAR confirmado). Sin esta marca,
  // context.go() pide al Navigator un pop que PopScope intercepta y dispara
  // showDialog en paralelo a la navegación — produce `!_debugLocked` assertion.
  bool _isFinalizing = false;

  // Canal de error de log/update de sets (finding 22). El notifier lo emite por
  // un ValueListenable SEPARADO del AsyncValue para no destruir la sesión activa
  // ante un solo set fallido. Nos suscribimos en initState y REMOVEMOS el listener
  // en dispose para no filtrarlo; guardamos la referencia al notifier para poder
  // hacer removeListener con el mismo objeto en dispose.
  SessionNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    // Diferido a post-frame: leer el provider y suscribirse al canal de error
    // recién cuando el árbol está montado, así el SnackBar tiene un
    // ScaffoldMessenger válido y no corremos ref.read durante initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier = ref.read(sessionNotifierProvider(widget.init).notifier);
      _notifier!.logSetError.addListener(_onLogSetError);
    });
  }

  @override
  void dispose() {
    _notifier?.logSetError.removeListener(_onLogSetError);
    super.dispose();
  }

  /// Reacciona a un fallo de log/update de set: muestra un SnackBar con
  /// Reintentar (finding 22) y limpia el canal para no re-emitir el mismo error.
  void _onLogSetError() {
    final notifier = _notifier;
    if (notifier == null || notifier.logSetError.value == null) return;
    if (!mounted) {
      notifier.clearLogSetError();
      return;
    }
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.sessionLogSetError),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: l10n.coachRetryLabel,
          onPressed: () {
            messenger.hideCurrentSnackBar();
            notifier.retryLastLogError();
          },
        ),
      ),
    );
    // Limpiamos el canal una vez mostrado el feedback para que no re-dispare el
    // mismo error en el próximo notify.
    notifier.clearLogSetError();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showAbandonConfirm() {
    if (_isFinalizing) return;
    showDialog<void>(
      context: context,
      builder: (_) => _AbandonConfirmDialog(
        onConfirm: _onAbandonConfirmed,
      ),
    );
  }

  Future<void> _onAbandonConfirmed() async {
    final notifier = ref.read(sessionNotifierProvider(widget.init).notifier);
    _isFinalizing = true;
    try {
      // El notifier RESETEA _finalized y RELANZA si el write a Firestore falla
      // (finding 23). Sin este try/catch, un fallo dejaba _isFinalizing=true sin
      // navegar → pantalla congelada. Capturamos, reseteamos la marca y ofrecemos
      // Reintentar sin navegar. El happy-path (navegar) queda intacto.
      await notifier.abandonSession();
    } catch (_) {
      if (mounted) {
        _isFinalizing = false;
        _showFinishError(_onAbandonConfirmed);
      }
      return;
    }
    if (mounted) {
      context.go('/workout');
    }
  }

  Future<void> _finishSession() async {
    final notifier = ref.read(sessionNotifierProvider(widget.init).notifier);
    final sessionId =
        ref.read(sessionNotifierProvider(widget.init)).value?.session.id;
    _isFinalizing = true;
    try {
      // Mismo contrato que abandon: el notifier relanza ante fallo de write
      // (finding 23). Capturamos para no dejar la pantalla congelada con el
      // botón inutilizable; reseteamos _isFinalizing y mostramos Reintentar.
      await notifier.finishSession();
    } catch (_) {
      if (mounted) {
        _isFinalizing = false;
        _showFinishError(_finishSession);
      }
      return;
    }
    if (mounted && sessionId != null) {
      context.go('/workout/session-summary/$sessionId');
    }
  }

  /// SnackBar de error de finalización/abandono con acción Reintentar
  /// (finding 23). [onRetry] re-invoca el mismo flujo (finish o abandon).
  void _showFinishError(Future<void> Function() onRetry) {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.sessionFinishError),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: l10n.coachRetryLabel,
          onPressed: () {
            messenger.hideCurrentSnackBar();
            onRetry();
          },
        ),
      ),
    );
  }

  /// Loguea un set directamente sin pasar por la sheet.
  void _logSet(RoutineSlot slot, int setNumber, int reps, double weightKg) {
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
  }

  /// Actualiza un set ya logueado con nuevos valores de peso.
  void _updateSet(SetLog existing, int reps, double weightKg) {
    final updated = existing.copyWith(reps: reps, weightKg: weightKg);
    ref.read(sessionNotifierProvider(widget.init).notifier).updateSet(updated);
  }

  /// Gathers everything a section needs for one slot: its logs (sorted ASC)
  /// plus the async-resolved technique + video.
  _SupersetEntry _entryFor(SessionState state, RoutineSlot slot) {
    final logs = state.setLogs
        .where((l) => l.exerciseId == slot.exerciseId)
        .toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    final exerciseAsync = ref.watch(exerciseByIdProvider(slot.exerciseId));
    return (
      slot: slot,
      logs: logs,
      technique: exerciseAsync.valueOrNull?.techniqueInstructions,
      videoUrl: exerciseAsync.valueOrNull?.videoUrl,
    );
  }

  /// Builds the exercise list with block gating: current block fully expanded,
  /// completed blocks collapsed to summary, future blocks locked/dimmed.
  List<Widget> _buildExerciseList(SessionState state) {
    // Source week ONCE here and thread down — single-week sessions use 0
    // so effectiveSetsForWeek(0) falls back to effectiveSets (REQ-PERIOD-042).
    final week = state.session.weekNumber;
    final blocks = buildBlocks(state.day.slots);
    final statuses = computeBlockStatuses(blocks, state.setLogs, week);
    final out = <Widget>[];

    for (var blockIdx = 0; blockIdx < blocks.length; blockIdx++) {
      final block = blocks[blockIdx];
      final status = statuses[blockIdx];

      if (block.isSuperset) {
        final entries = block.slots.map((s) => _entryFor(state, s)).toList();
        out.add(_SupersetBlock(
          entries: entries,
          status: status,
          allLogs: state.setLogs,
          week: week,
          onSetCheck: _logSet,
          onSetUpdate: _updateSet,
        ));
      } else {
        final entry = _entryFor(state, block.slots.first);
        out.add(_StandaloneBlock(
          entry: entry,
          status: status,
          week: week,
          onSetCheck: (setNumber, reps, weightKg) =>
              _logSet(entry.slot, setNumber, reps, weightKg),
          onSetUpdate: _updateSet,
        ));
      }
      out.add(const SizedBox(height: 14));
    }
    return out;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final sessionAsync = ref.watch(sessionNotifierProvider(widget.init));

    final routineId = switch (widget.init) {
      FreshSession(routineId: final rid) => rid,
      ResumeSession() => sessionAsync.value?.session.routineId,
    };
    final routineAsync = routineId != null
        ? ref.watch(routineByIdProvider(routineId))
        : const AsyncLoading<Routine?>();
    final routineSplit = routineAsync.valueOrNull?.split ?? '';

    return Scaffold(
      backgroundColor: palette.bg,
      body: sessionAsync.when(
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
          canPop: _isFinalizing,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || _isFinalizing) return;
            _showAbandonConfirm();
          },
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
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      physics: const ClampingScrollPhysics(),
                      overscroll: false,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      physics: const ClampingScrollPhysics(),
                      children: [
                        const SizedBox(height: 12),
                        const _AttendanceCard(),
                        const SizedBox(height: 14),
                        _SessionStatsCard(state: state),
                        const SizedBox(height: 20),
                        const _SectionLabel('EJERCICIOS'),
                        const SizedBox(height: 12),
                        ..._buildExerciseList(state),
                        const SizedBox(height: 20),
                      ],
                    ),
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
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l10n.commonBack,
            child: GestureDetector(
              onTap: onBack,
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
                alignment: Alignment.center,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.bgCard,
                  ),
                  child: Icon(TreinoIcon.back,
                      color: palette.textPrimary, size: 18),
                ),
              ),
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
          OutlinedButton(
            onPressed: onAbandon,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.highlight),
              foregroundColor: palette.highlight,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 44),
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

// ── Shared types ──────────────────────────────────────────────────────────────

typedef _SupersetEntry = ({
  RoutineSlot slot,
  List<SetLog> logs,
  List<String>? technique,
  String? videoUrl,
});

// ── _StandaloneBlock ──────────────────────────────────────────────────────────

/// Wraps a single exercise slot with block-gating applied.
/// - completed → compact summary row with ✓
/// - current   → full _ExerciseSection
/// - future    → collapsed, dimmed, locked
class _StandaloneBlock extends StatelessWidget {
  const _StandaloneBlock({
    required this.entry,
    required this.status,
    required this.week,
    required this.onSetCheck,
    required this.onSetUpdate,
  });

  final _SupersetEntry entry;
  final BlockStatus status;

  /// 0-based active week; single-week sessions use 0. (REQ-PERIOD-040)
  final int week;
  final void Function(int setNumber, int reps, double weightKg) onSetCheck;
  final void Function(SetLog existing, int reps, double weightKg) onSetUpdate;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case BlockStatus.completed:
        return _CompletedBlockSummary(
          exerciseName: entry.slot.exerciseName,
          totalSets: entry.slot.effectiveSetsForWeek(week).length,
        );
      case BlockStatus.future:
        return _FutureBlockPreview(exerciseName: entry.slot.exerciseName);
      case BlockStatus.current:
        final loggedCount = entry.logs.length;
        final totalSets = entry.slot.effectiveSetsForWeek(week).length;
        final isDone = loggedCount >= totalSets;
        return _ExerciseSection(
          slot: entry.slot,
          logsForExercise: entry.logs,
          currentSetNumber: isDone ? null : loggedCount + 1,
          week: week,
          techniqueInstructions: entry.technique,
          videoUrl: entry.videoUrl,
          onSetCheck: onSetCheck,
          onSetUpdate: onSetUpdate,
        );
    }
  }
}

// ── _SupersetBlock ────────────────────────────────────────────────────────────

/// Wraps a superset group with block-gating applied.
class _SupersetBlock extends StatelessWidget {
  const _SupersetBlock({
    required this.entries,
    required this.status,
    required this.allLogs,
    required this.week,
    required this.onSetCheck,
    required this.onSetUpdate,
  });

  final List<_SupersetEntry> entries;
  final BlockStatus status;
  final List<SetLog> allLogs;

  /// 0-based active week; single-week sessions use 0. (REQ-PERIOD-040)
  final int week;
  final void Function(
      RoutineSlot slot, int setNumber, int reps, double weightKg) onSetCheck;
  final void Function(SetLog existing, int reps, double weightKg) onSetUpdate;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case BlockStatus.completed:
        return _CompletedSupersetSummary(entries: entries);
      case BlockStatus.future:
        return _FutureSupersetPreview(entries: entries);
      case BlockStatus.current:
        return _SupersetSection(
          entries: entries,
          week: week,
          onSetCheck: onSetCheck,
          onSetUpdate: onSetUpdate,
        );
    }
  }
}

// ── _CompletedBlockSummary ────────────────────────────────────────────────────

/// Compact collapsed row for a completed standalone block.
class _CompletedBlockSummary extends StatelessWidget {
  const _CompletedBlockSummary({
    required this.exerciseName,
    required this.totalSets,
  });

  final String exerciseName;
  final int totalSets;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: palette.accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(TreinoIcon.checkBare, color: palette.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              exerciseName,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: palette.textMuted,
                decoration: TextDecoration.lineThrough,
                decorationColor: palette.textMuted,
              ),
            ),
          ),
          Text(
            '$totalSets/$totalSets',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: palette.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _CompletedSupersetSummary ─────────────────────────────────────────────────

/// Compact collapsed row for a completed superset block.
class _CompletedSupersetSummary extends StatelessWidget {
  const _CompletedSupersetSummary({required this.entries});

  final List<_SupersetEntry> entries;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final names = entries.map((e) => e.slot.exerciseName).join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: palette.accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(TreinoIcon.checkBare, color: palette.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SUPERSERIE',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    color: palette.accent,
                  ),
                ),
                Text(
                  names,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: palette.textMuted,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'COMPLETA',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: palette.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _FutureBlockPreview ───────────────────────────────────────────────────────

/// Dimmed, locked row for a future standalone block.
class _FutureBlockPreview extends StatelessWidget {
  const _FutureBlockPreview({required this.exerciseName});

  final String exerciseName;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: 0.4,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(TreinoIcon.lock, color: palette.textMuted, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                exerciseName,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _FutureSupersetPreview ────────────────────────────────────────────────────

/// Dimmed, locked row for a future superset block.
class _FutureSupersetPreview extends StatelessWidget {
  const _FutureSupersetPreview({required this.entries});

  final List<_SupersetEntry> entries;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final names = entries.map((e) => e.slot.exerciseName).join(' · ');
    return Opacity(
      opacity: 0.4,
      child: Container(
        decoration: BoxDecoration(
          color: palette.highlight.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.highlight),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(TreinoIcon.lock, color: palette.highlight, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SUPERSERIE',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 1.0,
                      color: palette.highlight,
                    ),
                  ),
                  Text(
                    names,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: palette.textMuted,
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

// ── _SupersetSection ──────────────────────────────────────────────────────────

/// Envuelve los ejercicios de una superserie en una tarjeta magenta
/// "SUPERSERIE" y fuerza el orden round-robin: A-1, B-1, A-2, B-2 …
/// Solo la celda activa (la primera no completada en esa secuencia aplanada)
/// queda interactiva; el resto se muestra como resumen bloqueado hasta su turno.
class _SupersetSection extends StatelessWidget {
  const _SupersetSection({
    required this.entries,
    required this.week,
    required this.onSetCheck,
    required this.onSetUpdate,
  });

  final List<_SupersetEntry> entries;

  /// 0-based active week; single-week sessions use 0. (REQ-PERIOD-040)
  final int week;
  final void Function(
      RoutineSlot slot, int setNumber, int reps, double weightKg) onSetCheck;
  final void Function(SetLog existing, int reps, double weightKg) onSetUpdate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Vueltas totales = el ejercicio más largo del bloque.
    final maxRounds = entries.fold<int>(
        0,
        (m, e) => e.slot.effectiveSetsForWeek(week).length > m
            ? e.slot.effectiveSetsForWeek(week).length
            : m);

    // Scan round-robin: la celda activa es el primer par (vuelta, ejercicio)
    // que aún no fue logueado.
    String? activeId;
    int? activeSet;
    var activeRound = 0;
    outer:
    for (var round = 1; round <= maxRounds; round++) {
      for (final e in entries) {
        if (round > e.slot.effectiveSetsForWeek(week).length) continue;
        if (e.logs.length < round) {
          activeId = e.slot.exerciseId;
          activeSet = round;
          activeRound = round;
          break outer;
        }
      }
    }
    final blockDone = activeId == null;
    final displayRound = blockDone ? maxRounds : activeRound;

    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      children.add(_ExerciseSection(
        slot: e.slot,
        logsForExercise: e.logs,
        currentSetNumber: e.slot.exerciseId == activeId ? activeSet : null,
        week: week,
        techniqueInstructions: e.technique,
        videoUrl: e.videoUrl,
        onSetCheck: (setNumber, reps, weightKg) =>
            onSetCheck(e.slot, setNumber, reps, weightKg),
        onSetUpdate: onSetUpdate,
      ));
      if (i != entries.length - 1) children.add(const SizedBox(height: 8));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.highlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Icon(TreinoIcon.streak, size: 14, color: palette.highlight),
                const SizedBox(width: 6),
                Text(
                  'SUPERSERIE',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: palette.highlight,
                  ),
                ),
                const Spacer(),
                Text(
                  blockDone ? 'COMPLETA' : 'VUELTA $displayRound/$maxRounds',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: blockDone ? palette.accent : palette.highlight,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

// ── _ExerciseSection ──────────────────────────────────────────────────────────

/// Sección de un ejercicio. Render condicional por fila:
/// - Sets ya logueados: fila compacta (tappable para expandir y editar).
/// - Set actual (siguiente pendiente): fila expandida con controles.
/// - Sets futuros (pendientes después del actual): solo resumen (sin controles).
class _ExerciseSection extends StatefulWidget {
  const _ExerciseSection({
    required this.slot,
    required this.logsForExercise,
    required this.currentSetNumber,
    required this.week,
    required this.techniqueInstructions,
    required this.videoUrl,
    required this.onSetCheck,
    required this.onSetUpdate,
  });

  final RoutineSlot slot;
  final List<SetLog> logsForExercise;

  /// Set (1-based) que debe estar activo. Null ⇒ ningún set activo.
  final int? currentSetNumber;

  /// 0-based active week; single-week sessions use 0. (REQ-PERIOD-040)
  final int week;
  final List<String>? techniqueInstructions;
  final String? videoUrl;

  final void Function(int setNumber, int reps, double weightKg) onSetCheck;
  final void Function(SetLog existing, int reps, double weightKg) onSetUpdate;

  @override
  State<_ExerciseSection> createState() => _ExerciseSectionState();
}

class _ExerciseSectionState extends State<_ExerciseSection> {
  /// Sets done que el usuario expandió manualmente para editar.
  final Set<int> _expandedDoneSets = {};

  void _toggleDoneRow(int setNumber) {
    setState(() {
      if (_expandedDoneSets.contains(setNumber)) {
        _expandedDoneSets.remove(setNumber);
      } else {
        _expandedDoneSets.add(setNumber);
      }
    });
  }

  bool get _hasTechnique =>
      widget.techniqueInstructions != null &&
      widget.techniqueInstructions!.isNotEmpty;

  void _showTechnique(BuildContext context) {
    if (!_hasTechnique) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TechniqueSheet(
        exerciseName: widget.slot.exerciseName,
        instructions: widget.techniqueInstructions!,
        videoUrl: widget.videoUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final effectiveSets = widget.slot.effectiveSetsForWeek(widget.week);
    final loggedCount = widget.logsForExercise.length;
    final totalSets = effectiveSets.length;
    final isDone = loggedCount >= totalSets;
    final mode = widget.slot.effectiveExerciseMode;

    final int? nextPendingSetNumber = widget.currentSetNumber;

    final rowWidgets = <Widget>[];
    for (var idx = 0; idx < totalSets; idx++) {
      final setNumber = idx + 1;
      final spec = effectiveSets[idx];
      final logged = widget.logsForExercise
          .where((l) => l.setNumber == setNumber)
          .firstOrNull;
      final isRowDone = logged != null;
      final isCurrent = !isRowDone && setNumber == nextPendingSetNumber;
      final isExpanded =
          isCurrent || (isRowDone && _expandedDoneSets.contains(setNumber));

      // For duration sets, the logged weight is 0.
      // For reps sets, the logged weight comes from the log or planned spec.
      final plannedWeight = spec.weightKg ?? widget.slot.targetWeightKg ?? 0.0;
      final initialWeight = isRowDone ? logged.weightKg : plannedWeight;
      final plannedReps = plannedRepsForSpec(spec, mode);

      final isDurationSet = mode == ExerciseMode.duration ||
          (spec.durationSeconds != null && spec.durationSeconds! > 0);
      final targetSeconds = isDurationSet ? (spec.durationSeconds ?? 0) : 0;

      final isFutureSet = !isRowDone && !isCurrent;
      Widget rowWidget = Padding(
        padding: EdgeInsets.only(top: rowWidgets.isEmpty ? 0 : 8),
        child: isDurationSet
            ? _DurationSetRow(
                key: ValueKey('dur-$setNumber-${logged?.id ?? "pending"}'),
                setNumber: setNumber,
                targetSeconds: targetSeconds,
                isDone: isRowDone,
                onDone: isCurrent
                    ? () => widget.onSetCheck(setNumber, 0, 0.0)
                    : null,
              )
            : _RepsSetRow(
                key: ValueKey('set-$setNumber-${logged?.id ?? "pending"}'),
                setNumber: setNumber,
                spec: spec,
                mode: mode,
                plannedReps: plannedReps,
                initialWeightKg: initialWeight,
                isDone: isRowDone,
                isExpanded: isExpanded,
                onCheck: isCurrent
                    ? (weightKg) =>
                        widget.onSetCheck(setNumber, plannedReps, weightKg)
                    : null,
                onWeightUpdate: isRowDone
                    ? (weightKg) =>
                        widget.onSetUpdate(logged, plannedReps, weightKg)
                    : null,
                onSummaryTap:
                    isRowDone ? () => _toggleDoneRow(setNumber) : null,
              ),
      );
      if (isFutureSet) {
        rowWidget = Opacity(opacity: 0.4, child: rowWidget);
      }
      rowWidgets.add(rowWidget);
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: ✓ (sólo si está hecho) + nombre + ⓘ (opcional) + "X/N".
          // El ejercicio EN CURSO no lleva ícono a la izquierda: el círculo
          // hueco parecía un botón apretable. Se distingue por estar expandido.
          Row(
            children: [
              if (isDone) ...[
                Icon(TreinoIcon.checkBare, color: palette.accent, size: 22),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  widget.slot.exerciseName,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: isDone ? palette.textMuted : palette.textPrimary,
                    decoration: isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: palette.textMuted,
                  ),
                ),
              ),
              if (_hasTechnique) ...[
                Semantics(
                  button: true,
                  label: l10n
                      .sessionPlayerTechniqueA11y(widget.slot.exerciseName),
                  child: GestureDetector(
                    onTap: () => _showTechnique(context),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        TreinoIcon.infoCircle,
                        size: 20,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDone
                      ? palette.accent.withValues(alpha: 0.15)
                      : palette.bg,
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(
                    color: isDone ? palette.accent : palette.border,
                    width: 1,
                  ),
                ),
                child: Text(
                  '$loggedCount/$totalSets',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.6,
                    color: isDone ? palette.accent : palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rowWidgets,
        ],
      ),
    );
  }
}

// ── _RepsSetRow ───────────────────────────────────────────────────────────────

/// Fila de un set basado en reps.
/// - Reps: texto fijo (no editable). Logged reps = planned (repsMax for ranges).
/// - Peso: TextField numérico (teclado decimal).
/// - Check: marca el set como done.
class _RepsSetRow extends StatefulWidget {
  const _RepsSetRow({
    super.key,
    required this.setNumber,
    required this.spec,
    required this.mode,
    required this.plannedReps,
    required this.initialWeightKg,
    required this.isDone,
    required this.isExpanded,
    required this.onCheck,
    required this.onWeightUpdate,
    required this.onSummaryTap,
  });

  final int setNumber;
  final SetSpec spec;
  final ExerciseMode mode;
  final int plannedReps;
  final double initialWeightKg;
  final bool isDone;
  final bool isExpanded;

  /// Called when the ☐ is tapped for a pending current row — (weightKg).
  final void Function(double weightKg)? onCheck;

  /// Called when weight changes for a done row.
  final void Function(double weightKg)? onWeightUpdate;

  /// Tap on summary row — only active for done rows to toggle expand.
  final VoidCallback? onSummaryTap;

  @override
  State<_RepsSetRow> createState() => _RepsSetRowState();
}

class _RepsSetRowState extends State<_RepsSetRow> {
  late TextEditingController _weightController;
  late double _weightKg;

  @override
  void initState() {
    super.initState();
    _weightKg = widget.initialWeightKg;
    _weightController = TextEditingController(
      text: _weightKg == 0 ? '' : _formatWeight(_weightKg),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  void _onWeightChanged(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    // Empty/unparseable -> 0; out-of-range -> clamped to [0, 500]. This keeps
    // _weightKg in sync with what the user sees and with what gets logged,
    // instead of silently retaining a stale value.
    final next = (parsed ?? 0).clamp(0.0, 500.0).toDouble();
    if (next == _weightKg) return;
    setState(() => _weightKg = next);
    if (widget.isDone) {
      widget.onWeightUpdate?.call(_weightKg);
    }
  }

  void _onCheckTap() {
    widget.onCheck?.call(_weightKg);
  }

  String get _repsDisplayText => repsDisplayText(widget.spec, widget.mode);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final textColor = widget.isDone ? palette.textMuted : palette.textPrimary;

    // Summary row — always visible.
    final summaryRow = GestureDetector(
      onTap: widget.onSummaryTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${widget.setNumber}',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$_repsDisplayText · ${_formatWeight(_weightKg)} kg',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: textColor,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: l10n.sessionPlayerSetCompleteA11y(widget.setNumber),
            child: GestureDetector(
              onTap: widget.isDone ? widget.onSummaryTap : _onCheckTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: Icon(
                  widget.isDone
                      ? TreinoIcon.checkCircleFill
                      : TreinoIcon.checkCircleEmpty,
                  color: widget.isDone ? palette.accent : palette.textMuted,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Expanded panel: fixed reps label + weight text field.
    final expandedPanel = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const SizedBox(width: 32),
          // Fixed reps display — NOT editable.
          Expanded(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: palette.border),
                ),
              ),
              child: Text(
                _repsDisplayText,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: textColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Editable weight field.
          Expanded(
            child: _WeightField(
              controller: _weightController,
              textColor: textColor,
              onChanged: _onWeightChanged,
            ),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          summaryRow,
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: widget.isExpanded
                ? expandedPanel
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ── _WeightField ──────────────────────────────────────────────────────────────

/// Editable numeric text field for weight input.
/// Underline style, ~16px font, min 44px tap target.
class _WeightField extends StatelessWidget {
  const _WeightField({
    required this.controller,
    required this.textColor,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Color textColor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        textAlign: TextAlign.center,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: textColor,
        ),
        decoration: InputDecoration(
          hintText: '0 kg',
          hintStyle: GoogleFonts.barlow(
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: palette.textMuted,
          ),
          suffix: Text(
            'kg',
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: palette.accent, width: 2),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

// ── _DurationSetRow ───────────────────────────────────────────────────────────

/// Fila de un set basado en duración.
/// Muestra el tiempo objetivo como MM:SS y un countdown timer.
/// "Iniciar" arranca el contador; al llegar a 0 auto-marca done con vibración.
class _DurationSetRow extends StatefulWidget {
  const _DurationSetRow({
    super.key,
    required this.setNumber,
    required this.targetSeconds,
    required this.isDone,
    required this.onDone,
  });

  final int setNumber;
  final int targetSeconds;
  final bool isDone;

  /// Called when the set is marked done. Null means not interactive.
  final VoidCallback? onDone;

  @override
  State<_DurationSetRow> createState() => _DurationSetRowState();
}

class _DurationSetRowState extends State<_DurationSetRow> {
  Timer? _timer;
  int _remaining = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.targetSeconds;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    if (_running || widget.isDone) return;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_remaining > 0) {
          _remaining--;
        } else {
          t.cancel();
          _running = false;
          // Buzz to alert the user that time is up.
          HapticFeedback.heavyImpact();
          // Auto-mark done when countdown reaches 0.
          widget.onDone?.call();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final textColor = widget.isDone ? palette.textMuted : palette.textPrimary;
    final isInteractive = widget.onDone != null && !widget.isDone;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${widget.setNumber}',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Timer display.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _running ||
                          (!widget.isDone && _remaining < widget.targetSeconds)
                      ? _formatMMSS(_remaining)
                      : _formatMMSS(widget.targetSeconds),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: _running ? palette.accent : textColor,
                  ),
                ),
                if (!widget.isDone)
                  Text(
                    'objetivo: ${_formatMMSS(widget.targetSeconds)}',
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 11,
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Action button.
          if (widget.isDone)
            Icon(TreinoIcon.checkCircleFill, color: palette.accent, size: 22)
          else if (!_running)
            Semantics(
              button: true,
              label: l10n.sessionPlayerTimerStartA11y,
              child: GestureDetector(
                onTap: isInteractive ? _startTimer : null,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isInteractive
                        ? palette.accent.withValues(alpha: 0.15)
                        : palette.bgCard,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(
                      color: isInteractive ? palette.accent : palette.border,
                    ),
                  ),
                  child: Text(
                    'Iniciar',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isInteractive ? palette.accent : palette.textMuted,
                    ),
                  ),
                ),
              ),
            )
          else
            // Timer running — show countdown-only state, no manual completion.
            Icon(TreinoIcon.timer, color: palette.accent, size: 22),
        ],
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
