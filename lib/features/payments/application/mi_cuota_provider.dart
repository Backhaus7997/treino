import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show currentAthleteLinkProvider;
import '../../coach/domain/trainer_link_status.dart';
import '../domain/athlete_billing.dart';
import '../domain/payment.dart';
import 'payment_providers.dart' show athletePaymentsProvider;

// ── Result types ──────────────────────────────────────────────────────────────

/// One charge the athlete currently owes their trainer — always backed by a
/// real pending `Payment` doc (never a computed/virtual amount).
///
/// Slice 1 (2026-07) — payments decoupled from training and made 100%
/// manual: this used to also synthesize a virtual charge for
/// `mensual`/`semanal` cadences (missing-period check) and for `porSesion`
/// (counting the athlete's finished `Session`s). Both were removed —
/// [BillingCadence] is now informative-only metadata the trainer sets (the
/// reference rate), and no longer drives any calculation here.
class MiCuotaItem {
  const MiCuotaItem({
    required this.amountArs,
    required this.cadence,
    required this.concept,
  });

  final int amountArs;

  /// Always [BillingCadence.suelto] — the only cadence this provider still
  /// produces, since every item now maps 1:1 to a real pending `Payment` doc.
  final BillingCadence cadence;
  final String concept;
}

/// What the current athlete owes their active trainer, plus the trainer's
/// payment alias (resolved by the widget). Read-only: the athlete pays offline
/// and the trainer confirms — see "solo informativo" decision (2026-06-03).
class MiCuotaState {
  const MiCuotaState({required this.items});

  /// Empty when the athlete has no pending real `Payment` docs.
  final List<MiCuotaItem> items;

  int get totalArs => items.fold(0, (sum, i) => sum + i.amountArs);
  bool get isEmpty => items.isEmpty;
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Athlete vantage of [pagosPorCobrarProvider]: surfaces the athlete's real
/// pending `Payment` docs — no computed or virtual charges.
///
/// Slice 1 (2026-07): previously derived a recurring charge from the active
/// trainer's [AthleteBilling] cadence (mensual/semanal missing-period check,
/// porSesion finished-session count). That auto-generation coupled billing to
/// training. It is gone — the trainer now creates/marks every charge by hand,
/// and this provider just reads the resulting ledger: any `Payment` with
/// `status == pending` addressed to this athlete IS what's owed, full stop.
///
/// Returns `data(null)` when there is no active link (nothing to show).
final miCuotaProvider = Provider.autoDispose<AsyncValue<MiCuotaState?>>((ref) {
  // ── 1. Athlete's link ──────────────────────────────────────────────────────
  final linkAsync = ref.watch(currentAthleteLinkProvider);

  if (linkAsync.isLoading && !linkAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (linkAsync.hasError && !linkAsync.hasValue) {
    return AsyncValue.error(linkAsync.error!, linkAsync.stackTrace!);
  }

  final link = linkAsync.valueOrNull;
  if (link == null || link.status != TrainerLinkStatus.active) {
    return const AsyncValue.data(null);
  }

  // ── 2. Payments addressed to this athlete ──────────────────────────────────
  final paymentsAsync = ref.watch(athletePaymentsProvider);
  if (paymentsAsync.isLoading && !paymentsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (paymentsAsync.hasError && !paymentsAsync.hasValue) {
    return AsyncValue.error(paymentsAsync.error!, paymentsAsync.stackTrace!);
  }
  // Scope to the ACTIVE trainer (fix #333). athletePaymentsProvider streams
  // every payment addressed to this athlete across ALL trainers (a terminated
  // link's included), so without this filter a previous trainer's pending
  // charge would surface under "Tu cuota" attributed to the current one.
  final payments = (paymentsAsync.valueOrNull ?? const <Payment>[])
      .where((p) => p.trainerId == link.trainerId)
      .toList();

  // ── 3. Real pending charges only (any cadence, even no config) ─────────────
  final items = <MiCuotaItem>[
    for (final p in payments)
      if (p.status == PaymentStatus.pending)
        MiCuotaItem(
          amountArs: p.amountArs,
          cadence: BillingCadence.suelto,
          concept: p.concept,
        ),
  ];

  return AsyncValue.data(MiCuotaState(items: items));
});
