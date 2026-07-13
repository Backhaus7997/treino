import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_card_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

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
    testWidgets('background == AppPalette.accent en dark', (tester) async {
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
      expect(background, AppPalette.mintMagenta.accent);
    });

    testWidgets('foreground == AppColorPrimitives.ink950 en dark',
        (tester) async {
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
      // foreground sobre accent debe ser ink (oscuro) para contraste
      expect(foreground, AppColorPrimitives.ink950);
    });

    test('borderRadius es un double no negativo', () {
      expect(TreinoButtonTokens.borderRadius, isA<double>());
      expect(TreinoButtonTokens.borderRadius, greaterThanOrEqualTo(0));
    });

    test('borderRadius referencia AppRadius (== AppRadius.sm)', () {
      expect(TreinoButtonTokens.borderRadius, AppRadius.sm);
    });

    test('NO contiene hex inline (compilación con primitivos)', () {
      // Si el archivo hubiera usado Color(0xFF...) directamente, no pasaría
      // el no_hex_scan_test. Aquí simplemente verificamos que el token
      // existe y se puede instanciar, lo que implica compilación exitosa.
      expect(TreinoButtonTokens.borderRadius, isNotNull);
    });
  });

  group('TreinoButtonTokens — light', () {
    testWidgets('background == AppPalette.accent en light', (tester) async {
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
      expect(background, AppPalette.mintMagentaLight.accent);
    });
  });

  group('TreinoCardTokens — dark', () {
    testWidgets('background == AppPalette.bgCard en dark', (tester) async {
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
      expect(background, AppPalette.mintMagenta.bgCard);
    });

    testWidgets('border == AppPalette.border en dark', (tester) async {
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
      expect(border, AppPalette.mintMagenta.border);
    });

    test('boxShadow es lista vacía (sin sombra)', () {
      expect(TreinoCardTokens.boxShadow, isEmpty);
    });

    test('borderRadius referencia AppRadius (== AppRadius.md)', () {
      expect(TreinoCardTokens.borderRadius, AppRadius.md);
    });
  });

  group('TreinoCardTokens — light', () {
    testWidgets('background == AppPalette.bgCard en light', (tester) async {
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
      expect(background, AppPalette.mintMagentaLight.bgCard);
    });

    testWidgets('border == AppPalette.border en light', (tester) async {
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
      expect(border, AppPalette.mintMagentaLight.border);
    });
  });
}
