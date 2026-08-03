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
      'accessibility text scale keeps every destination readable and tappable',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        TreinoBottomBar(currentIndex: 0, onTap: (_) {}),
        textScaler: const TextScaler.linear(3.2),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final label in ['ENTRENAR', 'FEED', 'INICIO', 'COACH', 'PERFIL']) {
      expect(find.text(label, skipOffstage: false), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      final text = tester.widget<Text>(
        find.text(label, skipOffstage: false),
      );
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
    }
    expect(find.byType(FittedBox), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  group('TreinoBottomBar — colapso al scrollear', () {
    /// Alto VISUAL de la pill. No sirve medir `TreinoBottomBar`: en el
    /// `Scaffold.body` del wrapper recibe constraints tight y ocupa la
    /// pantalla entera. El `ClipRRect` es el que envuelve la caja animada.
    double barHeight(WidgetTester tester) => tester
        .getSize(
          find
              .descendant(
                of: find.byType(TreinoBottomBar),
                matching: find.byType(ClipRRect),
              )
              .first,
        )
        .height;

    double labelOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.text('ENTRENAR', skipOffstage: false),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    testWidgets('collapsed false → alto expandido y labels a la vista', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(TreinoBottomBar(currentIndex: 0, onTap: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(
          barHeight(tester), greaterThanOrEqualTo(TreinoBottomBar.minHeight));
      expect(labelOpacity(tester), 1);
    });

    testWidgets('collapsed true → la barra se achica y el label se apaga', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(currentIndex: 0, onTap: (_) {}, collapsed: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(barHeight(tester), TreinoBottomBar.collapsedHeight);
      // El label sigue en el árbol —la semántica no se pierde— pero invisible.
      expect(labelOpacity(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('colapsar y expandir no desborda en ningún frame intermedio', (
      tester,
    ) async {
      // El overflow por desincronización entre alto y label es JUSTO el bug
      // que la animación única previene. Pumpeamos frame a frame para que,
      // si alguna vez desborda, el test lo vea.
      await tester.pumpWidget(
        _wrap(TreinoBottomBar(currentIndex: 0, onTap: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(currentIndex: 0, onTap: (_) {}, collapsed: true),
        ),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
    });
  });
}
