import 'package:flutter/widgets.dart';

/// El tamaño de fuente más GRANDE con el que [text] entra en [maxLines].
///
/// ## Por qué no alcanza un `FittedBox`
///
/// `FittedBox(fit: scaleDown)` mide a su hijo sin restricción de ancho, así que
/// un `Text` sin `maxLines` se calcula como UNA línea infinita y después se
/// escala entera para que entre. El resultado con nombres largos es un texto
/// diminuto de borde a borde: medido en el SM-L500, "movilidad de hombros
/// rotación interna por espalda con baston" quedaba en una sola línea de 392 px
/// —ilegible de reojo, que es la única forma en que se mira un reloj— y metida
/// en la zona curva de la pantalla, donde el círculo ya se está cerrando.
///
/// Y no tenía piso. El original de watchOS era `minimumScaleFactor(0.7)`: un
/// TOPE de cuánto se permite achicar. Al portarlo a `FittedBox` ese tope se
/// perdió, y sin él la escala baja todo lo que haga falta.
///
/// Acá se busca al revés: se prueban tamaños de [maxSize] para abajo y se
/// devuelve el primero que entra en [maxLines] renglones dentro de [maxWidth].
/// Envolver en dos o tres líneas conserva el tamaño de letra; achicar, no.
///
/// Si ni [minSize] alcanza, devuelve [minSize] y quien dibuja corta con
/// ellipsis: llegado ese extremo es preferible un nombre cortado y legible que
/// uno entero que no se puede leer.
///
/// [styleFor] arma el estilo para un tamaño dado. Se inyecta para que la medición
/// use la MISMA tipografía que el dibujo — medir con otra fuente daría un tamaño
/// que después no entra.
double wearFittedFontSize({
  required String text,
  required double maxWidth,
  required TextStyle Function(double size) styleFor,
  required int maxLines,
  required double maxSize,
  required double minSize,
  double textScaleFactor = 1,
  TextDirection textDirection = TextDirection.ltr,
}) {
  if (text.isEmpty || maxWidth <= 0) return maxSize;

  for (var size = maxSize; size > minSize; size -= 1) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: styleFor(size)),
      maxLines: maxLines,
      textDirection: textDirection,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout(maxWidth: maxWidth);
    final entra = !painter.didExceedMaxLines;
    painter.dispose();
    if (entra) return size;
  }
  return minSize;
}

/// Texto que se achica sólo lo necesario, después de envolver.
///
/// Reemplaza al `FittedBox` para los títulos del reloj. Ver [wearFittedFontSize]
/// para el porqué.
class WearFittedText extends StatelessWidget {
  const WearFittedText(
    this.text, {
    super.key,
    required this.styleFor,
    this.maxLines = 3,
    this.maxSize = 20,
    this.minSize = 13,
    this.widthFactor = 1,
    this.textAlign = TextAlign.center,
  });

  final String text;

  /// El estilo para un tamaño dado. Se usa para MEDIR y para DIBUJAR, así que
  /// no pueden divergir.
  final TextStyle Function(double size) styleFor;

  final int maxLines;
  final double maxSize;
  final double minSize;

  /// Qué fracción del ancho disponible puede ocupar.
  ///
  /// En una pantalla REDONDA el ancho útil no es constante: arriba y abajo el
  /// círculo se cierra. El título vive en la franja alta, así que ocupar el
  /// 100% del ancho lo mete en la curva. Achicar la caja acerca el texto al eje
  /// central, que es la parte ancha.
  final double widthFactor;

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth.isFinite
            ? constraints.maxWidth * widthFactor
            : 0.0;
        final size = wearFittedFontSize(
          text: text,
          maxWidth: ancho,
          styleFor: styleFor,
          maxLines: maxLines,
          maxSize: maxSize,
          minSize: minSize,
          textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
          textDirection: Directionality.of(context),
        );
        return SizedBox(
          width: ancho,
          child: Text(
            text,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: styleFor(size),
          ),
        );
      },
    );
  }
}
