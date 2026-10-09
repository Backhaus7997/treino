import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/presentation/widgets/carto_tiles.dart';

const _base =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

void main() {
  group('cartoTileUrl', () {
    test('sin key devuelve la URL de siempre, sin ?key=', () {
      expect(cartoTileUrl(''), _base);
    });

    test('con key la agrega como parámetro al final de la URL', () {
      expect(cartoTileUrl('abc123'), '$_base?key=abc123');
    });
  });
}
