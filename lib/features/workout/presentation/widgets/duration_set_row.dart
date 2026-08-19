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
import '../../application/workout_clock.dart';
import '../../domain/duration_timer.dart';
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

  /// Ahora, siempre en UTC: el instante de fin viaja al reloj y se compara
  /// contra el suyo, así que una zona horaria de por medio los desfasaría.
  ///
  /// Sale de [workoutClockProvider] y no de `DateTime.now` directo para que un
  /// test pueda mover el reloj de pared sin mover los ticks — que es la única
  /// forma de demostrar que la cuenta no depende de ellos.
  DateTime _ahora() => ref.read(workoutClockProvider)().toUtc();

  /// Instante de fin. Null ⇒ no hay cuenta corriendo.
  ///
  /// **Esta es la fuente de la verdad**, no [_remaining]: los segundos
  /// mostrados se derivan de acá en cada redibujo. Guardar lo que falta sería
  /// volver a atar la duración a cuántos ticks corrieron.
  DateTime? _endsAt;

  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _remaining = widget.targetSeconds;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startTimer() {
    if (_endsAt != null || widget.isDone) return;
    final fin = DurationTimerRules.endsAt(
      start: _ahora(),
      totalSeconds: widget.targetSeconds,
    );
    setState(() {
      _endsAt = fin;
      _remaining = widget.targetSeconds;
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

    _tick = Timer.periodic(DurationTimerRules.tickInterval, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final restante = DurationTimerRules.remaining(
        endsAt: fin,
        now: _ahora(),
      );
      // El tick es más rápido que el segundo que se muestra: sin esto se
      // redibujaría la fila dos veces por segundo para pintar el mismo número.
      if (restante == _remaining) return;

      final termino = restante == 0;
      setState(() {
        _remaining = restante;
        if (termino) _endsAt = null;
      });
      if (!termino) return;

      t.cancel();
      _tick = null;
      // Vibra para avisar que se acabó el tiempo.
      HapticFeedback.heavyImpact();
      // Al reloj NO se le avisa: llega a cero solo, porque cuenta contra el
      // mismo instante de fin.
      widget.onDone?.call();
    });
  }

  /// Corta la cuenta SIN cargar la serie.
  ///
  /// Existe por lo mismo que en el reloj: sin salida, un toque equivocado
  /// dejaba al atleta mirando una cuenta que no pidió, sin forma de volver y
  /// —peor— con la serie marcándose sola al llegar a cero.
  void _cancelTimer() {
    _tick?.cancel();
    _tick = null;
    setState(() {
      _endsAt = null;
      _remaining = widget.targetSeconds;
    });
    // Cancelar SÍ se avisa: adelanta un final que el instante de fin no
    // anticipa. Sin esto el reloj seguiría contando algo que ya no existe.
    unawaited(ref.read(watchTimerServiceProvider).cancel());
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final textColor = widget.isDone ? palette.textMuted : palette.textPrimary;
    final isInteractive = widget.onDone != null && !widget.isDone;
    final corriendo = _endsAt != null;

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
                      ? formatMMSS(_remaining)
                      : formatMMSS(widget.targetSeconds),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: corriendo ? palette.accent : textColor,
                  ),
                ),
                if (!widget.isDone)
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
          else
            // Corriendo: no hay forma de marcarla a mano —un ejercicio por
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
