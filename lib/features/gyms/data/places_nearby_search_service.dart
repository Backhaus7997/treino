import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/nearby_gym.dart';

/// Thrown when [PlacesNearbySearchService] is misconfigured — e.g. an empty
/// client API key. Distinct from [PlacesNearbySearchError] so callers can
/// tell a setup mistake (dev/CI forgot `--dart-define`) apart from a runtime
/// network/API failure. Mirrors [PlacesAutocompleteConfigError].
class PlacesNearbySearchConfigError implements Exception {
  const PlacesNearbySearchConfigError(this.message);

  final String message;

  @override
  String toString() => 'PlacesNearbySearchConfigError: $message';
}

/// Thrown on any searchNearby request failure (non-200 response or network
/// exception). NEVER includes the API key in [message] — mirrors the
/// no-key-leak guarantee of [PlacesAutocompleteError].
class PlacesNearbySearchError implements Exception {
  const PlacesNearbySearchError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PlacesNearbySearchError($statusCode): $message';
}

/// Client-side Google Places Nearby Search (New) service.
///
/// Per design gym-selection-v2 AD-7: mirrors [PlacesAutocompleteService]'s
/// injection/error-split pattern exactly. `searchNearby` bills as Nearby
/// Search Pro (no free-session model) — callers MUST NOT invoke [search]
/// more than once per screen-open; cost gating lives in the provider layer
/// (`nearbyGymsProvider`, AD-2/AD-9), never here.
///
/// `POST https://places.googleapis.com/v1/places:searchNearby`
/// Headers: `X-Goog-Api-Key`, `X-Goog-FieldMask` (AD-6, required — no
/// default field mask exists; omitting it errors the call),
/// `Content-Type: application/json`.
/// Body: `{includedTypes: ['gym'], maxResultCount, rankPreference: 'DISTANCE',
/// locationRestriction: {circle: {center, radius}}}`.
/// Response: `places[].{id, displayName, formattedAddress, location}`.
class PlacesNearbySearchService {
  PlacesNearbySearchService({
    required http.Client httpClient,
    required String clientApiKey,
  })  : _httpClient = httpClient,
        _clientApiKey = clientApiKey;

  static final Uri _endpoint =
      Uri.parse('https://places.googleapis.com/v1/places:searchNearby');

  /// Required field mask (AD-6) — `places.location` is included (same
  /// Essentials tier as id/displayName/formattedAddress, zero extra cost)
  /// so callers can compute client-side haversine "a X km" labels.
  static const String fieldMask =
      'places.id,places.displayName,places.formattedAddress,places.location';

  /// Fixed search radius (AD-3) — no expanding retry.
  static const int defaultRadiusMeters = 5000;

  /// Requested result count (AD-4) — headroom for current-gym dedup;
  /// callers render only the first 8.
  static const int defaultMaxResultCount = 20;

  final http.Client _httpClient;
  final String _clientApiKey;

  /// Runs a `searchNearby` search restricted to `gym`-typed places, ranked
  /// by distance from ([latitude], [longitude]).
  ///
  /// [latitude]/[longitude] are REQUIRED — unlike Autocomplete's optional
  /// bias, `locationRestriction.circle` cannot be omitted from this request.
  /// The "no location" case is handled upstream by the provider (AD-7), a
  /// distinct branch that never calls this method with null coordinates.
  ///
  /// Zero matches (empty `places` array) returns `const []`, NOT an error.
  Future<List<NearbyGym>> search({
    required double latitude,
    required double longitude,
    int radiusMeters = defaultRadiusMeters,
    int maxResultCount = defaultMaxResultCount,
  }) async {
    if (_clientApiKey.isEmpty) {
      throw const PlacesNearbySearchConfigError(
        'PLACES_CLIENT_KEY is empty — provide it via '
        '--dart-define=PLACES_CLIENT_KEY=<bundle-restricted-key> at build '
        'time. See README/docs for how the key is provisioned.',
      );
    }

    final body = <String, Object?>{
      'includedTypes': const ['gym'],
      'maxResultCount': maxResultCount,
      'rankPreference': 'DISTANCE',
      'locationRestriction': {
        'circle': {
          'center': {
            'latitude': latitude,
            'longitude': longitude,
          },
          'radius': radiusMeters,
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
      throw PlacesNearbySearchError('searchNearby request failed: $e');
    }

    if (response.statusCode != 200) {
      throw PlacesNearbySearchError(
        'searchNearby request returned an error',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['places'] is! List) {
      return const [];
    }

    final places = decoded['places'] as List;
    final out = <NearbyGym>[];
    for (final entry in places) {
      if (entry is! Map) continue;
      final placeId = entry['id'];
      if (placeId is! String || placeId.isEmpty) continue;

      final location = entry['location'];
      if (location is! Map) continue;
      final lat = location['latitude'];
      final lng = location['longitude'];
      if (lat is! num || lng is! num) continue;

      final name = _extractText(entry['displayName']) ?? '';
      final address = entry['formattedAddress'];

      out.add(NearbyGym(
        placeId: placeId,
        name: name,
        address: address is String ? address : null,
        lat: lat.toDouble(),
        lng: lng.toDouble(),
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
