import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';

void main() {
  group('AppPalette.borderHover token', () {
    test('mintMagenta expone un borderHover no nulo', () {
      expect(AppPalette.mintMagenta.borderHover, isNotNull);
      expect(AppPalette.mintMagenta.borderHover, isA<Color>());
    });

    test('borderHover por defecto es 0x33FFFFFF (~20% blanco)', () {
      expect(AppPalette.mintMagenta.borderHover, const Color(0x33FFFFFF));
    });

    test('borderHover es más brillante (mayor alpha) que border', () {
      expect(
        AppPalette.mintMagenta.borderHover.a,
        greaterThan(AppPalette.mintMagenta.border.a),
      );
    });

    test('copyWith() sin args preserva borderHover (exhaustividad)', () {
      final copy = AppPalette.mintMagenta.copyWith();
      expect(copy.borderHover, AppPalette.mintMagenta.borderHover);
    });

    test('copyWith(borderHover:) sobreescribe sólo ese campo', () {
      final copy =
          AppPalette.mintMagenta.copyWith(borderHover: const Color(0x40FFFFFF));
      expect(copy.borderHover, const Color(0x40FFFFFF));
      expect(copy.border, AppPalette.mintMagenta.border);
    });

    test('lerp interpola borderHover sin romper exhaustividad', () {
      const a = AppPalette.mintMagenta;
      final b = a.copyWith(borderHover: const Color(0x00FFFFFF));
      final result = a.lerp(b, 1.0);
      expect(result.borderHover, const Color(0x00FFFFFF));
    });
  });

  group('AppPalette.borderStrong token (#821)', () {
    test('las dos paletas lo exponen', () {
      expect(AppPalette.mintMagenta.borderStrong, isA<Color>());
      expect(AppPalette.mintMagentaLight.borderStrong, isA<Color>());
    });

    test('en dark es 0x59FFFFFF (~35% blanco)', () {
      expect(AppPalette.mintMagenta.borderStrong, const Color(0x59FFFFFF));
    });

    test('en light es 0x80000000 (~50% negro)', () {
      expect(AppPalette.mintMagentaLight.borderStrong, const Color(0x80000000));
    });

    test('tiene más alpha que border y que borderHover en las dos paletas', () {
      for (final p in [AppPalette.mintMagenta, AppPalette.mintMagentaLight]) {
        expect(p.borderStrong.a, greaterThan(p.border.a));
        expect(p.borderStrong.a, greaterThan(p.borderHover.a));
      }
    });

    test('copyWith() sin args lo preserva (exhaustividad)', () {
      final copy = AppPalette.mintMagenta.copyWith();
      expect(copy.borderStrong, AppPalette.mintMagenta.borderStrong);
    });

    test('copyWith(borderStrong:) sobreescribe sólo ese campo', () {
      final copy = AppPalette.mintMagenta
          .copyWith(borderStrong: const Color(0x40FFFFFF));
      expect(copy.borderStrong, const Color(0x40FFFFFF));
      expect(copy.border, AppPalette.mintMagenta.border);
      expect(copy.borderHover, AppPalette.mintMagenta.borderHover);
    });

    test('lerp lo interpola sin romper exhaustividad', () {
      const a = AppPalette.mintMagenta;
      final b = a.copyWith(borderStrong: const Color(0x00FFFFFF));
      expect(a.lerp(b, 1.0).borderStrong, const Color(0x00FFFFFF));
    });
  });
}
