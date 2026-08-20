import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../data/wear_workout_service.dart';
import '../../domain/watch_effort.dart';
import 'wear_fitted_text.dart';
import 'wear_round_scaffold.dart';
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
    required this.onCancelar,
  });

  final String exerciseName;
  final WearExerciseTimer timer;
  final WatchEffortDisplay effort;

  /// Esconde la pantalla sin tocar el temporizador, que sigue corriendo.
  final VoidCallback onOcultar;

  /// El tiempo terminó y el atleta lo da por hecho: marca la serie.
  final VoidCallback onListo;

  /// Abandona el ejercicio por tiempo SIN marcar la serie.
  ///
  /// Distinto de ocultar, y hace falta: si el atleta no aguanta la plancha, no
  /// tiene por qué esperar a que el reloj llegue a cero para poder salir.
  final VoidCallback onCancelar;

  /// Fracción ya transcurrida, de 0 a 1.
  double get _progreso {
    if (timer.totalMs <= 0) return 0;
    final hecho = (timer.totalMs - timer.remainingMs) / timer.totalMs;
    return hecho.clamp(0.0, 1.0);
  }

  /// `MM:SS`, igual que el temporizador del teléfono.
  ///
  /// Mismo formato en los dos aparatos a propósito: el atleta mira uno y otro
  /// durante la misma serie, y dos formatos distintos para el mismo número
  /// obligan a traducir mentalmente.
  ///
  /// Se redondea hacia ARRIBA: mostrar 0 durante el último segundo haría
  /// pensar que terminó cuando todavía falta.
  String get _tiempo {
    final total = (timer.remainingMs / 1000).ceil().clamp(0, 359999);
    final min = total ~/ 60;
    final seg = total % 60;
    return '${min.toString().padLeft(2, '0')}:${seg.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final termino = timer.finished;

    // `list` y no `centered`: el andamio centrado NO scrollea, así que cuando
    // el contenido no entra lo RECORTA — se vio en la muñeca con el título
    // cortado arriba y «Cancelar» pegado al borde de abajo. Con la lista, si no
    // entra se scrollea con la corona, que además ya está enganchada acá.
    //
    // El andamio también aporta el `Scaffold` —o sea el `Material`— y el inset
    // circular: sin él Flutter dibuja los textos con el subrayado amarillo de
    // "falta Material".
    // `centered` y no `list`: la lista impone ancho COMPLETO a sus hijos, así
    // que el `SizedBox` del anillo se ignoraba, el `Stack` se estiraba y el
    // indicador salía ELÍPTICO. Se vio en la muñeca. El andamio centrado
    // aporta igual el `Scaffold` —o sea el `Material`— y el inset circular.
    return WearRoundScaffold.centered(
      children: [
        WearFittedText(
          exerciseName,
          maxLines: 1,
          maxSize: 13,
          minSize: 10,
          widthFactor: 0.85,
          styleFor: (size) => GoogleFonts.barlowCondensed(
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        // El `Center` NO es decorativo: sin él, cualquier padre que imponga
        // ancho completo vuelve a deformar el anillo.
        Center(
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: _progreso,
                    strokeWidth: 5,
                    // Track visible: sobre el fondo negro del reloj, un track
                    // oscuro no se distingue y el anillo parece descentrado.
                    backgroundColor: palette.border,
                    // VERDE, igual que el temporizador del teléfono cuando
                    // corre. Es el color de "esto está en marcha" en toda la app.
                    valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                  ),
                ),
                Text(
                  _tiempo,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: termino ? palette.accent : palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        WearEffortRow(effort: effort),
        const SizedBox(height: 10),
        if (termino)
          WearButton(label: 'Marcar serie', onTap: onListo)
        else
          // Ocultar NO cancela: el temporizador sigue corriendo y vibra al
          // vencer igual. Es para poder mirar las series sin perder la cuenta.
          WearButton(
            label: 'Ocultar',
            onTap: onOcultar,
            tint: palette.textMuted,
          ),
        const SizedBox(height: 2),
        // Cancelar va como enlace y no como botón para que no compita con la
        // acción principal: salir del ejercicio es la excepción.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCancelar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
            child: Text(
              'Cancelar',
              style: GoogleFonts.barlow(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.danger,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
