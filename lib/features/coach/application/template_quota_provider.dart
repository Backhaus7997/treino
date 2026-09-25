import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'custom_exercise_quota_provider.dart' show kPlanLimitsField;

/// Tope y conteo de plantillas leídos SÓLO de `users/{uid}`
/// (docs/limite-plantillas-pf.md §2, §3 PR5), para superficies que muestran
/// el uso y no gatean nada (la línea de Facturación del Coach Hub).
///
/// Mismo tipo que `CustomExerciseQuota` en `custom_exercise_quota_provider.dart`
/// — no se reusa ese typedef a propósito: son dos cuotas de dominios
/// distintos que hoy tienen la misma forma por coincidencia, y acoplarlas
/// haría que cambiar una obligara a auditar la otra.
typedef TemplateQuota = ({int? limit, int count});

/// Sólo el provider de RESUMEN, calcado de
/// `customExerciseUsageSummaryProvider` en `custom_exercise_quota_provider.dart`
/// y por el mismo motivo exacto: leer `templateUsage.count` +
/// `planLimits.templates` del documento del PF es una lectura; el embudo del
/// gate (docs/limite-plantillas-pf.md §3 PR3) necesita en cambio el conteo EN
/// VIVO de `watchTemplatesBy`, que baja la colección entera — tiene sentido
/// ahí porque esa pantalla ya la lee para listarla, pero acá serían hasta 3
/// lecturas de más —o sin techo en un plan pago— sólo para un número que la
/// pestaña de Facturación no necesita fresco al segundo.
///
/// INDEPENDIENTE de ese gate: este archivo no importa nada de él y no debería
/// — si el gate todavía no existe, este provider igual funciona, porque lee
/// directo del documento que la CF de PR1 ya mantiene.
///
/// ## `null` = «no sé», nunca «cero»
///
/// Si `templateUsage.count` no existe todavía (functions sin deployar, o un
/// PF que el barrido todavía no recontó) devuelve `null` y la superficie se
/// oculta. Mostrar «0» afirmaría un conteo que nadie hizo — misma razón que
/// [customExerciseUsageSummaryProvider].
final templateUsageSummaryProvider =
    StreamProvider.autoDispose<TemplateQuota?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .snapshots()
      // Misma guarda de caché fría que `_customExercisePlanLimitProvider`:
      // con la cache local fría la PRIMERA snapshot llega con
      // `exists == false` antes de que el servidor confirme.
      .where((snap) => snap.exists || !snap.metadata.isFromCache)
      .map((snap) {
    final data = snap.data();
    final usage = data?['templateUsage'];
    final count = usage is Map ? usage['count'] : null;
    if (count is! int) return null;
    final limits = data?[kPlanLimitsField];
    final limit = limits is Map ? limits['templates'] : null;
    return (limit: limit is int ? limit : null, count: count);
  }).distinct();
});
