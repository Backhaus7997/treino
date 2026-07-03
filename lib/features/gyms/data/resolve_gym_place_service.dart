import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/geohash.dart';
import '../domain/gym.dart';
import '../domain/gym_source.dart';
import 'gym_repository.dart';

/// Result of a successful [ResolveGymPlaceService.call].
///
/// Kept as a plain data class (not [Gym]) so callers only see the fields
/// they actually need — mirrors `DeletionResult`.
class ResolveGymPlaceResult {
  const ResolveGymPlaceResult({
    required this.gymId,
    required this.name,
    required this.address,
    required this.source,
  });

  /// Google Place ID, reused as `gyms/{gymId}` doc id.
  final String gymId;
  final String name;
  final String? address;

  /// Always `'google-places'` here — kept as a plain string (not
  /// [GymSource]) so callers that only round-trip it don't need to import
  /// the domain enum.
  final String source;
}

/// Client-side failure resolving a gym place. Sealed so callers can
/// distinguish a clear, safe-to-display error from an unknown/network
/// failure — mirrors `PlacesAutocompleteError`/`PlacesAutocompleteConfigError`.
sealed class ResolveGymPlaceFailure implements Exception {
  const ResolveGymPlaceFailure();
}

/// Service misconfigured — e.g. an empty client API key, or an empty
/// [ResolveGymPlaceService.call] `placeId` argument.
final class ResolveGymPlaceFailure$Config extends ResolveGymPlaceFailure {
  const ResolveGymPlaceFailure$Config(this.message);

  final String message;

  @override
  String toString() => 'ResolveGymPlaceFailure\$Config: $message';
}

/// Places API request failed (non-200 response) or returned an incomplete
/// result (missing name/location). NEVER includes the API key in [message].
final class ResolveGymPlaceFailure$Server extends ResolveGymPlaceFailure {
  const ResolveGymPlaceFailure$Server(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ResolveGymPlaceFailure\$Server($statusCode): $message';
}

/// Unknown / network / unexpected error.
final class ResolveGymPlaceFailure$Unknown extends ResolveGymPlaceFailure {
  const ResolveGymPlaceFailure$Unknown({this.cause});

  final Object? cause;

  @override
  String toString() => 'ResolveGymPlaceFailure\$Unknown(cause: $cause)';
}

/// Resolves a Google Places `placeId` into a `gyms/{placeId}` Firestore
/// document — CLIENT-SIDE (Plan B pivot).
///
/// The original design called `resolveGymPlace`, a Cloud Function using the
/// Admin SDK + a server-side Places key held in Secret Manager. That CF
/// CANNOT be deployed: GCP project `treino-dev` sits under org
/// `code-assurance.com`, whose Domain-Restricted-Sharing policy blocks
/// making a Cloud Function publicly invokable (`allUsers`). Plan B moves
/// Place Details resolution to the client, mirroring
/// `PlacesTextSearchService`'s pattern (bundle-restricted client key,
/// direct HTTP call to Places API (New)).
///
/// Read-through cache: [GymRepository.getById] first — if `gyms/{placeId}`
/// already exists, it is returned without calling the Places API. On a
/// cache miss, this calls Place Details (New) and upserts the mapped [Gym]
/// via [GymRepository.upsert] (an authenticated user can now create/update
/// `googlePlaces`-sourced gym docs directly — see firestore.rules).
///
/// `GET https://places.googleapis.com/v1/places/{placeId}`
/// Headers: `X-Goog-Api-Key`, `X-Goog-FieldMask`.
/// Query:   `sessionToken` (optional, shared with the Autocomplete session).
/// Response fields used: `id`, `displayName.text`, `formattedAddress`,
/// `location.latitude`/`longitude`, `types`.
class ResolveGymPlaceService {
  ResolveGymPlaceService({
    required GymRepository gymRepository,
    required http.Client httpClient,
    required String clientApiKey,
  })  : _gymRepository = gymRepository,
        _httpClient = httpClient,
        _clientApiKey = clientApiKey;

  static const _fieldMask = 'id,displayName,formattedAddress,location,types';

  final GymRepository _gymRepository;
  final http.Client _httpClient;
  final String _clientApiKey;

  /// Resolves [placeId], reading through the `gyms/{placeId}` cache first.
  ///
  /// [sessionToken] MUST be the same token shared with the Autocomplete
  /// session that produced [placeId] (spec: "the same token in the one
  /// Place Details request triggered by the eventual selection").
  ///
  /// Throws [ResolveGymPlaceFailure] on error — never crashes.
  Future<ResolveGymPlaceResult> call({
    required String placeId,
    String? sessionToken,
  }) async {
    if (placeId.isEmpty) {
      throw const ResolveGymPlaceFailure$Config('placeId is required.');
    }

    // ── Read-through cache ──────────────────────────────────────────────
    final cached = await _gymRepository.getById(placeId);
    if (cached != null) {
      return ResolveGymPlaceResult(
        gymId: cached.id,
        name: cached.name,
        address: cached.address,
        source: cached.source.toWire(),
      );
    }

    // ── Cache miss: resolve via Place Details (New) ─────────────────────
    if (_clientApiKey.isEmpty) {
      throw const ResolveGymPlaceFailure$Config(
        'PLACES_CLIENT_KEY is empty — provide it via '
        '--dart-define=PLACES_CLIENT_KEY=<bundle-restricted-key> at build '
        'time. See README/docs for how the key is provisioned.',
      );
    }

    final baseUri =
        Uri.parse('https://places.googleapis.com/v1/places/$placeId');
    final uri = sessionToken != null
        ? baseUri.replace(queryParameters: {'sessionToken': sessionToken})
        : baseUri;

    http.Response response;
    try {
      response = await _httpClient.get(
        uri,
        headers: {
          'X-Goog-Api-Key': _clientApiKey,
          'X-Goog-FieldMask': _fieldMask,
        },
      );
    } catch (e) {
      throw ResolveGymPlaceFailure$Unknown(cause: e);
    }

    if (response.statusCode != 200) {
      throw ResolveGymPlaceFailure$Server(
        'Places API request failed. Please try again.',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const ResolveGymPlaceFailure$Server(
        'Places API returned an unexpected response.',
      );
    }

    final displayName = decoded['displayName'];
    final name = (displayName is Map) ? displayName['text'] as String? : null;
    final location = decoded['location'];
    final lat = (location is Map) ? location['latitude'] as num? : null;
    final lng = (location is Map) ? location['longitude'] as num? : null;

    if (name == null || lat == null || lng == null) {
      throw const ResolveGymPlaceFailure$Server(
        'Places API returned an incomplete result. Please try again.',
      );
    }

    final address = decoded['formattedAddress'] as String?;

    final gym = Gym(
      id: placeId,
      name: name,
      address: address,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      geohash: geohash5(lat.toDouble(), lng.toDouble()),
      source: GymSource.googlePlaces,
      createdAt: DateTime.now().toUtc(),
    );

    await _gymRepository.upsert(gym);

    return ResolveGymPlaceResult(
      gymId: placeId,
      name: name,
      address: address,
      source: 'google-places',
    );
  }
}
