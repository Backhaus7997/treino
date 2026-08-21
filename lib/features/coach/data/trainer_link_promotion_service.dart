import 'package:cloud_functions/cloud_functions.dart';

import '../domain/subscription_tier.dart';

/// Client-side failures from the `acceptTrainerLink` callable (Fase 7, PR4,
/// slice 2 — paywall enforcement). NOT freezed (Hard Constraint #3), mirrors
/// the sealed-class shape of `AccountDeletionFailure`.
///
/// The three variants map 1:1 to the three UI branches the callsites render:
/// upsell paywall, "ya no disponible" snackbar, "revisá tu conexión" snackbar.
sealed class LinkPromotionFailure implements Exception {
  const LinkPromotionFailure();
}

/// CF threw `resource-exhausted` with a well-formed weighted-load payload.
///
/// [reason] is the raw string from the CF (`'plan-limit'` |
/// `'subscription-inactive'`, see D-2 in accept-trainer-link.ts) —
/// deliberately NOT mapped to `PlanLimitReason` here: that enum lives in the
/// presentation layer (`plan_limit_paywall.dart`), and this service must not
/// depend upward on it. Callsites do the mapping.
final class LinkPromotionFailure$PlanLimitReached extends LinkPromotionFailure {
  const LinkPromotionFailure$PlanLimitReached({
    required this.reason,
    required this.tier,
    required this.limit,
    required this.currentLoad,
    required this.projectedLoad,
  });

  final String reason;
  final SubscriptionTier tier;

  /// `num`, not `int`: the CF sends these as JS numbers, which can arrive as
  /// either `int` or `double` depending on platform/codec — pinned by
  /// SCENARIO tests below (Android `Map<Object?, Object?>` gotcha).
  final num limit;
  final num currentLoad;
  final num projectedLoad;

  @override
  String toString() =>
      'LinkPromotionFailure\$PlanLimitReached(reason: $reason, tier: $tier, '
      'limit: $limit, currentLoad: $currentLoad, projectedLoad: $projectedLoad)';
}

/// Non-quota precondition: `failed-precondition` (`wrong-status` |
/// `link-blocked`), `not-found` (link doc missing), or `permission-denied`
/// (caller isn't the link's trainer). Design D-5: none of these are
/// retryable — the request is no longer valid, so the UI shows a
/// non-actionable "ya no disponible" snackbar instead of the generic
/// connectivity message. The stream will remove the pending card shortly.
final class LinkPromotionFailure$PromotionPrecondition
    extends LinkPromotionFailure {
  const LinkPromotionFailure$PromotionPrecondition();

  @override
  String toString() => 'LinkPromotionFailure\$PromotionPrecondition()';
}

/// Catch-all: `invalid-argument`, `unauthenticated`, network/unknown errors,
/// AND a malformed `resource-exhausted` payload (defensive degrade instead
/// of a runtime crash — see the Android `details` cast gotcha in
/// [_parsePlanLimit]). Design D-5: these ARE plausibly safe to retry (bad
/// client state, expired session, connectivity), so the UI shows the
/// "revisá tu conexión" message.
final class LinkPromotionFailure$PromotionUnavailable
    extends LinkPromotionFailure {
  const LinkPromotionFailure$PromotionUnavailable({this.cause});

  final Object? cause;

  @override
  String toString() =>
      'LinkPromotionFailure\$PromotionUnavailable(cause: $cause)';
}

/// Thin wrapper around the `acceptTrainerLink` and `resumeTrainerLink`
/// Firebase Callable Functions.
///
/// Replaces `TrainerLinkRepository.accept()`/`.resume()` — both promotions
/// are now server-authoritative behind the weighted-load gate (see
/// `functions/src/subscriptions/accept-trainer-link.ts` and
/// `functions/src/subscriptions/resume-trainer-link.ts`).
class TrainerLinkPromotionService {
  TrainerLinkPromotionService({required FirebaseFunctions functions})
      : _functions = functions;

  final FirebaseFunctions _functions;

  /// Invokes the `acceptTrainerLink` callable with [linkId] as payload.
  ///
  /// Throws [LinkPromotionFailure] on error. Never throws
  /// [FirebaseFunctionsException] or any other raw type — callers only need
  /// to catch the sealed class.
  Future<void> accept(String linkId) async {
    try {
      final callable = _functions.httpsCallable('acceptTrainerLink');
      await callable.call<Map<String, dynamic>>({'linkId': linkId});
    } on FirebaseFunctionsException catch (e) {
      throw _mapException(e);
    } catch (e) {
      throw LinkPromotionFailure$PromotionUnavailable(cause: e);
    }
  }

  /// Invokes the `resumeTrainerLink` callable with [linkId] as payload.
  ///
  /// Replaces `TrainerLinkRepository.resume()` — like [accept], the
  /// paused → active transition is now server-authoritative behind the
  /// weighted-load gate (Fase 7, PR4, slice 3 — see
  /// `functions/src/subscriptions/resume-trainer-link.ts`).
  ///
  /// Throws [LinkPromotionFailure] on error. Never throws
  /// [FirebaseFunctionsException] or any other raw type — callers only need
  /// to catch the sealed class. Reuses [_mapException]/[_parsePlanLimit]: the
  /// error contract mirrors `acceptTrainerLink` exactly.
  Future<void> resume(String linkId) async {
    try {
      final callable = _functions.httpsCallable('resumeTrainerLink');
      await callable.call<Map<String, dynamic>>({'linkId': linkId});
    } on FirebaseFunctionsException catch (e) {
      throw _mapException(e);
    } catch (e) {
      throw LinkPromotionFailure$PromotionUnavailable(cause: e);
    }
  }

  LinkPromotionFailure _mapException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'resource-exhausted':
        return _parsePlanLimit(e.details) ??
            LinkPromotionFailure$PromotionUnavailable(cause: e);
      case 'failed-precondition':
      case 'not-found':
      case 'permission-denied':
        // Design D-5: non-retryable — the request is no longer valid.
        return const LinkPromotionFailure$PromotionPrecondition();
      default:
        // invalid-argument, unauthenticated, and anything else: plausibly
        // retryable — degrade to the generic "revisá tu conexión" snackbar.
        return LinkPromotionFailure$PromotionUnavailable(cause: e);
    }
  }

  /// Parses the `resource-exhausted` `details` payload.
  ///
  /// GOTCHA: on Android, `FirebaseFunctionsException.details` arrives as
  /// `Map<Object?, Object?>` (the platform channel's StandardMessageCodec
  /// does NOT produce `Map<String, dynamic>` for nested maps), while on
  /// iOS/web it's typically `Map<String, dynamic>`. A direct
  /// `details as Map<String, dynamic>` cast compiles fine and passes on
  /// iOS/web/tests, then throws a `TypeError` at runtime ONLY on Android.
  ///
  /// Fix: never cast the outer map. Read fields dynamically (Dart's `dynamic`
  /// index operator works identically on both map shapes), validate each
  /// field's runtime type individually, and tolerate mixed `int`/`double`
  /// for the numeric fields. Any malformed shape degrades to `null` (caller
  /// falls back to [LinkPromotionFailure$PromotionUnavailable]) instead of
  /// throwing.
  LinkPromotionFailure$PlanLimitReached? _parsePlanLimit(dynamic details) {
    if (details is! Map) return null;
    final reason = details['reason'];
    final tierRaw = details['tier'];
    final limit = _asNum(details['limit']);
    final currentLoad = _asNum(details['currentLoad']);
    final projectedLoad = _asNum(details['projectedLoad']);
    if (reason is! String ||
        tierRaw is! String ||
        limit == null ||
        currentLoad == null ||
        projectedLoad == null) {
      return null;
    }
    return LinkPromotionFailure$PlanLimitReached(
      reason: reason,
      tier: SubscriptionTierX.fromJson(tierRaw),
      limit: limit,
      currentLoad: currentLoad,
      projectedLoad: projectedLoad,
    );
  }

  num? _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}
