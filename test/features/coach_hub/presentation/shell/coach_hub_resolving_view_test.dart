import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_logo.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_resolving_view.dart';

/// El indicador de progreso anima para siempre: `pumpAndSettle` no volvería.
/// Un `pump` alcanza para montar el árbol.
Future<void> _pumpView(
  WidgetTester tester, {
  required ThemeData theme,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(theme: theme, home: const CoachHubResolvingView()),
  );
  await tester.pump();
}

/// Contraste WCAG de [fg] sobre [bg], componiendo primero el alfa de [fg]:
/// `textMuted` es translúcido, y medirlo sin componer da un número que nadie ve.
double _contrast(Color fg, Color bg) {
  final solid = Color.alphaBlend(fg, bg);
  final a = solid.computeLuminance(), b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  group('CoachHubResolvingView', () {
    testWidgets('es neutra: fondo del tema, el logo y un progreso — sin texto',
        (tester) async {
      await _pumpView(tester, theme: AppTheme.dark());

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppPalette.mintMagenta.bg,
      );
      expect(find.byType(TreinoLogo), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Nada que pueda ser mentira: ni «Coach Hub en escritorio» ni ningún
      // otro mensaje.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('el logo y el progreso quedan centrados en la pantalla',
        (tester) async {
      await _pumpView(tester, theme: AppTheme.dark());

      final center = tester.getCenter(find.byType(Scaffold));
      final logoCenter = tester.getCenter(find.byType(TreinoLogo));
      expect(logoCenter.dx, closeTo(center.dx, 0.5));

      // El bloque logo + progreso está centrado como conjunto: el punto medio
      // entre el borde de arriba del logo y el de abajo del progreso cae en el
      // centro vertical.
      final top = tester.getTopLeft(find.byType(TreinoLogo)).dy;
      final bottom =
          tester.getBottomLeft(find.byType(CircularProgressIndicator)).dy;
      expect((top + bottom) / 2, closeTo(center.dy, 1));
    });

    testWidgets('tema oscuro: el wordmark va en accent', (tester) async {
      await _pumpView(tester, theme: AppTheme.dark());

      expect(
        tester.widget<TreinoLogo>(find.byType(TreinoLogo)).color,
        AppPalette.mintMagenta.accent,
      );
    });

    testWidgets('tema claro: el wordmark NO va en accent', (tester) async {
      await _pumpView(tester, theme: AppTheme.light());

      final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
      expect(logo.color, isNot(AppPalette.mintMagentaLight.accent));
      expect(logo.color, AppPalette.mintMagentaLight.textPrimary);
    });

    for (final (nombre, theme, palette) in [
      ('oscuro', AppTheme.dark(), AppPalette.mintMagenta),
      ('claro', AppTheme.light(), AppPalette.mintMagentaLight),
    ]) {
      testWidgets('tema $nombre: el progreso se distingue del fondo (≥ 3:1)',
          (tester) async {
        await _pumpView(tester, theme: theme);

        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(
          _contrast(spinner.color!, palette.bg),
          greaterThanOrEqualTo(3),
        );
      });
    }

    testWidgets('se anuncia como carga y con la marca en el árbol de semántica',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpView(tester, theme: AppTheme.dark());

      expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
      expect(find.bySemanticsLabel('TREINO'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('en un teléfono chico (320×568) no desborda', (tester) async {
      await _pumpView(
        tester,
        theme: AppTheme.dark(),
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
