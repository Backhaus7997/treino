import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_collapsing_top_bar.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/l10n/app_l10n.dart';

/// #1559: la barra superior aparece al scrollear. En offset 0 sólo flotan la
/// flecha y las acciones (sin fondo ni círculo) y el contenido arranca debajo;
/// pasado el umbral aparecen el fondo translúcido y el título chico.

const _title = 'DÍA 1';
const _safeTop = 47.0;
const _surface = Key('treino-top-bar-surface');
const _smallTitle = Key('treino-top-bar-title');
const _bigTitle = Key('big-title');
const _back = Key('treino-top-bar-back');

Widget _screen({
  VoidCallback? onBack,
  bool overHero = false,
  ThemeData? theme,
  List<Widget>? actions,
  bool insideSafeArea = false,
}) {
  Widget wrap(Widget child) => insideSafeArea ? SafeArea(child: child) : child;
  return MaterialApp(
    theme: theme ?? AppTheme.dark(),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('es', 'AR'),
    home: Scaffold(
      body: wrap(Builder(
        builder: (context) => TreinoCollapsingTopBar(
          title: _title,
          overHero: overHero,
          collapseOffset: 100,
          onBack: onBack ?? () {},
          actions: actions ??
              [
                TreinoTopBarAction(
                  buttonKey: const Key('action'),
                  icon: TreinoIcon.dotsThree,
                  tooltip: 'Más',
                  onPressed: () {},
                ),
              ],
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(height: TreinoTopBarMetrics.reservedHeightOf(context)),
              const Text(_title, key: _bigTitle),
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('$i')),
            ],
          ),
        ),
      )),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(390, 700);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(top: _safeTop);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
}

Future<void> _scroll(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(ListView), Offset(0, dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'dentro de un SafeArea (shell), el fondo colapsado igual cubre la '
      'status bar de borde a borde', (tester) async {
    await _pump(tester, _screen(insideSafeArea: true));
    await _scroll(tester, -300);

    final surface = tester.getRect(find.byKey(_surface));
    expect(surface.top, 0, reason: 'el fondo arranca debajo del reloj');
    expect(
      surface.bottom,
      _safeTop + TreinoTopBarMetrics.barHeight,
    );
    expect(surface.width, 390);
  });

  testWidgets(
      'offset 0: sin fondo ni título chico; el título grande queda '
      'debajo de la flecha', (tester) async {
    await _pump(tester, _screen());

    expect(find.byKey(_surface), findsNothing);
    expect(find.byKey(_smallTitle), findsNothing);

    final back = tester.getRect(find.byKey(_back));
    final bigTitleTop = tester.getTopLeft(find.byKey(_bigTitle)).dy;
    expect(
      bigTitleTop,
      greaterThanOrEqualTo(back.bottom + TreinoTopBarMetrics.clearance),
      reason: 'la flecha $back pisa el título que arranca en $bigTitleTop',
    );
    // Cuelga del borde superior del área segura.
    expect(back.top, _safeTop + TreinoTopBarMetrics.topInset);
  });

  testWidgets('tap targets de al menos 44 pt', (tester) async {
    await _pump(tester, _screen());

    for (final key in [_back, const Key('action')]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('al scrollear más allá del umbral aparecen el fondo y el título',
      (tester) async {
    await _pump(tester, _screen());

    await _scroll(tester, -300);

    final surface = tester.widget<AnimatedOpacity>(find.byKey(_surface));
    expect(surface.opacity, 1);
    final title = tester.widget<AnimatedOpacity>(find.byKey(_smallTitle));
    expect(title.opacity, 1);
    expect(
      find.descendant(
        of: find.byKey(_smallTitle),
        matching: find.text(_title),
      ),
      findsOneWidget,
    );
  });

  // Codex en #1596: el detalle de rutina pasa tres acciones y casi siempre
  // dos son `SizedBox.shrink()`. Reservar lugar por ENTRADA de la lista le
  // dejaba ~62 px al título en un teléfono de 390 y lo cortaba entero.
  testWidgets('el título chico usa el ancho que dejan las acciones VISIBLES',
      (tester) async {
    await _pump(
      tester,
      _screen(
        actions: [
          const SizedBox.shrink(),
          const SizedBox.shrink(),
          TreinoTopBarAction(
            buttonKey: const Key('action'),
            icon: TreinoIcon.dotsThree,
            tooltip: 'Más',
            onPressed: () {},
          ),
        ],
      ),
    );
    await _scroll(tester, -300);

    // Una sola acción visible: flecha (12 + 48) a la izquierda y acción a la
    // derecha. Centrado, el título tiene el ancho entre las dos simétricas.
    final ancho = tester.getSize(find.byKey(_smallTitle)).width;
    expect(ancho, greaterThanOrEqualTo(390 - 2 * (12 + 48 + 8)));
    // Y queda centrado en la pantalla.
    expect(tester.getCenter(find.byKey(_smallTitle)).dx, closeTo(195, 1));
  });

  testWidgets('scrollear de vuelta hacia arriba los oculta', (tester) async {
    await _pump(tester, _screen());

    await _scroll(tester, -300);
    expect(find.byKey(_surface), findsOneWidget);

    await _scroll(tester, 600);
    expect(find.byKey(_surface), findsNothing);
    expect(find.byKey(_smallTitle), findsNothing);
  });

  testWidgets('antes del umbral no aparece', (tester) async {
    await _pump(tester, _screen());

    await _scroll(tester, -60);

    expect(find.byKey(_surface), findsNothing);
  });

  testWidgets('la flecha hace pop de la ruta', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, _) => Scaffold(
            body: TreinoCollapsingTopBar(
              title: _title,
              onBack: context.pop,
              body: ListView(children: const [Text('detalle')]),
            ),
          ),
        ),
      ],
    );
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    );
    unawaited(router.push('/detail'));
    await tester.pumpAndSettle();
    expect(find.text('detalle'), findsOneWidget);

    await tester.tap(find.byKey(_back));
    await tester.pumpAndSettle();

    expect(find.text('detalle'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  for (final entry in {
    'oscuro': AppTheme.dark(),
    'claro': AppTheme.light(),
  }.entries) {
    for (final overHero in [false, true]) {
      testWidgets(
          'tema ${entry.key}, overHero=$overHero: renderiza sin errores',
          (tester) async {
        await _pump(tester, _screen(theme: entry.value, overHero: overHero));
        expect(tester.takeException(), isNull);

        await _scroll(tester, -300);
        expect(tester.takeException(), isNull);
        expect(find.byKey(_surface), findsOneWidget);
      });
    }
  }

  testWidgets(
      'sobre foto y en offset 0 el ícono va blanco con sombra; con la '
      'barra, del color del tema', (tester) async {
    await _pump(tester, _screen(overHero: true, theme: AppTheme.light()));

    IconThemeData iconTheme() => IconTheme.of(
          tester.element(
            find.descendant(
              of: find.byKey(_back),
              matching: find.byType(Icon),
            ),
          ),
        );

    expect(iconTheme().color, Colors.white);
    expect(iconTheme().shadows, isNotEmpty);

    await _scroll(tester, -300);

    expect(iconTheme().color, isNot(Colors.white));
    expect(iconTheme().shadows, anyOf(isNull, isEmpty));
  });
}
