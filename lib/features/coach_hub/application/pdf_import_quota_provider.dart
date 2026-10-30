import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_clock.dart';
import '../../../core/utils/argentina_time.dart';
import '../../../core/utils/firestore_snapshots.dart';
import '../../coach/domain/subscription_tier.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;

/// Lo que le queda al PF de imports de PDF esta semana y hoy, con los topes
/// de su plan (docs/plan-import-pdf.md, «Cupos»).
typedef PdfImportRemaining = ({
  int week,
  int day,
  int limitWeekly,
  int limitDaily,
});

/// El tier con el que el servidor cuenta el cupo, leído de
/// `users/{uid}.subscription` crudo. Espejo de `effectiveTier`
/// (`functions/src/subscriptions/effective-limit.ts`).
///
/// `null` = no se puede afirmar, y entonces la pantalla no muestra números:
/// un piso prepago vigente (el modelo Dart no lo trae y el servidor lo usa),
/// o un `tier`/`status` que no conocemos (el servidor lo degrada con su
/// propia regla; adivinarla acá sería inventar un cupo).
SubscriptionTier? pdfImportTierFrom(Object? raw, DateTime now) {
  if (raw == null) return SubscriptionTier.free;
  if (raw is! Map) return null;
  final prepaidUntil = raw['prepaidUntil'];
  final floorExpired =
      prepaidUntil is Timestamp && !now.isBefore(prepaidUntil.toDate());
  if ((raw['prepaidTier'] != null || prepaidUntil != null) && !floorExpired) {
    return null;
  }
  final tier = switch (raw['tier']) {
    'free' => SubscriptionTier.free,
    'plan1' => SubscriptionTier.plan1,
    'plan2' => SubscriptionTier.plan2,
    'plan3' => SubscriptionTier.plan3,
    _ => null,
  };
  if (tier == null) return null;
  final end = raw['currentPeriodEnd'];
  return switch (raw['status']) {
    'active' || 'grace' => tier,
    'cancelled' => end is Timestamp && now.isBefore(end.toDate())
        ? tier
        : SubscriptionTier.free,
    'pending' || 'paused' => SubscriptionTier.free,
    _ => null,
  };
}

String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lo restante según `pdfImportUsage/{uid}` ([usage], null = sin documento,
/// que el servidor cuenta como cero). Un contador cuya clave no es la de
/// [artNow] vale cero: así resetea el servidor (`countFor` de `quota.ts`).
PdfImportRemaining pdfImportRemainingFrom({
  required Map<String, dynamic>? usage,
  required SubscriptionTier tier,
  required DateTime artNow,
}) {
  final limits = kTierPdfImportLimits[tier]!;
  int count(String keyField, String countField, String key) {
    final c = usage?[countField];
    if (usage?[keyField] != key || c is! num) return 0;
    return c < 0 ? 0 : c.floor();
  }

  final week = count('weekKey', 'weekCount', _dateKey(mondayOfWeekArt(artNow)));
  final day = count('dayKey', 'dayCount', _dateKey(artNow));
  int left(int limit, int used) => used >= limit ? 0 : limit - used;
  return (
    week: left(limits.weekly, week),
    day: left(limits.daily, day),
    limitWeekly: limits.weekly,
    limitDaily: limits.daily,
  );
}

final _subscriptionRawProvider = StreamProvider.autoDispose<Object?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return const Stream.empty();
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .snapshotsSinCacheVacia()
      .map((snap) => snap.data()?['subscription']);
});

final _pdfImportUsageProvider =
    StreamProvider.autoDispose<Map<String, dynamic>?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return const Stream.empty();
  return ref
      .watch(firestoreProvider)
      .collection('pdfImportUsage')
      .doc(uid)
      .snapshotsSinCacheVacia()
      .map((snap) => snap.data());
});

/// El cupo restante, o `null` mientras no se sepa: cargando, con error, o
/// con un tier que el cliente no puede afirmar. Nunca «0» por no saber.
/// Es sólo para mostrar: el servidor descuenta y decide.
final pdfImportRemainingProvider =
    Provider.autoDispose<PdfImportRemaining?>((ref) {
  final sub = ref.watch(_subscriptionRawProvider);
  final usage = ref.watch(_pdfImportUsageProvider);
  // Las claves de día y semana cambian con el reloj, no con Firestore: sin
  // esto, una pantalla abierta al cruzar la medianoche ART (o el lunes)
  // seguiría mostrando el cupo de ayer. La medianoche del lunes también es
  // un borde de día, así que un solo timer cubre los dos.
  final artNow = argentinaNow();
  final nextMidnight = DateTime.utc(artNow.year, artNow.month, artNow.day + 1);
  final untilMidnight =
      nextMidnight.difference(artNow) + const Duration(seconds: 1);
  final timer = Timer(untilMidnight, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  if (!sub.hasValue || !usage.hasValue || sub.hasError || usage.hasError) {
    return null;
  }
  // El instante real para el vencimiento de la baja; el reloj ART sólo para
  // las claves de semana y día.
  final tier = pdfImportTierFrom(sub.requireValue, AppClock.now());
  if (tier == null) return null;
  return pdfImportRemainingFrom(
    usage: usage.requireValue,
    tier: tier,
    artNow: artNow,
  );
});
