// T3.1 RED — gym-google-places Phase 3 (Slice 3).
//
// Replaces gym_picker_parity_test.dart (two-step brand/branch picker,
// retired). Drives the shared GymSearchBox widget directly — the single
// debounced search box that step_2_gym.dart and profile_gym_screen.dart both
// wrap. Covers spec gym-catalog "Athlete gym selection is a single debounced
// search": type -> debounced suggestions, tap -> selection callback,
// kNoGymId option, loading/error+retry/empty-results states, and works
// without location permission (no bias, no crash).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/places_autocomplete_service.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/gyms/domain/gym_suggestion.dart';
import 'package:treino/features/profile_setup/presentation/widgets/gym_card.dart';
import 'package:treino/features/profile_setup/presentation/widgets/gym_search_box.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockPlacesAutocompleteService extends Mock
    implements PlacesAutocompleteService {}

Widget _wrap({
  required List<Override> overrides,
  required String? selectedGymId,
  required void Function(String?) onGymIdSelected,
  Widget? emptyQueryContent,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: GymSearchBox(
            selectedGymId: selectedGymId,
            onGymIdSelected: onGymIdSelected,
            emptyQueryContent: emptyQueryContent,
          ),
        ),
      ),
    );

void main() {
  late MockPlacesAutocompleteService mockService;

  setUp(() {
    mockService = MockPlacesAutocompleteService();
  });

  testWidgets('typing debounces and shows Autocomplete suggestions via GymCard',
      (tester) async {
    when(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const [
          GymSuggestion(
            placeId: 'ChIJ_1',
            primaryText: 'SportClub Belgrano',
            secondaryText: 'Cabildo 1789',
          ),
        ]);

    await tester.pumpWidget(_wrap(
      overrides: [
        placesAutocompleteServiceProvider.overrideWithValue(mockService),
        gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sport');
    // Not yet past the 300ms debounce.
    await tester.pump(const Duration(milliseconds: 100));
    verifyNever(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        ));

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byType(GymCard), findsWidgets);
    expect(find.text('SportClub Belgrano'), findsOneWidget);
    expect(find.text('Cabildo 1789'), findsOneWidget);
  });

  testWidgets('tapping a suggestion calls onGymIdSelected with the placeId',
      (tester) async {
    when(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const [
          GymSuggestion(
            placeId: 'ChIJ_1',
            primaryText: 'SportClub Belgrano',
            secondaryText: 'Cabildo 1789',
          ),
        ]);

    String? selected;
    await tester.pumpWidget(_wrap(
      overrides: [
        placesAutocompleteServiceProvider.overrideWithValue(mockService),
        gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (id) => selected = id,
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sport');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SportClub Belgrano'));
    await tester.pump();

    expect(selected, 'ChIJ_1');
  });

  testWidgets('kNoGymId option is present and selectable without a search',
      (tester) async {
    String? selected;
    await tester.pumpWidget(_wrap(
      overrides: [
        placesAutocompleteServiceProvider.overrideWithValue(mockService),
        gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (id) => selected = id,
    ));
    await tester.pump();

    expect(find.text('OTRO GYM / SIN GYM'), findsOneWidget);

    await tester.tap(find.text('OTRO GYM / SIN GYM'));
    await tester.pump();

    expect(selected, kNoGymId);
    verifyNever(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        ));
  });

  testWidgets('shows a loading indicator while the search is in flight',
      (tester) async {
    final completer = Completer<List<GymSuggestion>>();
    when(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_wrap(
      overrides: [
        placesAutocompleteServiceProvider.overrideWithValue(mockService),
        gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sport');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('shows an error state with retry when the search fails',
      (tester) async {
    when(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenThrow(const PlacesAutocompleteError('network error'));

    await tester.pumpWidget(_wrap(
      overrides: [
        placesAutocompleteServiceProvider.overrideWithValue(mockService),
        gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sport');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.textContaining('No pudimos'), findsOneWidget);

    when(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const [
          GymSuggestion(placeId: 'ChIJ_1', primaryText: 'SportClub Belgrano'),
        ]);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('SportClub Belgrano'), findsOneWidget);
  });

  testWidgets('shows an empty-results state distinct from loading/error',
      (tester) async {
    when(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const []);

    await tester.pumpWidget(_wrap(
      overrides: [
        placesAutocompleteServiceProvider.overrideWithValue(mockService),
        gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Sin resultados para "zzz-no-match"'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('works without location permission — no bias, no crash',
      (tester) async {
    when(() => mockService.search(
          query: any(named: 'query'),
          sessionToken: any(named: 'sessionToken'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const [
          GymSuggestion(placeId: 'ChIJ_1', primaryText: 'SportClub Belgrano'),
        ]);

    await tester.pumpWidget(_wrap(
      overrides: [
        placesAutocompleteServiceProvider.overrideWithValue(mockService),
        gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        // Explicit override, NOT the un-overridden real provider: under
        // `testWidgets` (TestWidgetsFlutterBinding), `Geolocator.checkPermission()`
        // hangs forever instead of throwing `MissingPluginException` (unlike
        // under a plain `test()`), so `pumpAndSettle` never settles if this
        // provider is left un-overridden. Mirrors `AthleteLocationNotifier`'s
        // `setDeniedForTest()` convention (trainer_discovery_providers.dart) —
        // widget tests always override the location provider explicitly
        // rather than relying on the platform channel to fail.
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sport');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('SportClub Belgrano'), findsOneWidget);
    verify(() => mockService.search(
          query: 'sport',
          sessionToken: 'tok-fixed',
          biasLatitude: null,
          biasLongitude: null,
        )).called(1);
  });

  // gym-selection-v2 Phase 2 task 2.1 — AD-10 emptyQueryContent seam.
  group('emptyQueryContent seam (AD-10)', () {
    testWidgets(
        'default (null) empty-query render is byte-for-byte the existing '
        'SizedBox.shrink() output', (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: [
          placesAutocompleteServiceProvider.overrideWithValue(mockService),
          gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
          gymSearchLocationBiasProvider.overrideWith((ref) async => null),
        ],
        selectedGymId: null,
        onGymIdSelected: (_) {},
        // emptyQueryContent omitted — defaults to null.
      ));
      await tester.pump();

      // No suggestions-list content rendered at all — matches pre-seam
      // behavior exactly (the empty-query slot renders nothing observable).
      expect(find.byType(GymCard), findsOneWidget); // only the kNoGymId card
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Sin resultados'), findsNothing);
    });

    testWidgets(
        'a non-null emptyQueryContent widget renders in its place when '
        'query is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: [
          placesAutocompleteServiceProvider.overrideWithValue(mockService),
          gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
          gymSearchLocationBiasProvider.overrideWith((ref) async => null),
        ],
        selectedGymId: null,
        onGymIdSelected: (_) {},
        emptyQueryContent: const Text('NEARBY_PLACEHOLDER'),
      ));
      await tester.pump();

      expect(find.text('NEARBY_PLACEHOLDER'), findsOneWidget);
    });

    testWidgets(
        'non-empty query still shows Autocomplete results regardless of '
        'emptyQueryContent', (tester) async {
      when(() => mockService.search(
            query: any(named: 'query'),
            sessionToken: any(named: 'sessionToken'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const [
            GymSuggestion(
              placeId: 'ChIJ_1',
              primaryText: 'SportClub Belgrano',
              secondaryText: 'Cabildo 1789',
            ),
          ]);

      await tester.pumpWidget(_wrap(
        overrides: [
          placesAutocompleteServiceProvider.overrideWithValue(mockService),
          gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
          gymSearchLocationBiasProvider.overrideWith((ref) async => null),
        ],
        selectedGymId: null,
        onGymIdSelected: (_) {},
        emptyQueryContent: const Text('NEARBY_PLACEHOLDER'),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'sport');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('SportClub Belgrano'), findsOneWidget);
      expect(find.text('NEARBY_PLACEHOLDER'), findsNothing);
    });
  });
}
