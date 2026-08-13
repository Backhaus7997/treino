// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

void main() {
  group('AppColorPrimitives — identidad de valores', () {
    test('mint500 == #2CE5A2', () {
      expect(AppColorPrimitives.mint500, const Color(0xFF2CE5A2));
    });

    test('magenta500 == #C123E0', () {
      expect(AppColorPrimitives.magenta500, const Color(0xFFC123E0));
    });

    test('ink950 == #0A0A0A', () {
      expect(AppColorPrimitives.ink950, const Color(0xFF0A0A0A));
    });

    test('ink900 == #0F1513', () {
      expect(AppColorPrimitives.ink900, const Color(0xFF0F1513));
    });

    test('bone == #FFFFFF', () {
      expect(AppColorPrimitives.bone, const Color(0xFFFFFFFF));
    });

    test('sage500 == #4F6358', () {
      expect(AppColorPrimitives.sage500, const Color(0xFF4F6358));
    });

    test('espresso500 == #3C3534', () {
      expect(AppColorPrimitives.espresso500, const Color(0xFF3C3534));
    });

    test('dangerRed == #E53935', () {
      expect(AppColorPrimitives.dangerRed, const Color(0xFFE53935));
    });

    test('dangerRedDark == #D32F2F', () {
      expect(AppColorPrimitives.dangerRedDark, const Color(0xFFD32F2F));
    });

    test('warningAmber == #FFB300', () {
      expect(AppColorPrimitives.warningAmber, const Color(0xFFFFB300));
    });

    test('warningAmberDark == #FB8C00', () {
      expect(AppColorPrimitives.warningAmberDark, const Color(0xFFFB8C00));
    });

    test('white == #FFFFFF', () {
      expect(AppColorPrimitives.white, const Color(0xFFFFFFFF));
    });

    test('black == #000000', () {
      expect(AppColorPrimitives.black, const Color(0xFF000000));
    });

    test('paper50 == #FAFAFA (fondo light)', () {
      expect(AppColorPrimitives.paper50, const Color(0xFFFAFAFA));
    });

    test('inkText900 == #0F1513 (textPrimary light)', () {
      expect(AppColorPrimitives.inkText900, const Color(0xFF0F1513));
    });

    test('sageTint50 == #DDE5DF (sage light)', () {
      expect(AppColorPrimitives.sageTint50, const Color(0xFFDDE5DF));
    });

    test('espressoTint50 == #EDE5E2 (espresso light)', () {
      expect(AppColorPrimitives.espressoTint50, const Color(0xFFEDE5E2));
    });

    test('white10 == 0x1AFFFFFF (border dark)', () {
      expect(AppColorPrimitives.white10, const Color(0x1AFFFFFF));
    });

    test('white20 == 0x33FFFFFF (borderHover dark)', () {
      expect(AppColorPrimitives.white20, const Color(0x33FFFFFF));
    });

    test('white55 == 0x8CFFFFFF (textMuted dark)', () {
      expect(AppColorPrimitives.white55, const Color(0x8CFFFFFF));
    });

    test('black10 == 0x1A000000 (border light)', () {
      expect(AppColorPrimitives.black10, const Color(0x1A000000));
    });

    test('black20 == 0x33000000 (borderHover light)', () {
      expect(AppColorPrimitives.black20, const Color(0x33000000));
    });

    test('black60 == 0x99000000 (textMuted light)', () {
      expect(AppColorPrimitives.black60, const Color(0x99000000));
    });

    test('transparent == 0x00000000', () {
      expect(AppColorPrimitives.transparent, const Color(0x00000000));
      expect(AppColorPrimitives.transparent, Colors.transparent);
    });

    test('todos los miembros son static const (sin BuildContext)', () {
      // Si el acceso falla en este contexto sin widget tree, el test explota.
      // El hecho de que compile y ejecute confirma que no requiere BuildContext.
      const values = [
        AppColorPrimitives.mint500,
        AppColorPrimitives.magenta500,
        AppColorPrimitives.ink950,
        AppColorPrimitives.ink900,
        AppColorPrimitives.bone,
        AppColorPrimitives.sage500,
        AppColorPrimitives.espresso500,
        AppColorPrimitives.dangerRed,
        AppColorPrimitives.dangerRedDark,
        AppColorPrimitives.warningAmber,
        AppColorPrimitives.warningAmberDark,
        AppColorPrimitives.white,
        AppColorPrimitives.black,
        AppColorPrimitives.paper50,
        AppColorPrimitives.inkText900,
        AppColorPrimitives.sageTint50,
        AppColorPrimitives.espressoTint50,
        AppColorPrimitives.white10,
        AppColorPrimitives.white20,
        AppColorPrimitives.white55,
        AppColorPrimitives.black10,
        AppColorPrimitives.black20,
        AppColorPrimitives.black60,
        AppColorPrimitives.transparent,
      ];
      expect(values, everyElement(isA<Color>()));
    });
  });

  group('AppSpacing — escala cerrada', () {
    test('s8 == 8.0', () => expect(AppSpacing.s8, 8.0));
    test('s12 == 12.0', () => expect(AppSpacing.s12, 12.0));
    test('s14 == 14.0', () => expect(AppSpacing.s14, 14.0));
    test('s18 == 18.0', () => expect(AppSpacing.s18, 18.0));
    test('s20 == 20.0', () => expect(AppSpacing.s20, 20.0));

    test(
      'hairline == 4.0 (única excepción sub-8, micro-gap)',
      () => expect(AppSpacing.hairline, 4.0),
    );
  });

  group('AppRadius — radios del sistema', () {
    test('sm == 12.0', () => expect(AppRadius.sm, 12.0));
    test('md == 16.0', () => expect(AppRadius.md, 16.0));
    test('lg == 20.0', () => expect(AppRadius.lg, 20.0));
    test('full == 9999.0', () => expect(AppRadius.full, 9999.0));
  });

  group('AppFonts — familias tipográficas', () {
    test("barlow == 'Barlow'", () => expect(AppFonts.barlow, 'Barlow'));
    test(
      "barlowCondensed == 'Barlow Condensed'",
      () => expect(AppFonts.barlowCondensed, 'Barlow Condensed'),
    );
  });
}
