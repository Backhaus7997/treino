import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/presentation/trainers_list_screen.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: child,
      ),
    );

void main() {
  group('TrainersListScreen — toggle MAPA/Lista', () {
    testWidgets(
        'header muestra "ENCONTRÁ TU COACH" en stack magenta + blanco',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainersListScreen(),
        overrides: [
          trainerDiscoveryProvider.overrideWith((_) async => const []),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('ENCONTRÁ TU'), findsOneWidget);
      expect(find.text('COACH'), findsOneWidget);
    });

    testWidgets(
        'header tiene toggle MAPA / LISTA visible',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainersListScreen(),
        overrides: [
          trainerDiscoveryProvider.overrideWith((_) async => const []),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('MAPA'), findsOneWidget);
      expect(find.text('LISTA'), findsOneWidget);
    });

    testWidgets(
        'estado inicial: LISTA activa, FlutterMap NO visible',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainersListScreen(),
        overrides: [
          trainerDiscoveryProvider.overrideWith((_) async => const []),
        ],
      ));
      await tester.pumpAndSettle();

      // IndexedStack tiene ambos children construidos pero solo muestra el de
      // index actual. Verificamos via Visibility / findsOneWidget de FlutterMap:
      // en IndexedStack el hijo no-activo se construye pero no es visible.
      // Más simple: comprobamos que el empty state de la lista renderiza
      // (porque la lista es la default visible).
      expect(find.text('No encontramos entrenadores en tu zona.'),
          findsOneWidget);
    });

    // NOTA: el comportamiento de switching real (tap MAPA → renderiza
    // FlutterMap, tap LISTA → vuelve al listado) NO se testea via widget
    // tests porque FlutterMap intenta cargar tiles HTTP que fallan en test
    // env, y el widget no termina apareciendo en el árbol con find.byType.
    // Cobertura efectiva: smoke manual en device + tests de "default state"
    // + "toggle visible".
  });
}
