import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/shell/content_max_width.dart';

void main() {
  test('Biblioteca usa el techo ancho y el resto conserva 1240', () {
    expect(contentMaxWidthForRoute('/biblioteca'), 1920);
    expect(contentMaxWidthForRoute('/biblioteca/ejercicio/bench-press'), 1920);
    expect(contentMaxWidthForRoute('/dashboard'), 1240);
    expect(contentMaxWidthForRoute('/pagos'), 1240);
  });
}
