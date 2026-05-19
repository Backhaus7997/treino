import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../profile/application/user_providers.dart';
import '../../feed/domain/gym_name.dart';
import '../application/exercise_providers.dart';
import '../application/routine_providers.dart';
import '../application/session_init.dart';
import '../application/session_providers.dart';
import '../application/session_state.dart';
import '../domain/routine.dart';
import '../domain/routine_slot.dart';
import '../domain/set_log.dart';
import 'widgets/set_entry_sheet.dart';

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
  // Marca que evita que el PopScope dispare el dialog de abandono cuando la
  // salida es intencional (TERMINAR o ABANDONAR confirmado). Sin esta marca,
  // context.go() pide al Navigator un pop que PopScope intercepta y dispara
  // showDialog en paralelo a la navegación — produce `!_debugLocked` assertion.
  bool _isFinalizing = false;

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
    await notifier.abandonSession();
    // Abandonar = salir, no celebrar. Navegación explícita al tab Workout
    // (evita revelar rutas residuales como /workout/session-summary del
    // stack — context.pop() depende del historial y puede caer ahí). La
    // sesión queda persistida como finished + wasFullyCompleted=false:
    // sets guardados, no aparece como activa para el resume.
    if (mounted) {
      context.go('/workout');
    }
  }

  Future<void> _finishSession() async {
    final notifier = ref.read(sessionNotifierProvider(widget.init).notifier);
    final sessionId =
        ref.read(sessionNotifierProvider(widget.init)).value?.session.id;
    _isFinalizing = true;
    await notifier.finishSession();
    if (mounted && sessionId != null) {
      context.go('/workout/session-summary/$sessionId');
    }
  }

  /// Loguea un set directamente sin pasar por la sheet. Llamado por el
  /// botón ☐ inline en cada fila — usa los valores actuales del stepper.
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

  /// Actualiza un set ya logueado con nuevos reps/peso. Llamado por el
  /// stepper inline cuando el usuario edita una fila done.
  void _updateSet(SetLog existing, int reps, double weightKg) {
    final updated = existing.copyWith(reps: reps, weightKg: weightKg);
    ref.read(sessionNotifierProvider(widget.init).notifier).updateSet(updated);
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
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    // ClampingScrollPhysics evita el efecto bouncing/stretch
                    // de iOS que estira y deforma las cards en overscroll.
                    physics: const ClampingScrollPhysics(),
                    children: [
                      const SizedBox(height: 12),
                      const _AttendanceCard(),
                      const SizedBox(height: 14),
                      _SessionStatsCard(state: state),
                      const SizedBox(height: 20),
                      const _SectionLabel('EJERCICIOS'),
                      const SizedBox(height: 12),
                      ...state.day.slots.expand((slot) {
                        final logsForExercise = state.setLogs
                            .where((l) => l.exerciseId == slot.exerciseId)
                            .toList()
                          ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
                        final exerciseAsync =
                            ref.watch(exerciseByIdProvider(slot.exerciseId));
                        return [
                          _ExerciseSection(
                            slot: slot,
                            logsForExercise: logsForExercise,
                            techniqueInstructions: exerciseAsync
                                .valueOrNull?.techniqueInstructions,
                            videoUrl: exerciseAsync.valueOrNull?.videoUrl,
                            onSetCheck: (setNumber, reps, weightKg) =>
                                _logSet(slot, setNumber, reps, weightKg),
                            onSetUpdate: (existing, reps, weightKg) =>
                                _updateSet(existing, reps, weightKg),
                          ),
                          const SizedBox(height: 14),
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

// ── _ExerciseSection + _SetRow + _StepperCell ────────────────────────────────

String _formatWeight(double w) =>
    w == w.truncateToDouble() ? w.toInt().toString() : w.toString();

/// Sección de un ejercicio. Render condicional por fila:
/// - Sets ya logueados: fila compacta (tappable para expandir y editar).
/// - Set actual (siguiente pendiente): fila expandida con steppers.
/// - Sets futuros (pendientes después del actual): NO se muestran.
class _ExerciseSection extends StatefulWidget {
  const _ExerciseSection({
    required this.slot,
    required this.logsForExercise,
    required this.techniqueInstructions,
    required this.videoUrl,
    required this.onSetCheck,
    required this.onSetUpdate,
  });

  final RoutineSlot slot;
  final List<SetLog> logsForExercise; // ordenados por setNumber ASC
  final List<String>? techniqueInstructions;
  final String? videoUrl;

  /// Loguea una fila pendiente con los valores actuales del stepper.
  final void Function(int setNumber, int reps, double weightKg) onSetCheck;

  /// Actualiza una fila ya logueada cuando el usuario cambia el stepper.
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

  /// Defaults para la fila actual (la siguiente pendiente).
  ({int reps, double weightKg}) _defaultsForRow() {
    if (widget.logsForExercise.isNotEmpty) {
      final last = widget.logsForExercise.last;
      return (reps: last.reps, weightKg: last.weightKg);
    }
    return (
      reps: widget.slot.targetRepsMin,
      weightKg: widget.slot.targetWeightKg ?? 0.0,
    );
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
    final loggedCount = widget.logsForExercise.length;
    final isDone = loggedCount >= widget.slot.targetSets;
    final defaults = _defaultsForRow();

    // Índice (1-based) de la siguiente serie pendiente. Si no quedan
    // pendientes, es null y el ejercicio está completo.
    final int? nextPendingSetNumber = isDone ? null : loggedCount + 1;

    // Lista de widgets — TODOS los sets visibles. La fila "actual" (la
    // siguiente pendiente) viene con el panel de steppers desplegado.
    // Los done pueden desplegarse manualmente para editar. Los futuros
    // pendientes muestran solo el resumen (sin steppers).
    final rowWidgets = <Widget>[];
    for (var setNumber = 1; setNumber <= widget.slot.targetSets; setNumber++) {
      final logged = widget.logsForExercise
          .where((l) => l.setNumber == setNumber)
          .firstOrNull;
      final isRowDone = logged != null;
      final isCurrent = !isRowDone && setNumber == nextPendingSetNumber;
      final isExpanded =
          isCurrent || (isRowDone && _expandedDoneSets.contains(setNumber));

      final initialReps = isRowDone ? logged.reps : defaults.reps;
      final initialWeight = isRowDone ? logged.weightKg : defaults.weightKg;

      rowWidgets.add(
        Padding(
          padding: EdgeInsets.only(top: rowWidgets.isEmpty ? 0 : 8),
          child: _SetRow(
            // Key estable para que el state del row sobreviva entre rebuilds
            // de la sección, pero distinta entre id-de-log distintos (al
            // pasar de pending a done se monta un row nuevo).
            key: ValueKey('set-$setNumber-${logged?.id ?? "pending"}'),
            setNumber: setNumber,
            initialReps: initialReps,
            initialWeightKg: initialWeight,
            isDone: isRowDone,
            isExpanded: isExpanded,
            onCheck: isCurrent
                ? (reps, weightKg) =>
                    widget.onSetCheck(setNumber, reps, weightKg)
                : null,
            onUpdate: isRowDone
                ? (reps, weightKg) => widget.onSetUpdate(logged, reps, weightKg)
                : null,
            onSummaryTap: isRowDone ? () => _toggleDoneRow(setNumber) : null,
          ),
        ),
      );
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
          // Header: icono + nombre + ⓘ (opcional) + progreso "X/N"
          Row(
            children: [
              Icon(
                isDone
                    ? TreinoIcon.checkCircleFill
                    : TreinoIcon.checkCircleEmpty,
                color: isDone ? palette.accent : palette.textMuted,
                size: 22,
              ),
              const SizedBox(width: 12),
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
                GestureDetector(
                  onTap: () => _showTechnique(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      TreinoIcon.infoCircle,
                      size: 20,
                      color: palette.textMuted,
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
                  '$loggedCount/${widget.slot.targetSets}',
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

/// Fila de un set individual. Estructura:
/// - Summary row siempre visible: número + "X reps · Y kg" + status icon.
/// - Panel de steppers desplegable hacia abajo (AnimatedSize). Se muestra
///   solo cuando `isExpanded == true` (set actual o set done que el
///   usuario tocó para editar).
///
/// Para sets pending no-actuales (futuros), el row muestra solo el summary
/// con valores "proyectados" (defaults) — no interactivo hasta que se
/// vuelva el actual.
class _SetRow extends StatefulWidget {
  const _SetRow({
    super.key,
    required this.setNumber,
    required this.initialReps,
    required this.initialWeightKg,
    required this.isDone,
    required this.isExpanded,
    required this.onCheck,
    required this.onUpdate,
    required this.onSummaryTap,
  });

  final int setNumber;
  final int initialReps;
  final double initialWeightKg;
  final bool isDone;
  final bool isExpanded;

  /// Llamado al tap del ☐ en filas pendientes actuales con (reps, weightKg).
  final void Function(int reps, double weightKg)? onCheck;

  /// Llamado al cambiar el stepper de una fila done — persiste el cambio
  /// inmediatamente vía notifier.updateSet.
  final void Function(int reps, double weightKg)? onUpdate;

  /// Tap en la summary row — solo activo en filas done para toggle expand.
  final VoidCallback? onSummaryTap;

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late int _reps;
  late double _weightKg;

  @override
  void initState() {
    super.initState();
    _reps = widget.initialReps;
    _weightKg = widget.initialWeightKg;
  }

  void _changeReps(int delta) {
    setState(() => _reps = (_reps + delta).clamp(0, 50));
    if (widget.isDone) widget.onUpdate?.call(_reps, _weightKg);
  }

  void _changeWeight(double delta) {
    setState(() => _weightKg = (_weightKg + delta).clamp(0.0, 500.0));
    if (widget.isDone) widget.onUpdate?.call(_reps, _weightKg);
  }

  void _onCheckTap() {
    widget.onCheck?.call(_reps, _weightKg);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textColor = widget.isDone ? palette.textMuted : palette.textPrimary;
    final canTapCheck =
        widget.isDone ? widget.onSummaryTap != null : widget.onCheck != null;

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
              '$_reps reps · ${_formatWeight(_weightKg)} kg',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: textColor,
              ),
            ),
          ),
          GestureDetector(
            onTap: canTapCheck
                ? (widget.isDone ? widget.onSummaryTap : _onCheckTap)
                : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
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
        ],
      ),
    );

    // Panel de steppers que se despliega hacia abajo cuando isExpanded.
    final stepperPanel = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const SizedBox(width: 32), // alineación con number
          Expanded(
            child: _StepperCell(
              value: '$_reps',
              suffix: 'reps',
              onDecrement: () => _changeReps(-1),
              onIncrement: () => _changeReps(1),
              textColor: textColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StepperCell(
              value: _formatWeight(_weightKg),
              suffix: 'kg',
              onDecrement: () => _changeWeight(-2.5),
              onIncrement: () => _changeWeight(2.5),
              textColor: textColor,
            ),
          ),
          const SizedBox(width: 32), // alineación con check icon
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
                ? stepperPanel
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Stepper compacto inline: −  valor suffix  +
class _StepperCell extends StatelessWidget {
  const _StepperCell({
    required this.value,
    required this.suffix,
    required this.onDecrement,
    required this.onIncrement,
    required this.textColor,
  });

  final String value;
  final String suffix;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepperButton(icon: '−', onTap: onDecrement),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$value $suffix',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StepperButton(icon: '+', onTap: onIncrement),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.bgCard,
          border: Border.all(color: palette.border),
        ),
        alignment: Alignment.center,
        child: Text(
          icon,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: palette.textPrimary,
          ),
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
