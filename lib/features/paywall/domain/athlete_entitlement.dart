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
/// **Tres, y el número lo fija el propio catálogo.** Las tres plantillas que
/// el alumno free puede seguir gratis —`ppl-beginner`, `full-body-3day`,
/// `calistenia-beginner` (`docs/video-catalog-audit/improved-templates.json`)—
/// tienen 3 días. Con el tope en 2, la app le mostraba esas tres como el
/// programa que debería hacer y después no lo dejaba armarse una igual. Esa
/// incoherencia no era cosmética: era la fuente del `permission-denied` al
/// guardar, porque `firestore.rules` mide la forma del documento RESULTANTE.
///
/// Un full body 3x/semana es el programa de principiante estándar. Dejarlo
/// afuera del free no vendía periodización: vendía frustración.
///
/// **La palanca de conversión son las SEMANAS, no los días.**
/// [kFreeMaxRoutineWeeks] es lo que separa un programa de principiante de uno
/// periodizado, y ese es el corte que el producto cobra.
///
/// Efecto secundario deliberado y valioso: con el tope en 3, una rutina de 4
/// días que quedó de antes **tiene salida** — sacarle un día deja el
/// resultante en 3 y la regla lo acepta. Con el tope en 2 no había ninguna, y
/// por eso el mensaje de límite podía ofrecer un camino en vez de sólo una
/// negativa. Ver `RoutineEditorScreen._freePlanBlocksShape`.
///
/// El piso sigue siendo 2 y no 1 por un motivo que no cambió: con
/// `numDays == 1`, `nextPlanPosition` rompe — `rolledOver` es
/// `lastFinished.dayNumber >= numDays`, que da siempre `true` y quema una
/// semana por sesión terminada (`plan_advance.dart`, y
/// `docs/paywall-alumno-suelto.md` §3.2).
///
/// ⚠️  Este número vive DUPLICADO en `firestore.rules` (`freeMaxRoutineDays()`).
/// Si cambiás uno, cambiá el otro: el cliente muestra un tope y el servidor
/// aplica otro, y el rebote llega sin que ninguna pantalla lo anticipe.
///
/// NO aplica al catálogo del sistema: seguir una plantilla precargada se gatea
/// por nivel, no por días (§4.1.1 de la spec).
const int kFreeMaxRoutineDays = 3;

/// Rutinas PROPIAS que puede tener guardadas un alumno del plan free.
///
/// Tres y no dos: como palanca de conversión rinden lo mismo —el límite que
/// de verdad muerde es el de SEMANAS— y la de tres no se siente mezquina.
///
/// (La justificación original decía "nadie arma tres rutinas distintas de dos
/// días". Ese argumento se apoyaba en [kFreeMaxRoutineDays] valiendo 2 y dejó
/// de ser cierto cuando pasó a 3: con 3 días sí se arman rutinas propias
/// distintas. La conclusión no cambia, pero el motivo sí, y dejar el viejo
/// escrito haría que el próximo que lo lea razone sobre una premisa muerta.)
///
/// **No cuenta las plantillas del catálogo que el alumno sigue**: seguir no
/// copia (#963), así que no crea un doc `user-created` y no ocupa cupo. Un
/// free puede seguir las 3 de principiante Y tener sus 3 rutinas propias.
///
/// Igual que [kMaxOwnRoutines], esto es **client-side y evadible archivando**:
/// `listUserCreated` filtra `status == 'active'`, y las reglas de Firestore no
/// tienen agregación — no pueden contar documentos de una colección. Cerrarlo
/// de verdad exige un contador denormalizado escrito por una Cloud Function.
/// Se aceptó el agujero a conciencia: el límite que de verdad muerde es el de
/// días, y ese SÍ es verificable en la regla porque `days` es un campo del
/// mismo documento que se está escribiendo.
const int kFreeMaxOwnRoutines = 3;

/// Tope estructural de rutinas propias, para cualquiera — pague o no.
///
/// Preexistente (ADR-USR-02); acá sólo se le pone nombre, porque vivía como un
/// `10` suelto en el editor. NO es un límite de paywall: es el techo del
/// producto, y por eso quien lo toca ve el aviso de siempre y no la hoja de
/// plan pago.
const int kMaxOwnRoutines = 10;

/// Semanas máximas de una rutina PROPIA en el plan free.
///
/// Una semana significa: sin periodización. Los campos `weeklySets` y
/// `activeWeeks` son justamente lo que distingue un programa intermedio de uno
/// de principiante, y son la parte paga.
const int kFreeMaxRoutineWeeks = 1;
