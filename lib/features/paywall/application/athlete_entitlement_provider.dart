import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show currentAthleteLinkProvider;
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../domain/athlete_entitlement.dart';

/// Si el paywall del alumno muerde. Default: [kAthletePaywallEnabled].
///
/// Existe como provider y no se lee la constante directo por dos motivos: los
/// tests pueden overridearlo para ejercitar el camino ENCENDIDO (si no, el
/// gate se shipearía con su rama principal sin cubrir), y el día que se quiera
/// encender por cohorte o por remote config, el punto de cambio es éste y no
/// cada call site.
final athletePaywallEnabledProvider =
    Provider<bool>((ref) => kAthletePaywallEnabled);

/// La clave del mapa de suscripción DEL ALUMNO dentro de `users/{uid}`.
///
/// Deliberadamente distinta de `subscription`, que es la del PF
/// (`TrainerSubscription`: tiers de cupo, `weightLimit`, carga ponderada). Son
/// dos productos con precios y entitlements distintos; meterlos en el mismo
/// campo obliga a desambiguar por `role` en cada lectura y en cada regla.
///
/// **Todavía no la escribe nadie.** El writer es el webhook de Mercado Pago
/// del alumno, hermano del del PF (`functions/src/subscriptions/**`, que hoy
/// está siendo cableado por otra línea de trabajo). Hasta que exista, este
/// campo está ausente en todos los docs — y ausente significa `free`, que es
/// exactamente el default correcto y no necesita backfill, igual que
/// `subscription` del PF.
const String kAthleteSubscriptionField = 'athleteSubscription';

/// Los `status` del mapa que otorgan derecho.
///
/// `grace` entra a propósito: es el período en que el cobro falló pero todavía
/// no se cortó el servicio. Cortarle las funciones a alguien mientras se
/// reintenta la tarjeta es la peor forma de pedirle que actualice el medio de
/// pago. Mismo criterio que usa el paywall del PF con su propio `graceUntil`.
const Set<String> kEntitlingSubscriptionStatuses = {'active', 'grace'};

/// Derecho del alumno actual sobre las funciones pagas, resuelto contra las
/// DOS fuentes que lo otorgan.
///
/// ## Por qué son dos fuentes
///
/// Un alumno está habilitado si **paga** (su `athleteSubscription`) **o** si
/// está **vinculado a un PF activo** — porque ese PF ya paga por su cupo, y la
/// spec es explícita en que el alumno vinculado no paga nunca
/// (`docs/paywall-alumno-suelto.md` §2, con seis plataformas de la categoría
/// declarándolo textualmente). Mirar sólo la suscripción le cobraría a alguien
/// que su PF ya pagó.
///
/// ## Por qué un read crudo y no `UserProfile.athleteSubscription`
///
/// Mismo motivo que `blockedAthletesProvider`: el campo es CF-write-only. Si
/// vive en el modelo que el cliente TAMBIÉN escribe, el primer `update` que
/// mande el objeto entero se come una denegación por un campo que nadie quiso
/// tocar. Se lee crudo y no se modela.
///
/// ## Por qué `Provider` sincrónico y no `FutureProvider`
///
/// Los call sites son handlers de tap (`_addDay`, `_addWeek` del editor): no
/// pueden esperar. Este provider colapsa los dos `AsyncValue` a un enum que se
/// lee con un `ref.read` y ya. Mismo patrón que `weeklyStreakTargetProvider`.
///
/// ## Qué devuelve mientras carga, y por qué importa
///
/// [AthleteEntitlement.unknown] — que **no gatea**. Ver el docstring de
/// `gatesFreeLimits`: fallar cerrado acá le bloquea el botón a alguien que
/// paga, y el servidor rebota igual la escritura si no corresponde.
final athleteEntitlementProvider = Provider.autoDispose<AthleteEntitlement>(
  (ref) {
    // Fuente 1 — vínculo activo con un PF. Si lo tiene, no hay nada más que
    // preguntar: su PF ya paga por él.
    final link = ref.watch(currentAthleteLinkProvider);
    if (link.hasValue && link.valueOrNull != null) {
      return AthleteEntitlement.entitled;
    }

    // Fuente 2 — su propia suscripción.
    final sub = ref.watch(_athleteSubscriptionStatusProvider);
    if (sub.hasValue &&
        sub.valueOrNull != null &&
        kEntitlingSubscriptionStatuses.contains(sub.valueOrNull)) {
      return AthleteEntitlement.entitled;
    }

    // A esta altura ninguna de las dos OTORGA. Para poder afirmar `free` las
    // dos tienen que haber CONTESTADO: una que todavía carga (o que falló) no
    // es una que dijo que no.
    final linkResolved = link.hasValue;
    final subResolved = sub.hasValue;
    if (linkResolved && subResolved) return AthleteEntitlement.free;

    return AthleteEntitlement.unknown;
  },
);

/// El `status` crudo de `users/{uid}.athleteSubscription`, o `null` si el mapa
/// no está.
///
/// Privado: nadie fuera de este archivo debería razonar sobre el string suelto
/// — para eso está [athleteEntitlementProvider], que ya cruzó las dos fuentes.
final _athleteSubscriptionStatusProvider =
    StreamProvider.autoDispose<String?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .snapshots()
      // Misma guarda que `UserRepository.watch` y `blockedAthletesProvider`,
      // por el mismo motivo: con la cache local fría la PRIMERA snapshot llega
      // con `exists == false` antes de que el servidor confirme. Sin esto, un
      // alumno que paga y abre la app ve `free` durante el round-trip — y con
      // él, el sheet de límite en la cara.
      .where((snap) => snap.exists || !snap.metadata.isFromCache)
      .map((snap) {
    final raw = snap.data()?[kAthleteSubscriptionField];
    if (raw is! Map) return null;
    final status = raw['status'];
    return status is String ? status : null;
  }).distinct();
});
