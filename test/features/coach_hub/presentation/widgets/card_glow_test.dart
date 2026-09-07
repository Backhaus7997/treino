import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

/// El glow mint de la welcome card es UN token, no una copia por card.
///
/// Antes vivía inline en `dashboard_hero.dart`: la welcome card lo tenía y el
/// resto del dashboard —KPIs y paneles— quedaba plano, como si fueran dos
/// diseños distintos en la misma pantalla.
void main() {
  late AppPalette palette;

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(builder: (ctx) {
            palette = AppPalette.of(ctx);
            return SizedBox(width: 900, height: 600, child: child);
          }),
        ),
      );

  group('TreinoCardTokens.glow —', () {
    testWidgets('es el degradé diagonal de la welcome card', (tester) async {
      late LinearGradient g;
      await tester.pumpWidget(wrap(Builder(builder: (ctx) {
        g = TreinoCardTokens.glow(ctx);
        return const SizedBox();
      })));

      expect(g.begin, Alignment.topLeft);
      expect(g.end, Alignment.bottomRight);
      expect(g.colors.first, palette.accent.withValues(alpha: 0.12));
      expect(g.colors.last, palette.bgCard);
      expect(g.stops, const [0.0, 0.45, 1.0]);
    });

    testWidgets('la intensidad se puede bajar para superficies chicas',
        (tester) async {
      late LinearGradient g;
      await tester.pumpWidget(wrap(Builder(builder: (ctx) {
        g = TreinoCardTokens.glow(ctx, alpha: 0.06);
        return const SizedBox();
      })));

      expect(g.colors.first, palette.accent.withValues(alpha: 0.06));
      expect(g.colors.last, palette.bgCard);
    });
  });

  group('KpiCard —', () {
    testWidgets('lleva el glow, más suave que el hero', (tester) async {
      await tester.pumpWidget(wrap(
        const KpiCard(value: '2', label: 'Alumnos activos'),
      ));

      final box = tester.widget<AnimatedContainer>(
        find.byKey(const Key('kpi_card_root')),
      );
      final d = box.decoration! as BoxDecoration;
      final g = d.gradient! as LinearGradient;

      expect(d.color, isNull, reason: 'gradient y color se excluyen');
      expect(g.colors.last, palette.bgCard);
      final alpha = g.colors.first.a;
      expect(alpha, lessThan(0.12), reason: 'no compite con la welcome card');
      expect(alpha, greaterThan(0.0));
    });
  });

  group('TreinoEmptyState —', () {
    testWidgets('el ícono va en un medallón mint, no suelto y gris',
        (tester) async {
      await tester.pumpWidget(wrap(
        const TreinoEmptyState(
          icon: TreinoIcon.emptyState,
          title: 'Todo al día',
        ),
      ));

      final medallion = tester.widget<Container>(
        find.byKey(const Key('empty_state_medallion')),
      );
      final d = medallion.decoration! as BoxDecoration;

      expect(d.shape, BoxShape.circle);
      expect(d.color, palette.accent.withValues(alpha: 0.10));

      final icon = tester.widget<Icon>(find.byIcon(TreinoIcon.emptyState));
      expect(icon.color, palette.accent);
      expect(icon.size, lessThan(TreinoEmptyStateTokens.iconSize));
    });

    testWidgets('el título y la descripción siguen intactos', (tester) async {
      await tester.pumpWidget(wrap(
        const TreinoEmptyState(
          icon: TreinoIcon.emptyState,
          title: 'Sin alumnos todavía',
          description: 'Invitá a tu primer alumno para empezar.',
        ),
      ));

      expect(find.text('Sin alumnos todavía'), findsOneWidget);
      expect(find.text('Invitá a tu primer alumno para empezar.'),
          findsOneWidget);
    });
  });

  group('CoachHubSectionHero —', () {
    testWidgets('usa el mismo token, no una copia', (tester) async {
      late LinearGradient expected;
      await tester.pumpWidget(wrap(Builder(builder: (ctx) {
        expected = TreinoCardTokens.glow(ctx);
        return const CoachHubSectionHero(title: 'Alumnos');
      })));

      final box = tester.widget<Container>(
        find.byKey(const Key('section_hero_root')),
      );
      expect((box.decoration! as BoxDecoration).gradient, expected);
    });
  });
}
