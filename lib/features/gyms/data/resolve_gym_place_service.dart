import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/moderation/moderation_guard.dart';
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
    this.needsName = false,
    this.existsUnnamed = false,
  });

  /// Google Place ID, reused as `gyms/{gymId}` doc id.
  final String gymId;

  /// Nombre que escribió un usuario. Vacío si [needsName].
  final String name;

  /// Always `'google-places'` here — kept as a plain string (not
  /// [GymSource]) so callers that only round-trip it don't need to import
  /// the domain enum.
  final String source;

  /// `true` cuando el gym no existe todavía, o existe sin nombre de usuario:
  /// quien llama tiene que pedirle el nombre al usuario y volver a llamar
  /// con `name`. En ese caso NO se escribió nada.
  final bool needsName;

  /// `true` cuando [needsName] y el doc `gyms/{gymId}` YA existe (migrado,
  /// marcado `nameNeeded`). Nombrarlo exige que el usuario esté vinculado a
  /// ese gym (regla de Firestore), cosa que todavía no pasa durante el alta.
  final bool existsUnnamed;
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
/// `GET https://places.googleapis.com/v1/places/{placeId}`
/// Headers: `X-Goog-Api-Key`, `X-Goog-FieldMask`.
/// Query:   `sessionToken` (optional, shared with the Autocomplete session).
/// Response fields used: `location.latitude`/`longitude` ONLY.
class ResolveGymPlaceService {
  ResolveGymPlaceService({
    required GymRepository gymRepository,
    required http.Client httpClient,
    required String clientApiKey,
  })  : _gymRepository = gymRepository,
        _httpClient = httpClient,
        _clientApiKey = clientApiKey;

  /// Solo `location`: Google no deja guardar su nombre ni su dirección, y
  /// el campo `location` es SKU Essentials (barato).
  static const _fieldMask = 'location';

  final GymRepository _gymRepository;
  final http.Client _httpClient;
  final String _clientApiKey;

  /// Resolves [placeId], reading through the `gyms/{placeId}` cache first.
  ///
  /// El nombre del gym lo escribe el PRIMER usuario que lo vincula
  /// ([name], sin prefill de Google) y todos ven ese. Sin [name]:
  /// - gym inexistente o marcado `nameNeeded` → devuelve `needsName: true`
  ///   sin escribir ni llamar a Google;
  /// - gym con nombre → lo devuelve tal cual.
  /// Con [name] sobre un gym ya nombrado, gana el nombre existente.
  ///
  /// [sessionToken] MUST be the same token shared with the Autocomplete
  /// session that produced [placeId] (spec: "the same token in the one
  /// Place Details request triggered by the eventual selection").
  ///
  /// [beforeNaming] se ejecuta justo ANTES de escribir el nombre de un gym
  /// `nameNeeded`: la regla de Firestore sólo deja nombrarlo a quien ya tiene
  /// `users/{uid}.gymId` apuntando a ese gym, así que quien llama vincula acá.
  ///
  /// Throws [ResolveGymPlaceFailure] on error and
  /// `ModerationBlockedException` when [name] is blocked — never crashes.
  Future<ResolveGymPlaceResult> call({
    required String placeId,
    String? name,
    String? sessionToken,
    Future<void> Function()? beforeNaming,
  }) async {
    if (placeId.isEmpty) {
      throw const ResolveGymPlaceFailure$Config('placeId is required.');
    }
    final typed = name?.trim();
    final hasTyped = typed != null && typed.isNotEmpty;
    // El nombre es texto público de usuario: mismo filtro que displayName.
    // Se valida ANTES de cualquier red o escritura.
    if (hasTyped) ModerationGuard.ensure(typed, campo: 'gym.name');

    // ── Read-through cache ──────────────────────────────────────────────
    final cached = await _gymRepository.getById(placeId);
    if (cached != null) {
      if (cached.nameNeeded) {
        if (!hasTyped) {
          return ResolveGymPlaceResult(
            gymId: cached.id,
            name: '',
            source: cached.source.toWire(),
            needsName: true,
            existsUnnamed: true,
          );
        }
        try {
          await beforeNaming?.call();
          await _gymRepository.setName(cached.id, typed);
        } catch (_) {
          // Carrera: otro usuario lo nombró entre nuestro getById y el
          // update (la regla niega al segundo). Gana el nombre del primero.
          final winner = await _gymRepository.getById(placeId);
          if (winner == null || winner.nameNeeded) rethrow;
          return ResolveGymPlaceResult(
            gymId: winner.id,
            name: winner.name,
            source: winner.source.toWire(),
          );
        }
        return ResolveGymPlaceResult(
          gymId: cached.id,
          name: typed,
          source: cached.source.toWire(),
        );
      }
      return ResolveGymPlaceResult(
        gymId: cached.id,
        name: cached.name,
        source: cached.source.toWire(),
      );
    }

    // ── Cache miss ──────────────────────────────────────────────────────
    if (!hasTyped) {
      return ResolveGymPlaceResult(
        gymId: placeId,
        name: '',
        source: GymSource.googlePlaces.toWire(),
        needsName: true,
      );
    }
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
      name: typed,
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
      // (la regla niega el segundo escritor). Gana el nombre del primero.
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
      name: typed,
      source: 'google-places',
    );
  }
}
