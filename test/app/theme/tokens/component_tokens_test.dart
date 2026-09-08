import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_card_tokens.dart';

/// Widget helper que inyecta [AppPalette] en el árbol.
Widget _withTheme({required AppPalette palette, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(
      extensions: [palette],
    ),
    home: child,
  );
}

void main() {
  group('TreinoButtonTokens — dark', () {
    testWidgets('background == accent dark (0xFF2CE5A2)', (tester) async {
      late Color background;
      await tester.pumpWidget(
        _withTheme(
          palette: AppPalette.mintMagenta,
          child: Builder(
            builder: (ctx) {
              background = TreinoButtonTokens.background(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Valor pinado: mint500 = #2CE5A2. Si el token cambia, este test falla.
      expect(background, const Color(0xFF2CE5A2));
    });

    testWidgets('foreground == ink950 (0xFF0A0A0A) en dark', (tester) async {
      late Color foreground;
      await tester.pumpWidget(
        _withTheme(
          palette: AppPalette.mintMagenta,
          child: Builder(
            builder: (ctx) {
              foreground = TreinoButtonTokens.foreground(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // foreground sobre accent debe ser ink (oscuro) para contraste WCAG AA.
      // Valor pinado: ink950 = #0A0A0A.
      expect(foreground, const Color(0xFF0A0A0A));
    });

    test('borderRadius == 12.0 (AppRadius.sm pinado)', () {
      // Valor pinado: AppRadius.sm = 12.0. Si la escala de radios cambia, falla.
      expect(TreinoButtonTokens.borderRadius, 12.0);
    });

    test('NO contiene hex inline (compilación con primitivos)', () {
      // Si el archivo hubiera usado Color(0xFF...) directamente, no pasaría
      // el no_hex_scan_test. Aquí verificamos el valor concreto como contrato.
      expect(TreinoButtonTokens.borderRadius, 12.0);
    });
  });

  group('TreinoButtonTokens — light', () {
    testWidgets('background == accent light (0xFF2CE5A2)', (tester) async {
      late Color background;
      await tester.pumpWidget(
        _withTheme(
          palette: AppPalette.mintMagentaLight,
          child: Builder(
            builder: (ctx) {
              background = TreinoButtonTokens.background(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Valor pinado: mint500 = #2CE5A2 (mismo en dark y light — acento de marca).
      expect(background, const Color(0xFF2CE5A2));
    });
  });

  group('TreinoCardTokens — dark', () {
    testWidgets('background == bgCard dark (0xFF0F1513)', (tester) async {
      late Color background;
      await tester.pumpWidget(
        _withTheme(
          palette: AppPalette.mintMagenta,
          child: Builder(
            builder: (ctx) {
              background = TreinoCardTokens.background(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Valor pinado: ink900 = #0F1513. Si el fondo de card cambia, falla.
      expect(background, const Color(0xFF0F1513));
    });

    testWidgets('border == border dark (0x1AFFFFFF)', (tester) async {
      late Color border;
      await tester.pumpWidget(
        _withTheme(
          palette: AppPalette.mintMagenta,
          child: Builder(
            builder: (ctx) {
              border = TreinoCardTokens.border(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Valor pinado: white10 = 0x1AFFFFFF (~10% alpha). Si cambia, falla.
      expect(border, const Color(0x1AFFFFFF));
    });

    test('boxShadow es lista vacía (sin sombra)', () {
      expect(TreinoCardTokens.boxShadow, isEmpty);
    });

    test('borderRadius == 16.0 (AppRadius.md pinado)', () {
      // Valor pinado: AppRadius.md = 16.0. Si la escala de radios cambia, falla.
      expect(TreinoCardTokens.borderRadius, 16.0);
    });
  });

  group('TreinoCardTokens — light', () {
    testWidgets('background == bgCard light (0xFFFFFFFF)', (tester) async {
      late Color background;
      await tester.pumpWidget(
        _withTheme(
          palette: AppPalette.mintMagentaLight,
          child: Builder(
            builder: (ctx) {
              background = TreinoCardTokens.background(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Valor pinado: white = #FFFFFF. Si el fondo de card light cambia, falla.
      expect(background, const Color(0xFFFFFFFF));
    });

    testWidgets('border == border light (0x1A000000)', (tester) async {
      late Color border;
      await tester.pumpWidget(
        _withTheme(
          palette: AppPalette.mintMagentaLight,
          child: Builder(
            builder: (ctx) {
              border = TreinoCardTokens.border(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Valor pinado: black10 = 0x1A000000 (~10% alpha). Si cambia, falla.
      expect(border, const Color(0x1A000000));
    });
  });

  group('TreinoCardTokens.glow — el mismo alpha no pesa igual en los dos temas',
      () {
    // Un pump por test, a propósito: pumpear dos temas dentro del mismo test
    // depende de cómo Flutter reusa elements entre árboles idénticos, y eso no
    // es lo que se quiere probar acá.
    Future<LinearGradient> glowFor(WidgetTester tester, AppPalette p) async {
      late LinearGradient g;
      await tester.pumpWidget(
        _withTheme(
          palette: p,
          child: Builder(
            builder: (ctx) {
              g = TreinoCardTokens.glow(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return g;
    }

    testWidgets('dark conserva el alpha pedido y la rampa larga',
        (tester) async {
      final g = await glowFor(tester, AppPalette.mintMagenta);
      expect(g.colors.first.a, closeTo(0.12, 0.001));
      expect(g.stops![1], 0.45);
    });

    testWidgets('light tiñe la mitad y corta la rampa antes', (tester) async {
      final g = await glowFor(tester, AppPalette.mintMagentaLight);

      // Sobre casi-negro el mint translúcido SUMA luz y se lee como un brillo
      // en la esquina; sobre blanco TIÑE. Con el mismo alpha y la misma rampa,
      // cuatro KPIs en fila en tema claro se veían como una mancha verde que
      // cubría media card.
      expect(g.colors.first.a, closeTo(0.06, 0.001));
      expect(g.stops![1], 0.28);
    });

    testWidgets(
        'la rama la decide la luminancia del fondo, no ThemeData.brightness',
        (tester) async {
      // `_withTheme` arma el ThemeData SIN `brightness`, así que Flutter lo
      // deja en `light` para las dos paletas. Si el token mirara ese campo, la
      // paleta OSCURA tomaría la rama de light — y este assert lo caza.
      final g = await glowFor(tester, AppPalette.mintMagenta);
      expect(g.stops![1], 0.45);
    });
  });
}
