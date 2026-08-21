import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../watch/application/watch_effort_notifier.dart';
import '../../../watch/domain/watch_effort.dart';
import '../../application/phone_duration_timer.dart';
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
    required this.enabled,
  });

  /// Para que el reloj sepa QUÉ está cronometrando y pueda nombrarlo.
  final String exerciseId;
  final int setNumber;
  final int targetSeconds;
  final bool isDone;

  /// Si esta fila acepta que el atleta arranque la cuenta.
  ///
  /// Acá vivía un `onDone` que la fila llamaba al llegar a cero. Ya no: quien
  /// marca la serie es la PANTALLA, porque esta fila se desmonta al scrollear.
  /// Se dejó de pasar el callback a propósito — uno que nadie invoca pero que
  /// parece la vía de marcado es peor que no tenerlo.
  final bool enabled;

  @override
  ConsumerState<DurationSetRow> createState() => _DurationSetRowState();
}

class _DurationSetRowState extends ConsumerState<DurationSetRow> {
  Timer? _tick;

  /// El último segundo que se dibujó, para no repintar por gusto.
  int? _ultimoSegundo;

  /// Ahora, siempre en UTC: el instante de fin viaja al reloj y se compara
  /// contra el suyo, así que una zona horaria de por medio los desfasaría.
  ///
  /// Sale de [workoutClockProvider] y no de `DateTime.now` directo para que un
  /// test pueda mover el reloj de pared sin mover los ticks — que es la única
  /// forma de demostrar que la cuenta no depende de ellos.
  DateTime _ahora() => ref.read(workoutClockProvider)().toUtc();

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Arranca o corta el tick según haya o no cuenta viva.
  ///
  /// Este tick SOLO REDIBUJA. No cuenta, no completa nada y no sobrevive al
  /// desmontaje: la cuenta vive en [phoneDurationTimerProvider] y quien la
  /// completa es la pantalla. Por eso desmontar esta fila —scrollear— ya no
  /// mata el cronómetro.
  ///
  /// Se apaga cuando no hay nada que mostrar porque esta fila se repite por
  /// cada serie de cada ejercicio de la pantalla más caliente de la app.
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
    // El tick corre cada 500ms y el número que se muestra cambia una vez por
    // segundo: sin esta guarda se repintaría la fila el doble de veces para
    // pintar lo mismo.
    final segundo = _segundoMostrado(_ahora());
    if (segundo == _ultimoSegundo) return;
    setState(() => _ultimoSegundo = segundo);
  }

  /// El segundo que la fila está mostrando ahora, sea de quien sea la cuenta.
  int? _segundoMostrado(DateTime ahora) {
    final fin = _resolver(ahora).endsAt;
    if (fin == null) return null;
    return DurationTimerRules.remaining(endsAt: fin, now: ahora);
  }

  /// De quién es la cuenta de esta fila y cuándo termina.
  DurationTimerView _resolver(DateTime ahora) {
    if (widget.isDone) {
      return (owner: DurationTimerOwner.nadie, endsAt: null);
    }
    final propia = ref.read(phoneDurationTimerProvider).value;
    final effort = ref.read(watchEffortNotifierProvider).value;
    return DurationTimerOwnership.resolve(
      exerciseId: widget.exerciseId,
      setNumber: widget.setNumber,
      localEndsAt: propia != null &&
              propia.esDe(
                exerciseId: widget.exerciseId,
                setNumber: widget.setNumber,
              )
          ? propia.endsAt
          : null,
      watchExerciseId: effort?.timerExerciseId,
      watchSetNumber: effort?.timerSetNumber,
      watchEndsAt: effort?.timerEndsAt,
      now: ahora,
    );
  }

  void _startTimer() {
    if (widget.isDone) return;
    unawaited(
      ref.read(phoneDurationTimerProvider).start(
            exerciseId: widget.exerciseId,
            setNumber: widget.setNumber,
            totalSeconds: widget.targetSeconds,
            endsAt: DurationTimerRules.endsAt(
              start: _ahora(),
              totalSeconds: widget.targetSeconds,
            ),
          ),
    );
  }

  /// Corta la cuenta SIN cargar la serie.
  ///
  /// Existe por lo mismo que en el reloj: sin salida, un toque equivocado
  /// dejaba al atleta mirando una cuenta que no pidió, sin forma de volver y
  /// —peor— con la serie marcándose sola al llegar a cero.
  void _cancelTimer() {
    unawaited(ref.read(phoneDurationTimerProvider).cancel());
  }

  @override
  Widget build(BuildContext context) {
    // La cuenta puede estar corriendo en el RELOJ. Escuchar acá —y no solo en
    // la card de arriba de la pantalla— es lo que faltaba: el dato llegaba al
    // teléfono desde el primer día y no lo consumía nadie, así que la fila
    // seguía ofreciendo "Iniciar" sobre una serie que ya se estaba cronometrando
    // en la muñeca.
    return ValueListenableBuilder<PhoneDurationTimer?>(
      valueListenable: ref.watch(phoneDurationTimerProvider),
      builder: (context, _, __) => ValueListenableBuilder<WatchEffort?>(
        valueListenable: ref.watch(watchEffortNotifierProvider),
        builder: (context, effort, ___) => _fila(context, effort),
      ),
    );
  }

  Widget _fila(BuildContext context, WatchEffort? effort) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final textColor = widget.isDone ? palette.textMuted : palette.textPrimary;
    final isInteractive = widget.enabled && !widget.isDone;

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
