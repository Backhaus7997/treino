import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/core/analytics/sub_tab_analytics.dart';

import '../../helpers/fake_analytics_service.dart';

/// Tests de [SubTabAnalytics] — el evento de sub-navegación (issue #665... no:
/// #666).
///
/// Lo que se protege acá es el motivo de existir del widget: las páginas de un
/// `TabBarView` comparten ruta, así que el observer del router no las
/// distingue. Y sobre todo el caso del SWIPE, que es exactamente lo que se
/// perdería si el evento colgara del `onTap` del `TabBar`.
void main() {
  late FakeAnalyticsService analytics;

  setUp(() => analytics = FakeAnalyticsService());

  /// Arma un [DefaultTabController] con [SubTabAnalytics] adentro, igual que
  /// lo usan Feed y Entrenar.
  Future<void> pumpTabs(
    WidgetTester tester, {
    int initialIndex = 0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(analytics),
        ],
        child: MaterialApp(
          home: DefaultTabController(
            length: 2,
            initialIndex: initialIndex,
            child: const SubTabAnalytics(
              surface: 'feed',
              tabs: ['feed', 'rankings'],
              child: Column(
                children: [
                  TabBar(tabs: [Tab(text: 'FEED'), Tab(text: 'RANKINGS')]),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Center(child: Text('page-feed')),
                        Center(child: Text('page-rankings')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SubTabAnalytics', () {
    testWidgets('loguea la página inicial al montar', (tester) async {
      await pumpTabs(tester);

      expect(analytics.subTabsFor('feed'), ['feed']);
    });

    testWidgets(
        'la página inicial logueada es la que corresponde al deep-link '
        '(?tab=rankings entra directo en index 1)', (tester) async {
      await pumpTabs(tester, initialIndex: 1);

      // Si esto fallara, entrar por `/feed?tab=rankings` no contaría como
      // visita a RANKINGS — que es justo el número que pide #642.
      expect(analytics.subTabsFor('feed'), ['rankings']);
    });

    testWidgets('loguea al cambiar de tab por TAP', (tester) async {
      await pumpTabs(tester);

      await tester.tap(find.text('RANKINGS'));
      await tester.pumpAndSettle();

      expect(analytics.subTabsFor('feed'), ['feed', 'rankings']);
    });

    testWidgets('loguea al cambiar de página por SWIPE', (tester) async {
      await pumpTabs(tester);

      // El caso que motivó colgarse del TabController y no del onTap del
      // TabBar: un swipe nunca pasa por el onTap.
      await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('page-rankings'), findsOneWidget);
      expect(analytics.subTabsFor('feed'), ['feed', 'rankings']);
    });

    testWidgets('un tap emite UN evento, no uno por frame de animación',
        (tester) async {
      await pumpTabs(tester);

      await tester.tap(find.text('RANKINGS'));
      await tester.pumpAndSettle();

      // El TabController notifica muchas veces por cambio. Sin la
      // deduplicación por índice esto sería una lista de 'rankings' repetidos
      // y los números saldrían inflados.
      expect(analytics.subTabsFor('feed'), ['feed', 'rankings']);
    });

    testWidgets('no loguea la tab nueva hasta que la animación asienta',
        (tester) async {
      await pumpTabs(tester);

      await tester.tap(find.text('RANKINGS'));
      await tester.pump(); // arranca la animación
      await tester.pump(const Duration(milliseconds: 40)); // a mitad de camino

      // Este es el guard de `indexIsChanging`: apenas se tapea, el controller
      // YA reporta index 1 aunque la página todavía se está moviendo. El
      // evento dice "esta página quedó visible", así que se emite cuando
      // asienta y no cuando arranca.
      expect(analytics.subTabsFor('feed'), ['feed']);

      await tester.pumpAndSettle();
      expect(analytics.subTabsFor('feed'), ['feed', 'rankings']);
    });

    testWidgets('un swipe que se arrepiente a mitad de camino no loguea nada',
        (tester) async {
      await pumpTabs(tester);

      // Arrastre parcial con frames intermedios y suelta antes del umbral: el
      // TabController notifica en cada frame del arrastre (cambia `offset`,
      // no `index`). Sin la deduplicación por índice, cada uno de esos frames
      // volvería a loguear 'feed' y una sola indecisión del usuario inflaría
      // el número de la página en la que ya estaba.
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TabBarView)));
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('page-feed'), findsOneWidget);
      expect(analytics.subTabsFor('feed'), ['feed']);
    });

    testWidgets('volver a la tab anterior vuelve a loguear', (tester) async {
      await pumpTabs(tester);

      await tester.tap(find.text('RANKINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('FEED'));
      await tester.pumpAndSettle();

      expect(analytics.subTabsFor('feed'), ['feed', 'rankings', 'feed']);
    });

    testWidgets('sin DefaultTabController ancestro no rompe ni loguea',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [analyticsServiceProvider.overrideWithValue(analytics)],
          child: const MaterialApp(
            home: SubTabAnalytics(
              surface: 'feed',
              tabs: ['feed', 'rankings'],
              child: Text('sin-controller'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Telemetría faltante es un bug de datos; una excepción es una pantalla
      // caída. El widget elige lo primero.
      expect(tester.takeException(), isNull);
      expect(find.text('sin-controller'), findsOneWidget);
      expect(analytics.events, isEmpty);
    });

    testWidgets('el evento lleva surface y tab como parámetros',
        (tester) async {
      await pumpTabs(tester);
      await tester.tap(find.text('RANKINGS'));
      await tester.pumpAndSettle();

      final last = analytics.calls.last;
      expect(last.name, 'sub_tab_viewed');
      expect(last.params, {'surface': 'feed', 'tab': 'rankings'});
    });
  });
}
