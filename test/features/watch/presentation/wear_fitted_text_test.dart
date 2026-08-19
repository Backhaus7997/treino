import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/presentation/wear/wear_fitted_text.dart';

void main() {
  // Ancho útil real del SM-L500: 438 px de pantalla menos el inset del 5.2%
  // por lado, por el widthFactor del título.
  const ancho = 345.0;

  TextStyle estilo(double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.1,
      );

  double medir(String texto, {int maxLines = 3}) => wearFittedFontSize(
        text: texto,
        maxWidth: ancho,
        styleFor: estilo,
        maxLines: maxLines,
        maxSize: 20,
        minSize: 13,
      );

  test('un nombre corto se queda en el tamaño grande', () {
    expect(medir('Sentadilla'), 20);
  });

  test('el nombre que rompió la pantalla queda legible, no diminuto', () {
    // El caso medido en la muñeca: con el `FittedBox` anterior esto terminaba
    // en UNA línea de borde a borde, ilegible de reojo.
    const largo =
        'movilidad de hombros rotación interna por espalda con baston';

    final size = medir(largo);

    // Nunca por debajo del piso: ése es el `minimumScaleFactor` que se había
    // perdido al portar desde watchOS.
    expect(size, greaterThanOrEqualTo(13));
    expect(size, lessThanOrEqualTo(20));
  });

  test('prefiere ENVOLVER antes que achicar', () {
    // Con más renglones disponibles tiene que poder usar una letra más grande.
    // Si el cálculo ignorara `maxLines`, las dos mediciones darían igual.
    const largo =
        'movilidad de hombros rotación interna por espalda con baston';

    expect(medir(largo, maxLines: 3), greaterThan(medir(largo, maxLines: 1)));
  });

  test('si no entra ni al mínimo, devuelve el mínimo y no sigue bajando', () {
    final size = medir('palabra ' * 80);
    expect(size, 13);
  });

  test('texto vacío o ancho cero no rompen', () {
    expect(medir(''), 20);
    expect(
      wearFittedFontSize(
        text: 'algo',
        maxWidth: 0,
        styleFor: estilo,
        maxLines: 3,
        maxSize: 20,
        minSize: 13,
      ),
      20,
    );
  });
}
