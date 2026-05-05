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

void main() {
  group('TreinoLogo', () {
    testWidgets('renders an SvgPicture pointing at the brand asset',
        (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      expect(find.byType(SvgPicture), findsOneWidget);
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

    testWidgets('default tint is palette.textPrimary', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      const palette = AppPalette.mintMagenta;
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        svg.colorFilter,
        ColorFilter.mode(palette.textPrimary, BlendMode.srcIn),
      );
    });

    testWidgets('custom color overrides the default tint', (tester) async {
      const custom = Color(0xFF00FF00);
      await tester.pumpWidget(_wrap(const TreinoLogo(color: custom)));
      await tester.pump();

      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        svg.colorFilter,
        const ColorFilter.mode(custom, BlendMode.srcIn),
      );
    });
  });
}
