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
}
