import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/custom_exercise_providers.dart'
    show customExercisesForTrainerStreamProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;

/// Cuota de ejercicios propios del PF actual (docs/limite-ejercicios-pf.md,
/// PR3), ya resuelta para el gate.
///
/// `limit == null` ⇒ sin tope (Plan 3, interruptor apagado, o campo todavía
/// ausente). El tipo obliga a contemplar el caso en cada call site, mismo
/// motivo que [kTierCustomExerciseLimits] en `subscription_tier.dart`.
typedef CustomExerciseQuota = ({int? limit, int count});

extension CustomExerciseQuotaX on CustomExerciseQuota {
  /// `true` cuando crear uno más está bloqueado: E6 dice que el borde es
  /// `count < limit` al crear, así que `count == limit` YA bloquea.
  bool get isAtOrOverLimit => limit != null && count >= limit!;
}

/// El campo que la CF `recountCustomExercises`/`syncTrainerEntitlements`
/// escribe en `users/{uid}.planLimits.customExercises`
/// (docs/limite-ejercicios-pf.md §2). `number | null`, `null` o ausente =
/// sin tope.
///
/// Se lee crudo y no se modela en `UserProfile`, por el MISMO motivo que
/// `kChatMediaUsageField`/`kCustomExerciseVideoUsageField` en
/// `athlete_entitlement_provider.dart`: es CF-write-only y está pineado en
/// `firestore.rules`. Si viviera en el modelo que el cliente también
/// escribe, el primer `update` que mande el objeto entero se comería una
/// denegación por un campo que nadie quiso tocar.
const String kPlanLimitsField = 'planLimits';

/// El tope vigente de `users/{uid}.planLimits.customExercises`, o `null` si
/// no hay tope (ausente, `null`, o el campo con otra forma).
///
/// Privado: nadie fuera de este archivo debería razonar sobre el read crudo
/// — para eso está [customExerciseQuotaProvider], que ya lo cruzó con el
/// conteo.
final _customExercisePlanLimitProvider = StreamProvider.autoDispose<int?>(
  (ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null || uid.isEmpty) return Stream.value(null);

    return ref
        .watch(firestoreProvider)
        .collection('users')
        .doc(uid)
        .snapshots()
        // Misma guarda que `chatMediaQuotaProvider` y
        // `_athleteSubscriptionStatusProvider` en
        // `athlete_entitlement_provider.dart`, y por el mismo motivo: con la
        // cache local fría la PRIMERA snapshot llega con `exists == false`
        // antes de que el servidor confirme. Sin esto, un PF con tope real
        // vería "sin tope" durante el round-trip.
        .where((snap) => snap.exists || !snap.metadata.isFromCache)
        .map((snap) {
      final raw = snap.data()?[kPlanLimitsField];
      final limit = raw is Map ? raw['customExercises'] : null;
      return limit is int ? limit : null;
    }).distinct();
  },
);

/// El campo del contador que escribe `recountCustomExercises`:
/// `users/{uid}.customExerciseUsage.count` (docs/limite-ejercicios-pf.md §2).
const String kCustomExerciseUsageField = 'customExerciseUsage';

/// Tope y conteo de ejercicios propios leídos SÓLO de `users/{uid}`, para
/// superficies que muestran el uso y no gatean nada (la línea de Facturación
/// del Coach Hub).
///
/// ## Por qué no [customExerciseQuotaProvider]
///
/// Aquél saca el `count` de [customExercisesForTrainerStreamProvider], que
/// baja la colección ENTERA: tiene sentido en «Mis ejercicios» y en los
/// pickers, que ya la leen para listarla, pero en Facturación serían hasta
/// 120 lecturas —o sin techo en Plan 3— por abrir la pestaña, sólo para un
/// `.length`. Acá alcanza el contador denormalizado: viene ~1 s atrasado, y
/// para mostrar el uso eso no importa.
///
/// ## `null` = «no sé», nunca «cero»
///
/// Si `customExerciseUsage.count` no existe todavía (functions sin deployar,
/// o un PF que el barrido todavía no recontó) devuelve `null` y la superficie
/// se oculta. Mostrar «0» afirmaría un conteo que nadie hizo.
final customExerciseUsageSummaryProvider =
    StreamProvider.autoDispose<CustomExerciseQuota?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .snapshots()
      // Misma guarda de caché fría que [_customExercisePlanLimitProvider].
      .where((snap) => snap.exists || !snap.metadata.isFromCache)
      .map((snap) {
    final data = snap.data();
    final usage = data?[kCustomExerciseUsageField];
    final count = usage is Map ? usage['count'] : null;
    if (count is! int) return null;
    final limits = data?[kPlanLimitsField];
    final limit = limits is Map ? limits['customExercises'] : null;
    return (limit: limit is int ? limit : null, count: count);
  }).distinct();
});

/// La cuota de ejercicios propios del PF actual, cruzando el tope del
/// servidor con el conteo EN VIVO.
///
/// ## Por qué el `count` sale del stream de `customExercises` y no del
/// contador denormalizado
///
/// `users/{uid}.customExerciseUsage.count` (que escribe
/// `recountCustomExercises`) viene atrasado ~1 s respecto de la escritura
/// (docs/limite-ejercicios-pf.md §6). El stream de
/// [customExercisesForTrainerStreamProvider] ya se lee entero para "Mis
/// ejercicios" y los pickers, y está fresco: cuenta lo que el PF ve en
/// pantalla en ESE instante. El servidor manda igual — esto es sólo el gate
/// de UX, la regla de Firestore hace cumplir el tope real contra el
/// contador denormalizado.
///
/// ## Por qué `Provider<AsyncValue<...>>` y no `StreamProvider<...?>` a
/// secas
///
/// A diferencia de `chatMediaQuotaProvider` (que lee tope y conteo del
/// MISMO documento, en un solo snapshot), acá el tope y el conteo salen de
/// DOS fuentes independientes —el doc de `users/{uid}` y la colección
/// `customExercises`— que pueden resolver en instantes distintos. Combinarlas
/// en un solo `Stream` a mano (sin rxdart en el repo, ver
/// `public_profile_providers.dart`) es más frágil que combinar los DOS
/// `AsyncValue` ya resueltos por Riverpod, que es el mismo patrón que usa
/// `athleteEntitlementProvider` para cruzar vínculo + suscripción: se
/// necesitan las DOS fuentes con `hasValue == true` para afirmar un dato: una
/// que todavía carga (o que falló) no es una que dijo "no hay tope".
///
/// ## Qué hace el consumidor mientras esto es `AsyncLoading`
///
/// **Falla ABIERTO — no bloquea.** Es la MISMA resolución que
/// `chatMediaQuotaProvider`: sus call sites leen `.valueOrNull` y sólo
/// bloquean si el valor ya aterrizó y está lleno (`quota != null &&
/// quota.isFull`); mientras carga, `valueOrNull` es `null` y el tap pasa. La
/// alternativa —fallar cerrado— le mostraría "llegaste al tope" a un PF sin
/// tope mientras su perfil carga, y el contrato del modelo de datos (§2) es
/// explícito: "ausente = sin tope". Bloquear sobre un dato que todavía no
/// se sabe sería inventar un tope que el servidor no afirmó. El servidor
/// manda de verdad: si el tap pasa y el tope sí corría, la regla de
/// Firestore rebota el create con `permission-denied`, y ESE rebote —no
/// este gate— es la red de verdad (ver "El rebote del servidor" en
/// docs/limite-ejercicios-pf.md PR3).
final customExerciseQuotaProvider =
    Provider.autoDispose<AsyncValue<CustomExerciseQuota>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) {
    return const AsyncValue.data((limit: null, count: 0));
  }

  final limitAsync = ref.watch(_customExercisePlanLimitProvider);
  final exercisesAsync =
      ref.watch(customExercisesForTrainerStreamProvider(uid));

  if (limitAsync.hasError) {
    return AsyncValue.error(limitAsync.error!, limitAsync.stackTrace!);
  }
  if (exercisesAsync.hasError) {
    return AsyncValue.error(
      exercisesAsync.error!,
      exercisesAsync.stackTrace!,
    );
  }

  // Las DOS fuentes tienen que haber CONTESTADO. Una que todavía carga no es
  // una que dijo "no hay tope" — ver el dartdoc de arriba.
  if (!limitAsync.hasValue || !exercisesAsync.hasValue) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data(
    (limit: limitAsync.value, count: exercisesAsync.value!.length),
  );
});
