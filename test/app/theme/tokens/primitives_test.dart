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

    test('white35 == 0x59FFFFFF (borderStrong dark)', () {
      expect(AppColorPrimitives.white35, const Color(0x59FFFFFF));
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

    test('black50 == 0x80000000 (borderStrong light)', () {
      expect(AppColorPrimitives.black50, const Color(0x80000000));
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

  group('AppTextSize — escala tipográfica', () {
    test('micro == 10', () => expect(AppTextSize.micro, 10));
    test('caption == 12', () => expect(AppTextSize.caption, 12));
    test('bodyDense == 13', () => expect(AppTextSize.bodyDense, 13));
    test('body == 14', () => expect(AppTextSize.body, 14));
    test('bodyLarge == 16', () => expect(AppTextSize.bodyLarge, 16));
    test('title == 18', () => expect(AppTextSize.title, 18));
    test('titleLarge == 20', () => expect(AppTextSize.titleLarge, 20));
    test('heading == 24', () => expect(AppTextSize.heading, 24));
    test('display == 28', () => expect(AppTextSize.display, 28));
    test('displayLarge == 32', () => expect(AppTextSize.displayLarge, 32));

    test('la escala es monótona creciente, sin escalones repetidos', () {
      const scale = [
        AppTextSize.micro,
        AppTextSize.caption,
        AppTextSize.bodyDense,
        AppTextSize.body,
        AppTextSize.bodyLarge,
        AppTextSize.title,
        AppTextSize.titleLarge,
        AppTextSize.heading,
        AppTextSize.display,
        AppTextSize.displayLarge,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(
          scale[i],
          greaterThan(scale[i - 1]),
          reason: 'El escalón $i (${scale[i]}) no es mayor que el anterior '
              '(${scale[i - 1]}). Una escala con un empate o un retroceso deja '
              'de servir para elegir: dos nombres para el mismo número son dos '
              'formas de escribir lo mismo, que es justo lo que el token viene '
              'a sacar.',
        );
      }
    });

    test('arriba de body la escala respira: todos los saltos son >= 2px', () {
      // Los escalones apretados están permitidos SÓLO en el racimo de texto
      // chico (12·13·14), y por una razón concreta: TREINO sirve una app de
      // teléfono y un panel de escritorio desde el mismo código. `caption` es
      // un label, `bodyDense` es una fila de tabla del Coach Hub y `body` es un
      // párrafo en un celular — tres roles reales que se pisan en el rango
      // donde el texto chico vive.
      //
      // De `body` para arriba esa excusa no existe: son títulos y números hero,
      // y ahí dos escalones a un píxel no son dos roles, son deriva. Es lo que
      // pasó con `26` (5 usos) al lado de `28`, o `17` y `19` al lado de `18`.
      const above = [
        AppTextSize.body,
        AppTextSize.bodyLarge,
        AppTextSize.title,
        AppTextSize.titleLarge,
        AppTextSize.heading,
        AppTextSize.display,
        AppTextSize.displayLarge,
      ];
      final tight = <String>[];
      for (var i = 1; i < above.length; i++) {
        if (above[i] - above[i - 1] < 2) {
          tight.add('${above[i - 1]}→${above[i]}');
        }
      }
      expect(
        tight,
        isEmpty,
        reason: 'Escalones a menos de 2px arriba de body: $tight. Si el valor '
            'que necesitás queda pegado a uno existente, lo que necesitás es '
            'el que ya está.',
      );
    });

    test('el racimo de texto chico es exactamente 12·13·14, ni uno más', () {
      // El racimo tiene tres escalones y se cierra ahí. Agregar un cuarto —un
      // `11` con nombre, digamos— reabre exactamente el problema que la escala
      // vino a cerrar: `11` tenía 146 usos un píxel abajo de `caption`,
      // haciendo su mismo trabajo, y nadie podía decir cuál correspondía.
      expect(
        [AppTextSize.caption, AppTextSize.bodyDense, AppTextSize.body],
        [12, 13, 14],
      );
      // El piso del racimo se despega de `micro`: 10 y 12 no compiten.
      expect(AppTextSize.caption - AppTextSize.micro, greaterThanOrEqualTo(2));
    });
  });
}
