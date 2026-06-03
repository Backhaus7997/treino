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
