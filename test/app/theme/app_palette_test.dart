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

  group('AppPalette.podium* tokens (top 3 de Rankings)', () {
    test('las dos paletas exponen los tres metálicos', () {
      for (final p in [AppPalette.mintMagenta, AppPalette.mintMagentaLight]) {
        expect(p.podiumGold, isA<Color>());
        expect(p.podiumSilver, isA<Color>());
        expect(p.podiumBronze, isA<Color>());
      }
    });

    test('dark y light NO comparten valores: el metálico se re-tonaliza', () {
      // Los `reaction*` ya sentaron el precedente. Un metálico pensado para
      // fondo oscuro sobre `bgCard` blanco no llega a 4,5:1 ni cerca — si
      // alguien "simplifica" reusando el mismo primitivo en las dos paletas,
      // esto se pone rojo antes que el test de contraste.
      expect(AppPalette.mintMagenta.podiumGold,
          isNot(AppPalette.mintMagentaLight.podiumGold));
      expect(AppPalette.mintMagenta.podiumSilver,
          isNot(AppPalette.mintMagentaLight.podiumSilver));
      expect(AppPalette.mintMagenta.podiumBronze,
          isNot(AppPalette.mintMagentaLight.podiumBronze));
    });

    test('copyWith() sin args los preserva (exhaustividad)', () {
      final copy = AppPalette.mintMagenta.copyWith();
      expect(copy.podiumGold, AppPalette.mintMagenta.podiumGold);
      expect(copy.podiumSilver, AppPalette.mintMagenta.podiumSilver);
      expect(copy.podiumBronze, AppPalette.mintMagenta.podiumBronze);
    });

    test('copyWith(podiumGold:) sobreescribe sólo ese campo', () {
      final copy =
          AppPalette.mintMagenta.copyWith(podiumGold: const Color(0xFF123456));
      expect(copy.podiumGold, const Color(0xFF123456));
      expect(copy.podiumSilver, AppPalette.mintMagenta.podiumSilver);
      expect(copy.podiumBronze, AppPalette.mintMagenta.podiumBronze);
    });

    test('lerp los interpola sin romper exhaustividad', () {
      const a = AppPalette.mintMagenta;
      final b = a.copyWith(
        podiumGold: const Color(0xFF000000),
        podiumSilver: const Color(0xFF000000),
        podiumBronze: const Color(0xFF000000),
      );
      final result = a.lerp(b, 1.0);
      expect(result.podiumGold, const Color(0xFF000000));
      expect(result.podiumSilver, const Color(0xFF000000));
      expect(result.podiumBronze, const Color(0xFF000000));
    });
  });
}
