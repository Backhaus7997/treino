import 'package:cloud_functions/cloud_functions.dart';

/// Result of a successful `resolveGymPlace` call.
///
/// Mirrors `functions/src/places-search.ts`'s `runResolveGymPlace` return
/// shape (`{gymId, name, address, source}`, Slice 1). NOT freezed — a
/// simple data class is enough, same rationale as `DeletionResult`.
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

  /// Always `'google-places'` for this CF — kept as a plain string here
  /// (not [GymSource]) so the data layer doesn't need to import the domain
  /// enum just to round-trip a value the caller never branches on.
  final String source;
}

/// Client-side failure calling `resolveGymPlace`. Sealed so callers can
/// distinguish a structured CF error from an unknown/network failure —
/// mirrors `AccountDeletionFailure` (account_deletion_service.dart).
sealed class ResolveGymPlaceFailure implements Exception {
  const ResolveGymPlaceFailure();
}

/// CF returned a [FirebaseFunctionsException] (e.g. `invalid-argument`,
/// `resource-exhausted`, `internal`).
final class ResolveGymPlaceFailure$Server extends ResolveGymPlaceFailure {
  const ResolveGymPlaceFailure$Server({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() =>
      'ResolveGymPlaceFailure\$Server(code: $code, message: $message)';
}

/// Unknown / network / unexpected error.
final class ResolveGymPlaceFailure$Unknown extends ResolveGymPlaceFailure {
  const ResolveGymPlaceFailure$Unknown({this.cause});

  final Object? cause;

  @override
  String toString() => 'ResolveGymPlaceFailure\$Unknown(cause: $cause)';
}

/// Thin wrapper around the `resolveGymPlace` Firebase Callable Function
/// (`functions/src/places-search.ts`, Slice 1).
///
/// Per spec gym-places-search: Place Details resolution happens
/// SERVER-SIDE ONLY — this is the sole client entry point that triggers it.
/// Region MUST be `southamerica-east1` (see [resolveGymPlaceServiceProvider])
/// — the Firebase client default is `us-central1`.
class ResolveGymPlaceService {
  ResolveGymPlaceService({required FirebaseFunctions functions})
      : _functions = functions;

  final FirebaseFunctions _functions;

  /// Invokes `resolveGymPlace` with [placeId] and the optional
  /// [sessionToken] shared with the Autocomplete session that produced it
  /// (spec: "the same token in the one Place Details request triggered by
  /// the eventual selection").
  ///
  /// Throws [ResolveGymPlaceFailure] on error.
  Future<ResolveGymPlaceResult> call({
    required String placeId,
    String? sessionToken,
  }) async {
    try {
      final callable = _functions.httpsCallable('resolveGymPlace');
      final result = await callable.call<Map<String, dynamic>>({
        'placeId': placeId,
        if (sessionToken != null) 'sessionToken': sessionToken,
      });
      final data = result.data;
      return ResolveGymPlaceResult(
        gymId: data['gymId'] as String,
        name: data['name'] as String,
        address: data['address'] as String?,
        source: data['source'] as String? ?? 'google-places',
      );
    } on FirebaseFunctionsException catch (e) {
      throw ResolveGymPlaceFailure$Server(
        code: e.code,
        message: e.message ?? 'Unknown error',
      );
    } catch (e) {
      throw ResolveGymPlaceFailure$Unknown(cause: e);
    }
  }
}
