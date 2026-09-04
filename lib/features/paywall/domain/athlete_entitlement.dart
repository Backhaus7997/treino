/// Derecho del ALUMNO sobre las funciones pagas de TREINO.
///
/// Es el paywall del alumno suelto (`docs/paywall-alumno-suelto.md`), distinto
/// del paywall del PF: aquel limita CUPO DE ALUMNOS y vive en
/// `users/{uid}.subscription` (`TrainerSubscription`); éste limita la FORMA de
/// las rutinas que el alumno se arma, y su fuente es
/// `users/{uid}.athleteSubscription`.
library;

/// El estado de derecho del alumno, resuelto por
/// `athleteEntitlementProvider`.
///
/// Son TRES estados y no un `bool`, por el mismo motivo por el que
/// `BlockedAthletes` distingue «publicado y vacío» de «sin publicar»: mientras
/// el read no aterrizó NO SE SABE, y colapsar eso en «free» le corta la mano a
/// alguien que está pagando.
enum AthleteEntitlement {
  /// Paga, o está vinculado a un PF activo que ya paga por él. No se le gatea
  /// nada. Ver `docs/paywall-alumno-suelto.md` §2: el alumno vinculado no paga
  /// NUNCA — su PF ya paga por ese cupo.
  entitled,

  /// Confirmado sin derecho: los topes del plan free aplican.
  free,

  /// El read todavía no aterrizó, o falló.
  unknown;

  /// Si el gate del CLIENTE tiene que morder.
  ///
  /// `unknown` **no** gatea, y es una decisión deliberada. El enforcement real
  /// vive en `firestore.rules`; este gate es UX. Fallar CERRADO acá significa
  /// bloquearle el botón a un usuario que paga por un parpadeo de red o por
  /// una cache fría — mucho peor que dejar pasar un tap cuya escritura el
  /// servidor rebota igual. Client-side es UX; server-side es la ley.
  bool get gatesFreeLimits => this == AthleteEntitlement.free;
}

/// Interruptor maestro del paywall del alumno. **Apagado a propósito.**
///
/// El mecanismo entero (provider de entitlement, topes, gate en el editor,
/// hoja de límite) está construido y testeado, pero no muerde hasta que se
/// ponga en `true`.
///
/// Por qué: hoy NO existe forma de que un alumno pague. El checkout web del
/// alumno no está construido (`docs/paywall-alumno-suelto.md` §7.1: el hub web
/// manda a `/not-allowed` a todo el que no sea PF) y el webhook que escribiría
/// `athleteSubscription` tampoco. Con el gate encendido, **todos** los usuarios
/// serían `free` sin ninguna manera de destrabarse: le sacaríamos a los
/// testers la posibilidad de armar una rutina de 3 días a cambio de nada.
///
/// Encenderlo requiere, en este orden: (1) checkout web del alumno, (2)
/// webhook escribiendo `athleteSubscription`, (3) la regla de `firestore.rules`
/// que es el enforcement REAL — este flag sólo gobierna la UX del cliente.
const bool kAthletePaywallEnabled = false;

/// Días máximos de una rutina PROPIA en el plan free.
///
/// Dos, no uno: dos días es el mínimo que expresa un programa de principiante
/// real (un A/B). Con uno, `nextPlanPosition` además rompe — `rolledOver` es
/// `lastFinished.dayNumber >= numDays`, que con `numDays == 1` da siempre
/// `true` y quema una semana por sesión terminada
/// (`plan_advance.dart`, y `docs/paywall-alumno-suelto.md` §3.2).
///
/// NO aplica al catálogo del sistema: seguir una plantilla precargada se gatea
/// por nivel, no por días (§4.1.1 de la spec).
const int kFreeMaxRoutineDays = 2;

/// Semanas máximas de una rutina PROPIA en el plan free.
///
/// Una semana significa: sin periodización. Los campos `weeklySets` y
/// `activeWeeks` son justamente lo que distingue un programa intermedio de uno
/// de principiante, y son la parte paga.
const int kFreeMaxRoutineWeeks = 1;
