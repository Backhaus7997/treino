import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import '../../coach/domain/trainer_link_status.dart';
import '../../workout/application/session_providers.dart'
    show sessionsByUidProvider;
import '../../workout/domain/session_status.dart';
import '../domain/athlete_billing.dart';
import '../domain/payment.dart';
import 'billing_providers.dart' show athleteBillingProvider;
import 'payment_providers.dart' show trainerPaymentsProvider;

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
/// ISO week maps to one key on both sides of the New Year boundary. Reader
/// (this provider, mi_cuota_provider) and writer (trainer_dashboard_tab) MUST
/// build the key the same way or weekly charges double-bill across year-end.
String isoWeekPeriodKey(DateTime date) =>
    '${_isoWeekYear(date)}-W${_isoWeekNumber(date).toString().padLeft(2, '0')}';

// ── Spanish month names ───────────────────────────────────────────────────────

const _kMeses = <String>[
  '',
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

// ── Result type ───────────────────────────────────────────────────────────────

/// One pending charge entry, derived per athlete.
class CobroPendiente {
  const CobroPendiente({
    required this.athleteId,
    required this.amountArs,
    required this.cadence,
    required this.concept,
    this.sessionsCount,
    this.pendingPaymentIds = const [],
  });

  final String athleteId;
  final int amountArs;
  final BillingCadence cadence;
  final String concept;

  /// Non-null only for [BillingCadence.porSesion].
  final int? sessionsCount;

  /// Non-empty only for [BillingCadence.suelto].
  final List<String> pendingPaymentIds;
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Derives pending charges per active athlete based on their billing cadence.
///
/// - Mirrors [trainedTodayProvider]'s AsyncValue-folding pattern.
/// - Returns loading while any required per-athlete stream is still loading
///   and no data has arrived yet.
/// - Skips athletes whose billing is not configured.
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
  // Without this guard, an errored payments stream falls back to an empty list,
  // which makes the "already paid" / lastPaidAt logic treat every athlete as
  // never paid and re-surface their full recurring charges. Surface the error
  // instead so the dashboard shows its error state rather than wrong amounts.
  if (paymentsAsync.hasError && !paymentsAsync.hasValue) {
    return AsyncValue.error(paymentsAsync.error!, paymentsAsync.stackTrace!);
  }

  final allPayments = paymentsAsync.valueOrNull ?? const [];

  // ── 3. Compute now once ───────────────────────────────────────────────────
  final now = DateTime.now().toUtc();
  final currentYear = now.year;
  final currentMonth = now.month;
  final currentWeek = _isoWeekNumber(now);

  final monthKey = '$currentYear-${currentMonth.toString().padLeft(2, '0')}';
  final weekKey = isoWeekPeriodKey(now);

  // ── 4. Per-athlete computation ────────────────────────────────────────────
  final results = <CobroPendiente>[];
  bool anyLoading = false;

  for (final link in activeLinks) {
    final athleteId = link.athleteId;

    final athletePayments =
        allPayments.where((p) => p.athleteId == athleteId).toList();

    // ── One-off pending charges ───────────────────────────────────────────
    // Surfaced ALWAYS — these are ad-hoc charges created via "+ Cobro" and
    // are independent of the athlete's configured cadence (or lack thereof).
    final pendingOneOff = athletePayments
        .where((p) => p.status == PaymentStatus.pending)
        .toList();
    if (pendingOneOff.isNotEmpty) {
      final total = pendingOneOff.fold<int>(0, (sum, p) => sum + p.amountArs);
      final n = pendingOneOff.length;
      results.add(CobroPendiente(
        athleteId: athleteId,
        amountArs: total,
        cadence: BillingCadence.suelto,
        concept: n == 1 ? pendingOneOff.first.concept : '$n cobros pendientes',
        pendingPaymentIds: pendingOneOff.map((p) => p.id).toList(),
      ));
    }

    // ── Recurring cadence charge ──────────────────────────────────────────
    // Only when a billing config exists. A `suelto` config has no recurring
    // charge — its charges are the one-off pendings handled above.
    final billingAsync = ref.watch(athleteBillingProvider(athleteId));

    if (billingAsync.isLoading && !billingAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    if (billingAsync.hasError && !billingAsync.hasValue) {
      // Cannot determine this athlete's recurring config — skip their recurring
      // charge rather than guess. One-off pendings above already surfaced.
      continue;
    }

    final billing = billingAsync.valueOrNull;
    if (billing == null) continue; // no recurring config — one-offs only

    switch (billing.cadence) {
      // ── mensual ─────────────────────────────────────────────────────────
      case BillingCadence.mensual:
        final alreadyPaid = athletePayments.any(
          (p) => p.status == PaymentStatus.paid && p.periodKey == monthKey,
        );
        if (!alreadyPaid) {
          results.add(CobroPendiente(
            athleteId: athleteId,
            amountArs: billing.amountArs,
            cadence: BillingCadence.mensual,
            concept: 'Mensual ${_kMeses[currentMonth]} $currentYear',
          ));
        }

      // ── semanal ─────────────────────────────────────────────────────────
      case BillingCadence.semanal:
        final alreadyPaid = athletePayments.any(
          (p) => p.status == PaymentStatus.paid && p.periodKey == weekKey,
        );
        if (!alreadyPaid) {
          results.add(CobroPendiente(
            athleteId: athleteId,
            amountArs: billing.amountArs,
            cadence: BillingCadence.semanal,
            concept: 'Semana ${currentWeek.toString().padLeft(2, '0')}',
          ));
        }

      // ── porSesion ────────────────────────────────────────────────────────
      case BillingCadence.porSesion:
        // Gate: only count sessions if the athlete shared their history.
        if (!link.sharedWithTrainer) {
          // Cannot count — skip (not an amount owed, just uncountable)
          continue;
        }

        final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));
        if (sessionsAsync.isLoading && !sessionsAsync.hasValue) {
          anyLoading = true;
          continue;
        }
        if (sessionsAsync.hasError && !sessionsAsync.hasValue) {
          // Cannot count sessions for this athlete — skip rather than charge 0.
          continue;
        }

        final sessions = sessionsAsync.valueOrNull ?? const [];

        // Billing window floor: start no earlier than when the relationship
        // began (link.acceptedAt) so sessions finished before the athlete ever
        // linked to this trainer are not charged. Falls back to epoch only
        // when acceptedAt is missing.
        final epoch = DateTime.utc(1970);
        DateTime lastPaidAt = link.acceptedAt?.toUtc() ?? epoch;
        for (final p in athletePayments) {
          if (p.status == PaymentStatus.paid && p.paidAt != null) {
            if (p.paidAt!.isAfter(lastPaidAt)) {
              lastPaidAt = p.paidAt!;
            }
          }
        }

        int count = 0;
        for (final s in sessions) {
          if (s.status != SessionStatus.finished) continue;
          final finished = s.finishedAt;
          if (finished == null) continue;
          if (finished.toUtc().isAfter(lastPaidAt)) count++;
        }

        if (count > 0) {
          results.add(CobroPendiente(
            athleteId: athleteId,
            amountArs: count * billing.amountArs,
            cadence: BillingCadence.porSesion,
            concept: '$count ${count == 1 ? 'sesión' : 'sesiones'}',
            sessionsCount: count,
          ));
        }

      // ── suelto ──────────────────────────────────────────────────────────
      // No recurring charge: ad-hoc charges are handled by the one-off block
      // above (which runs for every athlete regardless of cadence).
      case BillingCadence.suelto:
        break;
    }
  }

  if (anyLoading && results.isEmpty) {
    return const AsyncValue.loading();
  }

  // Sort by athleteId for stable ordering (names load asynchronously)
  results.sort((a, b) => a.athleteId.compareTo(b.athleteId));

  return AsyncValue.data(results);
});
