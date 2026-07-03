// T3.1 RED — gym-google-places Phase 3 (Slice 3).
// Rewritten for gym-selection-v2 Phase 3 (addendum, AD-12): typed search now
// runs via PlacesTextSearchService/placesTextSearchProvider (Text Search
// New) instead of the retired PlacesAutocompleteService. Debounce moved
// from a widget-owned Timer into the provider layer — tests override
// `textSearchDebounceDurationProvider` to a near-zero duration instead of
// pumping the real 300/600ms window.
//
// Drives the shared GymSearchBox widget directly — the single search box
// that step_2_gym.dart and profile_gym_screen.dart both wrap. Covers spec
// gym-catalog "Athlete gym selection is a single debounced search": type ->
// debounced suggestions, tap -> selection callback, kNoGymId option,
// loading/error+retry/empty-results states, and works without location
// permission (no bias, no crash).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/places_text_search_service.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/gyms/domain/gym_suggestion.dart';
import 'package:treino/features/profile_setup/presentation/widgets/gym_card.dart';
import 'package:treino/features/profile_setup/presentation/widgets/gym_search_box.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockPlacesTextSearchService extends Mock
    implements PlacesTextSearchService {}

/// Near-zero so widget tests don't have to pump the real 600ms debounce
/// window, while still exercising real Future-based scheduling.
const _testDebounce = Duration(milliseconds: 1);

Widget _wrap({
  required List<Override> overrides,
  required String? selectedGymId,
  required void Function(String?) onGymIdSelected,
  Widget? emptyQueryContent,
}) =>
    ProviderScope(
      overrides: [
        textSearchDebounceDurationProvider.overrideWithValue(_testDebounce),
        ...overrides,
      ],
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
  late MockPlacesTextSearchService mockService;

  setUp(() {
    mockService = MockPlacesTextSearchService();
  });

  testWidgets(
      'typing (>=3 chars) debounces and shows Text Search results via '
      'GymCard', (tester) async {
    when(() => mockService.search(
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const [
          GymSuggestion(
            placeId: 'ChIJ_1',
            primaryText: 'QIVOX Villa Warcalde',
            secondaryText: 'Some street 123',
          ),
        ]);

    await tester.pumpWidget(_wrap(
      overrides: [
        placesTextSearchServiceProvider.overrideWithValue(mockService),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'qivox');
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();

    expect(find.byType(GymCard), findsWidgets);
    expect(find.text('QIVOX Villa Warcalde'), findsOneWidget);
    expect(find.text('Some street 123'), findsOneWidget);
  });

  testWidgets('typing under 3 characters never calls the service',
      (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: [
        placesTextSearchServiceProvider.overrideWithValue(mockService),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'qi');
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();

    verifyNever(() => mockService.search(
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        ));
    expect(find.textContaining('Sin resultados'), findsNothing);
  });

  testWidgets('tapping a suggestion calls onGymIdSelected with the placeId',
      (tester) async {
    when(() => mockService.search(
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const [
          GymSuggestion(
            placeId: 'ChIJ_1',
            primaryText: 'QIVOX Villa Warcalde',
            secondaryText: 'Some street 123',
          ),
        ]);

    String? selected;
    await tester.pumpWidget(_wrap(
      overrides: [
        placesTextSearchServiceProvider.overrideWithValue(mockService),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (id) => selected = id,
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'qivox');
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('QIVOX Villa Warcalde'));
    await tester.pump();

    expect(selected, 'ChIJ_1');
  });

  testWidgets('kNoGymId option is present and selectable without a search',
      (tester) async {
    String? selected;
    await tester.pumpWidget(_wrap(
      overrides: [
        placesTextSearchServiceProvider.overrideWithValue(mockService),
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
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        ));
  });

  testWidgets('shows a loading indicator while the search is in flight',
      (tester) async {
    final completer = Completer<List<GymSuggestion>>();
    when(() => mockService.search(
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_wrap(
      overrides: [
        placesTextSearchServiceProvider.overrideWithValue(mockService),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'qivox');
    await tester.pump(const Duration(milliseconds: 5));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('shows an error state with retry when the search fails',
      (tester) async {
    when(() => mockService.search(
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenThrow(const PlacesTextSearchError('network error'));

    await tester.pumpWidget(_wrap(
      overrides: [
        placesTextSearchServiceProvider.overrideWithValue(mockService),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'qivox');
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining('No pudimos'), findsOneWidget);

    when(() => mockService.search(
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const [
          GymSuggestion(placeId: 'ChIJ_1', primaryText: 'QIVOX Villa Warcalde'),
        ]);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('QIVOX Villa Warcalde'), findsOneWidget);
  });

  testWidgets('shows an empty-results state distinct from loading/error',
      (tester) async {
    when(() => mockService.search(
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const []);

    await tester.pumpWidget(_wrap(
      overrides: [
        placesTextSearchServiceProvider.overrideWithValue(mockService),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Sin resultados para "zzz-no-match"'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('works without location permission — no bias, no crash',
      (tester) async {
    when(() => mockService.search(
          textQuery: any(named: 'textQuery'),
          biasLatitude: any(named: 'biasLatitude'),
          biasLongitude: any(named: 'biasLongitude'),
        )).thenAnswer((_) async => const [
          GymSuggestion(placeId: 'ChIJ_1', primaryText: 'QIVOX Villa Warcalde'),
        ]);

    await tester.pumpWidget(_wrap(
      overrides: [
        placesTextSearchServiceProvider.overrideWithValue(mockService),
        // Explicit override, NOT the un-overridden real provider: under
        // `testWidgets` (TestWidgetsFlutterBinding),
        // `Geolocator.checkPermission()` hangs forever instead of throwing
        // `MissingPluginException` — widget tests always override the
        // location provider explicitly rather than relying on the platform
        // channel to fail.
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ],
      selectedGymId: null,
      onGymIdSelected: (_) {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'qivox');
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('QIVOX Villa Warcalde'), findsOneWidget);
    verify(() => mockService.search(
          textQuery: 'qivox',
          biasLatitude: null,
          biasLongitude: null,
        )).called(1);
  });

  // gym-selection-v2 Phase 2 task 2.1 — AD-10 emptyQueryContent seam.
  // Unaffected by the Phase 3 backend swap — still exercised here to prove
  // the seam still holds against the new provider.
  group('emptyQueryContent seam (AD-10)', () {
    testWidgets(
        'default (null) empty-query render is byte-for-byte the existing '
        'SizedBox.shrink() output', (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: [
          placesTextSearchServiceProvider.overrideWithValue(mockService),
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
          placesTextSearchServiceProvider.overrideWithValue(mockService),
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
        'non-empty query still shows Text Search results regardless of '
        'emptyQueryContent', (tester) async {
      when(() => mockService.search(
            textQuery: any(named: 'textQuery'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const [
            GymSuggestion(
              placeId: 'ChIJ_1',
              primaryText: 'QIVOX Villa Warcalde',
              secondaryText: 'Some street 123',
            ),
          ]);

      await tester.pumpWidget(_wrap(
        overrides: [
          placesTextSearchServiceProvider.overrideWithValue(mockService),
          gymSearchLocationBiasProvider.overrideWith((ref) async => null),
        ],
        selectedGymId: null,
        onGymIdSelected: (_) {},
        emptyQueryContent: const Text('NEARBY_PLACEHOLDER'),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('QIVOX Villa Warcalde'), findsOneWidget);
      expect(find.text('NEARBY_PLACEHOLDER'), findsNothing);
    });
  });
}
