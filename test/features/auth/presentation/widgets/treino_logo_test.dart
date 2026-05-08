import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/treino_logo.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

/// The sharp foreground SVG is the LAST SvgPicture in the Stack (the
/// blurred copies behind it are accent-tinted glow layers).
SvgPicture _sharpSvg(WidgetTester tester) =>
    tester.widgetList<SvgPicture>(find.byType(SvgPicture)).last;

void main() {
  group('TreinoLogo', () {
    testWidgets('renders the brand SVG', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      expect(find.byType(SvgPicture), findsWidgets);
    });

    testWidgets('default size is 56 logical pixels', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
      expect(logo.size, 56.0);
    });

    testWidgets('honors custom size parameter', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo(size: 80)));
      await tester.pump();

      final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
      expect(logo.size, 80.0);
    });

    testWidgets('default tint of the sharp logo is palette.textPrimary',
        (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      const palette = AppPalette.mintMagenta;
      expect(
        _sharpSvg(tester).colorFilter,
        ColorFilter.mode(palette.textPrimary, BlendMode.srcIn),
      );
    });

    testWidgets('custom color overrides the default tint of the sharp logo',
        (tester) async {
      const custom = Color(0xFF00FF00);
      await tester.pumpWidget(_wrap(const TreinoLogo(color: custom)));
      await tester.pump();

      expect(
        _sharpSvg(tester).colorFilter,
        const ColorFilter.mode(custom, BlendMode.srcIn),
      );
    });

    testWidgets('glow:true paints accent halo layers behind the logo',
        (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      // 2 blurred accent layers + 1 sharp foreground = 3 SvgPictures total.
      expect(find.byType(SvgPicture), findsNWidgets(3));
    });

    testWidgets('glow:false renders only the sharp logo (no halo)',
        (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo(glow: false)));
      await tester.pump();

      expect(find.byType(SvgPicture), findsOneWidget);
    });
  });
}
