import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/domain/discovery_filters.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_advanced_filter_chips.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Position _fakePosition() => Position(
      latitude: -31.40,
      longitude: -64.18,
      timestamp: DateTime(2026, 5, 22),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Override del `athleteLocationProvider` con una Position fake.
Override _withFakeLocation() => athleteLocationProvider.overrideWith(
      (ref) => AthleteLocationNotifier()..setForTest(_fakePosition()),
    );

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('TrainerAdvancedFilterChips', () {
    testWidgets('renderiza ambos chips con labels default ("Distancia" + "Precio")',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerAdvancedFilterChips(),
        overrides: [_withFakeLocation()],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Distancia'), findsOneWidget);
      expect(find.text('Precio'), findsOneWidget);
    });

    testWidgets(
        'con filtro de distancia seleccionado, chip muestra el label corto activo',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerAdvancedFilterChips(),
        overrides: [
          _withFakeLocation(),
          selectedDistanceFilterProvider
              .overrideWith((_) => DistanceFilter.km5),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('< 5 km'), findsOneWidget);
      expect(find.text('Distancia'), findsNothing);
    });

    testWidgets(
        'con filtro de precio seleccionado, chip muestra el label corto activo',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerAdvancedFilterChips(),
        overrides: [
          _withFakeLocation(),
          selectedPriceFilterProvider
              .overrideWith((_) => PriceFilter.k5to10k),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('\$5-10k'), findsOneWidget);
      expect(find.text('Precio'), findsNothing);
    });

    testWidgets(
        'sin ubicación: chip Distancia muestra ícono location_off (disabled)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerAdvancedFilterChips(),
        // NO override de location → default null → disabled state
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.location_off), findsOneWidget);
    });

    testWidgets(
        'con ubicación: chip Distancia muestra arrow_down (enabled)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerAdvancedFilterChips(),
        overrides: [_withFakeLocation()],
      ));
      await tester.pumpAndSettle();

      // Hay 2 chips, ambos con arrow_down (Distancia + Precio). No
      // location_off porque hay location.
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(2));
      expect(find.byIcon(Icons.location_off), findsNothing);
    });

    testWidgets('chip de Precio funciona independiente de la ubicación',
        (tester) async {
      // Sin location, el chip de Precio debe seguir habilitado (no es
      // función de location).
      await tester.pumpWidget(_wrap(
        const TrainerAdvancedFilterChips(),
        overrides: [
          selectedPriceFilterProvider
              .overrideWith((_) => PriceFilter.under5k),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('< \$5k'), findsOneWidget);
    });
  });
}
