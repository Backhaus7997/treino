import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../insights/domain/chart_period.dart';
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

/// El catálogo tiene DOS ejes de cobro, no uno, y confundirlos rompe promesas.
///
/// La spec les da filas separadas (`docs/paywall-alumno-suelto.md` §4):
///
/// | Seguir el catálogo — principiante (3)        | free: **sí** |
/// | Seguir el catálogo — intermedio/avanzado (4) | free: no     |
/// | Editar / personalizar una plantilla          | free: no     |
///
/// O sea que sobre la MISMA plantilla de principiante el alumno free puede
/// entrenarla tal cual y no puede copiarla. Un solo booleano no expresa eso, y
/// el intento de forzarlo produce exactamente la falla que estos providers
/// existen para evitar: la grilla no pinta candado sobre `ppl-beginner` (bien:
/// seguirla es gratis) mientras el detalle bloquea el botón de copiar (bien
/// también) — pero si los dos leyeran el MISMO provider, uno de los dos estaría
/// mintiendo.
///
/// Por eso son dos, con el mismo cuerpo y contratos distintos. Lo que se
/// mantiene de la versión anterior es la razón de ser: cada eje tiene UNA
/// fuente, para que dos pantallas del mismo eje no puedan discrepar.
///
/// ---
///
/// Eje 1 — SEGUIR. `true` cuando una plantilla con `isPremium` le queda
/// bloqueada al alumno actual.
///
/// **Se combina con el campo de la plantilla, no lo reemplaza:**
/// `routine.isPremium && ref.watch(catalogLockActiveProvider)`.
///
/// Consumidores: el chip de la grilla (`plantillas_tab.dart`), el botón de
/// seguir y la acción de EMPEZAR (`routine_detail_screen.dart`). Los tres
/// cruzan `isPremium` porque los tres hablan de "entrenar ESTA plantilla".
final catalogLockActiveProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(athletePaywallEnabledProvider)) return false;
  return ref.watch(athleteEntitlementProvider).gatesFreeLimits;
});

/// Eje 2 — PERSONALIZAR. `true` cuando copiar una plantilla del catálogo para
/// editarla le queda bloqueado al alumno actual.
///
/// **NO se cruza con `isPremium`, y eso es el punto.** Personalizar cualquier
/// plantilla del catálogo es del plan pago, incluidas las tres de principiante
/// que seguir sí es gratis.
///
/// **Es política pura, y desde que [kFreeMaxRoutineDays] pasó a 3 eso es lo
/// único que la sostiene.** Antes había además un motivo de forma: las tres
/// plantillas gratis tienen 3 días y el tope era 2, así que copiar cualquiera
/// terminaba sí o sí en un `permission-denied` al guardar. Ese motivo ya no
/// existe — una copia de 3 días hoy entra en la forma free.
///
/// El gate SIGUE, porque la spec le da fila propia a "Editar / personalizar
/// una plantilla del catálogo" (`docs/paywall-alumno-suelto.md` §4) con
/// independencia de cuántos días tenga. Pero ahora frena por lo que el
/// producto decidió cobrar, no por una aritmética que se rompía sola. Si
/// mañana el producto abre personalizar, este provider se apaga y no queda
/// ninguna deuda de forma escondida atrás.
final customizeLockActiveProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(athletePaywallEnabledProvider)) return false;
  return ref.watch(athleteEntitlementProvider).gatesFreeLimits;
});

/// Los períodos de gráfico que son del plan pago.
///
/// El corte es "hasta un mes" gratis. `month` entra en free aunque sea
/// calendario: son 31 días como mucho, y sacarlo dejaría al free sin la vista
/// que la mayoría usa para mirar el mes en curso.
///
/// Ojo con el nombre: NO es "all-time vs 3 meses" como decía la spec §4.2. El
/// historial de sesiones está acotado a `kSessionHistoryFetchLimit` (365), así
/// que el techo real —y el máximo que se puede ofrecer sin mentir— es un año.
const Set<ChartPeriod> kPaidChartPeriods = {
  ChartPeriod.last3m,
  ChartPeriod.last1y,
};

/// Los períodos de gráfico bloqueados para el alumno actual. Vacío si no hay
/// nada bloqueado.
///
/// Una sola fuente para las cinco pantallas del alumno que muestran el
/// selector, por el mismo motivo que [catalogLockActiveProvider]: si una pinta
/// candado y otra deja pasar, el alumno ve una promesa rota.
///
/// **Las pantallas del PF no lo consultan, y es deliberado.** El entrenador ve
/// el historial completo de su alumno siempre: el paywall del alumno no puede
/// recortarle a su PF lo que ve de él. Por eso el gate se decide en el CALL
/// SITE y no adentro de `ChartPeriodSelector`, que es un widget compartido
/// entre las dos superficies.
final lockedChartPeriodsProvider =
    Provider.autoDispose<Set<ChartPeriod>>((ref) {
  if (!ref.watch(athletePaywallEnabledProvider)) return const {};
  if (!ref.watch(athleteEntitlementProvider).gatesFreeLimits) return const {};
  return kPaidChartPeriods;
});

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
