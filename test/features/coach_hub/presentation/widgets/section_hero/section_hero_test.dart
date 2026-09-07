import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

/// El hero de sección lleva el lenguaje visual de la welcome card del
/// dashboard (glow mint diagonal + título grande con el dato en accent +
/// pills) al resto de las secciones del Coach Hub.
void main() {
  late AppPalette palette;

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              palette = AppPalette.of(ctx);
              return SizedBox(width: 900, child: child);
            },
          ),
        ),
      );

  group('CoachHubSectionHero —', () {
    testWidgets('el título se uppercasea y va en tamaño hero (28)',
        (tester) async {
      await tester.pumpWidget(wrap(
        const CoachHubSectionHero(title: 'Mis alumnos'),
      ));

      final title = tester.widget<Text>(find.byKey(const Key('sh_title')));
      expect(title.data, 'MIS ALUMNOS');
      expect(title.style?.fontSize, 28);
      expect(title.style?.fontFamily, AppFonts.barlowCondensed);
    });

    testWidgets('el count se resalta en accent, como el nombre de la '
        'welcome card', (tester) async {
      await tester.pumpWidget(wrap(
        const CoachHubSectionHero(title: 'Alumnos', count: 24),
      ));

      final count = tester.widget<Text>(find.text('24'));
      expect(count.style?.color, palette.accent);
      expect(count.style?.fontSize, 28);
    });

    testWidgets('la card lleva el glow mint en diagonal de la welcome card',
        (tester) async {
      await tester.pumpWidget(wrap(
        const CoachHubSectionHero(title: 'Pagos'),
      ));

      final box = tester.widget<Container>(
        find.byKey(const Key('section_hero_root')),
      );
      final decoration = box.decoration! as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;

      expect(gradient.begin, Alignment.topLeft);
      expect(gradient.end, Alignment.bottomRight);
      expect(gradient.colors.first, palette.accent.withValues(alpha: 0.12));
      expect(gradient.colors.last, palette.bgCard);
      expect(decoration.color, isNull, reason: 'gradient y color se excluyen');
    });

    testWidgets('el subtítulo va en textMuted 13', (tester) async {
      await tester.pumpWidget(wrap(
        const CoachHubSectionHero(
          title: 'Biblioteca',
          subtitle: '12 ejercicios · 3 templates',
        ),
      ));

      final sub = tester.widget<Text>(
        find.text('12 ejercicios · 3 templates'),
      );
      expect(sub.style?.color, palette.textMuted);
      expect(sub.style?.fontSize, 13);
    });

    testWidgets('la acción primaria es una pill mint y dispara el tap',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        CoachHubSectionHero(
          title: 'Alumnos',
          actions: [
            CoachHubHeroAction(
              label: 'Nuevo alumno',
              icon: TreinoIcon.plus,
              onTap: () => taps++,
              primary: true,
            ),
          ],
        ),
      ));

      final pill = tester.widget<Container>(
        find.byKey(const Key('hero_action_0')),
      );
      final decoration = pill.decoration! as BoxDecoration;
      expect(decoration.color, palette.accent);
      expect(decoration.borderRadius,
          BorderRadius.circular(AppRadius.full));

      await tester.tap(find.text('Nuevo alumno'));
      expect(taps, 1);
    });

    testWidgets('las acciones secundarias son pills outlined y disparan',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        CoachHubSectionHero(
          title: 'Biblioteca',
          actions: [
            CoachHubHeroAction(
              label: 'Nuevo ejercicio',
              icon: TreinoIcon.plus,
              onTap: () => taps++,
            ),
          ],
        ),
      ));

      expect(find.byType(OutlinedButton), findsOneWidget);
      await tester.tap(find.byType(OutlinedButton));
      expect(taps, 1);
    });

    testWidgets('sin acciones no se renderiza ninguna pill', (tester) async {
      await tester.pumpWidget(wrap(
        const CoachHubSectionHero(title: 'Rutinas'),
      ));

      expect(find.byKey(const Key('hero_actions')), findsNothing);
    });

    testWidgets('el trailing se renderiza a la derecha del hero',
        (tester) async {
      await tester.pumpWidget(wrap(
        const CoachHubSectionHero(
          title: 'Pagos',
          trailing: Text('registrar'),
        ),
      ));

      expect(find.text('registrar'), findsOneWidget);
    });

    testWidgets('sigue exponiendo un TreinoSectionHeader — el kit no se '
        'duplica', (tester) async {
      await tester.pumpWidget(wrap(
        const CoachHubSectionHero(title: 'Nutrición'),
      ));

      expect(find.byType(TreinoSectionHeader), findsOneWidget);
    });
  });

  group('TreinoSectionHeader — variantes', () {
    testWidgets('la variante label no cambia: 12px y count apagado',
        (tester) async {
      await tester.pumpWidget(wrap(
        const TreinoSectionHeader(title: 'Pendientes', count: 3),
      ));

      final title = tester.widget<Text>(find.byKey(const Key('sh_title')));
      expect(title.style?.fontSize, TreinoSectionHeaderTokens.fontSize);
      final count = tester.widget<Text>(find.text('3'));
      expect(count.style?.color, palette.textMuted);
    });
  });
}
