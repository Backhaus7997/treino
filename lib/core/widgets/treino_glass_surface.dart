import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

/// Acabado "liquid glass" de TREINO: relleno translúcido + brillo especular
/// diagonal, para que el contenido que pasa por debajo se insinúe sin competir
/// con lo que la superficie contiene.
///
/// **Por qué NO hay `BackdropFilter` acá**: el blur re-samplea en cada frame en
/// el que se mueve contenido por detrás (todas las pantallas del shell corren
/// con `extendBody: true`), y en device tiraba frames incluso a sigma 8
/// (medido 2026-06-11, ver [TreinoBottomBar]). El efecto vidrio se consigue con
/// alpha + gradiente: mismo lenguaje visual, costo cero.
///
/// Se pinta en dos capas anidadas en vez de un [Stack]: el `DecoratedBox`
/// externo aporta el relleno y el borde, el interno el brillo. Así el `child`
/// queda por encima de ambos sin sumar un nivel de layout.
class TreinoGlassSurface extends StatelessWidget {
  const TreinoGlassSurface({
    super.key,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
    this.fillOpacity = surfaceFillOpacity,
    this.borderColor,
    this.child,
  }) : assert(
          shape == BoxShape.rectangle || borderRadius == null,
          'BoxDecoration rechaza borderRadius cuando shape es circle.',
        );

  /// Opacidad para superficies grandes (barra de navegación). Alta a propósito:
  /// la barra tapa contenido en movimiento y por debajo de ~0.75 el texto de
  /// los labels empieza a pelear con los posts que pasan atrás.
  static const double surfaceFillOpacity = 0.82;

  /// Opacidad para burbujas chicas (íconos del header). Pueden ser más
  /// transparentes porque su contenido es un ícono, no texto.
  static const double bubbleFillOpacity = 0.58;

  final BoxShape shape;
  final BorderRadius? borderRadius;
  final double fillOpacity;

  /// Borde. Por defecto `palette.border`; pasá `Colors.transparent` para
  /// superficies que ya viven adentro de otro borde.
  final Color? borderColor;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bgCard.withValues(alpha: fillOpacity),
        shape: shape,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? palette.border),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: borderRadius,
          // Reflejo especular: filo superior-izquierdo iluminado que se apaga
          // antes de la mitad, más un rebote tenue abajo a la derecha. Es el
          // gesto que lee como "vidrio"; subirle el alpha lo vuelve un fondo
          // claro y arruina el contraste del contenido.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.42, 1],
            colors: [
              palette.textPrimary.withValues(alpha: 0.10),
              Colors.transparent,
              palette.textPrimary.withValues(alpha: 0.04),
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}
