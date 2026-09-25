import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/routine_providers.dart'
    show trainerTemplatesStreamProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/domain/routine_status.dart';
import 'custom_exercise_quota_provider.dart' show kPlanLimitsField;

/// Cuota de plantillas del PF actual (docs/limite-plantillas-pf.md, PR3), ya
/// resuelta para el gate.
///
/// `limit == null` ⇒ sin tope (Plan 3, interruptor apagado, o campo todavía
/// ausente). El tipo obliga a contemplar el caso en cada call site, mismo
/// motivo que [CustomExerciseQuota] en `custom_exercise_quota_provider.dart`.
typedef TemplateQuota = ({int? limit, int count});

extension TemplateQuotaX on TemplateQuota {
  /// `true` cuando crear una más está bloqueado: el borde es `count < limit`
  /// al crear, así que `count == limit` YA bloquea.
  bool get isAtOrOverLimit => limit != null && count >= limit!;
}

/// El tope vigente de `users/{uid}.planLimits.templates`, o `null` si no hay
/// tope (ausente, `null`, o el campo con otra forma).
///
/// Privado: nadie fuera de este archivo debería razonar sobre el read crudo
/// — para eso está [templateQuotaProvider], que ya lo cruzó con el conteo.
final _templatePlanLimitProvider = StreamProvider.autoDispose<int?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .snapshots()
      // Misma guarda que `_customExercisePlanLimitProvider`: con la cache
      // local fría la PRIMERA snapshot llega con `exists == false` antes de
      // que el servidor confirme. Sin esto, un PF con tope real vería "sin
      // tope" durante el round-trip.
      .where((snap) => snap.exists || !snap.metadata.isFromCache)
      .map((snap) {
    final raw = snap.data()?[kPlanLimitsField];
    final limit = raw is Map ? raw['templates'] : null;
    return limit is int ? limit : null;
  }).distinct();
});

/// La cuota de plantillas del PF actual, cruzando el tope del servidor con
/// el conteo EN VIVO.
///
/// ## Por qué el `count` sale de [trainerTemplatesStreamProvider] filtrando
/// las archivadas, y no de `templateUsage.count`
///
/// `users/{uid}.templateUsage.count` (que escribe `recountTemplates`) viene
/// atrasado respecto de la escritura (docs/limite-plantillas-pf.md §2). El
/// PF ya lee el stream de sus plantillas para la grilla del Hub y la
/// sección de plantillas del móvil, y está fresco: cuenta lo que el PF ve
/// en pantalla en ESE instante. El servidor manda igual — esto es sólo el
/// gate de UX, la regla de Firestore hace cumplir el tope real contra el
/// contador denormalizado.
///
/// El stream trae TODAS las plantillas del PF, publicadas o no, archivadas
/// o no (docs/limite-plantillas-pf.md §2: "qué se limita" cuenta las
/// publicadas, no las archivadas) — acá se filtran las archivadas a mano
/// porque `watchTemplatesBy` no lo hace.
///
/// ## Qué hace el consumidor mientras esto es `AsyncLoading`
///
/// **Falla ABIERTO — no bloquea.** Misma resolución que
/// `customExerciseQuotaProvider`: sus call sites leen `.valueOrNull` y sólo
/// bloquean si el valor ya aterrizó y está lleno (`quota != null &&
/// quota.isAtOrOverLimit`); mientras carga, `valueOrNull` es `null` y el tap
/// pasa. El servidor manda de verdad: si el tap pasa y el tope sí corría, la
/// regla de Firestore rebota el create con `permission-denied`, y ESE
/// rebote —no este gate— es la red de verdad.
final templateQuotaProvider =
    Provider.autoDispose<AsyncValue<TemplateQuota>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) {
    return const AsyncValue.data((limit: null, count: 0));
  }

  final limitAsync = ref.watch(_templatePlanLimitProvider);
  final templatesAsync = ref.watch(trainerTemplatesStreamProvider(uid));

  if (limitAsync.hasError) {
    return AsyncValue.error(limitAsync.error!, limitAsync.stackTrace!);
  }
  if (templatesAsync.hasError) {
    return AsyncValue.error(
      templatesAsync.error!,
      templatesAsync.stackTrace!,
    );
  }

  // Las DOS fuentes tienen que haber CONTESTADO. Una que todavía carga no es
  // una que dijo "no hay tope" — ver el dartdoc de arriba.
  if (!limitAsync.hasValue || !templatesAsync.hasValue) {
    return const AsyncValue.loading();
  }

  final count = templatesAsync.value!
      .where((r) => r.status != RoutineStatus.archived)
      .length;

  return AsyncValue.data((limit: limitAsync.value, count: count));
});
