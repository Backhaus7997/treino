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
    testWidgets(
        '${entry.key}: el borde marca error SÓLO con la card cerrada',
        (tester) async {
      final palette = entry.value;
      Future<BoxDecoration> bordeCon({
        required bool hasError,
        required bool expanded,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [palette]),
            home: Scaffold(
              body: card(hasError: hasError, expanded: expanded),
            ),
          ),
        );
        return tester
            .widgetList<Container>(find.descendant(
              of: find.byType(ExerciseCard),
              matching: find.byType(Container),
            ))
            .map((c) => c.decoration as BoxDecoration)
            .firstWhere((d) => d.border != null && d.color == palette.bg);
      }

      Color borde(BoxDecoration d) => (d.border! as Border).top.color;

      // #868 sacó el borde rojo del todo, y tenía razón en el problema: un
      // campo de reps vacío llegó a marcar CINCO cosas a la vez —celda, borde
      // de la card, texto de su meta, punto de la pestaña y el pie—, y con
      // 3 días × 5 ejercicios eso es una pantalla en rojo donde ninguna señal
      // manda.
      //
      // Lo que aquella versión no cubría es el estado CERRADO: ahí la celda no
      // está en pantalla y una card sin completar se ve igual que una completa.
      // Se resolvía abriéndola sola, y en device eso resultó peor —reacomodar
      // ejercicios desplegaba media pantalla.
      //
      // Así que la señal no se suma: se MUEVE. Este test es el que impide que
      // vuelvan a convivir.
      expect(
        borde(await bordeCon(hasError: true, expanded: false)),
        palette.danger,
        reason: 'cerrada y sin completar, el borde es lo ÚNICO que puede '
            'avisar: la celda no está en pantalla',
      );
      expect(
        borde(await bordeCon(hasError: true, expanded: true)),
        palette.border,
        reason: 'abierta manda la celda, que dice QUÉ campo falta. Si el borde '
            'también se pinta, volvimos al #868',
      );
      expect(
        borde(await bordeCon(hasError: false, expanded: false)),
        palette.border,
      );
      expect(
        borde(await bordeCon(hasError: false, expanded: true)),
        palette.border,
      );
    });
  }
}
