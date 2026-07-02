import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/gym_suggestion.dart';

/// Thrown when [PlacesAutocompleteService] is misconfigured — e.g. an empty
/// client API key. Distinct from [PlacesAutocompleteError] so callers can
/// tell a setup mistake (dev/CI forgot `--dart-define`) apart from a runtime
/// network/API failure.
class PlacesAutocompleteConfigError implements Exception {
  const PlacesAutocompleteConfigError(this.message);

  final String message;

  @override
  String toString() => 'PlacesAutocompleteConfigError: $message';
}

/// Thrown on any Autocomplete request failure (non-200 response or network
/// exception). NEVER includes the API key in [message] — mirrors the
/// no-key-leak guarantee of the server-side `resolveGymPlace` CF (Slice 1).
class PlacesAutocompleteError implements Exception {
  const PlacesAutocompleteError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PlacesAutocompleteError($statusCode): $message';
}

/// Client-side Google Places Autocomplete (New) service.
///
/// Per design gym-google-places #348 / spec gym-places-search: Autocomplete
/// runs CLIENT-SIDE using a bundle-restricted key (never the server key held
/// in Secret Manager). Place Details resolution stays server-side exclusively
/// — see `ResolveGymPlaceService` — this class never calls the Details
/// endpoint.
///
/// `POST https://places.googleapis.com/v1/places:autocomplete`
/// Headers: `X-Goog-Api-Key`, `Content-Type: application/json`.
/// Body: `{input, sessionToken, locationBias?, includedPrimaryTypes: [gym]}`.
/// Response: `suggestions[].placePrediction.{placeId, structuredFormat}`.
class PlacesAutocompleteService {
  PlacesAutocompleteService({
    required http.Client httpClient,
    required String clientApiKey,
  })  : _httpClient = httpClient,
        _clientApiKey = clientApiKey;

  static final Uri _endpoint =
      Uri.parse('https://places.googleapis.com/v1/places:autocomplete');

  /// Default location-bias radius when a position is available. 30km covers
  /// a full metro area (design open question, resolved at apply time).
  static const int defaultBiasRadiusMeters = 30000;

  final http.Client _httpClient;
  final String _clientApiKey;
  final Random _random = Random.secure();

  /// Runs an Autocomplete search restricted to `gym`-typed places.
  ///
  /// [sessionToken] MUST be the same token reused across every keystroke of
  /// one search session (see [newSessionToken]) and forwarded to the eventual
  /// `resolveGymPlace` Details call.
  ///
  /// [biasLatitude]/[biasLongitude]/[biasRadiusMeters] are all-or-nothing: a
  /// null latitude/longitude (no location permission, per spec's no-permission
  /// fallback) omits `locationBias` entirely from the request body — the
  /// search still runs, just unbiased.
  ///
  /// Empty/blank [query] returns `[]` without hitting the network — mirrors
  /// the "no fetch on empty query" contract used elsewhere in this codebase
  /// (see `searchUsersProvider`).
  Future<List<GymSuggestion>> search({
    required String query,
    required String sessionToken,
    double? biasLatitude,
    double? biasLongitude,
    int biasRadiusMeters = defaultBiasRadiusMeters,
  }) async {
    if (_clientApiKey.isEmpty) {
      throw const PlacesAutocompleteConfigError(
        'PLACES_CLIENT_KEY is empty — provide it via '
        '--dart-define=PLACES_CLIENT_KEY=<bundle-restricted-key> at build '
        'time. See README/docs for how the key is provisioned.',
      );
    }

    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final body = <String, Object?>{
      'input': trimmed,
      'sessionToken': sessionToken,
      'includedPrimaryTypes': const ['gym'],
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
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw PlacesAutocompleteError('Autocomplete request failed: $e');
    }

    if (response.statusCode != 200) {
      throw PlacesAutocompleteError(
        'Autocomplete request returned an error',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['suggestions'] is! List) {
      return const [];
    }

    final suggestions = decoded['suggestions'] as List;
    final out = <GymSuggestion>[];
    for (final entry in suggestions) {
      if (entry is! Map) continue;
      final prediction = entry['placePrediction'];
      if (prediction is! Map) continue;
      final placeId = prediction['placeId'];
      if (placeId is! String || placeId.isEmpty) continue;

      final structured = prediction['structuredFormat'];
      final mainText =
          (structured is Map) ? _extractText(structured['mainText']) : null;
      final secondaryText = (structured is Map)
          ? _extractText(structured['secondaryText'])
          : null;
      final fallbackText = _extractText(prediction['text']);

      out.add(GymSuggestion(
        placeId: placeId,
        primaryText: mainText ?? fallbackText ?? '',
        secondaryText: secondaryText,
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

  /// Generates a new opaque session token. Google requires a fresh,
  /// non-reused token per search session (spec: "A new search starts a new
  /// session token"). Not a real UUID (no new dependency added) — a
  /// sufficiently random 122-bit hex string serves the same opaque-token
  /// purpose Google's API expects.
  String newSessionToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
