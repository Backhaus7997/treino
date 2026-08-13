import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';

Widget _wrap(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: appChild!,
      ),
      home: Scaffold(body: child),
    );

void main() {
  group('TreinoBottomBar — Coach tab badge', () {
    testWidgets('coachUnreadCount 0 → no badge rendered', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 0,
          ),
        ),
      );
      await tester.pump();

      // No badge text should be visible
      expect(find.text('1'), findsNothing);
      expect(find.text('5'), findsNothing);
      expect(find.text('99+'), findsNothing);
    });

    testWidgets('coachUnreadCount 3 → badge "3" visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 3,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('coachUnreadCount 100 → badge shows "99+"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 100,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('coachUnreadCount defaults to 0 (no badge)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            // no coachUnreadCount parameter
          ),
        ),
      );
      await tester.pump();

      // Confirm no badge-style text leaks in
      expect(find.text('0'), findsNothing);
    });
  });

  group('TreinoBottomBar — Feed tab badge', () {
    testWidgets('feedUnreadCount 0 → no badge rendered', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 0,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1'), findsNothing);
      expect(find.text('5'), findsNothing);
      expect(find.text('99+'), findsNothing);
    });

    testWidgets('feedUnreadCount 2 → badge "2" visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 2,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('feedUnreadCount 100 → badge shows "99+"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 100,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('feed 2 + coach 3 → both badges visible independently',
        (tester) async {
      // Regression guard: the two badges must not shadow each other. This
      // reproduces the "message from friend surfaces on both tabs" bug —
      // pre-split, only one badge existed and could render on the wrong tab.
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 2,
            coachUnreadCount: 3,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  testWidgets(
      'accessibility text scale keeps every destination reachable on screen',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        TreinoBottomBar(currentIndex: 0, onTap: (_) {}),
        textScaler: const TextScaler.linear(3.2),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final label in _labels) {
      // El destino sigue existiendo y el lector de pantalla lo sigue
      // anunciando aunque el label visible se haya sacrificado por ancho.
      final tab = find.bySemanticsLabel(label);
      expect(tab, findsOneWidget);

      // Y sigue estando DENTRO de la pantalla: el bug de #634 era exactamente
      // que PERFIL quedaba afuera.
      final rect = tester.getRect(tab);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(screen.width));
    }

    // Achicar el texto le desarmaría al usuario justo lo que pidió, y una
    // barra de navegación que hay que scrollear no es una barra de navegación.
    expect(find.byType(FittedBox), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  group('TreinoBottomBar — geometría (regresión issue #634)', () {
    // La barra quedaba corrida tras el primer arranque: medía los labels con la
    // fuente fallback del sistema (más ancha que Barlow Condensed, que
    // `google_fonts` todavía no había registrado), decidía que no entraban y
    // caía a una tira scrolleable de tabs de ancho FIJO. Esos cinco tabs
    // sumaban más que la pantalla, así que PERFIL quedaba afuera y el resto de
    // los destinos —INICIO incluido— aparecían corridos hacia la derecha.
    //
    // Estos tests miden geometría RENDERIZADA, no la aritmética del layout, y
    // por eso valen aunque en `flutter_test` la tipografía real nunca cargue:
    // el reparto en partes iguales no depende de la fuente.
    for (final currentIndex in [0, 2, 4]) {
      testWidgets(
          'los 5 destinos se reparten en partes iguales '
          '(currentIndex $currentIndex)', (tester) async {
        tester.view.physicalSize = const Size(430 * 3, 932 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _wrap(TreinoBottomBar(currentIndex: currentIndex, onTap: (_) {})),
        );
        await tester.pump();

        final rects = [
          for (final label in _labels)
            tester.getRect(find.bySemanticsLabel(label)),
        ];

        // Todos del mismo ancho, pegados uno al lado del otro y adentro de la
        // pantalla.
        for (final rect in rects) {
          expect(
              rect.width, moreOrLessEquals(rects.first.width, epsilon: 0.01));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(430));
        }
        for (var i = 1; i < rects.length; i++) {
          expect(rects[i].left,
              moreOrLessEquals(rects[i - 1].right, epsilon: 0.01));
        }

        // Y con cinco tabs iguales, INICIO —el del medio— cae en el centro
        // exacto de la pantalla. Es la forma más directa de decir "la barra
        // está centrada".
        expect(rects[2].center.dx, moreOrLessEquals(215, epsilon: 0.01));
      });
    }
  });
}

const _labels = ['ENTRENAR', 'FEED', 'INICIO', 'COACH', 'PERFIL'];
