import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/shell/content_max_width.dart';

void main() {
  test('Biblioteca usa el techo ancho y el resto conserva 1240', () {
    expect(contentMaxWidthForRoute('/biblioteca'), 1920);
    expect(contentMaxWidthForRoute('/biblioteca/ejercicio/bench-press'), 1920);
    expect(contentMaxWidthForRoute('/dashboard'), 1240);
    expect(contentMaxWidthForRoute('/pagos'), 1240);
  });

  // El editor es una superficie de TRABAJO de dos paneles: la rutina y el
  // catálogo, a la vez. Con el techo de 1240 y el sidebar afuera, a 1280 de
  // viewport quedan 1040 — el panel se lleva 400 y a la rutina 640. En un
  // monitor de 1920 quedaban los MISMOS 640, porque el cap no lo levanta una
  // pantalla más grande. El PF lo reportó como «la lista de ejercicios no se
  // adapta a la pantalla»: no era la lista, era el cap.
  test('el editor de rutina y el de plantilla también salen del cap', () {
    expect(contentMaxWidthForRoute('/routine-editor/abc123'), 1920);
    expect(contentMaxWidthForRoute('/routine-editor/abc123/rut-9'), 1920);
    expect(contentMaxWidthForRoute('/template-editor'), 1920);
    expect(contentMaxWidthForRoute('/template-editor/tpl-4'), 1920);
  });
}
