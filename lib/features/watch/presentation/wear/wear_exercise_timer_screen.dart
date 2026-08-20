import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../data/wear_workout_service.dart';
import '../../domain/watch_effort.dart';
import 'wear_fitted_text.dart';
import 'wear_widgets.dart';

/// La pantalla de un ejercicio POR TIEMPO mientras corre.
///
/// ## Por qué es una pantalla y no una fila más
///
/// Un ejercicio por tiempo no se "marca": se AGUANTA. Durante esos segundos el
/// atleta no tiene nada que tocar, y lo único que necesita ver —de reojo, con
/// la muñeca en una plancha o un hollow— es cuánto falta. Meter eso en la lista
/// de series lo dejaría chiquito y compitiendo con círculos que en ese momento
/// no sirven para nada.
///
/// ## Lo que NO vive acá
///
/// La cuenta regresiva no la lleva esta pantalla: llega ya resuelta desde el
/// deadline persistido en el nativo. Por eso sobrevive a que se apague la
/// pantalla y a que se destruya la Activity, y por eso el aviso al vencer
/// —la vibración— funciona aunque esto no se esté dibujando. Acá sólo se
/// pinta lo que el temporizador dice.
class WearExerciseTimerScreen extends StatelessWidget {
  const WearExerciseTimerScreen({
    super.key,
    required this.exerciseName,
    required this.timer,
    required this.effort,
    required this.onOcultar,
    required this.onListo,
  });

  final String exerciseName;
  final WearExerciseTimer timer;
  final WatchEffortDisplay effort;

  /// Esconde la pantalla sin tocar el temporizador, que sigue corriendo.
  final VoidCallback onOcultar;

  /// El tiempo terminó y el atleta lo da por hecho: marca la serie.
  final VoidCallback onListo;

  /// Fracción ya transcurrida, de 0 a 1.
  double get _progreso {
    if (timer.totalMs <= 0) return 0;
    final hecho = (timer.totalMs - timer.remainingMs) / timer.totalMs;
    return hecho.clamp(0.0, 1.0);
  }

  /// `m:ss`, o sólo los segundos cuando falta menos de un minuto.
  ///
  /// Se redondea hacia ARRIBA: mostrar "0" durante el último segundo haría
  /// pensar que terminó cuando todavía falta.
  String get _tiempo {
    final total = (timer.remainingMs / 1000).ceil().clamp(0, 359999);
    final min = total ~/ 60;
    final seg = total % 60;
    if (min == 0) return '$seg';
    return '$min:${seg.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final termino = timer.finished;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            WearFittedText(
              exerciseName,
              maxLines: 2,
              maxSize: 14,
              minSize: 11,
              widthFactor: 0.9,
              styleFor: (size) => GoogleFonts.barlowCondensed(
                fontSize: size,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 118,
              height: 118,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // El anillo se lee ANTES que el número cuando el reloj se
                  // mira de reojo: la posición dice cuánto falta sin leer.
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: _progreso,
                      strokeWidth: 6,
                      backgroundColor: palette.bgCard,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        termino ? palette.accent : palette.highlight,
                      ),
                    ),
                  ),
                  Text(
                    termino ? '¡Listo!' : _tiempo,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: termino ? 28 : 44,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            WearEffortRow(effort: effort),
            const SizedBox(height: 14),
            if (termino)
              WearButton(label: 'Marcar serie', onTap: onListo)
            else
              // Ocultar NO cancela: el temporizador sigue corriendo y vibra al
              // vencer igual. Es para poder mirar las series sin perder la
              // cuenta.
              WearButton(
                label: 'Ocultar',
                onTap: onOcultar,
                tint: palette.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
