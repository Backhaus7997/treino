import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import '../../coach/domain/trainer_link_status.dart';
import '../domain/athlete_billing.dart';
import '../domain/payment.dart';
import 'payment_providers.dart' show trainerPaymentsProvider;

// The ART wall-clock helpers moved to core/utils/argentina_time.dart. Re-export
// them so the payment writers/readers that import them from here (mi_cuota,
// trainer_dashboard, marcar_pagado) keep compiling unchanged.
export '../../../core/utils/argentina_time.dart'
    show argentinaNow, argentinaUtcOffset, toArgentina;

// ── ISO week helper ───────────────────────────────────────────────────────────

/// Returns the ISO 8601 week number for [date].
///
/// ISO weeks start on Monday. Week 1 is the week containing the first
/// Thursday of the year (equivalently, the week containing 4 January).
int _isoWeekNumber(DateTime date) {
  // Thursday in the same week as [date].
  final thursday = date.subtract(Duration(days: date.weekday - 4));
  // Week 1 starts on the Monday of the week that contains 4 January.
  final jan4 = DateTime.utc(thursday.year, 1, 4);
  final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
  return ((thursday.difference(week1Monday).inDays) ~/ 7) + 1;
}

/// Returns the ISO 8601 week-owning year for [date].
///
/// Near the New Year boundary this differs from [date]'s calendar year: the
/// owning year is the year of the Thursday in the same ISO week (the same
/// Thursday [_isoWeekNumber] keys off). E.g. 2027-01-01 (Fri) belongs to ISO
/// week 53 of 2026, so its owning year is 2026.
int _isoWeekYear(DateTime date) =>
    date.subtract(Duration(days: date.weekday - 4)).year;

/// Stable `YYYY-Www` period key for the ISO week containing [date].
///
/// Uses the ISO week-owning year (not the calendar year) so the same physical
/// ISO week maps to one key on both sides of the New Year boundary. Kept for
/// callers that still write/compare a `periodKey` on manually-registered
/// recurring payments (mi_cuota_provider, marcar_pagado_actions, the CF).
String isoWeekPeriodKey(DateTime date) =>
    '${_isoWeekYear(date)}-W${_isoWeekNumber(date).toString().padLeft(2, '0')}';

// ── Result type ───────────────────────────────────────────────────────────────

/// One pending charge entry, derived per athlete — always backed by one or
/// more real `Payment` docs (never a computed/virtual amount).
///
/// Slice 1 (2026-07) — payments decoupled from training and made 100% manual:
/// this used to also synthesize a virtual charge for `mensual`/`semanal`
/// cadences (missing-period check) and for `porSesion` (counting finished
/// `Session`s). Both were removed — [BillingCadence] is now informative-only
/// metadata on [AthleteBilling] (the reference rate the trainer charges), and
/// no longer drives any calculation here. What remains is the athlete's real
/// pending one-off `Payment` docs, aggregated into a single row so the coach
/// can settle them together via `pendingPaymentIds`.
class CobroPendiente {
  const CobroPendiente({
    required this.athleteId,
    required this.amountArs,
    required this.cadence,
    required this.concept,
    this.pendingPaymentIds = const [],
  });

  final String athleteId;
  final int amountArs;

  /// Always [BillingCadence.suelto] — the only cadence this provider still
  /// produces, since it now only aggregates real pending `Payment` docs.
  /// Kept as a field (rather than dropped) because downstream widgets
  /// (coach_hub `marcar_pagado_actions.dart`, `estado_cuenta_card.dart`)
  /// still branch/display on it.
  final BillingCadence cadence;
  final String concept;

  /// Ids of the real pending `Payment` docs this row aggregates. Always
  /// non-empty for a row produced by this provider — used by
  /// `PaymentRepository.markManyPaid` to settle them all in one batch.
  final List<String> pendingPaymentIds;
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Surfaces each active athlete's real pending `Payment` docs — no computed
/// or virtual charges.
///
/// Slice 1 (2026-07): previously derived a recurring charge from
/// [AthleteBilling]'s cadence (mensual/semanal missing-period check,
/// porSesion finished-session count). That auto-generation coupled billing to
/// training and to a "did the trainer already charge this period" guess. It
/// is gone — the trainer now creates/marks every charge by hand ("Registrar
/// pago" / "Marcar pagado"), and this provider just reads the resulting
/// ledger: any `Payment` with `status == pending` IS what's owed, full stop.
///
/// - Mirrors [trainedTodayProvider]'s AsyncValue-folding pattern.
/// - Returns loading while a required stream is still loading and no data
///   has arrived yet.
final pagosPorCobrarProvider =
    Provider.autoDispose<AsyncValue<List<CobroPendiente>>>((ref) {
  // ── 1. Trainer links ──────────────────────────────────────────────────────
  final linksAsync = ref.watch(trainerLinksStreamProvider);

  if (linksAsync.isLoading && !linksAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (linksAsync.hasError && !linksAsync.hasValue) {
    return AsyncValue.error(linksAsync.error!, linksAsync.stackTrace!);
  }

  final links = linksAsync.valueOrNull ?? const [];

  final activeLinks =
      links.where((l) => l.status == TrainerLinkStatus.active).toList();

  if (activeLinks.isEmpty) {
    return const AsyncValue.data([]);
  }

  // ── 2. All trainer payments (one stream for all athletes) ─────────────────
  final paymentsAsync = ref.watch(trainerPaymentsProvider);

  if (paymentsAsync.isLoading && !paymentsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  // Without this guard, an errored payments stream falls back to an empty
  // list, which would make every athlete look "up to date" and silently hide
  // real pending charges. Surface the error instead.
  if (paymentsAsync.hasError && !paymentsAsync.hasValue) {
    return AsyncValue.error(paymentsAsync.error!, paymentsAsync.stackTrace!);
  }

  final allPayments = paymentsAsync.valueOrNull ?? const [];

  // ── 3. Per-athlete: aggregate real pending Payment docs ───────────────────
  final results = <CobroPendiente>[];

  for (final link in activeLinks) {
    final athleteId = link.athleteId;

    final pendingForAthlete = allPayments
        .where((p) =>
            p.athleteId == athleteId && p.status == PaymentStatus.pending)
        .toList();

    if (pendingForAthlete.isEmpty) continue;

    final total = pendingForAthlete.fold<int>(0, (sum, p) => sum + p.amountArs);
    final n = pendingForAthlete.length;
    results.add(CobroPendiente(
      athleteId: athleteId,
      amountArs: total,
      cadence: BillingCadence.suelto,
      concept:
          n == 1 ? pendingForAthlete.first.concept : '$n cobros pendientes',
      pendingPaymentIds: pendingForAthlete.map((p) => p.id).toList(),
    ));
  }

  // Sort by athleteId for stable ordering (names load asynchronously)
  results.sort((a, b) => a.athleteId.compareTo(b.athleteId));

  return AsyncValue.data(results);
});
