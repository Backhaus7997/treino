import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'subscription_tier.dart';

/// Lo que el servidor dejó publicado del tope de alumnos del PF en
/// `users/{uid}.planLimits` (`athletes`, `athletesHasta`, `athletesDespues`;
/// `resolveAthleteLimits` en `functions/src/subscriptions/trainer-plan-limits.ts`).
///
/// ## Por qué el cliente lo lee y no lo calcula
///
/// El tope REAL no se ve desde `subscription`: el servidor trata `pending` y
/// `paused` como Free, y el piso prepago (`prepaidTier`/`prepaidUntil`,
/// `conPisoPrepago` en `effective-limit.ts`) puede sostener un plan que la
/// suscripción actual ya no tiene. `VigenciaDelPlan` espeja sólo la baja. En
/// vez de sumar una segunda matriz en Dart —la que se desincroniza—, el
/// servidor publica el número que él mismo hace cumplir, y acá se lee.
///
/// ## Tres estados que NO se pueden confundir
///
/// - [TopeNoPublicado]: la clave `athletes` NO está (el PF nunca pasó por un
///   sync desde que existe, o el doc quedó degradado) o no se entiende. Es
///   «el servidor todavía no lo dijo»: el cliente cae a su cálculo de siempre.
/// - [TopePublicado] con `limite == null`: el servidor dijo «SIN TOPE» (Plan 3
///   o un piso prepago de Plan 3).
/// - [TopePublicado] con `limite == n`: el tope es `n`.
///
/// Por eso es una jerarquía sellada y no un `int?`: con un `int?`, «ausente» y
/// «sin tope» colapsan en `null`, y un PF que no sincronizó pasaría por
/// ilimitado.
///
/// Se lee crudo del doc y no se modela en `UserProfile`, por el mismo motivo
/// que `kPlanLimitsField` en `custom_exercise_quota_provider.dart`: es
/// CF-write-only y está pineado en `firestore.rules`.
sealed class TopeDeAlumnosPublicado {
  const TopeDeAlumnosPublicado();

  /// Lee el mapa `planLimits` del doc de un PF. [planLimits] es lo que haya en
  /// `data['planLimits']`: `null`, otro tipo, o el mapa.
  ///
  /// Devuelve [TopeNoPublicado] cuando no hay nada que afirmar:
  ///
  /// - `planLimits` no es un mapa, o no trae la clave `athletes`. Ausente no es
  ///   `null`: `containsKey` y no `map['athletes'] == null`.
  /// - `athletes` no es ni entero ni `null` (otro tipo, o un número con
  ///   decimales: los topes son enteros).
  /// - Hay un cambio programado (`athletesHasta` es un `Timestamp`) pero
  ///   `athletesDespues` no viene o no se entiende. El contrato publica las
  ///   tres claves juntas, así que eso es un doc roto, y adivinar el tope
  ///   posterior sería inventarlo.
  ///
  /// Un `athletesHasta` que NO es `Timestamp` se toma como «sin cambio
  /// programado»: `athletes` sigue siendo un dato bueno.
  factory TopeDeAlumnosPublicado.leer(Object? planLimits) {
    if (planLimits is! Map || !planLimits.containsKey('athletes')) {
      return const TopeNoPublicado();
    }
    final athletes = planLimits['athletes'];
    final limite = _comoTope(athletes);
    if (athletes != null && limite == null) return const TopeNoPublicado();

    final hasta = planLimits['athletesHasta'];
    if (hasta is! Timestamp) {
      return TopePublicado(limite: limite);
    }

    // `athletesDespues: null` CON `athletesHasta` es «sin tope» (ver el
    // dartdoc del servidor): se mira SIEMPRE `athletesHasta` primero.
    if (!planLimits.containsKey('athletesDespues')) {
      return const TopeNoPublicado();
    }
    final despuesCrudo = planLimits['athletesDespues'];
    final despues = _comoTope(despuesCrudo);
    if (despuesCrudo != null && despues == null) {
      return const TopeNoPublicado();
    }
    return TopePublicado(
      limite: limite,
      hasta: hasta.toDate().toUtc(),
      despues: despues,
    );
  }
}

/// El servidor no publicó un tope (o no se entiende): hay que calcularlo
/// del lado del cliente, como antes de que existiera `planLimits.athletes`.
final class TopeNoPublicado extends TopeDeAlumnosPublicado {
  const TopeNoPublicado();
}

/// El tope que el servidor publicó, con su próximo cambio por reloj.
final class TopePublicado extends TopeDeAlumnosPublicado {
  const TopePublicado({required this.limite, this.hasta, this.despues});

  /// El tope vigente al momento de la escritura, en unidades de PESO (activo 1,
  /// pausado 0.5). `null` = SIN TOPE.
  final int? limite;

  /// Desde cuándo rige [despues]. `null` = el servidor no tiene ningún cambio
  /// programado.
  final DateTime? hasta;

  /// El tope desde [hasta] (`null` = SIN TOPE). Sólo significa algo con [hasta]
  /// no nulo.
  final int? despues;

  /// El tope que rige en [ahora]: [despues] desde [hasta] inclusive (el
  /// servidor evalúa el cambio con `nowMs < borde` estricto, así que EN el
  /// borde ya rige el nuevo), y [limite] antes. `null` = sin tope.
  int? vigenteEn(DateTime ahora) {
    final borde = hasta;
    if (borde != null && !ahora.isBefore(borde)) return despues;
    return limite;
  }

  /// El borde que todavía no pasó en [ahora], o `null` si no queda ninguno por
  /// delante. Lo que espera el provider para releer el tope.
  DateTime? proximoCambioDesde(DateTime ahora) {
    final borde = hasta;
    return borde != null && ahora.isBefore(borde) ? borde : null;
  }

  @override
  bool operator ==(Object other) =>
      other is TopePublicado &&
      other.limite == limite &&
      other.hasta == hasta &&
      other.despues == despues;

  @override
  int get hashCode => Object.hash(limite, hasta, despues);
}

/// Un tope de la forma que escribe el servidor: entero, o `null`. Lo demás
/// (texto, decimales) devuelve `null` y el llamador lo distingue del `null`
/// legítimo mirando el valor crudo.
int? _comoTope(Object? crudo) {
  if (crudo is int) return crudo;
  if (crudo is num && crudo.isFinite && crudo == crudo.truncateToDouble()) {
    return crudo.toInt();
  }
  return null;
}

/// El tier cuya tabla ([kTierWeightLimits]) tiene exactamente [tope] de cupo, o
/// `null` si ninguno (un tope que la tabla del cliente no conoce).
///
/// Sirve para ponerle nombre a un tope que vino del servidor: el número
/// manda, y la etiqueta tiene que decir lo mismo que el número. La tabla es
/// inyectiva (2, 7, 15, sin tope), así que hay a lo sumo un tier.
SubscriptionTier? tierConTope(int? tope) {
  for (final e in kTierWeightLimits.entries) {
    if (e.value == tope) return e.key;
  }
  return null;
}
