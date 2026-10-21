import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_collapsing_top_bar.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/l10n/app_l10n.dart';

/// #1559: la barra superior aparece al scrollear. En offset 0 sólo flotan la
/// flecha (en su burbuja) y las acciones, sin barra, y el contenido arranca debajo;
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
}) {
  return MaterialApp(
    theme: theme ?? AppTheme.dark(),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('es', 'AR'),
    home: Scaffold(
      body: Builder(
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
      ),
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

    final surface = tester.widget<Opacity>(find.byKey(_surface));
    expect(surface.opacity, 1);
    final title = tester.widget<Opacity>(find.byKey(_smallTitle));
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

  testWidgets('antes de que arranque la aparición no hay barra',
      (tester) async {
    await _pump(tester, _screen());

    // La aparición arranca `revealDistance` px antes de `collapseOffset`
    // (100 en este helper): 20 px quedan antes de ese tramo.
    await _scroll(tester, -20);

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

  group('aparición que sigue al scroll', () {
    // Lo que se desliza es el contenido del FractionalTranslation, no su caja.
    final surfacePaint = find.descendant(
      of: find.byKey(const Key('treino-top-bar-surface-slide')),
      matching: find.byType(BackdropFilter),
    );
    const bubble = Key('treino-top-bar-back-bubble');
    double opacityOf(WidgetTester tester, Key key) =>
        tester.widget<Opacity>(find.byKey(key)).opacity;

    // `collapseOffset` del helper: 100. La aparición dura `revealDistance` px
    // y termina ahí.
    const start = 100 - TreinoTopBarMetrics.revealDistance;

    Future<void> scrollTo(WidgetTester tester, double pixels) async {
      final pos =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      pos.jumpTo(pixels);
      await tester.pump();
    }

    testWidgets('a mitad del recorrido, la barra queda a mitad',
        (tester) async {
      await _pump(tester, _screen());
      await scrollTo(tester, start + TreinoTopBarMetrics.revealDistance / 2);

      final opacity = opacityOf(tester, _surface);
      expect(opacity, greaterThan(0));
      expect(opacity, lessThan(1));
      expect(tester.getRect(surfacePaint).top, lessThan(0),
          reason: 'el fondo todavía viene bajando');
      expect(opacityOf(tester, bubble), closeTo(1 - opacity, 1e-9));
    });

    testWidgets('no avanza sola: sin scroll, no cambia aunque pase el tiempo',
        (tester) async {
      await _pump(tester, _screen());
      await scrollTo(tester, start + 20);
      final antes = opacityOf(tester, _surface);

      await tester.pump(const Duration(seconds: 1));

      expect(opacityOf(tester, _surface), antes);
    });

    testWidgets('pasado el umbral: barra entera, sin burbuja', (tester) async {
      await _pump(tester, _screen());
      await scrollTo(tester, 300);

      expect(opacityOf(tester, _surface), 1);
      expect(tester.getRect(surfacePaint).top, 0);
      expect(find.byKey(bubble), findsNothing);
    });

    testWidgets('arriba del todo: burbuja en la flecha y nada de barra',
        (tester) async {
      await _pump(tester, _screen());

      expect(find.byKey(_surface), findsNothing);
      expect(opacityOf(tester, bubble), 1);
      final burbuja = tester.getRect(find.byKey(bubble));
      final flecha = tester.getRect(find.byKey(_back));
      expect(burbuja.center, flecha.center);
      expect(burbuja.width, TreinoTopBarMetrics.bubbleSize);
    });

    testWidgets('al volver arriba se va al mismo ritmo y se desmonta',
        (tester) async {
      await _pump(tester, _screen());
      await scrollTo(tester, 300);
      await scrollTo(tester, start + TreinoTopBarMetrics.revealDistance / 2);
      expect(opacityOf(tester, _surface), lessThan(1));

      await scrollTo(tester, 0);
      expect(find.byKey(_surface), findsNothing);
    });

    testWidgets('con «reducir movimiento» no se desliza, sólo funde',
        (tester) async {
      await _pump(
        tester,
        MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            padding: EdgeInsets.only(top: _safeTop),
          ),
          child: _screen(),
        ),
      );
      await scrollTo(tester, start + TreinoTopBarMetrics.revealDistance / 2);

      expect(opacityOf(tester, _surface), lessThan(1));
      expect(tester.getRect(surfacePaint).top, 0);
    });
  });

  group('sobre foto: status bar integrada al hero (#1559)', () {
    const scrim = Key('treino-top-bar-hero-scrim');

    SystemUiOverlayStyle overlayStyle(WidgetTester tester) => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find
              .ancestor(
                of: find.byKey(_back),
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              )
              .first,
        )
        .value;

    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets(
          'tema ${entry.key}: en offset 0 el scrim cubre desde el borde '
          'físico y los íconos de la status bar van claros', (tester) async {
        await _pump(tester, _screen(overHero: true, theme: entry.value));

        final rect = tester.getRect(find.byKey(scrim));
        expect(rect.top, 0, reason: 'arranca en el borde físico');
        expect(
          rect.bottom,
          greaterThan(_safeTop + TreinoTopBarMetrics.barHeight),
          reason: 'cubre la status bar Y la flecha',
        );
        expect(overlayStyle(tester), SystemUiOverlayStyle.light);
      });

      testWidgets(
          'tema ${entry.key}: con la barra puesta el scrim se va y la '
          'status bar vuelve al estilo del tema', (tester) async {
        await _pump(tester, _screen(overHero: true, theme: entry.value));
        await _scroll(tester, -300);

        expect(find.byKey(scrim), findsNothing);
        expect(
          overlayStyle(tester),
          AppTheme.systemOverlayStyleFor(entry.value.brightness),
        );
      });
    }

    testWidgets('sin foto no hay scrim y la status bar sigue al tema',
        (tester) async {
      await _pump(tester, _screen(theme: AppTheme.light()));

      expect(find.byKey(scrim), findsNothing);
      expect(overlayStyle(tester), SystemUiOverlayStyle.dark);
    });
  });
}
