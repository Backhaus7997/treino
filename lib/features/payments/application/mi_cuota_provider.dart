import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show currentAthleteLinkProvider;
import '../../coach/domain/trainer_link_status.dart';
import '../../workout/application/session_providers.dart'
    show sessionsByUidProvider;
import '../../workout/domain/session_status.dart';
import '../domain/athlete_billing.dart';
import '../domain/payment.dart';
import 'billing_providers.dart' show athleteBillingPairProvider;
import 'pagos_por_cobrar_provider.dart' show argentinaNow, isoWeekPeriodKey;
import 'payment_providers.dart' show athletePaymentsProvider;

// ── ISO week helper (mirrors pagos_por_cobrar_provider) ───────────────────────

int _isoWeekNumber(DateTime date) {
  final thursday = date.subtract(Duration(days: date.weekday - 4));
  final jan4 = DateTime.utc(thursday.year, 1, 4);
  final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
  return ((thursday.difference(week1Monday).inDays) ~/ 7) + 1;
}

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

// ── Result types ──────────────────────────────────────────────────────────────

/// One charge the athlete currently owes their trainer.
class MiCuotaItem {
  const MiCuotaItem({
    required this.amountArs,
    required this.cadence,
    required this.concept,
  });

  final int amountArs;
  final BillingCadence cadence;
  final String concept;
}

/// What the current athlete owes their active trainer, plus the trainer's
/// payment alias (resolved by the widget). Read-only: the athlete pays offline
/// and the trainer confirms — see "solo informativo" decision (2026-06-03).
class MiCuotaState {
  const MiCuotaState({required this.items});

  /// Empty when the athlete is up to date or has no billing configured.
  final List<MiCuotaItem> items;

  int get totalArs => items.fold(0, (sum, i) => sum + i.amountArs);
  bool get isEmpty => items.isEmpty;
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Athlete vantage of [pagosPorCobrarProvider]: derives what the viewer owes
/// their active trainer based on the billing cadence the trainer configured.
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

  final trainerId = link.trainerId;
  final athleteId = link.athleteId;

  // ── 2. Payments addressed to this athlete ──────────────────────────────────
  final paymentsAsync = ref.watch(athletePaymentsProvider);
  if (paymentsAsync.isLoading && !paymentsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (paymentsAsync.hasError && !paymentsAsync.hasValue) {
    return AsyncValue.error(paymentsAsync.error!, paymentsAsync.stackTrace!);
  }
  // Scope to the ACTIVE trainer. athletePaymentsProvider streams every payment
  // addressed to this athlete across ALL trainers (a terminated link's
  // included), so without this filter a previous trainer's pending charge would
  // surface under "Tu cuota" attributed to the current one. This also keeps the
  // mensual/semanal paid-checks and the porSesion paidAt floor below from
  // honouring a prior trainer's payments.
  final payments = (paymentsAsync.valueOrNull ?? const <Payment>[])
      .where((p) => p.trainerId == trainerId)
      .toList();

  // ── 3. Now (ART — period keys + concept strings are calendar concepts) ─────
  final now = argentinaNow();
  final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final weekKey = isoWeekPeriodKey(now);

  final items = <MiCuotaItem>[];

  // ── 4. One-off pending charges (any cadence, even no config) ────────────────
  final pendingOneOff =
      payments.where((p) => p.status == PaymentStatus.pending).toList();
  for (final p in pendingOneOff) {
    items.add(MiCuotaItem(
      amountArs: p.amountArs,
      cadence: BillingCadence.suelto,
      concept: p.concept,
    ));
  }

  // ── 5. Recurring cadence charge ─────────────────────────────────────────────
  final billingAsync = ref.watch(
    athleteBillingPairProvider((trainerId: trainerId, athleteId: athleteId)),
  );
  if (billingAsync.isLoading && !billingAsync.hasValue) {
    // Still surface the one-off charges if we already have them.
    if (items.isNotEmpty) return AsyncValue.data(MiCuotaState(items: items));
    return const AsyncValue.loading();
  }
  if (billingAsync.hasError && !billingAsync.hasValue) {
    // Still surface the one-off charges if we already have them.
    if (items.isNotEmpty) return AsyncValue.data(MiCuotaState(items: items));
    return AsyncValue.error(billingAsync.error!, billingAsync.stackTrace!);
  }

  final billing = billingAsync.valueOrNull;
  if (billing != null) {
    switch (billing.cadence) {
      case BillingCadence.mensual:
        final paid = payments.any(
          (p) => p.status == PaymentStatus.paid && p.periodKey == monthKey,
        );
        if (!paid) {
          items.add(MiCuotaItem(
            amountArs: billing.amountArs,
            cadence: BillingCadence.mensual,
            concept: 'Mensual ${_kMeses[now.month]} ${now.year}',
          ));
        }

      case BillingCadence.semanal:
        final paid = payments.any(
          (p) => p.status == PaymentStatus.paid && p.periodKey == weekKey,
        );
        if (!paid) {
          items.add(MiCuotaItem(
            amountArs: billing.amountArs,
            cadence: BillingCadence.semanal,
            concept: 'Semana ${_isoWeekNumber(now).toString().padLeft(2, '0')}',
          ));
        }

      case BillingCadence.porSesion:
        // Athlete always sees their own sessions — no share gate here.
        final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));
        if (sessionsAsync.isLoading && !sessionsAsync.hasValue) {
          if (items.isNotEmpty) {
            return AsyncValue.data(MiCuotaState(items: items));
          }
          return const AsyncValue.loading();
        }
        if (sessionsAsync.hasError && !sessionsAsync.hasValue) {
          if (items.isNotEmpty) {
            return AsyncValue.data(MiCuotaState(items: items));
          }
          return AsyncValue.error(
            sessionsAsync.error!,
            sessionsAsync.stackTrace!,
          );
        }
        final sessions = sessionsAsync.valueOrNull ?? const [];

        // Billing window floor: start no earlier than when the relationship
        // began (link.acceptedAt) so sessions finished before linking to this
        // trainer are not charged. Falls back to epoch only when missing.
        final epoch = DateTime.utc(1970);
        var lastPaidAt = link.acceptedAt?.toUtc() ?? epoch;
        for (final p in payments) {
          if (p.status == PaymentStatus.paid && p.paidAt != null) {
            if (p.paidAt!.isAfter(lastPaidAt)) lastPaidAt = p.paidAt!;
          }
        }

        var count = 0;
        for (final s in sessions) {
          if (s.status != SessionStatus.finished) continue;
          final finished = s.finishedAt;
          if (finished == null) continue;
          if (finished.toUtc().isAfter(lastPaidAt)) count++;
        }

        if (count > 0) {
          items.add(MiCuotaItem(
            amountArs: count * billing.amountArs,
            cadence: BillingCadence.porSesion,
            concept: '$count ${count == 1 ? 'sesión' : 'sesiones'}',
          ));
        }

      case BillingCadence.suelto:
        // No recurring charge — one-offs handled above.
        break;
    }
  }

  return AsyncValue.data(MiCuotaState(items: items));
});
