import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/payment_repository.dart';
import '../domain/payment.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream of all payments created by the current trainer.
///
/// Returns an empty list when no trainer is authenticated.
final trainerPaymentsProvider = StreamProvider.autoDispose<List<Payment>>(
  (ref) {
    final trainerId = ref.watch(currentUidProvider);
    if (trainerId == null) return Stream.value(const []);
    return ref.watch(paymentRepositoryProvider).watchForTrainer(trainerId);
  },
);

/// Live stream of all payments addressed to the current athlete (the viewer).
///
/// Athlete vantage of [trainerPaymentsProvider]. Firestore rules allow an
/// athlete to read payments where `athleteId == auth.uid`. Returns an empty
/// list when nobody is authenticated.
final athletePaymentsProvider = StreamProvider.autoDispose<List<Payment>>(
  (ref) {
    final athleteId = ref.watch(currentUidProvider);
    if (athleteId == null) return Stream.value(const []);
    return ref.watch(paymentRepositoryProvider).watchForAthlete(athleteId);
  },
);
