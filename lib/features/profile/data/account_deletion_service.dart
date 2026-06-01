import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Simple data class for the CF response (NOT freezed — Hard Constraint #3).
class DeletionResult {
  const DeletionResult({
    required this.status,
    required this.deletedCollections,
    required this.errors,
  });

  /// 'success' | 'partial'
  final String status;
  final List<String> deletedCollections;

  /// CF reports errors as a list of human-readable strings, e.g.
  /// `"friendships: PERMISSION_DENIED: ..."`. NOT structured objects.
  final List<String> errors;
}

/// Sealed class for client-side account deletion failures (NOT freezed).
sealed class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure();
}

/// CF returned a FirebaseFunctionsException.
final class AccountDeletionFailure$Server extends AccountDeletionFailure {
  const AccountDeletionFailure$Server({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() =>
      'AccountDeletionFailure\$Server(code: $code, message: $message)';
}

/// Unknown / network / unexpected error.
final class AccountDeletionFailure$Unknown extends AccountDeletionFailure {
  const AccountDeletionFailure$Unknown({this.cause});

  final Object? cause;

  @override
  String toString() => 'AccountDeletionFailure\$Unknown(cause: $cause)';
}

/// Thin wrapper around the `deleteAccount` Firebase Callable Function.
///
/// Per ADR-ACCDEL-009: AccountDeletionService owns ONLY the CF call. All
/// orchestration lives in [AccountDeletionNotifier].
class AccountDeletionService {
  AccountDeletionService({required FirebaseFunctions functions})
      : _functions = functions;

  final FirebaseFunctions _functions;

  /// Invokes the `deleteAccount` callable with [uid] as payload.
  ///
  /// Throws [AccountDeletionFailure] on error.
  Future<DeletionResult> call({required String uid}) async {
    try {
      final callable = _functions.httpsCallable('deleteAccount');
      final result = await callable.call<Map<String, dynamic>>({'uid': uid});
      final data = result.data;
      return DeletionResult(
        status: data['status'] as String? ?? 'partial',
        deletedCollections: List<String>.from(
          data['deletedCollections'] as List<dynamic>? ?? const [],
        ),
        errors: List<String>.from(
          (data['errors'] as List<dynamic>? ?? const [])
              .map((e) => e.toString()),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      throw AccountDeletionFailure$Server(
        code: e.code,
        message: e.message ?? 'Unknown error',
      );
    } catch (e) {
      throw AccountDeletionFailure$Unknown(cause: e);
    }
  }
}

/// Riverpod provider for [AccountDeletionService].
///
/// Uses the `southamerica-east1` region to match the `deleteAccount` CF
/// deployment region (see functions/src/delete-account.ts). The Firebase
/// client default is `us-central1`, so an explicit `instanceFor` is required.
final accountDeletionServiceProvider = Provider<AccountDeletionService>(
  (ref) => AccountDeletionService(
    functions: FirebaseFunctions.instanceFor(region: 'southamerica-east1'),
  ),
);
