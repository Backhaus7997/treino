import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart'
    show kPlanLimitsField;
import 'package:treino/features/coach/application/vigencia_del_plan_provider.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/tope_de_alumnos.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

/// El tope de alumnos del PF logueado, listo para mostrar.
///
/// [tope] es el cupo en unidades de PESO (activo 1, pausado 0.5); `null` = SIN
/// TOPE. [tier] es el plan cuyo nombre acompaña al número, o `null` si no hay
/// ninguno que diga lo mismo que el número.
///
/// Es un record, no una clase: compara por valor, así que quien lo mira no se
/// reconstruye cada vez que el provider se re-evalúa con el mismo resultado
/// (con un borde por delante, cada minuto).
typedef LimiteDeAlumnos = ({int? tope, SubscriptionTier? tier});

/// Lo que el servidor publicó en `users/{uid}.planLimits` (`athletes`,
/// `athletesHasta`, `athletesDespues`) para el PF actual.
///
/// Se lee del doc crudo y no de `userProfileProvider`: `planLimits` es
/// CF-write-only y no vive en `UserProfile` (ver [kPlanLimitsField]). Misma
/// guarda de caché fría que `_customExercisePlanLimitProvider`: con la caché
/// local fría la PRIMERA snapshot llega con `exists == false` antes de que el
/// servidor confirme, y sin la guarda un PF con tope publicado pasaría por
/// «no publicado» durante el round-trip.
///
/// Sin uid, o con un doc sin `planLimits`, emite [TopeNoPublicado].
final _topePublicadoProvider =
    StreamProvider.autoDispose<TopeDeAlumnosPublicado>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) {
    return Stream.value(const TopeNoPublicado());
  }

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .snapshots()
      .where((snap) => snap.exists || !snap.metadata.isFromCache)
      .map(
        (snap) => TopeDeAlumnosPublicado.leer(snap.data()?[kPlanLimitsField]),
      )
      .distinct();
});

/// El tope de alumnos que rige para el PF logueado: el que el servidor HACE
/// CUMPLIR, y sólo si todavía no lo publicó, el que calcula el cliente.
///
/// ## Dos fuentes, una prioridad
///
/// 1. **`planLimits.athletes`** (ver [TopeDeAlumnosPublicado]): el número sale
///    del servidor tal cual. Resuelve lo que el cliente no ve —`pending` y
///    `paused` valen Free, el piso prepago sostiene un plan que la
///    suscripción ya no tiene— sin una segunda matriz en Dart. El tier que se
///    nombra se deduce DEL NÚMERO ([tierConTope]), no del doc: un PF `paused`
///    con Plan 2 en el doc y tope 2 se muestra como «Plan Free», no «2 DE 2 ·
///    PLAN 2». Si el número no coincide con ningún tier de la tabla, [tier]
///    es `null` y el medidor no nombra plan en vez de nombrar uno que no
///    corresponde.
/// 2. **El cálculo de siempre** (`vigenciaDelPlanProvider` + la tabla de
///    tiers), cuando la clave no está: el PF nunca pasó por un sync desde que
///    el servidor publica el tope, o su doc está degradado. También mientras
///    el doc todavía carga, si falla la lectura, o si lo publicado no se
///    entiende (ver [TopeDeAlumnosPublicado.leer]): el medidor no se puede
///    quedar mudo, y esa era su respuesta antes de que existiera la clave.
///    Ausente NO es «sin tope».
///
/// ## El cambio por reloj
///
/// El servidor no reescribe el doc cuando un `cancelled` vence o un piso
/// prepago se acaba (ningún trigger lo ve; lo corrige el barrido de las
/// 04:00), pero publica CUÁNDO va a pasar (`athletesHasta`) y a qué tope
/// (`athletesDespues`). Este provider espera hasta ese instante y se
/// invalida solo, igual que [vigenciaDelPlanProvider]: re-armado de a lo
/// sumo un minuto ([esperaHasta], por la web y por el timer tardío) y sin
/// emisión del perfil. Pasado el borde usa `athletesDespues`, aunque el doc
/// siga con el valor viejo.
///
/// ## Lo que NO cubre
///
/// - El servidor publica SÓLO el primer cambio por reloj
///   (`proximoCambioDeLimite` en `effective-limit.ts`). Si después de ese
///   borde viene otro (un plan cancelado que vence y, más tarde, el fin de un
///   piso prepago), este provider se queda con `athletesDespues` hasta que el
///   servidor vuelva a publicar: el próximo sync o, a más tardar, el barrido
///   de las 04:00.
/// - Con la clave presente, el número se mueve con el doc: un cambio de plan
///   llega al medidor cuando la CF de sincronización termina de escribir, no
///   en el instante de la compra o la baja.
///
/// `autoDispose` y SIN `keepAlive`, por el mismo motivo que
/// [vigenciaDelPlanProvider]: el timer se cancela en `onDispose`.
final limiteDeAlumnosProvider = Provider.autoDispose<LimiteDeAlumnos>((ref) {
  final publicado =
      ref.watch(_topePublicadoProvider).valueOrNull ?? const TopeNoPublicado();

  if (publicado is TopePublicado) {
    // El MISMO instante para decidir y para medir la espera.
    final ahora = AppClock.now();
    final cambio = publicado.proximoCambioDesde(ahora);
    if (cambio != null) {
      // Un milisegundo después del borde, no en el borde: el `Timer` de web
      // cuenta en milisegundos (`inMilliseconds`), y una espera que se trunca
      // a 0 antes del borde dispararía, vería que todavía no llegó y
      // reagendaría en un loop corto. Mismo criterio que `proximoCambio` en
      // `plan_vigencia.dart`.
      final timer = Timer(
        esperaHasta(
          cambio.add(const Duration(milliseconds: 1)),
          ahora: ahora,
        ),
        ref.invalidateSelf,
      );
      ref.onDispose(timer.cancel);
    }
    final tope = publicado.vigenteEn(ahora);
    return (tope: tope, tier: tierConTope(tope));
  }

  // Sin tope publicado: el cálculo del cliente, SIN cambios respecto de cuando
  // el medidor lo hacía en su build. Se mira recién acá para que el timer de
  // la vigencia sólo exista cuando hace falta.
  final (tier, vencida) = ref.watch(
    vigenciaDelPlanProvider.select((v) => (v.tierEfectivo, v.vencida)),
  );
  final weightLimitDelDoc = ref.watch(
    userProfileProvider.select((p) => p.valueOrNull?.subscription?.weightLimit),
  );
  // El TIER decide si hay tope, NO el `weightLimit` del doc. El servidor no
  // escribe ese campo (ver `TrainerSubscription.weightLimit`), pero si un doc
  // de un plan3 lo trajera, leerlo de ahí volvería a meter un denominador en
  // el plan ilimitado. Con la baja vencida, además, un `weightLimit` en el doc
  // sería el del plan viejo: el tope sale de la tabla del tier efectivo.
  final tope = tier.isUnlimited
      ? null
      : vencida
          ? tier.weightLimit
          : (weightLimitDelDoc ?? tier.weightLimit);
  return (tope: tope, tier: tier);
});
