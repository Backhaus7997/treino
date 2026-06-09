import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainers_map_bottom_sheet.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

TrainerPublicProfile _trainer({
  String uid = 'trainer-1',
  String displayName = 'Camila Ruiz',
  TrainerSpecialty? specialty = TrainerSpecialty.crossfit,
  double? lat = -31.40,
  double? lon = -64.18,
  String? geohash = '6d6m7',
  int? rate = 7500,
}) =>
    TrainerPublicProfile(
      uid: uid,
      displayName: displayName,
      displayNameLowercase: displayName.toLowerCase(),
      trainerSpecialty: specialty,
      // Legacy singular fields — el fallback de `effectiveLocationsOf` los
      // sigue usando para PFs no migrados al schema array todavía.
      trainerLatitude: lat,
      trainerLongitude: lon,
      trainerGeohash: geohash,
      trainerMonthlyRate: rate,
    );

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

/// Override del `athleteLocationProvider` con una `Position` fake, usado
/// en tests que validan la variante "CERCA" del label del header.
Override _withFakeLocation() => athleteLocationProvider.overrideWith(
      (ref) => AthleteLocationNotifier()..setForTest(_fakePosition()),
    );

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(height: 200, child: child),
        ),
      ),
    );

void main() {
  group('TrainersMapBottomSheet', () {
    testWidgets('con ubicación: header dice "N ENTRENADORES CERCA" (plural)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainersMapBottomSheet(
          collapsed: false,
          onCollapsedChanged: (_) {},
        ),
        overrides: [
          _withFakeLocation(),
          trainerDiscoveryProvider.overrideWith((_) async => [
                _trainer(uid: 't1', displayName: 'Camila Ruiz'),
                _trainer(uid: 't2', displayName: 'Diego Aguirre'),
              ]),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('2 ENTRENADORES CERCA'), findsOneWidget);
      expect(find.text('Camila Ruiz'), findsOneWidget);
      expect(find.text('Diego Aguirre'), findsOneWidget);
    });

    testWidgets('con ubicación: header singular cuando count == 1',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainersMapBottomSheet(
          collapsed: false,
          onCollapsedChanged: (_) {},
        ),
        overrides: [
          _withFakeLocation(),
          trainerDiscoveryProvider.overrideWith((_) async => [_trainer()]),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 ENTRENADOR CERCA'), findsOneWidget);
    });

    testWidgets(
        'SIN ubicación: header dice "N ENTRENADORES" (sin CERCA — Fase 2b polish)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainersMapBottomSheet(
          collapsed: false,
          onCollapsedChanged: (_) {},
        ),
        overrides: [
          // NO override de location → default AsyncData(null) → hasLocation false
          trainerDiscoveryProvider.overrideWith((_) async => [_trainer()]),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 ENTRENADOR'), findsOneWidget);
      // Asegurar que NO dice CERCA cuando no hay location
      expect(find.text('1 ENTRENADOR CERCA'), findsNothing);
    });

    testWidgets('filtra trainers sin lat/lon — solo cuenta los que tienen',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainersMapBottomSheet(
          collapsed: false,
          onCollapsedChanged: (_) {},
        ),
        overrides: [
          _withFakeLocation(),
          trainerDiscoveryProvider.overrideWith((_) async => [
                _trainer(uid: 't1', displayName: 'Con Loc'),
                _trainer(
                    uid: 't2', displayName: 'Sin Loc', lat: null, lon: null),
              ]),
        ],
      ));
      await tester.pumpAndSettle();

      // Solo "Con Loc" se cuenta y renderiza
      expect(find.text('1 ENTRENADOR CERCA'), findsOneWidget);
      expect(find.text('Con Loc'), findsOneWidget);
      expect(find.text('Sin Loc'), findsNothing);
    });

    testWidgets('empty state cuando ningún trainer tiene location',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainersMapBottomSheet(
          collapsed: false,
          onCollapsedChanged: (_) {},
        ),
        overrides: [
          _withFakeLocation(),
          trainerDiscoveryProvider.overrideWith((_) async => [
                _trainer(lat: null, lon: null),
              ]),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('0 ENTRENADORES CERCA'), findsOneWidget);
      expect(
        find.textContaining('Sin entrenadores con ubicación'),
        findsOneWidget,
      );
    });

    testWidgets('card muestra nombre + specialty + precio', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainersMapBottomSheet(
          collapsed: false,
          onCollapsedChanged: (_) {},
        ),
        overrides: [
          trainerDiscoveryProvider.overrideWith((_) async => [
                _trainer(
                  displayName: 'Camila Ruiz',
                  specialty: TrainerSpecialty.crossfit,
                  rate: 7500,
                ),
              ]),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Camila Ruiz'), findsOneWidget);
      expect(find.text('crossfit'), findsOneWidget); // wire encoding lowercase
      expect(find.textContaining('7500'), findsOneWidget);
    });

    // NOTA: loading state ("provider en AsyncLoading → sheet renderiza nada")
    // no se testea aquí por problemas de leaked timers — el comportamiento
    // está implementado como SizedBox.shrink() default y es trivial de
    // verificar visualmente. Empty + data states sí cubren los casos reales.
  });
}
