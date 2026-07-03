import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/gym_suggestion.dart';

/// Thrown when [PlacesTextSearchService] is misconfigured — e.g. an empty
/// client API key. Distinct from [PlacesTextSearchError] so callers can tell
/// a setup mistake (dev/CI forgot `--dart-define`) apart from a runtime
/// network/API failure. Mirrors [PlacesNearbySearchConfigError].
class PlacesTextSearchConfigError implements Exception {
  const PlacesTextSearchConfigError(this.message);

  final String message;

  @override
  String toString() => 'PlacesTextSearchConfigError: $message';
}

/// Thrown on any searchText request failure (non-200 response or network
/// exception). NEVER includes the API key in [message] — mirrors the
/// no-key-leak guarantee of [PlacesNearbySearchError].
class PlacesTextSearchError implements Exception {
  const PlacesTextSearchError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PlacesTextSearchError($statusCode): $message';
}

/// Client-side Google Places Text Search (New) service.
///
/// Per design gym-selection-v2 AD-12: replaces [PlacesAutocompleteService]
/// (deleted) as the backend for `GymSearchBox`'s typed search. Device
/// testing showed Autocomplete's prominence ranking systematically hid a
/// real, correctly-typed, nearby Place even with location bias; Text
/// Search's relevance/bias-oriented ranking fixed this empirically.
///
/// `POST https://places.googleapis.com/v1/places:searchText`
/// Headers: `X-Goog-Api-Key`, `X-Goog-FieldMask` (required — no default
/// field mask exists; omitting it errors the call), `Content-Type:
/// application/json`.
/// Body: `{textQuery, pageSize: 20, locationBias?: {circle: {center,
/// radius}}}` — `locationBias` is OMITTED ENTIRELY (not null-valued) when no
/// location is available, mirroring [PlacesAutocompleteService]'s exact
/// all-or-nothing `locationBias` contract.
/// Response: `places[].{id, displayName, formattedAddress}` — mapped to the
/// EXISTING [GymSuggestion] DTO, no new domain type (Text Search results
/// don't carry coordinates the way `searchNearby`'s do, unlike [NearbyGym]).
///
/// Text Search bills as Text Search Pro (~$32/1000, no free-session model,
/// same tier as `searchNearby`) — callers MUST NOT invoke [search] per
/// keystroke; cost gating (debounce, min-chars, cache) lives in the
/// provider layer (`placesTextSearchProvider`), never here.
class PlacesTextSearchService {
  PlacesTextSearchService({
    required http.Client httpClient,
    required String clientApiKey,
  })  : _httpClient = httpClient,
        _clientApiKey = clientApiKey;

  static final Uri _endpoint =
      Uri.parse('https://places.googleapis.com/v1/places:searchText');

  /// Required field mask (AD-12) — mirrors [PlacesNearbySearchService]'s
  /// `fieldMask` constant but omits `places.location` (Text Search results
  /// feed [GymSuggestion], which has no coordinates).
  static const String fieldMask =
      'places.id,places.displayName,places.formattedAddress';

  /// Requested result count (AD-12) — mirrors
  /// [PlacesNearbySearchService.defaultMaxResultCount].
  static const int defaultPageSize = 20;

  /// Default location-bias radius when a position is available — mirrors
  /// [PlacesAutocompleteService.defaultBiasRadiusMeters] (30km, a full metro
  /// area).
  static const int defaultBiasRadiusMeters = 30000;

  final http.Client _httpClient;
  final String _clientApiKey;

  /// Runs a `searchText` search for [textQuery], restricted to `gym`-typed
  /// places by query relevance, optionally biased toward
  /// ([biasLatitude]/[biasLongitude]).
  ///
  /// [biasLatitude]/[biasLongitude]/[biasRadiusMeters] are all-or-nothing —
  /// mirrors [PlacesAutocompleteService.search]: a null latitude/longitude
  /// (no location permission) omits `locationBias` entirely from the
  /// request body, the search still runs, just unbiased.
  ///
  /// Zero matches (empty `places` array) returns `const []`, NOT an error.
  Future<List<GymSuggestion>> search({
    required String textQuery,
    double? biasLatitude,
    double? biasLongitude,
    int biasRadiusMeters = defaultBiasRadiusMeters,
    int pageSize = defaultPageSize,
  }) async {
    if (_clientApiKey.isEmpty) {
      throw const PlacesTextSearchConfigError(
        'PLACES_CLIENT_KEY is empty — provide it via '
        '--dart-define=PLACES_CLIENT_KEY=<bundle-restricted-key> at build '
        'time. See README/docs for how the key is provisioned.',
      );
    }

    final body = <String, Object?>{
      'textQuery': textQuery,
      'pageSize': pageSize,
      if (biasLatitude != null && biasLongitude != null)
        'locationBias': {
          'circle': {
            'center': {
              'latitude': biasLatitude,
              'longitude': biasLongitude,
            },
            'radius': biasRadiusMeters,
          },
        },
    };

    http.Response response;
    try {
      response = await _httpClient.post(
        _endpoint,
        headers: {
          'X-Goog-Api-Key': _clientApiKey,
          'X-Goog-FieldMask': fieldMask,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw PlacesTextSearchError('searchText request failed: $e');
    }

    if (response.statusCode != 200) {
      throw PlacesTextSearchError(
        'searchText request returned an error',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['places'] is! List) {
      return const [];
    }

    final places = decoded['places'] as List;
    final out = <GymSuggestion>[];
    for (final entry in places) {
      if (entry is! Map) continue;
      final placeId = entry['id'];
      if (placeId is! String || placeId.isEmpty) continue;

      final name = _extractText(entry['displayName']) ?? '';
      final address = entry['formattedAddress'];

      out.add(GymSuggestion(
        placeId: placeId,
        primaryText: name,
        secondaryText: address is String ? address : null,
      ));
    }
    return out;
  }

  String? _extractText(Object? field) {
    if (field is Map && field['text'] is String) {
      return field['text'] as String;
    }
    return null;
  }
}
