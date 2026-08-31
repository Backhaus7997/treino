/// Los botones que agregan cosas al editor de rutina, con una sola geometría.
///
/// La revisión en device del 28/08 los encontró como lo peor que se veía en la
/// pantalla: `+ Agregar set`, `Agregar ejercicio` y `+ Superserie` eran tres
/// `TextButton.icon` sin contenedor, alineados a la izquierda en tres márgenes
/// distintos y sin alto ni ancho compartidos. Se leían como una lista despareja
/// de links, no como acciones.
///
/// Viven en un archivo porque el problema era justamente que no compartían
/// nada: separarlos es lo que dejó que cada uno derivara por su lado.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Alto de todos los botones de acción, en dp.
///
/// El handoff pedía 44 para "+ Agregar set" y 48 para los del día. Van los tres
/// a 48: el criterio de aceptación de la épica #862 dice que ningún target
/// interactivo queda por debajo de 48 dp, y la jerarquía entre "agregar set" y
/// "agregar ejercicio" ya la carga el contorno punteado contra el relleno
/// sólido — no necesita cuatro dp que nadie percibe y que sí achican el área
/// que se toca.
const double _kAltoAccion = 48;

/// Ancho del botón secundario del día. Del handoff.
const double _kAnchoSuperserie = 140;

/// Relleno del botón primario, sobre 255. `accentText` encima mide 9,00:1 en
/// dark y 4,99:1 en light — AA con margen en las dos paletas.
const int _kRellenoPrimario = 30;

/// Relleno del botón secundario, sobre 255.
const int _kRellenoSecundario = 36;

/// Opacidad del contorno punteado, sobre 255. Da 7,27:1 en dark y 3,54:1 en
/// light contra la card: el contorno es lo ÚNICO que delimita este botón —no
/// tiene relleno—, así que le aplica el 3:1 de SC 1.4.11 sin atenuantes.
///
/// Va sobre `accentText`, no sobre `accent`. El mint pleno sobre papel mide
/// **1,64:1 incluso al 100% de opacidad**: como contorno en tema claro no se ve
/// a ninguna intensidad. Es el mismo motivo por el que `accentText` existe.
const int _kContornoPunteado = 200;

/// Fila de acciones de un día: agregar un ejercicio suelto, o una superserie.
///
/// Antes eran dos botones apilados a ancho completo, cada uno con su propio
/// padding heredado. Acá comparten fila, alto y radio, y el peso visual dice
/// cuál es la acción primaria.
class DayActionButtons extends StatelessWidget {
  const DayActionButtons({
    required this.exerciseLabel,
    required this.onAddExercise,
    this.supersetLabel,
    this.onAddSuperset,
    super.key,
  });

  final String exerciseLabel;
  final VoidCallback? onAddExercise;

  /// Cuando es null, la fila renderiza sólo el botón de ejercicio, que pasa a
  /// ocupar el ancho completo.
  final String? supersetLabel;
  final VoidCallback? onAddSuperset;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final muestraSuperserie = supersetLabel != null;

    return Row(
      children: [
        Expanded(
          child: _BotonAccion(
            key: const Key('day_add_exercise_button'),
            label: exerciseLabel,
            icon: TreinoIcon.plus,
            relleno: palette.accent.withAlpha(_kRellenoPrimario),
            tinta: palette.accentText,
            colorIcono: palette.accentText,
            onPressed: onAddExercise,
          ),
        ),
        if (muestraSuperserie) ...[
          const SizedBox(width: AppSpacing.s8),
          SizedBox(
            width: _kAnchoSuperserie,
            child: _BotonAccion(
              key: const Key('add_superset_button'),
              label: supersetLabel!,
              icon: TreinoIcon.streak,
              relleno: palette.highlight.withAlpha(_kRellenoSecundario),
              // El magenta pleno sobre este relleno mide 3,65:1 (dark) y
              // 3,70:1 (light): alcanza para un ícono —SC 1.4.11 pide 3:1— y
              // NO para texto chico, que pide 4,5:1. Misma razón por la que
              // existe `accentText` para el mint. El label va en textPrimary.
              tinta: palette.textPrimary,
              colorIcono: palette.highlight,
              onPressed: onAddSuperset,
            ),
          ),
        ],
      ],
    );
  }
}

/// "+ Agregar set" — la acción de menor jerarquía del editor.
///
/// Contorno punteado y sin relleno: es la única acción que se repite dentro de
/// cada ejercicio, y con relleno sólido competiría con la fila del día. Las
/// rayas son lo que la marca como "sumá una fila acá", igual que en el deck de
/// onboarding de ejercicio propio.
class AddSetButton extends StatelessWidget {
  const AddSetButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SizedBox(
      width: double.infinity,
      height: _kAltoAccion,
      child: CustomPaint(
        painter: _ContornoPunteado(
          color: palette.accentText.withAlpha(_kContornoPunteado),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(TreinoIcon.plus, size: 14, color: palette.accentText),
                const SizedBox(width: AppSpacing.hairline),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.accentText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// Botón relleno de alto fijo. Privado: la geometría es lo que este archivo
/// existe para mantener igual entre las acciones.
class _BotonAccion extends StatelessWidget {
  const _BotonAccion({
    required this.label,
    required this.icon,
    required this.relleno,
    required this.tinta,
    required this.colorIcono,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color relleno;
  final Color tinta;
  final Color colorIcono;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kAltoAccion,
      child: Material(
        color: relleno,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: colorIcono),
                const SizedBox(width: AppSpacing.hairline),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: tinta,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// Contorno punteado. Flutter no trae bordes con rayas, así que hay que
/// recorrer el path y dibujar tramos — misma técnica que el deck de onboarding
/// de ejercicio propio, que fue el primero que la necesitó.
class _ContornoPunteado extends CustomPainter {
  const _ContornoPunteado({required this.color});

  final Color color;

  static const double _raya = 4;
  static const double _hueco = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadius.sm),
    );
    final trazo = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distancia = 0.0;
      while (distancia < metric.length) {
        final fin = (distancia + _raya).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distancia, fin), trazo);
        distancia = fin + _hueco;
      }
    }
  }

  @override
  bool shouldRepaint(_ContornoPunteado old) => old.color != color;
}
