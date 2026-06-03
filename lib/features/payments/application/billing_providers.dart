import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/billing_repository.dart';
import '../domain/athlete_billing.dart';

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream of the billing config for [athleteId] set by the current trainer.
///
/// Returns null when no config has been set yet or no trainer is authenticated.
final athleteBillingProvider =
    StreamProvider.autoDispose.family<AthleteBilling?, String>(
  (ref, athleteId) {
    final trainerId = ref.watch(currentUidProvider);
    if (trainerId == null) return Stream.value(null);
    return ref.watch(billingRepositoryProvider).watch(trainerId, athleteId);
  },
);

/// Identifies a single (trainer, athlete) billing document. Used by the
/// athlete-facing read path, where the trainerId comes from the link rather
/// than from the current uid.
typedef BillingPair = ({String trainerId, String athleteId});

/// Live stream of the billing config for an explicit (trainer, athlete) pair.
///
/// Athlete vantage of [athleteBillingProvider]: the athlete is `auth.uid`
/// and the trainerId comes from their link. Firestore rules allow the athlete
/// to read `athlete_billing/{trainerId}_{athleteId}` when athleteId matches.
final athleteBillingPairProvider =
    StreamProvider.autoDispose.family<AthleteBilling?, BillingPair>(
  (ref, pair) => ref
      .watch(billingRepositoryProvider)
      .watch(pair.trainerId, pair.athleteId),
);
