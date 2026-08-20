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

    // `centered` y no un `Center` propio: el andamio es el que aporta el
    // `Scaffold` —o sea el `Material`— y el inset de la pantalla redonda. Sin
    // él, Flutter dibuja los `Text` con el subrayado amarillo de "falta
    // Material", el título se corta contra el borde de arriba y el botón se va
    // de pantalla abajo. Se vio en la muñeca.
    return WearRoundScaffold.centered(
      children: [
        // UNA línea: con dos, el título más el anillo más el esfuerzo más los
        // botones pasaban los 206 dp de alto y el botón quedaba cortado contra
        // el borde de abajo. Se vio en la muñeca.
        WearFittedText(
          exerciseName,
          maxLines: 1,
          maxSize: 13,
          minSize: 10,
          widthFactor: 0.9,
          styleFor: (size) => GoogleFonts.barlowCondensed(
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          // Medido para que entren título, anillo, esfuerzo, botón y el enlace
          // de cancelar dentro de los 206 dp del SM-L500.
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // El anillo se lee ANTES que el número cuando el reloj se mira de
              // reojo: la posición dice cuánto falta sin leer.
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: _progreso,
                  strokeWidth: 5,
                  backgroundColor: palette.bgCard,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    termino ? palette.accent : palette.highlight,
                  ),
                ),
              ),
              Text(
                termino ? 'LISTO' : _tiempo,
                style: GoogleFonts.barlowCondensed(
                  fontSize: termino ? 18 : 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        WearEffortRow(effort: effort),
        const SizedBox(height: 8),
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
        const SizedBox(height: 4),
        // Cancelar va como enlace y no como botón para que no compita con la
        // acción principal: salir del ejercicio es la excepción, no lo que el
        // atleta viene a hacer.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCancelar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text(
              'Cancelar',
              style: GoogleFonts.barlow(
                fontSize: 12,
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
