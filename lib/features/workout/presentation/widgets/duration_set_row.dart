import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../watch/application/watch_credential_providers.dart'
    show watchTimerServiceProvider;
import '../../../watch/application/watch_effort_notifier.dart';
import '../../../watch/application/watch_timer_control_notifier.dart';
import '../../../watch/data/watch_timer_service.dart';
import '../../../watch/domain/watch_effort.dart';
import '../../application/workout_clock.dart';
import '../../domain/duration_timer.dart';
import '../../domain/duration_timer_owner.dart';
import 'mmss.dart';

/// Fila de un set basado en duración.
/// Muestra el tiempo objetivo como MM:SS y un countdown timer.
/// "Iniciar" arranca el contador; al llegar a 0 auto-marca done con vibración.
///
/// ── La cuenta va contra el RELOJ DE PARED ─────────────────────────────────
///
/// Antes esta fila decrementaba un contador con un `Timer.periodic` de un
/// segundo. Eso hacía que la duración real dependiera de cuántos ticks
/// alcanzaran a correr: con la app estrangulada —pantalla bloqueada, batería
/// baja, otra app adelante— los ticks se pierden y NO se recuperan, así que una
/// plancha de 60 segundos terminaba durando 70 sin que el atleta tuviera cómo
/// notarlo.
///
/// Ahora se guarda el INSTANTE de fin y la cuenta se deriva de él. El tick pasa
/// a ser lo único que es: cuándo redibujar. La aritmética vive en
/// [DurationTimerRules] y está bajo contrato compartido con el reloj en
/// `conformance/duration_timer.json`.
///
/// ── Y se espeja en la muñeca ──────────────────────────────────────────────
///
/// Arrancar acá se lo avisa al reloj, que muestra la misma cuenta sin cargar la
/// serie: el dueño de la serie es el lado que arrancó el cronómetro. El porqué
/// completo está en [WatchTimerCommand].
class DurationSetRow extends ConsumerStatefulWidget {
  const DurationSetRow({
    super.key,
    required this.exerciseId,
    required this.setNumber,
    required this.targetSeconds,
    required this.isDone,
    required this.onDone,
  });

  /// Para que el reloj sepa QUÉ está cronometrando y pueda nombrarlo.
  final String exerciseId;
  final int setNumber;
  final int targetSeconds;
  final bool isDone;

  /// Called when the set is marked done. Null means not interactive.
  final VoidCallback? onDone;

  @override
  ConsumerState<DurationSetRow> createState() => _DurationSetRowState();
}

class _DurationSetRowState extends ConsumerState<DurationSetRow> {
  Timer? _tick;

  /// El instante de fin de la cuenta arrancada en ESTE teléfono, ya vencido o
  /// no. Lo consulta la regla de propiedad; `null` ⇒ acá no arrancó nada.
  ///
  /// **Es la fuente de la verdad**, no un contador de segundos: los segundos
  /// mostrados se derivan de acá en cada redibujo. Guardar lo que falta sería
  /// volver a atar la duración a cuántos ticks corrieron.
  DateTime? _endsAt;

  /// Ya se disparó el final de la cuenta propia (háptico + marcar la serie).
  /// Existe para que no se dispare dos veces si entran dos ticks juntos.
  bool _completada = false;

  /// El último segundo que se dibujó, para no repintar por gusto.
  int? _ultimoSegundo;

  /// Ahora, siempre en UTC: el instante de fin viaja al reloj y se compara
  /// contra el suyo, así que una zona horaria de por medio los desfasaría.
  ///
  /// Sale de [workoutClockProvider] y no de `DateTime.now` directo para que un
  /// test pueda mover el reloj de pared sin mover los ticks — que es la única
  /// forma de demostrar que la cuenta no depende de ellos.
  DateTime _ahora() => ref.read(workoutClockProvider)().toUtc();

  /// El canal por el que el RELOJ pide cortar la cuenta que corre acá.
  ///
  /// Se escucha con un listener y no con `ref.watch`/`ref.listen` porque el
  /// provider devuelve el notifier, y ese objeto no cambia nunca de identidad:
  /// Riverpod no re-evaluaría nada. Lo que cambia es su `value`.
  WatchTimerControlNotifier? _control;

  /// El servicio, cacheado: `ref.read` no se puede usar desde `dispose`.
  WatchTimerService? _servicioReloj;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _servicioReloj = ref.read(watchTimerServiceProvider);
    final control = ref.read(watchTimerControlNotifierProvider);
    if (identical(control, _control)) return;
    _control?.removeListener(_cancelarPorPedidoDelReloj);
    _control = control..addListener(_cancelarPorPedidoDelReloj);
  }

  @override
  void dispose() {
    _control?.removeListener(_cancelarPorPedidoDelReloj);
    _tick?.cancel();

    // La fila se desmonta con la cuenta CORRIENDO: el atleta scrolleó y el
    // `ListView` la sacó del viewport. El cronómetro muere acá —vive en el
    // State— y nadie va a marcar la serie.
    //
    // Hay que decírselo al reloj. Si no, su espejo llega a cero, VIBRA
    // "terminaste" por una serie que nadie cargó, y encima bloquea arrancarla
    // de nuevo desde la muñeca.
    //
    // No se dispara en el desmontaje normal: al marcarse la serie cambia la
    // ValueKey y este State se destruye, pero ahí `_completada` ya es true.
    if (_endsAt != null && !_completada) {
      unawaited(_servicioReloj?.cancel() ?? Future<bool>.value(false));
    }
    super.dispose();
  }

  /// Arranca o corta el tick según haya o no cuenta viva.
  ///
  /// El tick NO cuenta: solo dice cuándo redibujar. Se apaga cuando no hay nada
  /// que mostrar porque esta fila se repite por cada serie de cada ejercicio de
  /// la pantalla más caliente de la app, y un timer por fila para no dibujar
  /// nada es exactamente el rebuild que `docs/performance.md` pide evitar.
  void _syncTick(bool debeCorrer) {
    if (debeCorrer && _tick == null) {
      _tick = Timer.periodic(DurationTimerRules.tickInterval, (_) => _onTick());
    } else if (!debeCorrer && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  void _onTick() {
    if (!mounted) return;
    final ahora = _ahora();

    final fin = _endsAt;
    if (fin != null &&
        !_completada &&
        DurationTimerRules.isFinished(endsAt: fin, now: ahora)) {
      _completada = true;
      // `_endsAt` se limpia ACÁ, y no es opcional.
      //
      // Sin esto la fila queda con un instante de fin vencido, y `_startTimer`
      // corta con `if (_endsAt != null) return`. En el camino feliz no se nota
      // —al marcarse la serie cambia la ValueKey y este State se destruye— pero
      // si el log falla (gimnasio sin señal: `SessionNotifier.logSet` atrapa el
      // error a propósito y deja la fila interactiva) el State SOBREVIVE, la
      // fila vuelve a dibujar "Iniciar"… y el botón no hace absolutamente nada.
      // Para siempre.
      _endsAt = null;
      // Vibra para avisar que se acabó el tiempo.
      HapticFeedback.heavyImpact();
      // Al reloj NO se le avisa: llega a cero solo, porque cuenta contra el
      // mismo instante de fin.
      widget.onDone?.call();
      setState(() {});
      return;
    }

    // El tick corre cada 500ms y el número que se muestra cambia una vez por
    // segundo: sin esta guarda se repintaría la fila el doble de veces para
    // pintar lo mismo, en la pantalla más caliente de la app.
    //
    // Se compara el SEGUNDO RESUELTO y no `_endsAt`, para que también sirva
    // cuando la cuenta la trae el reloj.
    final segundo = _segundoMostrado(ahora);
    if (segundo == _ultimoSegundo) return;
    setState(() => _ultimoSegundo = segundo);
  }

  /// El segundo que la fila está mostrando ahora, sea de quien sea la cuenta.
  /// Null si no hay ninguna.
  int? _segundoMostrado(DateTime ahora) {
    final vista = _resolver(ahora);
    final fin = vista.endsAt;
    if (fin == null) return null;
    return DurationTimerRules.remaining(endsAt: fin, now: ahora);
  }

  /// De quién es la cuenta de esta fila y cuándo termina.
  DurationTimerView _resolver(DateTime ahora) {
    if (widget.isDone) {
      return (owner: DurationTimerOwner.nadie, endsAt: null);
    }
    final effort = ref.read(watchEffortNotifierProvider).value;
    return DurationTimerOwnership.resolve(
      exerciseId: widget.exerciseId,
      setNumber: widget.setNumber,
      localEndsAt: _endsAt,
      watchExerciseId: effort?.timerExerciseId,
      watchSetNumber: effort?.timerSetNumber,
      watchEndsAt: effort?.timerEndsAt,
      now: ahora,
    );
  }

  void _startTimer() {
    if (_endsAt != null || widget.isDone) return;
    final fin = DurationTimerRules.endsAt(
      start: _ahora(),
      totalSeconds: widget.targetSeconds,
    );
    setState(() {
      _endsAt = fin;
      _completada = false;
    });

    // Al reloj le viaja el instante de fin, así que la muñeca cuenta sola: no
    // hay tráfico por segundo y las dos pantallas no se pueden desfasar.
    unawaited(
      ref.read(watchTimerServiceProvider).start(
            exerciseId: widget.exerciseId,
            setNumber: widget.setNumber,
            totalSeconds: widget.targetSeconds,
            endsAt: fin,
          ),
    );
  }

  /// Corta la cuenta SIN cargar la serie.
  ///
  /// Existe por lo mismo que en el reloj: sin salida, un toque equivocado
  /// dejaba al atleta mirando una cuenta que no pidió, sin forma de volver y
  /// —peor— con la serie marcándose sola al llegar a cero.
  void _cancelTimer({bool avisarAlReloj = true}) {
    setState(() {
      _endsAt = null;
      _completada = false;
    });
    if (!avisarAlReloj) return;
    // Cancelar SÍ se avisa: adelanta un final que el instante de fin no
    // anticipa. Sin esto el reloj seguiría contando algo que ya no existe.
    unawaited(ref.read(watchTimerServiceProvider).cancel());
  }

  /// El reloj pidió cortar la cuenta que corre acá.
  ///
  /// Se compara la IDENTIDAD. El notifier es uno solo y todas las filas
  /// montadas lo escuchan: sin este chequeo, cancelar en la muñeca cortaría
  /// también la plancha que el atleta está aguantando en otra fila.
  ///
  /// Y SÍ se le contesta al reloj. El `cancel` de vuelta no es un eco: es el
  /// acuse. `WCSession` no da callback de éxito, así que sin esto la muñeca no
  /// tiene forma de saber que el pedido llegó. El ida y vuelta termina — el
  /// `.cancel` que recibe el reloj no manda nada de regreso.
  void _cancelarPorPedidoDelReloj() {
    final pedido = _control?.value;
    if (pedido == null) return;
    if (!pedido.aplicaA(
      exerciseId: widget.exerciseId,
      setNumber: widget.setNumber,
    )) {
      return;
    }
    if (_endsAt == null) return;
    _cancelTimer();
  }

  @override
  Widget build(BuildContext context) {
    // La cuenta puede estar corriendo en el RELOJ. Escuchar acá —y no solo en
    // la card de arriba de la pantalla— es lo que faltaba: el dato llegaba al
    // teléfono desde el primer día y no lo consumía nadie, así que la fila
    // seguía ofreciendo "Iniciar" sobre una serie que ya se estaba cronometrando
    // en la muñeca.
    final notifier = ref.watch(watchEffortNotifierProvider);
    return ValueListenableBuilder<WatchEffort?>(
      valueListenable: notifier,
      builder: (context, effort, _) => _fila(context, effort),
    );
  }

  Widget _fila(BuildContext context, WatchEffort? effort) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final textColor = widget.isDone ? palette.textMuted : palette.textPrimary;
    final isInteractive = widget.onDone != null && !widget.isDone;

    final vista = _resolver(_ahora());

    final corriendo = vista.owner != DurationTimerOwner.nadie;
    final enElReloj = vista.owner == DurationTimerOwner.reloj;
    final fin = vista.endsAt;
    final remaining = fin == null
        ? widget.targetSeconds
        : DurationTimerRules.remaining(endsAt: fin, now: _ahora());

    // El tick tiene que correr también cuando la cuenta la trae el reloj: sin
    // eso el número quedaría congelado en el que vino con el último contexto,
    // y el reloj solo publica cada ~5 segundos.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTick(corriendo);
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        // bgCard (no bg): misma delimitación por-fila que _RepsSetRow.
        color: palette.bgCard,
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
                  corriendo
                      ? formatMMSS(remaining)
                      : formatMMSS(widget.targetSeconds),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: corriendo ? palette.accent : textColor,
                  ),
                ),
                if (enElReloj)
                  // De dónde viene la cuenta. Sin esto el atleta ve un número
                  // bajando sobre una serie que él no arrancó acá, y no tiene
                  // cómo saber por qué el teléfono no le deja cancelarla.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(TreinoIcon.timer, size: 11, color: palette.accent),
                      const SizedBox(width: 4),
                      Text(
                        'corriendo en el reloj',
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  )
                else if (!widget.isDone)
                  Text(
                    'objetivo: ${formatMMSS(widget.targetSeconds)}',
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
          else if (!corriendo)
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
                        : palette.bg,
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
          else if (enElReloj)
            // La cuenta es del RELOJ: acá no se cancela.
            //
            // El dueño de la serie es el lado que la arrancó, y es el único que
            // la marca al llegar a cero. Ofrecer "Cancelar" acá mandaría una
            // orden por un cronómetro que este teléfono no arrancó, y dejaría
            // al reloj marcando una serie que el atleta cree cancelada.
            Icon(TreinoIcon.timer, color: palette.accent, size: 22)
          else
            // Corriendo acá: no hay forma de marcarla a mano —un ejercicio por
            // tiempo se completa cuando pasa el tiempo, no por decisión del
            // atleta— pero sí de SALIR. Mismo criterio que el botón "Cancelar"
            // del reloj.
            Semantics(
              button: true,
              label: 'Cancelar el cronómetro de la serie ${widget.setNumber}',
              child: TreinoTappable(
                onTap: _cancelTimer,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
