import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/shell/responsive.dart';

void main() {
  group('viewportFor()', () {
    test('ancho < 768 → mobile', () {
      expect(viewportFor(320), Viewport.mobile);
      expect(viewportFor(600), Viewport.mobile);
      expect(viewportFor(767.9), Viewport.mobile);
    });

    test('ancho entre 768 y 1279 → compact', () {
      expect(viewportFor(768), Viewport.compact);
      expect(viewportFor(1100), Viewport.compact);
      expect(viewportFor(1279.9), Viewport.compact);
    });

    test('ancho >= 1280 → desktop', () {
      expect(viewportFor(1280), Viewport.desktop);
      expect(viewportFor(1300), Viewport.desktop);
      expect(viewportFor(1920), Viewport.desktop);
    });

    test('constantes de breakpoint quedan bloqueadas (ADR-CHW-004)', () {
      expect(kMobileBreakpoint, 768);
      expect(kCompactBreakpoint, 1024);
      expect(kDesktopBreakpoint, 1280);
    });
  });
}
