import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../../gyms/application/gym_providers.dart';
import '../../gyms/domain/gym_display_name.dart';
import '../application/exercise_providers.dart';
import '../application/routine_providers.dart';
import '../application/session_init.dart';
import '../application/session_notifier.dart';
import '../application/session_providers.dart';
import '../application/session_state.dart';
import '../domain/routine.dart';
import '../domain/routine_slot.dart';
import '../domain/set_enums.dart';
import '../domain/set_limits.dart';
import '../domain/set_log.dart';
import '../domain/set_spec.dart';
import 'widgets/bounded_number_formatter.dart';
import 'widgets/coach_note.dart';
import 'widgets/set_entry_sheet.dart';

// ── Helpers de formato ────────────────────────────────────────────────────────

/// Formatea segundos totales como MM:SS (máx 99:59). Diseño §9.4.
String _formatMMSS(int totalSeconds) {
  final m = (totalSeconds ~/ 60).clamp(0, 99).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

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
///
/// [plannedCountFor] is the live-set-editing resolver ([SITE-4], AD-5) —
/// pass `state.plannedSetsFor` from real call sites so an added/removed set
/// is reflected in the completion denominator. Optional and defaults to the
/// raw plan count (`slot.effectiveSetsForWeek(week).length`) when omitted,
/// keeping this signature backward-compatible for callers that predate
/// live-set-editing.
bool isStandaloneBlockComplete(RoutineSlot slot, List<SetLog> allLogs, int week,
    [int Function(RoutineSlot)? plannedCountFor]) {
  final logged = allLogs.where((l) => l.exerciseId == slot.exerciseId).length;
  final planned = plannedCountFor != null
      ? plannedCountFor(slot)
      : slot.effectiveSetsForWeek(week).length;
  return logged >= planned;
}

/// Returns true if a superset block (round-robin) is fully completed.
/// Complete = every member has [plannedCountFor] (or the raw plan count)
/// logs. See [isStandaloneBlockComplete] for [plannedCountFor] semantics
/// ([SITE-5], AD-5).
bool isSupersetBlockComplete(
    List<RoutineSlot> members, List<SetLog> allLogs, int week,
    [int Function(RoutineSlot)? plannedCountFor]) {
  return members.every((slot) {
    final logged = allLogs.where((l) => l.exerciseId == slot.exerciseId).length;
    final planned = plannedCountFor != null
        ? plannedCountFor(slot)
        : slot.effectiveSetsForWeek(week).length;
    return logged >= planned;
  });
}

/// Determines the [BlockStatus] for each block given the current logs.
/// The "current" block is the first non-completed one.
/// [week] threads through to the slot-complete helpers. (REQ-PERIOD-040)
/// [plannedCountFor] threads the live-set-editing resolver through to both
/// helpers (AD-5) — see [isStandaloneBlockComplete].
List<BlockStatus> computeBlockStatuses(
    List<BlockInfo> blocks, List<SetLog> allLogs, int week,
    [int Function(RoutineSlot)? plannedCountFor]) {
  var foundCurrent = false;
  return blocks.map((block) {
    final complete = block.isSuperset
        ? isSupersetBlockComplete(block.slots, allLogs, week, plannedCountFor)
        : isStandaloneBlockComplete(
            block.slots.first, allLogs, week, plannedCountFor);
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
///
/// [spec] is null for an added-beyond-plan row (live-set-editing AD-4) — a
/// bare row has no prescription, so this returns 0 (no planned target).
int plannedRepsForSpec(SetSpec? spec, ExerciseMode mode) {
  if (spec == null) return 0;
  if (mode == ExerciseMode.duration) return 0;
  if (spec.reps != null) return spec.reps!;
  if (spec.repsMax != null) return spec.repsMax!;
  if (spec.repsMin != null) return spec.repsMin!;
  return 0;
}

/// Human-readable display for planned reps (e.g. "10" or "8–12").
/// Failure sets ([SetType.failure]) display "Al fallo" regardless of mode.
///
/// [spec] is null for an added-beyond-plan row (AD-4) — returns an empty
/// string so no prescription hint text renders for a bare row.
String repsDisplayText(SetSpec? spec, ExerciseMode mode) {
  if (spec == null) return '';
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

  // Navegación libre (SCENARIO-ORDER): bloques `future` que el usuario destrabó
  // a mano para adelantarlos (p.ej. la máquina del sugerido está ocupada).
  // Clave = índice del bloque en buildBlocks — estable porque day.slots NO cambia
  // durante la sesión. Estado efímero de UI: NO se persiste. El progreso real
  // vive en los setLogs, que ya son independientes del orden de ejecución, así
  // que el bloque salteado sigue disponible aunque se cierre y retome la app.
  final Set<int> _activatedBlocks = {};

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
  ///
  /// Defensive: en sets por REPS, `reps == 0` no crea log. El TextField del row
  /// puede quedar vacío/en 0 como estado intermedio de tipeo, y el athlete puede
  /// apretar el check antes de completar — preferimos no-op silencioso a
  /// loggear un set falso que después habría que borrar.
  ///
  /// QA-WKT-001: los sets por DURACIÓN se completan legítimamente con `reps == 0`
  /// (su métrica es el tiempo; el `_DurationSetRow` loguea vía
  /// `onSetCheck(setNumber, 0, 0.0)` cuando el countdown llega a 0). Ahí el guard
  /// NO aplica — si no, el set nunca se marca hecho y un día con cualquier
  /// ejercicio por tiempo jamás puede terminarse.
  void _logSet(RoutineSlot slot, int setNumber, int reps, double weightKg) {
    if (slot.effectiveExerciseMode != ExerciseMode.duration && reps <= 0) {
      return;
    }
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

  /// Actualiza un set ya logueado con nuevos valores de reps y/o peso.
  /// Reps == 0 se ignora — mismo criterio defensivo que [_logSet].
  void _updateSet(SetLog existing, int reps, double weightKg) {
    if (reps <= 0) return;
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
    // live-set-editing AD-5: single resolver every gating/render denominator
    // routes through. Bound method closes over `state`, so callers never
    // read the raw plan count directly.
    final plannedCountFor = state.plannedSetsFor;
    final statuses =
        computeBlockStatuses(blocks, state.setLogs, week, plannedCountFor);
    final out = <Widget>[];

    for (var blockIdx = 0; blockIdx < blocks.length; blockIdx++) {
      final block = blocks[blockIdx];
      final status = statuses[blockIdx];
      // Navegación libre: un bloque `future` puede estar destrabado a mano.
      final activated = _activatedBlocks.contains(blockIdx);
      final idx = blockIdx;

      if (block.isSuperset) {
        final entries = block.slots.map((s) => _entryFor(state, s)).toList();
        out.add(_SupersetBlock(
          entries: entries,
          status: status,
          activated: activated,
          onActivate: () => setState(() => _activatedBlocks.add(idx)),
          allLogs: state.setLogs,
          week: week,
          plannedCountFor: plannedCountFor,
          onSetCheck: _logSet,
          onSetUpdate: _updateSet,
        ));
      } else {
        final entry = _entryFor(state, block.slots.first);
        out.add(_StandaloneBlock(
          entry: entry,
          status: status,
          activated: activated,
          onActivate: () => setState(() => _activatedBlocks.add(idx)),
          week: week,
          plannedCountFor: plannedCountFor,
          onSetCheck: (setNumber, reps, weightKg) =>
              _logSet(entry.slot, setNumber, reps, weightKg),
          onSetUpdate: _updateSet,
          onAddSet: () => _addSet(entry.slot),
          onRemoveSet: (log) => _onRemoveSetTapped(entry.slot, log),
        ));
      }
      out.add(const SizedBox(height: 14));
    }
    return out;
  }

  /// Agrega un set extra al ejercicio (live-set-editing AD-1/AD-6). El write
  /// real ocurre cuando el athlete completa la fila nueva vía [_logSet].
  void _addSet(RoutineSlot slot) {
    ref.read(sessionNotifierProvider(widget.init).notifier).addSet(slot);
  }

  /// Elimina un set del ejercicio (live-set-editing AD-2/AD-6). [log] es
  /// `null` para una fila pendiente/sin loguear (delete inmediato, sin
  /// diálogo); si trae un `SetLog`, ya fue confirmado por el diálogo (data
  /// loss) — ver [_showRemoveSetConfirm].
  void _removeSet(RoutineSlot slot, SetLog? log) {
    ref.read(sessionNotifierProvider(widget.init).notifier).removeSet(
          slot,
          log,
        );
  }

  /// Callback wired to each row's delete icon (AD-6). Una fila SIN loguear
  /// (log == null) se borra directo, sin diálogo. Una fila LOGUEADA muestra
  /// el diálogo de confirmación (data loss) antes de disparar [_removeSet].
  void _onRemoveSetTapped(RoutineSlot slot, SetLog? log) {
    if (log == null) {
      _removeSet(slot, null);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _RemoveSetConfirmDialog(
        onConfirm: () => _removeSet(slot, log),
      ),
    );
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
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
    // DETAIL context (self) — UserProfile has no denormalized gymName, so
    // resolve live via gymByIdProvider. gyms-foundation Phase 3.
    final gymName = gymId == null
        ? ''
        : gymDisplayNameFromGym(ref.watch(gymByIdProvider(gymId)).valueOrNull);
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
                  '${formatVolumeKg(state.totalVolumeKg)} kg vol.',
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
/// - current   → full _ExerciseSection (el sugerido, abierto por defecto)
/// - future    → tarjeta colapsada TAPPABLE ([onActivate]); si el usuario la
///   destrabó ([activated] == true) se expande al _ExerciseSection completo.
///   (Navegación libre: adelantar un bloque si el sugerido está ocupado.)
class _StandaloneBlock extends StatelessWidget {
  const _StandaloneBlock({
    required this.entry,
    required this.status,
    required this.activated,
    required this.onActivate,
    required this.week,
    required this.plannedCountFor,
    required this.onSetCheck,
    required this.onSetUpdate,
    this.onAddSet,
    this.onRemoveSet,
  });

  final _SupersetEntry entry;
  final BlockStatus status;

  /// Bloque `future` destrabado a mano → se renderiza interactivo.
  final bool activated;
  final VoidCallback onActivate;

  /// 0-based active week; single-week sessions use 0. (REQ-PERIOD-040)
  final int week;

  /// live-set-editing AD-5 resolver ([SITE-6], [SITE-7]) — "sets today" for a
  /// slot, honoring any session-local add/remove override.
  final int Function(RoutineSlot) plannedCountFor;
  final void Function(int setNumber, int reps, double weightKg) onSetCheck;
  final void Function(SetLog existing, int reps, double weightKg) onSetUpdate;

  /// "+ agregar serie" callback (AD-6). Null on blocks that shouldn't offer
  /// it — never wired for completed/future blocks (see build() below).
  final VoidCallback? onAddSet;

  /// Per-row delete icon callback (AD-2/AD-6). `log` is `null` for the
  /// pending/unlogged row. Null on blocks that shouldn't offer it — never
  /// wired for completed/future blocks (see build() below).
  final void Function(SetLog? log)? onRemoveSet;

  @override
  Widget build(BuildContext context) {
    if (status == BlockStatus.completed) {
      return _CompletedBlockSummary(
        exerciseName: entry.slot.exerciseName,
        totalSets: plannedCountFor(entry.slot),
      );
    }
    if (status == BlockStatus.future && !activated) {
      return _FutureBlockPreview(
        exerciseName: entry.slot.exerciseName,
        onActivate: onActivate,
      );
    }
    // current, o future destrabado → interactivo.
    final loggedCount = entry.logs.length;
    final totalSets = plannedCountFor(entry.slot);
    final isDone = loggedCount >= totalSets;
    return _ExerciseSection(
      slot: entry.slot,
      logsForExercise: entry.logs,
      currentSetNumber: isDone ? null : loggedCount + 1,
      week: week,
      totalSets: totalSets,
      techniqueInstructions: entry.technique,
      videoUrl: entry.videoUrl,
      onSetCheck: onSetCheck,
      onSetUpdate: onSetUpdate,
      onAddSet: onAddSet,
      onRemoveSet: onRemoveSet,
    );
  }
}

// ── _SupersetBlock ────────────────────────────────────────────────────────────

/// Wraps a superset group with block-gating applied.
/// `future` no destrabado → preview tappable; destrabado ([activated]) o
/// `current` → _SupersetSection interactivo. (Navegación libre.)
class _SupersetBlock extends StatelessWidget {
  const _SupersetBlock({
    required this.entries,
    required this.status,
    required this.activated,
    required this.onActivate,
    required this.allLogs,
    required this.week,
    required this.plannedCountFor,
    required this.onSetCheck,
    required this.onSetUpdate,
  });

  final List<_SupersetEntry> entries;
  final BlockStatus status;

  /// Bloque `future` destrabado a mano → se renderiza interactivo.
  final bool activated;
  final VoidCallback onActivate;
  final List<SetLog> allLogs;

  /// 0-based active week; single-week sessions use 0. (REQ-PERIOD-040)
  final int week;

  /// live-set-editing AD-5 resolver ([SITE-5], [SITE-8]) — see
  /// [_StandaloneBlock.plannedCountFor]. Superset add/remove UI is out of
  /// scope this change (design.md AD-5 superset note); the gating switch is
  /// applied uniformly for correctness only.
  final int Function(RoutineSlot) plannedCountFor;
  final void Function(
      RoutineSlot slot, int setNumber, int reps, double weightKg) onSetCheck;
  final void Function(SetLog existing, int reps, double weightKg) onSetUpdate;

  @override
  Widget build(BuildContext context) {
    if (status == BlockStatus.completed) {
      return _CompletedSupersetSummary(entries: entries);
    }
    if (status == BlockStatus.future && !activated) {
      return _FutureSupersetPreview(entries: entries, onActivate: onActivate);
    }
    // current, o future destrabado → interactivo.
    return _SupersetSection(
      entries: entries,
      week: week,
      plannedCountFor: plannedCountFor,
      onSetCheck: onSetCheck,
      onSetUpdate: onSetUpdate,
    );
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

/// Fila colapsada y TAPPABLE de un bloque `future` (navegación libre): en vez de
/// bloquear, invita a adelantarlo si la máquina del sugerido está ocupada. Al
/// tocar dispara [onActivate], que lo destraba y lo expande interactivo.
class _FutureBlockPreview extends StatelessWidget {
  const _FutureBlockPreview({
    required this.exerciseName,
    required this.onActivate,
  });

  final String exerciseName;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onActivate,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: 0.75,
          child: Container(
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exerciseName,
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tocá para adelantar este bloque',
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(TreinoIcon.play, color: palette.accent, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── _FutureSupersetPreview ────────────────────────────────────────────────────

/// Preview colapsado y TAPPABLE de una superserie `future` (navegación libre).
/// Al tocar dispara [onActivate] y la superserie se expande interactiva.
class _FutureSupersetPreview extends StatelessWidget {
  const _FutureSupersetPreview({
    required this.entries,
    required this.onActivate,
  });

  final List<_SupersetEntry> entries;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final names = entries.map((e) => e.slot.exerciseName).join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onActivate,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: 0.75,
          child: Container(
            decoration: BoxDecoration(
              color: palette.highlight.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.highlight),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
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
                      const SizedBox(height: 2),
                      Text(
                        'Tocá para adelantar este bloque',
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(TreinoIcon.play, color: palette.accent, size: 16),
              ],
            ),
          ),
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
    required this.plannedCountFor,
    required this.onSetCheck,
    required this.onSetUpdate,
  });

  final List<_SupersetEntry> entries;

  /// 0-based active week; single-week sessions use 0. (REQ-PERIOD-040)
  final int week;

  /// live-set-editing AD-5 resolver ([SITE-8]) — see
  /// [_StandaloneBlock.plannedCountFor].
  final int Function(RoutineSlot) plannedCountFor;
  final void Function(
      RoutineSlot slot, int setNumber, int reps, double weightKg) onSetCheck;
  final void Function(SetLog existing, int reps, double weightKg) onSetUpdate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Vueltas totales = el ejercicio más largo del bloque.
    final maxRounds = entries.fold<int>(
        0, (m, e) => plannedCountFor(e.slot) > m ? plannedCountFor(e.slot) : m);

    // Scan round-robin: la celda activa es el primer par (vuelta, ejercicio)
    // que aún no fue logueado.
    String? activeId;
    int? activeSet;
    var activeRound = 0;
    outer:
    for (var round = 1; round <= maxRounds; round++) {
      for (final e in entries) {
        if (round > plannedCountFor(e.slot)) continue;
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
        totalSets: plannedCountFor(e.slot),
        techniqueInstructions: e.technique,
        videoUrl: e.videoUrl,
        onSetCheck: (setNumber, reps, weightKg) =>
            onSetCheck(e.slot, setNumber, reps, weightKg),
        onSetUpdate: onSetUpdate,
        // Superset add/remove UI is out of scope this change (AD-5 note).
        onAddSet: null,
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
    required this.totalSets,
    required this.techniqueInstructions,
    required this.videoUrl,
    required this.onSetCheck,
    required this.onSetUpdate,
    this.onAddSet,
    this.onRemoveSet,
  });

  final RoutineSlot slot;
  final List<SetLog> logsForExercise;

  /// Set (1-based) que debe estar activo. Null ⇒ ningún set activo.
  final int? currentSetNumber;

  /// 0-based active week; single-week sessions use 0. (REQ-PERIOD-040)
  final int week;

  /// live-set-editing AD-5/[SITE-9] resolved "sets today" — the render loop
  /// bound. Replaces the previous direct read of
  /// `slot.effectiveSetsForWeek(week).length`, so an add/remove is reflected
  /// in the number of rows drawn, not just the completion math.
  final int totalSets;
  final List<String>? techniqueInstructions;
  final String? videoUrl;

  final void Function(int setNumber, int reps, double weightKg) onSetCheck;
  final void Function(SetLog existing, int reps, double weightKg) onSetUpdate;

  /// "+ agregar serie" callback (AD-6). Null ⇒ affordance hidden (e.g.
  /// superset members this change, or a write already in flight).
  final VoidCallback? onAddSet;

  /// Per-row delete icon callback (AD-2/AD-6). `log` is `null` for the
  /// pending/unlogged row (single tap, no confirm) — the caller decides
  /// whether to show the confirmation dialog (see
  /// `_SessionPlayerScreenState._onRemoveSetTapped`). Null ⇒ affordance
  /// hidden (e.g. superset members this change).
  final void Function(SetLog? log)? onRemoveSet;

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
    // live-set-editing [SITE-9]: the render loop bound is the resolved
    // session-local count, NOT effectiveSets.length — an added-beyond-plan
    // row must draw even though it has no SetSpec.
    final totalSets = widget.totalSets;
    final isDone = loggedCount >= totalSets;
    final mode = widget.slot.effectiveExerciseMode;

    final int? nextPendingSetNumber = widget.currentSetNumber;

    final rowWidgets = <Widget>[];
    for (var idx = 0; idx < totalSets; idx++) {
      final setNumber = idx + 1;
      // AD-4: idx beyond the plan's effectiveSets has no SetSpec — an added
      // row is bare free-entry, never synthesized from the previous set.
      final SetSpec? spec =
          idx < effectiveSets.length ? effectiveSets[idx] : null;
      final logged = widget.logsForExercise
          .where((l) => l.setNumber == setNumber)
          .firstOrNull;
      final isRowDone = logged != null;
      final isCurrent = !isRowDone && setNumber == nextPendingSetNumber;
      final isExpanded =
          isCurrent || (isRowDone && _expandedDoneSets.contains(setNumber));

      // For duration sets, the logged weight is 0.
      // For reps sets, the logged weight comes from the log or planned spec.
      // spec == null (added row) → no planned target → 0, never prefilled
      // from the previous logged set (AD-4 rejected-alternative guard).
      final plannedWeight = spec == null
          ? 0.0
          : spec.weightKg ?? widget.slot.targetWeightKg ?? 0.0;
      final initialWeight = isRowDone ? logged.weightKg : plannedWeight;
      final plannedReps = plannedRepsForSpec(spec, mode);

      final specDurationSeconds = spec?.durationSeconds;
      final isDurationSet = spec != null &&
          (mode == ExerciseMode.duration ||
              (specDurationSeconds != null && specDurationSeconds > 0));
      final targetSeconds = isDurationSet ? (specDurationSeconds ?? 0) : 0;

      final isFutureSet = !isRowDone && !isCurrent;
      // live-set-editing AD-6: the delete icon shows on LOGGED rows and on
      // an added-but-unlogged pending row (spec == null, beyond the plan) —
      // NOT on a normal within-plan pending/future row.
      final isAddedUnlogged = !isRowDone && spec == null;
      final showRemoveIcon =
          widget.onRemoveSet != null && (isRowDone || isAddedUnlogged);

      Widget innerRow = isDurationSet
          ? _DurationSetRow(
              key: ValueKey('dur-$setNumber-${logged?.id ?? "pending"}'),
              setNumber: setNumber,
              targetSeconds: targetSeconds,
              isDone: isRowDone,
              onDone:
                  isCurrent ? () => widget.onSetCheck(setNumber, 0, 0.0) : null,
            )
          : _RepsSetRow(
              key: ValueKey('set-$setNumber-${logged?.id ?? "pending"}'),
              setNumber: setNumber,
              spec: spec,
              mode: mode,
              plannedReps: plannedReps,
              // For done rows preserve the athlete's original entry so
              // re-editing does not silently snap back to the planned
              // value; for pending rows preload with the planned target.
              initialReps: isRowDone ? logged.reps : plannedReps,
              initialWeightKg: initialWeight,
              isDone: isRowDone,
              isExpanded: isExpanded,
              onCheck: isCurrent
                  ? (reps, weightKg) =>
                      widget.onSetCheck(setNumber, reps, weightKg)
                  : null,
              onSetUpdate: isRowDone
                  ? (reps, weightKg) =>
                      widget.onSetUpdate(logged, reps, weightKg)
                  : null,
              onSummaryTap: isRowDone ? () => _toggleDoneRow(setNumber) : null,
            );

      if (showRemoveIcon) {
        innerRow = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: innerRow),
            _RemoveSetIcon(
              onTap: () => widget.onRemoveSet!(logged),
            ),
          ],
        );
      }

      Widget rowWidget = Padding(
        padding: EdgeInsets.only(top: rowWidgets.isEmpty ? 0 : 8),
        child: innerRow,
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
                  label:
                      l10n.sessionPlayerTechniqueA11y(widget.slot.exerciseName),
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
          // PF's per-exercise note — shown only on the CURRENT exercise block
          // (currentSetNumber != null) and only when non-empty. Read-only;
          // distinct from the technique ⓘ via the "DEL COACH" tag.
          if (widget.currentSetNumber != null &&
              (widget.slot.notes?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            CoachNote(text: widget.slot.notes!),
          ],
          const SizedBox(height: 12),
          ...rowWidgets,
          if (widget.onAddSet != null) ...[
            const SizedBox(height: 8),
            _AddSetButton(onTap: widget.onAddSet!),
          ],
        ],
      ),
    );
  }
}

// ── _AddSetButton ─────────────────────────────────────────────────────────────

/// "+ agregar serie" (live-set-editing AD-6). Botón sutil full-width al pie
/// del bloque interactivo de un ejercicio. Al tocar, dispara
/// [SessionNotifier.addSet] — la fila nueva se renderiza vacía (AD-4) y el
/// write real ocurre cuando el athlete la completa vía el check existente.
///
/// TREINO Motion PR3: TreinoTappable reemplaza al Material+InkWell — el
/// scale de presión sustituye al ripple como feedback (reemplazo limpio,
/// un solo manejador de tap).
class _AddSetButton extends StatelessWidget {
  const _AddSetButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(TreinoIcon.plus, size: 16, color: palette.accent),
            const SizedBox(width: 8),
            Text(
              'agregar serie',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.6,
                color: palette.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _RemoveSetIcon ────────────────────────────────────────────────────────────

/// Trailing delete icon per row (live-set-editing AD-2/AD-6). Static, NOT
/// swipe — matches the exploration's accessibility/discoverability
/// rationale. Shown on logged rows and on an added-but-unlogged pending row.
/// The caller (`_SessionPlayerScreenState._onRemoveSetTapped`) decides
/// whether to show the confirmation dialog based on whether the row was
/// logged.
class _RemoveSetIcon extends StatelessWidget {
  const _RemoveSetIcon({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Semantics(
      button: true,
      label: l10n.sessionPlayerRemoveSetA11y,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(TreinoIcon.trash, color: palette.textMuted, size: 18),
        ),
      ),
    );
  }
}

// ── _RemoveSetConfirmDialog ───────────────────────────────────────────────────

/// Confirmation dialog shown before deleting a LOGGED set (data loss).
/// live-set-editing AD-6 — same family as [_AbandonConfirmDialog].
class _RemoveSetConfirmDialog extends StatelessWidget {
  const _RemoveSetConfirmDialog({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        'Eliminar serie',
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: palette.textPrimary,
        ),
      ),
      content: Text(
        'Se va a borrar esta serie registrada.',
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
            'Eliminar',
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

// ── _RepsSetRow ───────────────────────────────────────────────────────────────

/// Fila de un set basado en reps.
/// - Reps: TextField numérico (entero). Pre-rellena con [plannedReps] (para
///   rangos, `repsMax`). El athlete puede loggear más o menos reps que las
///   planned — el rango del PF queda como referencia, no jaula.
/// - Peso: TextField numérico (teclado decimal).
/// - Check: marca el set como done con los valores actuales de reps y peso.
class _RepsSetRow extends StatefulWidget {
  const _RepsSetRow({
    super.key,
    required this.setNumber,
    required this.spec,
    required this.mode,
    required this.plannedReps,
    required this.initialReps,
    required this.initialWeightKg,
    required this.isDone,
    required this.isExpanded,
    required this.onCheck,
    required this.onSetUpdate,
    required this.onSummaryTap,
  });

  final int setNumber;

  /// Null for an added-beyond-plan row (live-set-editing AD-4) — a bare row
  /// has no prescription. [_repsDisplayText] and [_summaryReps] guard this.
  final SetSpec? spec;
  final ExerciseMode mode;
  final int plannedReps;

  /// Reps preseleccionadas al montar la row: para rows done son las loggeadas
  /// (así el athlete puede reeditar sin perder lo que ya puso), para rows
  /// current/futuras son [plannedReps].
  final int initialReps;
  final double initialWeightKg;
  final bool isDone;
  final bool isExpanded;

  /// Called when the ☐ is tapped for a pending current row — (reps, weightKg).
  final void Function(int reps, double weightKg)? onCheck;

  /// Called when reps or weight change for a done row — (reps, weightKg).
  final void Function(int reps, double weightKg)? onSetUpdate;

  /// Tap on summary row — only active for done rows to toggle expand.
  final VoidCallback? onSummaryTap;

  @override
  State<_RepsSetRow> createState() => _RepsSetRowState();
}

class _RepsSetRowState extends State<_RepsSetRow> {
  late TextEditingController _weightController;
  late TextEditingController _repsController;
  late double _weightKg;
  late int _reps;

  @override
  void initState() {
    super.initState();
    // QA-WKT-003: clamp the prefill so a corrupt spec (or a legacy Firestore
    // doc written before the caps existed) can't seed an impossible value that
    // the athlete would then commit untouched by tapping the check.
    _weightKg = clampWeightKg(widget.initialWeightKg);
    _reps = clampReps(widget.initialReps);
    _weightController = TextEditingController(
      text: _weightKg == 0 ? '' : formatWeightKg(_weightKg),
    );
    _repsController = TextEditingController(
      text: _reps == 0 ? '' : _reps.toString(),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  void _onWeightChanged(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    // Empty/unparseable -> 0; out-of-range -> clamped to [0, 500]. This keeps
    // _weightKg in sync with what the user sees and with what gets logged,
    // instead of silently retaining a stale value.
    final next = clampWeightKg(parsed ?? 0);
    if (next == _weightKg) return;
    setState(() => _weightKg = next);
    if (widget.isDone) {
      widget.onSetUpdate?.call(_reps, _weightKg);
    }
  }

  void _onRepsChanged(String value) {
    // Empty/unparseable -> 0; clamp to [0, 999] to keep _reps in sync with
    // what the user sees. 0 is allowed as an intermediate typing state — the
    // check button is what commits the value; the parent's check handler
    // guards against 0-rep sets.
    final parsed = int.tryParse(value);
    final next = clampReps(parsed ?? 0);
    if (next == _reps) return;
    setState(() => _reps = next);
    if (widget.isDone) {
      widget.onSetUpdate?.call(_reps, _weightKg);
    }
  }

  void _onCheckTap() {
    widget.onCheck?.call(_reps, _weightKg);
  }

  String get _repsDisplayText => repsDisplayText(widget.spec, widget.mode);

  /// Reps label for the always-visible summary row. When the athlete has
  /// touched the reps field (or logged the set) we show the actual [_reps];
  /// otherwise fall back to the planned display so the range hint (e.g.
  /// "8–12 reps") stays visible until the athlete engages.
  String _summaryReps() {
    if (widget.isDone) return '$_reps reps';
    if (_reps != widget.plannedReps) return '$_reps reps';
    return _repsDisplayText;
  }

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
            // Summary line — shows the actual _reps (which the athlete may
            // have edited) rather than the planned range. Falls back to the
            // planned display when the row is not done and _reps still equals
            // plannedReps, so the range hint stays visible pre-check.
            child: Text(
              '${_summaryReps()} · ${formatWeightKg(_weightKg)} kg',
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
            // TREINO Motion PR3: TreinoTappable reemplaza al GestureDetector
            // (absorbe su onTap) — el check de set es EL tap más frecuente
            // de una sesión, feedback de presión obligado.
            child: TreinoTappable(
              onTap: widget.isDone ? widget.onSummaryTap : _onCheckTap,
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

    // Expanded panel: editable reps field + editable weight field.
    final expandedPanel = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const SizedBox(width: 32),
          // Editable reps field — pre-filled with planned reps (repsMax for
          // ranges). Athlete overrides freely if they hit more or fewer.
          Expanded(
            child: _RepsField(
              controller: _repsController,
              textColor: textColor,
              onChanged: _onRepsChanged,
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
            duration: AppMotion.base,
            curve: AppMotion.emphasized,
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
        inputFormatters: const [
          // QA-WKT-002/003: single separator + hard cap so the field text can
          // never diverge from the value that gets logged, nor exceed 500 kg.
          BoundedNumberFormatter(max: kMaxWeightKg, decimal: true),
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

// ── _RepsField ────────────────────────────────────────────────────────────────

/// Editable integer text field for reps input.
/// Same underline style as [_WeightField] with a "reps" suffix. Digits only,
/// no decimals — reps are always integer.
class _RepsField extends StatelessWidget {
  const _RepsField({
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
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        textAlign: TextAlign.center,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: textColor,
        ),
        decoration: InputDecoration(
          hintText: '0 reps',
          hintStyle: GoogleFonts.barlow(
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: palette.textMuted,
          ),
          suffix: Text(
            'reps',
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
              // TREINO Motion PR3: TreinoTappable reemplaza al
              // GestureDetector (absorbe su onTap). onTap null cuando no es
              // interactivo → child pelado, mismo no-op que antes.
              child: TreinoTappable(
                onTap: isInteractive ? _startTimer : null,
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
