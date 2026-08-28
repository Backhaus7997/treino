import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_card.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/presentation/widgets/prescription_chips.dart';

void main() {
  testWidgets('header toggles the exercise body', (tester) async {
    var expanded = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ExerciseCard(
              title: 'Press de banca',
              summary: const PrescriptionChips(
                prescription: '3 × 10 · 60 kg',
                rest: '1:30',
              ),
              expanded: expanded,
              onToggle: () => setState(() => expanded = !expanded),
              menu: const SizedBox(key: Key('menu')),
              child: const Text('BODY', key: Key('body')),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('body')), findsNothing);

    await tester.tap(find.byKey(const Key('exercise_card_header')));
    await tester.pump();

    expect(find.byKey(const Key('body')), findsOneWidget);
  });

  testWidgets('error summary uses the danger palette', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: PrescriptionChips(prescription: '2 sets', hasError: true),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('2 sets'));
    expect(text.style?.color, AppPalette.mintMagenta.danger);
  });

  ExerciseCard card({bool hasError = false, bool expanded = false}) =>
      ExerciseCard(
        title: 'Press de banca',
        summary: const PrescriptionChips(prescription: '3 × 10 · 60 kg'),
        expanded: expanded,
        onToggle: () {},
        menu: const Icon(TreinoIcon.dotsThree, key: Key('menu')),
        hasError: hasError,
        child: const Text('BODY', key: Key('body')),
      );

  testWidgets('el agarre y el ⋮ NO usan el mismo glifo', (tester) async {
    // Los dos arrancaron usando TreinoIcon.dotsThree, uno al lado del otro:
    // el usuario no tenía forma de saber cuál arrastra y cuál abre el menú.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: card()),
      ),
    );

    final iconos =
        tester.widgetList<Icon>(find.byType(Icon)).map((i) => i.icon).toList();
    expect(iconos, contains(TreinoIcon.dragHandle));
    expect(TreinoIcon.dragHandle, isNot(TreinoIcon.dotsThree));
  });

  for (final entry in <String, AppPalette>{
    'dark': AppPalette.mintMagenta,
    'light': AppPalette.mintMagentaLight,
  }.entries) {
    testWidgets('${entry.key}: con error el borde de la card es danger',
        (tester) async {
      final palette = entry.value;
      Future<BoxDecoration> bordeCon({required bool hasError}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [palette]),
            home: Scaffold(body: card(hasError: hasError)),
          ),
        );
        // El segundo Container es la card; el primero es el agarre.
        return tester
            .widgetList<Container>(find.descendant(
              of: find.byType(ExerciseCard),
              matching: find.byType(Container),
            ))
            .map((c) => c.decoration as BoxDecoration)
            .firstWhere((d) => d.border != null && d.color == palette.bg);
      }

      final conError = await bordeCon(hasError: true);
      final sinError = await bordeCon(hasError: false);

      expect(
        (conError.border! as Border).top.color,
        palette.danger.withAlpha(128),
        reason: 'Un ejercicio con sets sin reps tiene que verse desde el '
            'scroll, sin abrir la card.',
      );
      expect((sinError.border! as Border).top.color, palette.border);
    });
  }
}
