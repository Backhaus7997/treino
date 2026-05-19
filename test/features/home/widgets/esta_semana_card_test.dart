import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/home/widgets/esta_semana_card.dart';
import 'package:treino/features/insights/presentation/widgets/body_silhouette_placeholder.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('EstaSemanaCard', () {
    testWidgets('REQ-HOME-SEMANA-001: renders title "ESTA SEMANA"',
        (tester) async {
      await tester.pumpWidget(_wrap(const EstaSemanaCard()));
      await tester.pump();
      expect(find.text('ESTA SEMANA'), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-SEMANA-001: renders BodySilhouettePlaceholder, no streak, no SVG',
        (tester) async {
      await tester.pumpWidget(_wrap(const EstaSemanaCard()));
      await tester.pump();

      expect(find.byType(BodySilhouettePlaceholder), findsOneWidget);
      // No streak number (e.g. "5 DÍAS") — diferido a Etapa 6 completa.
      expect(find.textContaining(RegExp(r'\d+ DÍAS')), findsNothing);
      // No muscle map SVG — el placeholder usa Icon, no SVG.
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('REQ-HOME-SEMANA-002: card decoration — bgCard, r=20, border',
        (tester) async {
      await tester.pumpWidget(_wrap(const EstaSemanaCard()));
      await tester.pump();

      // El primer Container es el GestureDetector wrapper que NO tiene
      // decoration. El segundo es el card con styling.
      final containers =
          tester.widgetList<Container>(find.byType(Container)).toList();
      final styledContainer = containers.firstWhere(
        (c) => c.decoration is BoxDecoration,
      );
      final decoration = styledContainer.decoration as BoxDecoration;

      expect(
        decoration.borderRadius,
        equals(BorderRadius.circular(20)),
      );
      expect(decoration.color, equals(AppPalette.mintMagenta.bgCard));
      expect(decoration.border, isNotNull);
    });

    testWidgets('REQ-HOME-SEMANA-003: tap en la card pushea /home/insights',
        (tester) async {
      String? pushedLocation;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const EstaSemanaCard(),
          ),
          GoRoute(
            path: '/home/insights',
            builder: (_, state) {
              pushedLocation = state.matchedLocation;
              return const Scaffold(body: Center(child: Text('insights-stub')));
            },
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(EstaSemanaCard));
      await tester.pumpAndSettle();

      expect(pushedLocation, equals('/home/insights'));
    });
  });
}
