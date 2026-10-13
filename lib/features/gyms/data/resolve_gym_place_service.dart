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
    required this.source,
  });

  /// Google Place ID, reused as `gyms/{gymId}` doc id.
  final String gymId;

  /// Nombre ALMACENADO del gym (`gyms/{gymId}.name`). Para un gym de Places
  /// es el marcador [kGymPlaceholderName]: el nombre de Google se muestra en
  /// vivo (`gymDisplayNameProvider`) y nunca se guarda.
  final String name;

  /// Always `'google-places'` for newly created docs — kept as a plain string
  /// (not [GymSource]) so callers that only round-trip it don't need to
  /// import the domain enum.
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
/// cache miss, this calls Place Details (New) and creates the [Gym] via
/// [GymRepository.createFromPlace] (an authenticated user can create
/// `googlePlaces`-sourced gym docs directly — see firestore.rules).
///
/// POLÍTICA DE PLACES: los términos de Google Maps Platform prohíben GUARDAR
/// su contenido (nombre, dirección) — sólo el `place_id` (y lat/lng ≤30 días).
/// Por eso el doc se crea con el marcador [kGymPlaceholderName] y el nombre
/// real se pide en vivo con [fetchDisplayName], en memoria y sin persistir.
///
/// `GET https://places.googleapis.com/v1/places/{placeId}`
/// Headers: `X-Goog-Api-Key`, `X-Goog-FieldMask`.
/// Query:   `sessionToken` (optional, shared with the Autocomplete session).
class ResolveGymPlaceService {
  ResolveGymPlaceService({
    required GymRepository gymRepository,
    required http.Client httpClient,
    required String clientApiKey,
  })  : _gymRepository = gymRepository,
        _httpClient = httpClient,
        _clientApiKey = clientApiKey;

  /// Para crear el doc sólo hace falta `location` (SKU Essentials, barato).
  static const _fieldMask = 'location';

  /// Para mostrar el nombre en vivo.
  static const _displayNameFieldMask = 'displayName';

  final GymRepository _gymRepository;
  final http.Client _httpClient;
  final String _clientApiKey;

  /// Resolves [placeId], reading through the `gyms/{placeId}` cache first.
  ///
  /// Si el gym ya existe se devuelve tal cual, sin llamar a Google. Si no, se
  /// pide la ubicación y se crea con [kGymPlaceholderName] — nunca se escribe
  /// texto de Google.
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
        source: cached.source.toWire(),
      );
    }

    // ── Cache miss ──────────────────────────────────────────────────────
    final decoded = await _getDetails(
      placeId,
      fieldMask: _fieldMask,
      sessionToken: sessionToken,
    );

    final location = decoded['location'];
    final lat = (location is Map) ? location['latitude'] as num? : null;
    final lng = (location is Map) ? location['longitude'] as num? : null;

    if (lat == null || lng == null) {
      throw const ResolveGymPlaceFailure$Server(
        'Places API returned an incomplete result. Please try again.',
      );
    }

    final gym = Gym(
      id: placeId,
      name: kGymPlaceholderName,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      geohash: geohash5(lat.toDouble(), lng.toDouble()),
      source: GymSource.googlePlaces,
      createdAt: DateTime.now().toUtc(),
    );

    try {
      await _gymRepository.createFromPlace(gym);
    } catch (_) {
      // Carrera: otro usuario creó el gym entre nuestro getById y el create
      // (la regla niega el segundo escritor). Gana el doc del primero.
      final winner = await _gymRepository.getById(placeId);
      if (winner == null) rethrow;
      return ResolveGymPlaceResult(
        gymId: winner.id,
        name: winner.name,
        source: winner.source.toWire(),
      );
    }

    return ResolveGymPlaceResult(
      gymId: placeId,
      name: kGymPlaceholderName,
      source: 'google-places',
    );
  }

  /// Nombre actual del lugar según Google (`displayName.text`), pedido EN VIVO.
  ///
  /// Es contenido de Places: quien llama lo muestra y lo descarta (cache en
  /// memoria de la sesión como máximo). NUNCA se escribe en Firestore.
  /// Devuelve `null` si Google no trae nombre. Throws [ResolveGymPlaceFailure]
  /// ante error de red/servidor/configuración.
  Future<String?> fetchDisplayName(String placeId) async {
    if (placeId.isEmpty) {
      throw const ResolveGymPlaceFailure$Config('placeId is required.');
    }
    final decoded =
        await _getDetails(placeId, fieldMask: _displayNameFieldMask);
    final displayName = decoded['displayName'];
    final text = (displayName is Map) ? displayName['text'] : null;
    if (text is! String) return null;
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<Map<dynamic, dynamic>> _getDetails(
    String placeId, {
    required String fieldMask,
    String? sessionToken,
  }) async {
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
          'X-Goog-FieldMask': fieldMask,
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
    return decoded;
  }
}
