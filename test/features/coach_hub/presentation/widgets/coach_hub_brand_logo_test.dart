import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_logo.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_brand_logo.dart';

Widget _wrap(ThemeData theme, Widget child) => MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    );

/// La capa NÍTIDA del wordmark es la última `SvgPicture` del Stack: las de
/// atrás son las copias desenfocadas del halo (mismo criterio que
/// `treino_logo_test.dart`).
SvgPicture _sharpSvg(WidgetTester tester) =>
    tester.widgetList<SvgPicture>(find.byType(SvgPicture)).last;

/// Contraste WCAG entre dos colores opacos.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('CoachHubBrandLogo', () {
    testWidgets('fondo oscuro: accent con su halo, como el sidebar',
        (tester) async {
      await tester.pumpWidget(
        _wrap(AppTheme.dark(), const CoachHubBrandLogo(size: 26)),
      );
      await tester.pump();

      const palette = AppPalette.mintMagenta;
      final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
      expect(logo.color, palette.accent);
      expect(logo.glow, isTrue);
      expect(
        _sharpSvg(tester).colorFilter,
        ColorFilter.mode(palette.accent, BlendMode.srcIn),
      );
      // Dos copias desenfocadas del halo + la nítida.
      expect(find.byType(SvgPicture), findsNWidgets(3));
    });

    testWidgets(
        'fondo claro: textPrimary y sin halo — NUNCA el mint, que sobre el '
        'papel compone 1,57:1', (tester) async {
      await tester.pumpWidget(
        _wrap(AppTheme.light(), const CoachHubBrandLogo(size: 26)),
      );
      await tester.pump();

      const palette = AppPalette.mintMagentaLight;
      final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
      expect(logo.color, palette.textPrimary);
      expect(logo.color, isNot(palette.accent));
      expect(logo.glow, isFalse);
      expect(
        _sharpSvg(tester).colorFilter,
        ColorFilter.mode(palette.textPrimary, BlendMode.srcIn),
      );
      // Sin halo: sólo la capa nítida.
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    // El candado numérico: el test de arriba dice QUÉ color sale; éste dice
    // que ese color se lee. Si mañana alguien cambia el color de tema claro
    // por otro que pase `isNot(accent)` pero no se vea, cae acá.
    for (final (nombre, theme, palette) in [
      ('oscuro', AppTheme.dark(), AppPalette.mintMagenta),
      ('claro', AppTheme.light(), AppPalette.mintMagentaLight),
    ]) {
      testWidgets('tema $nombre: el wordmark contrasta ≥ 3:1 con el fondo',
          (tester) async {
        await tester.pumpWidget(
          _wrap(theme, const CoachHubBrandLogo(size: 26)),
        );
        await tester.pump();

        final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
        // 3:1 es el piso WCAG 1.4.11 para un gráfico; el wordmark es grande.
        expect(_contrast(logo.color!, palette.bg), greaterThanOrEqualTo(3));
      });
    }

    testWidgets('le pasa el size a TreinoLogo', (tester) async {
      await tester.pumpWidget(
        _wrap(AppTheme.dark(), const CoachHubBrandLogo(size: 48)),
      );
      await tester.pump();

      expect(tester.widget<TreinoLogo>(find.byType(TreinoLogo)).size, 48);
    });

    // La marca era el texto "TREINO", que un lector de pantalla leía. El SVG
    // no tiene texto: sin este label la marca desaparecería del árbol de
    // semántica.
    testWidgets('se anuncia como imagen "TREINO" en el árbol de semántica',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(AppTheme.dark(), const CoachHubBrandLogo(size: 26)),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('TREINO'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('TREINO')),
        matchesSemantics(label: 'TREINO', isImage: true),
      );

      handle.dispose();
    });
  });
}
