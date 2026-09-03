import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/utils/join_non_empty.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../../gyms/application/gym_providers.dart';
import '../../gyms/domain/gym_display_name.dart';
import '../../coach/application/trainer_link_providers.dart';
import '../application/duration_timer_providers.dart';
import '../application/exercise_providers.dart';
import '../application/routine_providers.dart';
import '../application/session_init.dart';
import '../application/session_notifier.dart';
import '../application/session_providers.dart';
import '../application/phone_duration_timer.dart';
import '../application/session_state.dart';
import '../application/workout_clock.dart';
import '../domain/duration_timer.dart';
import '../domain/routine.dart';
import '../domain/superset_order.dart';
import '../domain/routine_slot.dart';
import '../domain/superset_blocks.dart';
import '../domain/set_enums.dart';
import '../domain/set_limits.dart';
import '../domain/session_time_fit.dart';
import '../domain/set_log.dart';
import '../../watch/application/watch_effort_notifier.dart';
import '../../watch/application/watch_timer_control_notifier.dart';
import '../../watch/domain/watch_effort.dart';
import '../domain/set_spec.dart';
import 'exercise_detail_screen.dart';
import 'widgets/bounded_number_formatter.dart';
import 'widgets/coach_note.dart';
import 'widgets/duration_set_row.dart';
import 'widgets/exercise_feedback_sheet.dart';
import 'widgets/mmss.dart';
import 'widgets/set_entry_sheet.dart';
import 'widgets/time_fit_sheet.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

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
/// El agrupamiento en sí vive en `superset_blocks.dart`, o sea en DOMINIO.
///
/// Estaba acá adentro, y por eso el companion de Wear no lo vio nunca: aplanaba
/// los slots del día en una lista lineal y trataba una superserie A/B/C como
/// tres ejercicios sueltos. Ahora los dos lados leen la misma definición de
/// bloque y no pueden volver a divergir. Esta función sólo la envuelve en el
/// tipo que consume la pantalla.
List<BlockInfo> buildBlocks(List<RoutineSlot> slots) => [
      for (final posiciones
          in supersetBlockIndices([for (final s in slots) s.supersetGroup]))
        (
          slots: [for (final i in posiciones) slots[i]],
          isSuperset: posiciones.length >= 2,
        ),
    ];

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
    return formatMMSS(secs);
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

  /// El cronómetro por tiempo que corre en este teléfono.
  ///
  /// La PANTALLA es la autoridad de completado, no la fila. La fila se desmonta
  /// al scrollear —el `ListView` de ejercicios no tiene keep-alive— y con ella
  /// moría la cuenta: el tiempo se perdía y nadie marcaba la serie. Esta
  /// pantalla, en cambio, está montada todo el tiempo que el player está
  /// abierto, y además es la que tiene los slots para armar el `SetLog`.
  PhoneDurationTimerNotifier? _cronometro;
  Timer? _cronometroTick;

  /// El canal por el que el RELOJ pide cortar la cuenta del teléfono.
  WatchTimerControlNotifier? _controlDelReloj;

  /// El contenedor del `ProviderScope` que ESTA pantalla monta en su rama
  /// `data`, capturado para poder escribir desde el `State`.
  ///
  /// Parece un rodeo y no lo es (#817). `durationTimerRecorderProvider` declara
  /// `dependencies: [playerSessionIdProvider]`, o sea que sólo resuelve la
  /// sesión DENTRO de ese scope. Y el `ref` de este `State` cuelga del elemento
  /// de la pantalla, que está ARRIBA del scope que la propia pantalla crea en
  /// `build`: leer el recorder desde acá con `ref.read` devuelve uno cuyo
  /// `playerSessionIdProvider` es el default `null`, así que `borrar()` no
  /// borra nada — y no falla, no loguea, no deja rastro. Un fix que no borra y
  /// no rompe es peor que el bug, porque además parece arreglado.
  ///
  /// Se guarda el CONTENEDOR y no el `WidgetRef`: el contenedor es un objeto
  /// plano, estable mientras el scope viva, y no ata nada al ciclo de vida de
  /// un widget que se reconstruye en cada frame.
  ProviderContainer? _contenedorDelPlayer;

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
      _notifier!.finishedElsewhere.addListener(_onFinishedElsewhere);

      final cronometro = ref.read(phoneDurationTimerProvider);
      cronometro.addListener(_onCronometroCambio);
      _cronometro = cronometro;

      final control = ref.read(watchTimerControlNotifierProvider);
      control.addListener(_onElRelojPideCancelar);
      _controlDelReloj = control;
      _onCronometroCambio();
    });
  }

  /// Arranca o corta el tick que vigila el vencimiento de la cuenta.
  ///
  /// Es UNO por pantalla, no uno por fila: la cuenta es una sola.
  void _onCronometroCambio() {
    final hay = _cronometro?.value != null;
    if (hay && _cronometroTick == null) {
      _cronometroTick = Timer.periodic(
        DurationTimerRules.tickInterval,
        (_) => _revisarCronometro(),
      );
    } else if (!hay && _cronometroTick != null) {
      _cronometroTick!.cancel();
      _cronometroTick = null;
    }
  }

  /// La cuenta llegó a cero: vibra y marca la serie.
  ///
  /// Corre acá y no en la fila para que el scroll no pueda impedirlo. Al reloj
  /// NO se le avisa: llega a cero solo, porque cuenta contra el mismo instante
  /// de fin.
  void _revisarCronometro() {
    final cuenta = _cronometro?.value;
    if (cuenta == null) return;
    final ahora = ref.read(workoutClockProvider)().toUtc();
    if (!DurationTimerRules.isFinished(endsAt: cuenta.endsAt, now: ahora)) {
      return;
    }

    // Se limpia ANTES de marcar: `logSet` puede fallar y dejar la fila
    // interactiva a propósito, y con la cuenta vencida todavía puesta el botón
    // "Iniciar" quedaría muerto.
    _cronometro!.clear();
    // Y con el estado local se va también la anotación de la sesión (#817).
    // `clear()` toca sólo el `ValueNotifier` —a propósito: no le avisa al
    // reloj, que llega a cero solo—, así que hasta acá el fin natural de la
    // cuenta era el ÚNICO camino que no borraba el espejo de Firestore: los
    // dos que sí borraban cubren cancelaciones (la fila y el pedido del
    // reloj). El dato quedaba huérfano y el companion de Wear, que espeja lo
    // anotado en la sesión, podía mostrar horas después un cronómetro vencido
    // que nadie limpió. `wearTimerAjenoProvider` ya documentaba este borrado
    // como un hecho ("el teléfono borra el documento al llegar a cero") — el
    // teléfono era el que no cumplía.
    _borrarAnotacionDelCronometro();
    HapticFeedback.heavyImpact();

    final slot = _slotDe(cuenta.exerciseId);
    if (slot == null) return;
    _logSet(slot, cuenta.setNumber, 0, 0.0);
  }

  /// Saca de la sesión la anotación del cronómetro que acaba de terminar.
  ///
  /// ── Por qué no se espera ──────────────────────────────────────────────────
  ///
  /// Igual que los otros dos borrados (`duration_set_row` cuando cancela el
  /// teléfono, `WearTimerSync.cancelar` cuando cancela el reloj): la escritura
  /// es el ESPEJO, no la serie. `DurationTimerRecorder.borrar()` es `void` y ya
  /// hace `unawaited` con su propio `catchError` adentro, así que no hay nada
  /// que esperar ni forma de esperarlo. Atar la vibración y el marcado de la
  /// serie al ack del servidor es exactamente el error que costó tres bugs en
  /// este ciclo: sin señal en el gimnasio, el atleta se queda mirando.
  ///
  /// ── Y por qué acá arriba y no después de `_logSet` ────────────────────────
  ///
  /// No hay carrera entre las dos escrituras: ésta borra campos del documento
  /// de la sesión con `merge`, y `_logSet` crea un documento en la
  /// subcolección `setLogs` — no se pisan, y ningún camino de log vuelve a
  /// escribir los campos del timer. Pero el orden igual importa por otra
  /// razón: abajo hay un `return` temprano si el slot ya no está en el día, y
  /// con el borrado después de ese `return` el caso raro volvería a dejar la
  /// anotación colgada. Se borra en el mismo punto en que se corta el estado
  /// local, que es donde la cuenta termina de verdad.
  void _borrarAnotacionDelCronometro() {
    final contenedor = _contenedorDelPlayer;
    // Sin scope montado no hay sesión resuelta y no hay nada que borrar: la
    // cuenta no pudo haber arrancado desde una fila que nunca se dibujó.
    if (contenedor == null) return;
    try {
      contenedor.read(durationTimerRecorderProvider).borrar();
    } catch (e) {
      // El scope puede haberse desmontado entre el tick y esta lectura (la
      // sesión dejó de ser `data`). Un espejo que no se limpia no puede tumbar
      // el entreno que está corriendo.
      debugPrint('[duration-timer] no se pudo borrar al llegar a cero — $e');
    }
  }

  /// El reloj pidió cortar la cuenta que corre acá.
  ///
  /// Se compara la IDENTIDAD: el pedido nombra la serie, y cancelar la
  /// equivocada le mataría al atleta una plancha que está aguantando.
  ///
  /// Se le contesta al reloj —`cancel()` avisa— y eso no es un eco: es el
  /// acuse. `WCSession` no da callback de éxito, así que sin esto la muñeca no
  /// sabe si el pedido llegó. El ida y vuelta termina ahí.
  void _onElRelojPideCancelar() {
    final pedido = _controlDelReloj?.value;
    final cuenta = _cronometro?.value;
    if (pedido == null || cuenta == null) return;
    if (!pedido.aplicaA(
      exerciseId: cuenta.exerciseId,
      setNumber: cuenta.setNumber,
    )) {
      return;
    }
    unawaited(_cronometro!.cancel());
  }

  /// El slot de un ejercicio del día, o null si ya no está.
  RoutineSlot? _slotDe(String exerciseId) {
    final day = ref.read(sessionNotifierProvider(widget.init)).value?.day;
    if (day == null) return null;
    for (final slot in day.slots) {
      if (slot.exerciseId == exerciseId) return slot;
    }
    return null;
  }

  @override
  void dispose() {
    _notifier?.logSetError.removeListener(_onLogSetError);
    _notifier?.finishedElsewhere.removeListener(_onFinishedElsewhere);
    _cronometro?.removeListener(_onCronometroCambio);
    _controlDelReloj?.removeListener(_onElRelojPideCancelar);
    _cronometroTick?.cancel();
    super.dispose();
  }

  /// El entreno se cerró desde el RELOJ. Se sale del player.
  ///
  /// Quedarse acá sería peor que salir: la sesión ya está terminada en el
  /// historial, con su volumen y su duración calculados, y cualquier cosa que
  /// el atleta marcara desde esta pantalla escribiría sobre un entreno cerrado.
  void _onFinishedElsewhere() {
    final notifier = _notifier;
    if (notifier == null || !notifier.finishedElsewhere.value) return;
    if (!mounted) return;
    final l10n = AppL10n.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.sessionFinishedOnWatch),
          behavior: SnackBarBehavior.floating,
        ),
      );
    // `canPop` para no explotar si el player ya no es la ruta de arriba (el
    // atleta pudo navegar a un ejercicio mientras el reloj cerraba).
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
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

  /// La ranura del ajuste de tiempo (#645): la invitacion a declararlo cuando
  /// no hay nada recortado, o el aviso con el resultado y el deshacer cuando
  /// si lo hay. Nunca las dos: un solo camino a mano en cada estado.
  ///
  /// Sin nada medible en el dia no se dibuja NADA. Ofrecer "ajustar" sobre una
  /// sesion cuya duracion no se puede estimar es prometer una cuenta que la
  /// pantalla despues no puede mostrar — misma postura que las tarjetas de
  /// rutina, que ante `minutes == null` no escriben ni "0 min" ni un guion.
  List<Widget> _buildTimeFitSlot(SessionState state) {
    if (state.droppedExerciseIds.isNotEmpty) {
      return [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _SessionTrimNotice(state: state, onUndo: _undoTrim),
        ),
      ];
    }
    final current = estimateSessionMinutes(state.day, week: state.activeWeek);
    if (current == null) return const [];
    return [
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _TimeFitPrompt(
          currentMinutes: current,
          onTap: () => _openTimeFit(state),
        ),
      ),
    ];
  }

  /// Builds the exercise list with block gating: current block fully expanded,
  /// completed blocks collapsed to summary, future blocks locked/dimmed.
  ///
  /// La lista se arma sobre [SessionState.activeSlots], no sobre `day.slots`:
  /// un ejercicio recortado (#645) no se dibuja. Dibujarlo lo mostraria como
  /// bloque COMPLETADO —`plannedSetsFor` le da 0 y `computeBlockStatuses` lee
  /// eso como "todo hecho"—, o sea, la lista le diria "lo hiciste" sobre algo
  /// que el atleta saco. Lo que salio se cuenta en `_SessionTrimNotice`, que
  /// es tambien donde esta el deshacer.
  ///
  /// Los indices de `_activatedBlocks` siguen siendo validos: el recorte es
  /// siempre una cola contigua del final (`planSessionTimeFit`), asi que lo
  /// que queda es un PREFIJO de los bloques y ningun indice se corre.
  List<Widget> _buildExerciseList(SessionState state) {
    final palette = AppPalette.of(context);
    // Source week ONCE here and thread down — single-week sessions use 0
    // so effectiveSetsForWeek(0) falls back to effectiveSets (REQ-PERIOD-042).
    final week = state.session.weekNumber;
    final blocks = buildBlocks(state.activeSlots.toList(growable: false));
    // live-set-editing AD-5: single resolver every gating/render denominator
    // routes through. Bound method closes over `state`, so callers never
    // read the raw plan count directly.
    final plannedCountFor = state.plannedSetsFor;
    final statuses =
        computeBlockStatuses(blocks, state.setLogs, week, plannedCountFor);

    // #628 — "Comentar / Reportar" sólo aparece si hay a QUIÉN reportarle.
    //
    // El riesgo de producto que el issue pide resolver es dejar al alumno
    // mandar al vacío creyendo que su PF lo lee. Sin vínculo `active` no hay
    // `session_shares` —lo crea `syncSessionShareOnTrainerLink` cuando el
    // vínculo se activa— así que el reporte no tendría destinatario. Se
    // esconde el CTA en vez de mostrarlo y explicar después: el alumno que
    // quiere registrar una molestia para sí mismo ya tiene el check-in
    // post-entreno (#643, dolor sí/no + zona), que es el lugar correcto.
    //
    // Es el MISMO provider que usa el resto de la app para "¿este alumno
    // tiene PF?" — no se lee `session_shares` desde el cliente, que además
    // es un doc que el cliente sólo escribe.
    final hasActiveTrainer =
        ref.watch(currentAthleteLinkProvider).valueOrNull != null;

    final out = <Widget>[];

    for (var blockIdx = 0; blockIdx < blocks.length; blockIdx++) {
      final block = blocks[blockIdx];
      final status = statuses[blockIdx];
      // Navegación libre: un bloque `future` puede estar destrabado a mano.
      final activated = _activatedBlocks.contains(blockIdx);
      final idx = blockIdx;

      if (block.isSuperset) {
        final entries = block.slots.map((s) => _entryFor(state, s)).toList();
        // Las superseries van edge-to-edge: su barra lateral magenta y tinte
        // de fondo son la delimitación del grupo, sin margen del wrapper.
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
          onOpenDetail: _openExerciseDetail,
          onFeedback: hasActiveTrainer ? _openExerciseFeedback : null,
        ));
      } else {
        final entry = _entryFor(state, block.slots.first);
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _StandaloneBlock(
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
            onOpenDetail: () => _openExerciseDetail(entry.slot),
            onFeedback: hasActiveTrainer
                ? (setNumber) => _openExerciseFeedback(entry.slot, setNumber)
                : null,
          ),
        ));
      }
      // Separador sutil entre bloques — reemplaza el encajonado en cards como
      // delimitación de la lista full-width.
      if (blockIdx != blocks.length - 1) {
        out.add(const SizedBox(height: 8));
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Divider(
            height: 1,
            thickness: 1,
            color: palette.border.withValues(alpha: 0.5),
          ),
        ));
        out.add(const SizedBox(height: 8));
      }
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

  /// Abre la hoja donde el atleta declara cuanto tiempo tiene hoy (#645).
  ///
  /// Los ejercicios que ya tienen series cargadas viajan como
  /// `lockedExerciseIds`: el recorte nunca puede esconder trabajo hecho, y el
  /// recorrido de `planSessionTimeFit` frena ahi.
  void _openTimeFit(SessionState state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TimeFitSheet(
        day: state.day,
        week: state.activeWeek,
        lockedExerciseIds: state.setLogs.map((l) => l.exerciseId).toSet(),
        onApply: _applyTrim,
      ),
    );
  }

  /// Aplica el recorte que el atleta acepto. Solo toca la sesion de hoy.
  void _applyTrim(List<String> exerciseIds) {
    ref
        .read(sessionNotifierProvider(widget.init).notifier)
        .dropExercisesForToday(exerciseIds);
  }

  /// Devuelve a la sesion todo lo que se habia recortado por tiempo (#645).
  void _undoTrim() {
    ref
        .read(sessionNotifierProvider(widget.init).notifier)
        .restoreDroppedExercises();
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

  /// Abre "Comentar / Reportar" para [slot] (#628).
  ///
  /// CONTRATO DEL ANCLA — [setNumber] es la ÚLTIMA serie que el atleta
  /// REALMENTE hizo en esa card, o null si todavía no hizo ninguna (reporte a
  /// nivel ejercicio). Una sola frase, verdadera en los tres call sites: card
  /// activa, bloque completado y miembro de superserie.
  ///
  /// NO es la serie en curso ni la pendiente. El dolor pasa en la serie que se
  /// soltó, no en la que falta, y del lado del PF `session_exercise_block.dart`
  /// matchea por `setNumber`: anclarlo una adelante deja la nota colgada de un
  /// log que no existe. Eso es justo lo que el chat no puede dar — el PF lo ve
  /// pegado a la serie que lo originó.
  ///
  /// Y null significa "todavía no hizo ninguna", NO "la card no está activa":
  /// el bloque completado no tiene serie en curso y aun así manda el número de
  /// su última serie hecha (ver [_CompletedBlockSummary]) — es el escenario que
  /// motivó el botón, la molestia aparece al soltar la última serie.
  ///
  /// No pausa el cronómetro ni toca el estado de la sesión: el sheet es una
  /// ruta modal aparte y esta pantalla sigue montada abajo.
  void _openExerciseFeedback(RoutineSlot slot, int? setNumber) {
    final uid = ref.read(currentUidProvider);
    final sessionId =
        ref.read(sessionNotifierProvider(widget.init)).value?.session.id;
    // Sin sesión persistida todavía no hay dónde anclar el reporte. El botón
    // ya no debería estar visible en ese estado; el guard es defensivo.
    if (uid == null || sessionId == null || sessionId.isEmpty) return;
    showExerciseFeedbackSheet(
      context,
      uid: uid,
      sessionId: sessionId,
      exerciseId: slot.exerciseId,
      exerciseName: slot.exerciseName,
      setNumber: setNumber,
    );
  }

  /// Abre el detalle completo del ejercicio (video hero + técnica + stats).
  ///
  /// Push IMPERATIVO con Scaffold host propio: el player es una ruta immersive
  /// fuera del ShellRoute, y pushear la ruta de shell `/workout/exercise/:id`
  /// desde acá monta el detalle sin _ShellScaffold → pantalla negra (mismo
  /// caso documentado en exercise_picker_sheet._openDetail).
  void _openExerciseDetail(RoutineSlot slot) {
    // Dueño de la rutina, para resolver custom exercises cuando el id no está
    // en el catálogo público: plan asignado → el trainer (assignedBy); rutina
    // propia del atleta → el atleta (createdBy). Mismo criterio que
    // routine_detail_screen.
    final routineId = switch (widget.init) {
      FreshSession(routineId: final rid) => rid,
      ResumeSession() =>
        ref.read(sessionNotifierProvider(widget.init)).value?.session.routineId,
    };
    final routine = routineId != null
        ? ref.read(routineByIdProvider(routineId)).valueOrNull
        : null;
    final ownerId = routine?.assignedBy ?? routine?.createdBy;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppPalette.of(context).bg,
          body: SafeArea(
            child: ExerciseDetailScreen(
              exerciseId: slot.exerciseId,
              ownerId: ownerId,
              exerciseName: slot.exerciseName,
            ),
          ),
        ),
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
        // El subarbol que dibuja ESTA sesion sabe cual es.
        //
        // Sin esto, la fila por tiempo tenia que deducirla —y la deducia con
        // `getActive`, una lectura que va al servidor primero y no tiene
        // timeout—: hasta que resolviera, el cronometro no se anotaba en la
        // sesion y el reloj nunca se enteraba, sin ningun sintoma de este lado.
        // Medido. El porque completo esta en [playerSessionIdProvider].
        //
        // Va en la rama `data` y no mas arriba porque es el unico punto donde
        // la sesion esta resuelta de verdad.
        data: (state) => ProviderScope(
          overrides: [
            playerSessionIdProvider.overrideWithValue(state.session.id),
          ],
          // El `Builder` existe para tomar el contexto de ADENTRO del scope
          // (#817): es la única forma de que el `State` —que cuelga de un
          // elemento de más arriba— alcance el contenedor donde el override de
          // la sesion vale. Ver [_contenedorDelPlayer]. Es una asignación
          // idempotente y sin `setState`, así que no reprograma el frame.
          child: Builder(
            builder: (scopeContext) {
              _contenedorDelPlayer = ProviderScope.containerOf(
                scopeContext,
                listen: false,
              );
              return _cuerpoDelPlayer(state, routineSplit);
            },
          ),
        ),
      ),
    );
  }

  /// El árbol del player, ya con la sesión resuelta.
  ///
  /// Vive afuera de `build` sólo para que el `Builder` que captura el contenedor
  /// del scope (#817) no empuje sesenta líneas de árbol dos niveles más adentro.
  /// El `context` que usa adentro es el mismo `State.context` de siempre, así
  /// que las búsquedas por herencia —`ScrollConfiguration.of`— resuelven igual.
  Widget _cuerpoDelPlayer(SessionState state, String routineSplit) {
    return PopScope(
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
                  // Sin padding horizontal global: las cards de arriba
                  // conservan su margen de 20, pero la zona EJERCICIOS
                  // corre full-width con margen propio reducido (12).
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: _AttendanceCard(),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _SessionStatsCard(state: state),
                    ),
                    ..._buildTimeFitSlot(state),
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: _SectionLabel('EJERCICIOS'),
                    ),
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
              // joinNonEmpty: while the routine resolves (or has no split)
              // the header degrades to "DÍA N" instead of " · DÍA N" (#550).
              joinNonEmpty(
                [routineSplit.toUpperCase(), 'DÍA $dayNumber'],
                ' · ',
              ),
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
                borderRadius: BorderRadius.circular(AppRadius.full),
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
    // Los ejercicios recortados (#645) no estan en el denominador: la barra
    // mide lo que se hace HOY, no lo que decia el plan.
    final total = state.activeExerciseCount;
    final completed = state.completedExerciseCount;
    final progress = total > 0 ? completed / total : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMMSS(state.elapsedSeconds),
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 40,
                      color: palette.accent,
                    ),
                  ),
                  const _WatchTimerRow(),
                  const _WatchEffortRow(),
                ],
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

// ── _TimeFitPrompt ────────────────────────────────────────────────────────────

/// La invitación a declarar el tiempo disponible, arriba del listado (#645).
///
/// Se dibuja sólo cuando NO hay nada recortado: una vez aplicado el ajuste,
/// este lugar lo ocupa `_SessionTrimNotice`, que muestra el resultado y el
/// deshacer. Dos estados de la misma ranura, nunca los dos juntos — así el
/// atleta siempre tiene un solo camino a mano y no puede apilar recortes sin
/// entender de dónde salió cada uno.
class _TimeFitPrompt extends StatelessWidget {
  const _TimeFitPrompt({required this.currentMinutes, required this.onTap});

  final int currentMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          // Contorno tenue en acento: es la unica fila de esta pantalla que
          // ABRE ALGO sin ser un ejercicio, y el chevron —la senal de "esto
          // lleva al detalle"— ya esta gastado en las filas del listado.
          border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(TreinoIcon.clock, size: 16, color: palette.accent),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sessionTimeFitPromptTitle,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1.2,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                  Text(
                    l10n.sessionTimeFitCurrent('~$currentMinutes'),
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
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

// ── _SessionTrimNotice ────────────────────────────────────────────────────────

/// El aviso de que la sesión de hoy va recortada para entrar en el tiempo que
/// el atleta declaró tener (#645).
///
/// Existe SÓLO cuando hay algo recortado, y es el único lugar de la pantalla
/// que nombra lo que salió: la lista de abajo dibuja la sesión de hoy y nada
/// más. Sin este aviso el recorte sería invisible —la sesión se vería como una
/// rutina más corta, sin rastro de la decisión— y no habría forma de volver
/// atrás. Por eso el deshacer vive acá y no escondido en un menú.
///
/// El número se recalcula sobre lo que QUEDA ([estimateSessionMinutes]), no
/// sobre el día del plan, y lleva siempre "~" porque siempre es calculado —
/// misma convención que la duración de las tarjetas (#639).
class _SessionTrimNotice extends StatelessWidget {
  const _SessionTrimNotice({required this.state, required this.onUndo});

  final SessionState state;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // En el orden del día, no en el orden en que se sacaron.
    final names = state.day.slots
        .where((s) => state.droppedExerciseIds.contains(s.exerciseId))
        .map((s) => s.exerciseName)
        .join(' · ');
    final minutes = estimateSessionMinutes(
      state.day,
      week: state.activeWeek,
      droppedExerciseIds: state.droppedExerciseIds,
    );

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.clock, size: 16, color: palette.accent),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (minutes != null) ...[
                  Text(
                    l10n.sessionTrimAdjustedTo('~$minutes'),
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1.2,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                ],
                Text(
                  l10n.sessionTrimDroppedList(names),
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUndo,
            child: Text(
              l10n.sessionTrimUndo,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5,
                color: palette.accent,
              ),
            ),
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
    this.onOpenDetail,
    this.onFeedback,
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

  /// Tap en el NOMBRE del ejercicio → detalle completo (video + técnica).
  /// En bloques `future` NO se wirea: ahí el tap ya significa "adelantar
  /// este bloque" y superponer destinos confunde.
  final VoidCallback? onOpenDetail;

  /// "Comentar / Reportar" al PF (#628). El ARGUMENTO es la ÚLTIMA serie que
  /// el atleta realmente hizo, o null si todavía no hizo ninguna (reporte a
  /// nivel ejercicio) — ver el contrato completo en [_openExerciseFeedback].
  /// NO es la serie en curso: los dos call sites de abajo pasan la última
  /// hecha, tanto el bloque completado (:1419) como la card activa (:1449).
  ///
  /// Que el CALLBACK sea null es otra cosa: ⇒ affordance oculta, que es lo que
  /// pasa cuando el atleta no tiene un vínculo `active` con un PF. Sin
  /// destinatario, el botón sería una promesa vacía.
  final void Function(int? setNumber)? onFeedback;

  @override
  Widget build(BuildContext context) {
    if (status == BlockStatus.completed) {
      return _CompletedBlockSummary(
        exerciseName: entry.slot.exerciseName,
        totalSets: plannedCountFor(entry.slot),
        onOpenDetail: onOpenDetail,
        // El reporte SIGUE disponible con el ejercicio terminado (#628). La
        // molestia que importa aparece muchas veces justo al soltar la última
        // serie, y hasta acá el bloque se colapsaba en el mismo frame y se
        // llevaba puesto el único acceso al canal.
        onFeedback: onFeedback,
        // ...y se ancla a la ÚLTIMA serie hecha, no a null. Este resumen ES el
        // escenario que motivó el botón, así que tirar el ancla justo acá era
        // regalar el dato más caro: el bloque completado no tiene serie EN
        // CURSO, pero sí tiene una última serie HECHA, que es lo que el
        // contrato pide (ver
        // [_SessionPlayerScreenState._openExerciseFeedback]).
        //
        // Y es la ÚNICA superficie del caso: dentro de _ExerciseSection el
        // camino `isDone == true` no se alcanza nunca para un standalone
        // —`isDone` ⇔ `status == completed`, mismo conteo y mismo resolver—,
        // así que el bloque terminado siempre cae en este widget.
        feedbackSetNumber: entry.logs.isNotEmpty ? entry.logs.length : null,
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
      // OJO: `currentSetNumber` y `feedbackSetNumber` NO son el mismo número y
      // no hay que volver a fusionarlos. El primero es la serie que TODAVÍA NO
      // se hizo (resalta la fila a completar) y el segundo es la última que SÍ
      // se hizo, que es a la que el reporte tiene que quedar anclado: si el
      // atleta cargó la serie 3 y le tira el hombro, el dolor pasó en la 3, no
      // en la 4 que ni existe. Fusionados, el reporte se guardaba con
      // `loggedCount + 1` y encima se perdía entero al terminar el ejercicio
      // (ahí `currentSetNumber` es null), así que del lado del PF la nota caía
      // bajo el log equivocado — `session_exercise_block.dart` matchea por
      // `setNumber`. Sin ninguna serie hecha el ancla es `null` (reporte a
      // nivel ejercicio), NO la serie 1: inventar la 1 persiste el reporte
      // contra una serie que el atleta no hizo — el mismo defecto que arriba,
      // corrido un lugar.
      feedbackSetNumber: loggedCount > 0 ? loggedCount : null,
      week: week,
      totalSets: totalSets,
      techniqueInstructions: entry.technique,
      videoUrl: entry.videoUrl,
      onSetCheck: onSetCheck,
      onSetUpdate: onSetUpdate,
      onAddSet: onAddSet,
      onRemoveSet: onRemoveSet,
      onOpenDetail: onOpenDetail,
      onFeedback: onFeedback,
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
    this.onOpenDetail,
    this.onFeedback,
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

  /// Tap en el nombre de un MIEMBRO → detalle de ese ejercicio. Solo se wirea
  /// en la sección interactiva; los resúmenes colapsados agrupan varios
  /// ejercicios en una fila y el destino sería ambiguo.
  final void Function(RoutineSlot slot)? onOpenDetail;

  /// "Comentar / Reportar" sobre un MIEMBRO de la superserie (#628). Se ancla
  /// al miembro, no al grupo: en una superserie el hombro te tira en UNO de
  /// los dos ejercicios, y esa es justo la información que el PF necesita.
  final void Function(RoutineSlot slot, int? setNumber)? onFeedback;

  @override
  Widget build(BuildContext context) {
    if (status == BlockStatus.completed) {
      // Mismo motivo que en _StandaloneBlock: la superserie terminada no puede
      // ser un callejón sin salida para el reporte (#628).
      return _CompletedSupersetSummary(
          entries: entries, onFeedback: onFeedback);
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
      onOpenDetail: onOpenDetail,
      onFeedback: onFeedback,
    );
  }
}

// ── _CompletedBlockSummary ────────────────────────────────────────────────────

/// Compact collapsed row for a completed standalone block. Sin card: fila
/// full-width plana (layout ampliado del player). Tap en el nombre → detalle
/// del ejercicio ([onOpenDetail]); el ícono de chat abre "Comentar / Reportar"
/// ([onFeedback]).
class _CompletedBlockSummary extends StatelessWidget {
  const _CompletedBlockSummary({
    required this.exerciseName,
    required this.totalSets,
    required this.feedbackSetNumber,
    this.onOpenDetail,
    this.onFeedback,
  });

  final String exerciseName;
  final int totalSets;
  final VoidCallback? onOpenDetail;

  /// Serie a la que se ancla el reporte: la ÚLTIMA que el atleta hizo en este
  /// ejercicio, o null si no hizo ninguna.
  ///
  /// Que el bloque esté cerrado NO significa reportar a nivel ejercicio. Es al
  /// revés: acá es donde el ancla más vale. La molestia se siente al soltar la
  /// última serie y el bloque colapsa en ese mismo frame, así que este resumen
  /// es la única puerta que le queda al atleta — mandarla con `null` tiraba
  /// justo el dato que el PF necesita para saber en qué serie pasó.
  final int? feedbackSetNumber;

  /// "Comentar / Reportar" al PF (#628). Recibe [feedbackSetNumber]. Null ⇒
  /// affordance oculta (sin PF vinculado no hay destinatario).
  final void Function(int? setNumber)? onFeedback;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // El tappable envuelve SOLO el nombre, no la fila entera: el botón de
    // reporte tiene que quedar afuera para que su propio nodo de semántica sea
    // alcanzable (anidado dentro del `button` de la fila, VoiceOver lo fusiona
    // y el atleta pierde la acción). Mismo armado que el header de
    // _ExerciseSection, que ya resolvió este par nombre + acciones.
    return Row(
      children: [
        Expanded(
          // hint (no label): el nombre descendiente ya se fusiona como label
          // del nodo — un label explícito duplicaría el nombre en VoiceOver.
          child: Semantics(
            button: onOpenDetail != null,
            hint: onOpenDetail != null ? 'Ver detalle del ejercicio' : null,
            child: TreinoTappable(
              onTap: onOpenDetail,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(TreinoIcon.checkBare, color: palette.accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              exerciseName.toUpperCase(),
                              style: GoogleFonts.barlowCondensed(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: 0.5,
                                color: palette.textMuted,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: palette.textMuted,
                              ),
                            ),
                          ),
                          // Señal de navegación pegada al nombre — misma regla
                          // que el header de _ExerciseSection: solo cuando el
                          // tap abre el detalle. Decorativa para VoiceOver
                          // (el hint de arriba ya anuncia la acción).
                          if (onOpenDetail != null) ...[
                            const SizedBox(width: 8),
                            ExcludeSemantics(
                              child: Icon(
                                TreinoIcon.chevronRight,
                                size: 14,
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onFeedback != null)
          _FeedbackIconButton(
            exerciseName: exerciseName,
            onTap: () => onFeedback!(feedbackSetNumber),
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
    );
  }
}

// ── _FeedbackIconButton ───────────────────────────────────────────────────────

/// El acceso a "Comentar / Reportar" (#628): 44x44, ícono de chat, sin caja.
///
/// Vive suelto porque lo usan TRES lugares — el header del ejercicio activo y
/// los dos resúmenes de bloque completado. Que el bloque terminado también lo
/// lleve es el punto: la molestia articular aparece casi siempre al soltar la
/// última serie, y ese es justo el frame en que el bloque colapsa.
class _FeedbackIconButton extends StatelessWidget {
  const _FeedbackIconButton({
    required this.exerciseName,
    required this.onTap,
  });

  /// Nombre del ejercicio ANCLADO (en superserie, el del miembro) — va al
  /// label de VoiceOver para que la acción no quede ambigua entre miembros.
  final String exerciseName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Semantics(
      button: true,
      label: l10n.exerciseFeedbackActionA11y(exerciseName),
      child: GestureDetector(
        key: const Key('exercise_feedback_open'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            TreinoIcon.chat,
            size: 20,
            color: palette.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── _CompletedSupersetSummary ─────────────────────────────────────────────────

/// Compact collapsed row for a completed superset block. Sin card: fila
/// edge-to-edge con barra lateral accent — conserva la identidad visual de
/// superserie (agrupación lateral) sin el encajonado.
class _CompletedSupersetSummary extends StatelessWidget {
  const _CompletedSupersetSummary({required this.entries, this.onFeedback});

  final List<_SupersetEntry> entries;

  /// "Comentar / Reportar" al PF (#628), anclado al MIEMBRO y a la ÚLTIMA serie
  /// que ese miembro hizo (null si no hizo ninguna). Que el bloque haya cerrado
  /// no vuelve el reporte "a nivel ejercicio": es justo al revés, acá el ancla
  /// es lo más valioso — ver [_CompletedBlockSummary.feedbackSetNumber].
  final void Function(RoutineSlot slot, int? setNumber)? onFeedback;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // CON PF vinculado los nombres se listan uno por línea en vez del clásico
    // "A · B" unido. No es cosmético: acá cuelga el reporte y en una superserie
    // el hombro te tira en UNO de los dos ejercicios. Con la línea unida el
    // botón no tendría a qué miembro apuntar —dos íconos de chat idénticos al
    // lado de un texto único es una moneda al aire, y en VoiceOver directamente
    // no se distinguen—, así que cada miembro se lleva su propia fila y su
    // propio botón.
    //
    // SIN PF vinculado ([onFeedback] null) vuelve la línea unida. El costo de
    // las N filas se paga sólo donde compra algo: el atleta sin PF nunca ve el
    // botón, y hacerle crecer un resumen COLAPSADO de 1 a N líneas es empeorar
    // la pantalla a cambio de nada. Ese caso además recupera el filtrado de
    // [joinNonEmpty] (#550), que el desglose por miembro no tiene.
    //
    // En el desglose los nombres vacíos se saltean por la misma razón que
    // joinNonEmpty los tira: una fila sin texto con un ícono de chat al lado es
    // un botón cuyo label de VoiceOver queda vacío — una acción que se anuncia
    // sin decir sobre qué.
    final named = [
      for (final e in entries)
        if (e.slot.exerciseName.trim().isNotEmpty) e,
    ];
    final nameStyle = GoogleFonts.barlowCondensed(
      fontWeight: FontWeight.w700,
      fontSize: 16,
      letterSpacing: 0.5,
      color: palette.textMuted,
      decoration: TextDecoration.lineThrough,
      decorationColor: palette.textMuted,
    );
    return Container(
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.04),
        border: Border(
          left: BorderSide(color: palette.accent, width: 3),
        ),
      ),
      padding: const EdgeInsets.all(12),
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
                if (onFeedback == null)
                  Text(
                    joinNonEmpty(entries.map((e) => e.slot.exerciseName), ' · ')
                        .toUpperCase(),
                    style: nameStyle,
                  )
                else
                  for (final e in named)
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.slot.exerciseName.toUpperCase(),
                            style: nameStyle,
                          ),
                        ),
                        _FeedbackIconButton(
                          exerciseName: e.slot.exerciseName,
                          // El ancla es de ESTE miembro: en el round-robin cada
                          // uno puede cerrar con distinta cantidad de series
                          // (planes con targetSets desparejos), así que leer el
                          // conteo del grupo pondría la nota bajo el log del
                          // otro ejercicio.
                          onTap: () => onFeedback!(
                            e.slot,
                            e.logs.isNotEmpty ? e.logs.length : null,
                          ),
                        ),
                      ],
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
    return TreinoTappable(
      onTap: onActivate,
      child: Opacity(
        opacity: 0.75,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exerciseName.toUpperCase(),
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 0.5,
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
    final names = joinNonEmpty(entries.map((e) => e.slot.exerciseName), ' · ');
    return TreinoTappable(
      onTap: onActivate,
      child: Opacity(
        opacity: 0.75,
        child: Container(
          decoration: BoxDecoration(
            color: palette.highlight.withValues(alpha: 0.04),
            border: Border(
              left: BorderSide(color: palette.highlight, width: 3),
            ),
          ),
          padding: const EdgeInsets.all(12),
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
                      names.toUpperCase(),
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 0.5,
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
    this.onOpenDetail,
    this.onFeedback,
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

  /// Tap en el nombre de un miembro → detalle de ese ejercicio.
  final void Function(RoutineSlot slot)? onOpenDetail;

  /// Ver [_SupersetBlock.onFeedback].
  final void Function(RoutineSlot slot, int? setNumber)? onFeedback;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // La regla del round-robin vive en `SupersetOrder`, no acá.
    //
    // Estaba escrita adentro de este `build()`, y por eso el reloj no podía
    // portarla: reimplementaba el recorrido por su cuenta, ejercicio por
    // ejercicio en vez de vuelta por vuelta, y producía 1a, 2a, 3a, 1b… El dato
    // salía válido y el orden equivocado, que en una superserie es el
    // entrenamiento entero. Ahora las dos implementaciones responden al mismo
    // fixture: `conformance/superset_order.json`.
    final miembros = [
      for (final e in entries)
        (
          exerciseId: e.slot.exerciseId,
          plannedSets: plannedCountFor(e.slot),
          loggedSets: e.logs.length,
        ),
    ];
    final maxRounds = SupersetOrder.totalRounds(miembros);
    final celda = SupersetOrder.nextCell(miembros);

    final String? activeId = celda?.exerciseId;
    final int? activeSet = celda?.setNumber;
    final blockDone = celda == null;
    final displayRound = blockDone ? maxRounds : celda.round;

    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      children.add(_ExerciseSection(
        slot: e.slot,
        logsForExercise: e.logs,
        currentSetNumber: e.slot.exerciseId == activeId ? activeSet : null,
        // El ancla del reporte es del MIEMBRO, no de la celda activa del
        // round-robin: `currentSetNumber` es null en todos los miembros salvo
        // en el que tiene el turno, y con eso el reporte del otro ejercicio se
        // quedaba sin serie. Acá cada miembro apunta a su propia última serie
        // hecha (ver el comentario largo en _StandaloneBlock: son dos
        // conceptos distintos y no hay que volver a fusionarlos).
        // Sin series hechas, `null` (nivel ejercicio) y no la serie 1: en el
        // round-robin es normal que un miembro no haya arrancado todavía.
        feedbackSetNumber: e.logs.isNotEmpty ? e.logs.length : null,
        week: week,
        totalSets: plannedCountFor(e.slot),
        techniqueInstructions: e.technique,
        videoUrl: e.videoUrl,
        onSetCheck: (setNumber, reps, weightKg) =>
            onSetCheck(e.slot, setNumber, reps, weightKg),
        onSetUpdate: onSetUpdate,
        // Superset add/remove UI is out of scope this change (AD-5 note).
        onAddSet: null,
        onOpenDetail: onOpenDetail == null ? null : () => onOpenDetail!(e.slot),
        onFeedback: onFeedback == null
            ? null
            : (setNumber) => onFeedback!(e.slot, setNumber),
      ));
      if (i != entries.length - 1) children.add(const SizedBox(height: 8));
    }

    // Sin caja: la superserie se identifica por la barra lateral magenta y un
    // tinte de fondo suave, edge-to-edge (layout ampliado del player).
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.04),
        border: Border(
          left: BorderSide(color: palette.highlight, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
    required this.feedbackSetNumber,
    required this.week,
    required this.totalSets,
    required this.techniqueInstructions,
    required this.videoUrl,
    required this.onSetCheck,
    required this.onSetUpdate,
    this.onAddSet,
    this.onRemoveSet,
    this.onOpenDetail,
    this.onFeedback,
  });

  final RoutineSlot slot;
  final List<SetLog> logsForExercise;

  /// Set (1-based) que debe estar activo. Null ⇒ ningún set activo.
  ///
  /// Es una decisión de RESALTADO DE FILA, no el ancla del reporte: mira hacia
  /// adelante (la serie pendiente). Para el reporte usar [feedbackSetNumber].
  final int? currentSetNumber;

  /// Set (1-based) al que se ancla "Comentar / Reportar": la última serie que
  /// el atleta REALMENTE hizo, o `null` si todavía no hizo ninguna (reporte a
  /// nivel ejercicio).
  ///
  /// El caso vacío NO es la serie 1. Persistir `setNumber: 1` sin que exista la
  /// serie 1 es el mismo defecto que anclar a la pendiente: el PF ve la nota
  /// colgada de un log que nunca ocurrió. La API ya acepta null justo para
  /// esto.
  ///
  /// Deliberadamente separado de [currentSetNumber] — se intentó reusar aquel y
  /// el reporte terminaba una serie adelantado (y sin serie al completarse el
  /// ejercicio, cuando `currentSetNumber` pasa a null). Miran para lados
  /// distintos: uno a la serie que falta, este a la que ya pasó.
  final int? feedbackSetNumber;

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

  /// Tap en el NOMBRE del ejercicio → detalle completo. Acceso ADICIONAL al
  /// ⓘ de técnica (que sigue abriendo la TechniqueSheet in-place).
  final VoidCallback? onOpenDetail;

  /// "Comentar / Reportar" al PF (#628) — la contraparte simétrica de
  /// [CoachNote], que muestra el mensaje del PF en la otra dirección. Recibe
  /// [feedbackSetNumber] para que el reporte quede anclado a la última serie
  /// hecha (o a nivel ejercicio si no hizo ninguna). Null ⇒ affordance oculta
  /// (sin PF vinculado).
  final void Function(int? setNumber)? onFeedback;

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
          ? DurationSetRow(
              key: ValueKey('dur-$setNumber-${logged?.id ?? "pending"}'),
              exerciseId: widget.slot.exerciseId,
              setNumber: setNumber,
              targetSeconds: targetSeconds,
              isDone: isRowDone,
              // Sin callback de marcado: la serie la marca la pantalla cuando
              // la cuenta llega a cero, esté esta fila montada o no.
              enabled: isCurrent,
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

    // Sin Container-card (layout ampliado del player): la sección corre
    // full-width sobre el fondo; las filas de sets llevan su propio chip
    // bgCard como delimitación.
    return Column(
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
              // El nombre es protagonista (heading condensed) y tocable:
              // abre el detalle completo del ejercicio (video + técnica).
              // hint (no label): el Text del nombre ya se fusiona como label
              // del nodo — un label explícito lo duplicaría en VoiceOver.
              child: Semantics(
                button: widget.onOpenDetail != null,
                hint: widget.onOpenDetail != null
                    ? 'Ver detalle del ejercicio'
                    : null,
                child: TreinoTappable(
                  onTap: widget.onOpenDetail,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.slot.exerciseName.toUpperCase(),
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                              letterSpacing: 0.5,
                              height: 1.05,
                              color: isDone
                                  ? palette.textMuted
                                  : palette.textPrimary,
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              decorationColor: palette.textMuted,
                            ),
                          ),
                        ),
                        // Señal de navegación pegada al nombre (#578 hizo el
                        // tap invisible): solo cuando el tap realmente abre
                        // el detalle. Decorativa para VoiceOver — el hint del
                        // Semantics de arriba ya anuncia la acción.
                        if (widget.onOpenDetail != null) ...[
                          const SizedBox(width: 8),
                          ExcludeSemantics(
                            child: Icon(
                              TreinoIcon.chevronRight,
                              size: 16,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.onFeedback != null)
              _FeedbackIconButton(
                exerciseName: widget.slot.exerciseName,
                onTap: () => widget.onFeedback!(widget.feedbackSetNumber),
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
                borderRadius: BorderRadius.circular(AppRadius.full),
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
          borderRadius: BorderRadius.circular(AppRadius.full),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
        // bgCard (no bg): sin el Container-card de la sección, la fila se
        // delimita a sí misma como chip sobre el fondo de pantalla.
        color: palette.bgCard,
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
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
        child: Text(
          'TERMINAR SESIÓN',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 1.0,
            color: enabled
                ? TreinoButtonTokens.foreground(context)
                : palette.textMuted,
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
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

/// El esfuerzo que esta midiendo el reloj, al lado del tiempo del entreno.
///
/// Change `watch-workout-session`, fase F4.
///
/// **Es un agregado.** Sin reloj conectado no se dibuja NADA y la pantalla
/// queda exactamente como estaba: ni un hueco, ni un "--", ni un aviso de que
/// falta un reloj. El atleta que entrena sin reloj no tiene por que enterarse
/// de que existe esta fila.
///
/// Es un widget aparte y no parte del header por rendimiento: el dato cambia
/// cada pocos segundos, y metiendolo inline haria rebuild de toda la cabecera
/// del player —incluido el cronometro y la barra de progreso— por un dato
/// secundario. Asi el rebuild queda acotado a esta fila.
/// La cuenta regresiva de un ejercicio por tiempo que corre EN EL RELOJ.
///
/// El reloj manda el INSTANTE DE FIN, no los segundos restantes, así que acá se
/// calcula la cuenta sola. Eso hace que no haga falta tráfico por segundo entre
/// los dispositivos, y que un envío que llega tarde —el reloj throttlea a 5s—
/// muestre igual el número correcto.
///
/// Es stateful porque hay que redibujar cada segundo: el notifier del esfuerzo
/// solo emite cuando llega un payload nuevo, y entre payload y payload la
/// cuenta tiene que seguir bajando.
class _WatchTimerRow extends ConsumerStatefulWidget {
  const _WatchTimerRow();

  @override
  ConsumerState<_WatchTimerRow> createState() => _WatchTimerRowState();
}

class _WatchTimerRowState extends ConsumerState<_WatchTimerRow> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Arranca o corta el tick según haya o no cuenta viva.
  ///
  /// No se deja corriendo siempre: un timer por segundo en la pantalla más
  /// caliente de la app, para no mostrar nada, es exactamente el tipo de
  /// rebuild que este proyecto evita.
  void _syncTick(bool debeCorrer) {
    if (debeCorrer && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!debeCorrer && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final notifier = ref.watch(watchEffortNotifierProvider);

    return ValueListenableBuilder<WatchEffort?>(
      valueListenable: notifier,
      builder: (context, effort, _) {
        final endsAt = effort?.timerEndsAt;
        final restante = endsAt == null
            ? 0
            : endsAt.difference(DateTime.now().toUtc()).inSeconds;

        // Vencido o inexistente: nada que mostrar. Que se apague solo al llegar
        // a cero es la red contra un "se apagó" que no llegue.
        final vivo = endsAt != null && restante > 0;
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncTick(vivo));
        if (!vivo) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TreinoIcon.timer, size: 12, color: palette.accent),
              const SizedBox(width: 4),
              Text(
                formatMMSS(restante),
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 4),
              // De dónde viene. Sin esto es un MM:SS suelto pegado abajo del
              // cronómetro de sesión de 40px, sin nada que diga qué cuenta es
              // ni de qué ejercicio. La cuenta de la serie se ve en su propia
              // fila; esto es el recordatorio para cuando el atleta scrolleó y
              // esa fila no está en pantalla.
              Text(
                'en el reloj',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 11,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WatchEffortRow extends ConsumerWidget {
  const _WatchEffortRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final notifier = ref.watch(watchEffortNotifierProvider);

    return ValueListenableBuilder<WatchEffort?>(
      valueListenable: notifier,
      builder: (context, effort, _) {
        final display = WatchEffortRules.display(
          effort: effort,
          now: DateTime.now().toUtc(),
        );
        if (display.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (display.bpm != null) ...[
                Icon(TreinoIcon.heartRate,
                    size: 12, color: palette.reactionLike),
                const SizedBox(width: 4),
                Text(
                  '${display.bpm}',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
              if (display.bpm != null && display.kcal != null)
                const SizedBox(width: 12),
              if (display.kcal != null) ...[
                Icon(TreinoIcon.calories,
                    size: 12, color: palette.reactionFire),
                const SizedBox(width: 4),
                Text(
                  '${display.kcal} kcal',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
