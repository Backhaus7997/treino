// Los estados de interacción del tema: hover / foco / pressed / splash y el
// thumb del scrollbar.
//
// Sin ellos rige el default de Material 3, que pinta el overlay con
// `colorScheme.onSurface` al 8%. En este tema `onSurface` es
// `palette.textPrimary`, que EN CLARO ES CASI NEGRO: pasar el mouse por un
// `ListTile` dibujaba un bloque gris que no pertenece a ninguna paleta del
// sistema.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';

void main() {
  // `AppTheme.*` resuelve las fuentes con `google_fonts`, que necesita el
  // binding. Sin esta línea el archivo entero muere antes del primer test con
  // un error que habla de fuentes y no de lo que se está probando.
  TestWidgetsFlutterBinding.ensureInitialized();

  final temas = {
    'dark': (AppTheme.dark(), AppPalette.mintMagenta),
    'light': (AppTheme.light(), AppPalette.mintMagentaLight),
  };

  group('los cuatro estados salen de la paleta, no de Material', () {
    temas.forEach((nombre, par) {
      final (tema, palette) = par;

      test('$nombre: hover/foco/pressed/splash tiñen con accent', () {
        for (final (etiqueta, color) in [
          ('hoverColor', tema.hoverColor),
          ('focusColor', tema.focusColor),
          ('highlightColor', tema.highlightColor),
          ('splashColor', tema.splashColor),
        ]) {
          // El canal, no el color completo: cada estado usa su propia alfa.
          expect(color.r, palette.accent.r, reason: '$etiqueta.r');
          expect(color.g, palette.accent.g, reason: '$etiqueta.g');
          expect(color.b, palette.accent.b, reason: '$etiqueta.b');
        }
      });

      test('$nombre: el hover NO es el gris de onSurface de Material', () {
        // ESTA es la afirmación que importa. Sin ella, un test que sólo mire
        // "hoverColor no es null" pasa con el default puesto.
        expect(tema.hoverColor.r, isNot(palette.textPrimary.r));
      });

      test('$nombre: el hover es una insinuación, no un relleno', () {
        // Arriba de ~0.15 deja de leerse como superficie y empieza a leerse
        // como un bloque de color, que es justo lo que se estaba arreglando.
        expect(tema.hoverColor.a, lessThan(0.15));
        expect(tema.hoverColor.a, greaterThan(0));
      });

      test('$nombre: el thumb del scrollbar sale de la paleta y se aclara',
          () {
        // En el sidebar aparecía como una píldora gris oscura flotando al
        // costado de los items, sin relación con nada.
        final thumb = tema.scrollbarTheme.thumbColor;
        expect(thumb, isNotNull);

        final reposo = thumb!.resolve({});
        final encima = thumb.resolve({WidgetState.hovered});
        expect(reposo!.r, palette.textMuted.r);
        // Se marca al pasar el mouse: si fuera igual, el scrollbar no diría
        // que es agarrable.
        expect(encima!.a, greaterThan(reposo.a));
      });
    });
  });

  group('la igualdad del tema — la regla 6 de AGENTS.md', () {
    test('dos temas de la misma paleta comparten scrollbarTheme igual', () {
      // ESTA es la invariante cara. La forma natural de escribir el thumb es
      // `WidgetStateProperty.resolveWith((states) => ...)`, y su clase interna
      // NO define `==`: cada construccion del tema devuelve una instancia
      // nueva, el `ThemeData` nunca compara igual, y todo lo que depende del
      // tema se reconstruye en cada frame.
      //
      // El sintoma barato fueron cuatro tests de `core/widgets/motion` con
      // `hasRunningAnimations` en `true` para siempre. El caro es que la app
      // entera rebuildea desde el tema.
      expect(
        AppTheme.dark().scrollbarTheme,
        AppTheme.dark().scrollbarTheme,
      );
      expect(
        AppTheme.light().scrollbarTheme,
        AppTheme.light().scrollbarTheme,
      );
    });

    test('paletas distintas dan thumbs distintos', () {
      // Sin esto, un `==` que devolviera siempre true pasaria el test de
      // arriba y romperia el tema claro en silencio.
      expect(
        AppTheme.dark().scrollbarTheme == AppTheme.light().scrollbarTheme,
        isFalse,
      );
    });
  });
}
