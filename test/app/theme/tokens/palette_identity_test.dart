import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';

/// Test de identidad de valor — guard anti-deriva.
///
/// Pina los valores ARGB EXACTOS de [AppPalette.mintMagenta] y
/// [AppPalette.mintMagentaLight] tal como estaban ANTES de la refactorización
/// a primitivos. Si algún campo cambia su valor en runtime, este test falla.
///
/// TDD: test escrito ANTES de tocar app_palette.dart.
void main() {
  group('AppPalette.mintMagenta — identidad dark (valores pinados)', () {
    const p = AppPalette.mintMagenta;

    test('accent == 0xFF2CE5A2',
        () => expect(p.accent, const Color(0xFF2CE5A2)));
    test('highlight == 0xFFC123E0',
        () => expect(p.highlight, const Color(0xFFC123E0)));
    test('bg == 0xFF0A0A0A', () => expect(p.bg, const Color(0xFF0A0A0A)));
    test('bgCard == 0xFF0F1513',
        () => expect(p.bgCard, const Color(0xFF0F1513)));
    test('border == 0x1AFFFFFF',
        () => expect(p.border, const Color(0x1AFFFFFF)));
    test('borderHover == 0x33FFFFFF',
        () => expect(p.borderHover, const Color(0x33FFFFFF)));
    test('textPrimary == 0xFFFFFFFF',
        () => expect(p.textPrimary, const Color(0xFFFFFFFF)));
    test('textMuted == 0x8CFFFFFF',
        () => expect(p.textMuted, const Color(0x8CFFFFFF)));
    test('sage == 0xFF4F6358', () => expect(p.sage, const Color(0xFF4F6358)));
    test('espresso == 0xFF3C3534',
        () => expect(p.espresso, const Color(0xFF3C3534)));
    test('danger == 0xFFE53935',
        () => expect(p.danger, const Color(0xFFE53935)));
    test('warning == 0xFFFFB300',
        () => expect(p.warning, const Color(0xFFFFB300)));
    test('onDanger == 0xFFFFFFFF',
        () => expect(p.onDanger, const Color(0xFFFFFFFF)));
    test('scrimDark == 0xFF000000',
        () => expect(p.scrimDark, const Color(0xFF000000)));
  });

  group('AppPalette.mintMagentaLight — identidad light (valores pinados)', () {
    const p = AppPalette.mintMagentaLight;

    test('accent == 0xFF2CE5A2',
        () => expect(p.accent, const Color(0xFF2CE5A2)));
    test('highlight == 0xFFC123E0',
        () => expect(p.highlight, const Color(0xFFC123E0)));
    test('bg == 0xFFFAFAFA', () => expect(p.bg, const Color(0xFFFAFAFA)));
    test('bgCard == 0xFFFFFFFF',
        () => expect(p.bgCard, const Color(0xFFFFFFFF)));
    test('border == 0x1A000000',
        () => expect(p.border, const Color(0x1A000000)));
    test('borderHover == 0x33000000',
        () => expect(p.borderHover, const Color(0x33000000)));
    test('textPrimary == 0xFF0F1513',
        () => expect(p.textPrimary, const Color(0xFF0F1513)));
    test('textMuted == 0x99000000',
        () => expect(p.textMuted, const Color(0x99000000)));
    test('sage == 0xFFDDE5DF', () => expect(p.sage, const Color(0xFFDDE5DF)));
    test('espresso == 0xFFEDE5E2',
        () => expect(p.espresso, const Color(0xFFEDE5E2)));
    test('danger == 0xFFD32F2F',
        () => expect(p.danger, const Color(0xFFD32F2F)));
    test('warning == 0xFFFB8C00',
        () => expect(p.warning, const Color(0xFFFB8C00)));
    test('onDanger == 0xFFFFFFFF',
        () => expect(p.onDanger, const Color(0xFFFFFFFF)));
    test('scrimDark == 0xFF000000',
        () => expect(p.scrimDark, const Color(0xFF000000)));
  });

  group('AppPalette — API compat', () {
    test('of() existe como método estático (compilación)', () {
      // No podemos llamar of() sin BuildContext, pero sí verificar que la
      // constante no compila si la firma cambió — basta con instanciar.
      expect(AppPalette.mintMagenta, isA<AppPalette>());
    });

    test('copyWith() sin args retorna instancia con mismos valores', () {
      final copy = AppPalette.mintMagenta.copyWith();
      expect(copy.accent, AppPalette.mintMagenta.accent);
      expect(copy.bg, AppPalette.mintMagenta.bg);
      expect(copy.scrimDark, AppPalette.mintMagenta.scrimDark);
    });

    test('copyWith(accent:) sobreescribe solo accent', () {
      final copy =
          AppPalette.mintMagenta.copyWith(accent: const Color(0xFFFF0000));
      expect(copy.accent, const Color(0xFFFF0000));
      expect(copy.bg, AppPalette.mintMagenta.bg);
    });

    test('lerp con t=0 retorna this', () {
      final result =
          AppPalette.mintMagenta.lerp(AppPalette.mintMagentaLight, 0.0);
      expect(result.accent, AppPalette.mintMagenta.accent);
      expect(result.bg, AppPalette.mintMagenta.bg);
    });

    test('lerp con t=1 retorna other', () {
      final result =
          AppPalette.mintMagenta.lerp(AppPalette.mintMagentaLight, 1.0);
      expect(result.bg, AppPalette.mintMagentaLight.bg);
    });

    test('mintMagenta.bg != mintMagentaLight.bg (dark vs light distinguibles)',
        () {
      expect(AppPalette.mintMagenta.bg, isNot(AppPalette.mintMagentaLight.bg));
    });
  });

  group('AppPalette — trazabilidad dark a primitivos (post-refactor)', () {
    // Estos tests TAMBIÉN pasan con hex hardcoded (antes del refactor).
    // Son el contrato de valor: si los primitivos apuntan al valor correcto,
    // pasan. Si el refactor introduce drift, fallan.
    test('mintMagenta.accent == AppColorPrimitives.mint500 (bit a bit)', () {
      expect(AppPalette.mintMagenta.accent, const Color(0xFF2CE5A2));
    });

    test('mintMagenta.bg == AppColorPrimitives.ink950 (bit a bit)', () {
      expect(AppPalette.mintMagenta.bg, const Color(0xFF0A0A0A));
    });

    test('mintMagenta.bgCard == AppColorPrimitives.ink900 (bit a bit)', () {
      expect(AppPalette.mintMagenta.bgCard, const Color(0xFF0F1513));
    });
  });
}
