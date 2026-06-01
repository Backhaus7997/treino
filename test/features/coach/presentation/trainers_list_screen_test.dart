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
    testWidgets('header muestra "ENCONTRÁ TU COACH" en stack magenta + blanco',
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

    testWidgets('header tiene toggle MAPA / LISTA visible', (tester) async {
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

    testWidgets('estado inicial: LISTA activa, FlutterMap NO visible',
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
      expect(
          find.text('No encontramos entrenadores en tu zona.'), findsOneWidget);
    });

    // NOTA: el comportamiento de switching real (tap MAPA → renderiza
    // FlutterMap, tap LISTA → vuelve al listado) NO se testea via widget
    // tests porque FlutterMap intenta cargar tiles HTTP que fallan en test
    // env, y el widget no termina apareciendo en el árbol con find.byType.
    // Cobertura efectiva: smoke manual en device + tests de "default state"
    // + "toggle visible".
  });

  group('TrainersListScreen — auto-switch a LISTA al activar Online', () {
    testWidgets(
        'tap tab ONLINE cuando MAPA está activo → mapModeProvider queda false '
        'Y virtualOnlyFilterProvider queda true',
        (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerDiscoveryProvider.overrideWith((_) async => const []),
            // Override del location notifier en estado "denied" para evitar
            // que la rationale sheet abra en initState — ese modal cubre los
            // tabs y rompe el tap test.
            athleteLocationProvider.overrideWith((ref) {
              final n = AthleteLocationNotifier();
              n.setDeniedForTest();
              return n;
            }),
          ],
          child: Consumer(builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: AppTheme.dark(),
              home: const TrainersListScreen(),
            );
          }),
        ),
      );
      await tester.pumpAndSettle();

      // Seed estado: MAPA activo + Online OFF (default false). Simulamos el
      // usuario que ya tocó MAPA antes de tocar ONLINE.
      container.read(mapModeProvider.notifier).state = true;
      await tester.pumpAndSettle();
      expect(container.read(mapModeProvider), isTrue);

      // Tap ONLINE.
      await tester.tap(find.text('ONLINE'));
      await tester.pumpAndSettle();

      // Auto-switch: ambos providers actualizados en el mismo gesto.
      expect(container.read(virtualOnlyFilterProvider), isTrue);
      expect(container.read(mapModeProvider), isFalse);
    });

    testWidgets(
        'tap tab PRESENCIAL viniendo de ONLINE → mapModeProvider queda true '
        '(auto-switch simétrico)',
        (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerDiscoveryProvider.overrideWith((_) async => const []),
            // Seed: virtualOnly ON desde el override.
            virtualOnlyFilterProvider.overrideWith((ref) => true),
            athleteLocationProvider.overrideWith((ref) {
              final n = AthleteLocationNotifier();
              n.setDeniedForTest();
              return n;
            }),
          ],
          child: Consumer(builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: AppTheme.dark(),
              home: const TrainersListScreen(),
            );
          }),
        ),
      );
      await tester.pumpAndSettle();

      // Estado inicial: virtualOnly ON + mapMode default false.
      expect(container.read(virtualOnlyFilterProvider), isTrue);
      expect(container.read(mapModeProvider), isFalse);

      // Tap PRESENCIAL.
      await tester.tap(find.text('PRESENCIAL'));
      await tester.pumpAndSettle();

      // Auto-switch simétrico: virtualOnly → false Y mapMode → true.
      expect(container.read(virtualOnlyFilterProvider), isFalse);
      expect(container.read(mapModeProvider), isTrue,
          reason: 'PRESENCIAL viniendo de ONLINE debe auto-switch a MAPA');
    });

    testWidgets(
        're-tap PRESENCIAL ya estando en PRESENCIAL+LISTA NO fuerza MAPA',
        (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerDiscoveryProvider.overrideWith((_) async => const []),
            athleteLocationProvider.overrideWith((ref) {
              final n = AthleteLocationNotifier();
              n.setDeniedForTest();
              return n;
            }),
          ],
          child: Consumer(builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: AppTheme.dark(),
              home: const TrainersListScreen(),
            );
          }),
        ),
      );
      await tester.pumpAndSettle();

      // Estado inicial: virtualOnly false + mapMode false (LISTA en PRESENCIAL).
      expect(container.read(virtualOnlyFilterProvider), isFalse);
      expect(container.read(mapModeProvider), isFalse);

      // Tap PRESENCIAL otra vez — no debe cambiar mapMode (sigue en LISTA).
      await tester.tap(find.text('PRESENCIAL'));
      await tester.pumpAndSettle();

      expect(container.read(mapModeProvider), isFalse,
          reason:
              're-tap PRESENCIAL ya estando ahí debe respetar elección de LISTA');
    });

    testWidgets(
        'cuando virtualOnly:true → tap pill MAPA NO cambia mapModeProvider '
        '(disabled)',
        (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerDiscoveryProvider.overrideWith((_) async => const []),
            virtualOnlyFilterProvider.overrideWith((ref) => true),
          ],
          child: Consumer(builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: AppTheme.dark(),
              home: const TrainersListScreen(),
            );
          }),
        ),
      );
      await tester.pumpAndSettle();

      // virtualOnly ON desde el override; mapMode default false.
      expect(container.read(virtualOnlyFilterProvider), isTrue);
      expect(container.read(mapModeProvider), isFalse);

      // Tap en pill MAPA — debería ser no-op por disabled. El GestureDetector
      // tiene onTap=null cuando disabled, así que el tap "missea" — usamos
      // warnIfMissed:false para silenciar el warning (esa es exactamente la
      // condición que estamos verificando).
      await tester.tap(find.text('MAPA'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(container.read(mapModeProvider), isFalse,
          reason: 'MAPA disabled cuando virtualOnly ON');
    });
  });
}
