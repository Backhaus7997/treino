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

  /// Este estado, expresado como el tri-estado que comparten las DOS
  /// implementaciones del gate del catálogo — la de Dart y la de Swift.
  ///
  /// Es el puente hacia `catalogGateBlocks`, y existe porque el reloj de Apple
  /// no resuelve un `AthleteEntitlement`: lee
  /// `users/{uid}.athletePaywallEnforced` por REST, que puede estar en `true`,
  /// en `false`, o **ausente**. Los tres valores de este enum mapean uno a uno
  /// contra esos tres:
  ///
  /// | este enum  | `athletePaywallEnforced` | gatea |
  /// |------------|--------------------------|-------|
  /// | `entitled` | `false`                  | no    |
  /// | `free`     | `true`                   | sí    |
  /// | `unknown`  | **ausente** (`null`)     | no    |
  ///
  /// El `null` de `unknown` NO es una conveniencia de tipos: es lo que hace
  /// que "no se sabe" viaje como tal hasta la decisión, en vez de que cada
  /// plataforma elija su propio default y diverjan. Ver el dartdoc de
  /// `catalogGateBlocks`.
  bool? get paywallEnforced => switch (this) {
        AthleteEntitlement.entitled => false,
        AthleteEntitlement.free => true,
        AthleteEntitlement.unknown => null,
      };
}

/// Interruptor maestro del paywall del alumno. **Apagado a propósito.**
///
/// El mecanismo entero (provider de entitlement, topes, gate en el editor,
/// hoja de límite) está construido y testeado, pero no muerde hasta que se
/// ponga en `true`.
///
/// ─── Lo que ya NO es el motivo ───
///
/// Este dartdoc decía que el bloqueante era que no existía forma de pagar: ni
/// checkout, ni webhook. **Las dos cosas existen** desde el 2026-09-10, sólo
/// que por un camino distinto del que decía la spec — el alumno paga por IAP,
/// no por web, y el porqué está en `docs/paywall-alumno-suelto.md` §7.1.
///
///   • la compra: `athlete_checkout.dart` + `athlete_paywall_screen.dart`
///   • el webhook: `functions/src/subscriptions/rc/webhook.ts`
///
/// Lo que sigue valiendo del razonamiento viejo, y por eso no se borra: con el
/// gate encendido y sin forma de pagar, **todos** los usuarios serían `free`
/// sin ninguna manera de destrabarse. Esa sigue siendo la prueba a pasar antes
/// de tocar este valor.
///
/// ─── Lo que falta HOY ───
///
///   1. **La verificación en device del gate del reloj de Apple.** El código
///      está (`ios/TreinoWatch Watch App/CatalogGate*.swift`) pero se escribió
///      desde Windows: CI compila la función pura del contrato de conformidad
///      y nada más. El checklist está en `docs/paywall-watchos-plan.md` §5, y
///      el caso que más importa no es el obvio — es el CONTROL NEGATIVO: que
///      un free entrene una plantilla de principiante sin fricción.
///   2. **El candado del catálogo vive sólo acá, no en el servidor.**
///      `isPremium` aparece en `firestore.rules` únicamente dentro del bloque
///      de `sessions`; el CREATE de `/routines` no lo mira NUNCA. Copiar una
///      plantilla paga a rutina propia pasa el servidor si la copia entra en
///      `withinFreeRoutineShape`, y `hipertrofia-intermedio` —3 días, sin
///      `numWeeks`— entra exacto. No se arregla con una cláusula nueva: el
///      servidor no puede distinguir tres días copiados de tres días escritos
///      a mano, porque el payload es idéntico. Es una decisión de producto.
///   3. **Los tres carteles de steering** de la app móvil del PF, declarados
///      con fecha límite en `test/features/paywall/anti_steering_movil_test.dart`.
///
/// ─── Lo que SALIÓ de esta lista, y por qué ───
///
/// **El seed que apagaba el cobro del catálogo**, que estuvo acá y ya no está.
/// Cerrado el 2026-09-14 por `bef1b3b8`, que le sacó a
/// `scripts/seed_workout_catalog.js` la mitad que sembraba `/routines`. Hoy ese
/// script sólo siembra ejercicios, `--routines` y `--all` **cortan con un
/// error** en vez de destruir en silencio, y los alias `seed:routines` y
/// `seed:all` dejaron de existir. El que quedó —`seed:templates`— es dry-run
/// por default. Lo guarda `scripts/test/catalogo_una_sola_fuente.test.js`.
///
/// Verificado contra producción el 2026-09-15: las 4 plantillas pagas siguen
/// con `isPremium: true`. El bug nunca llegó a disparar.
///
/// ⚠️ Esta entrada existe porque el ítem se quedó acá **un día entero después
/// de estar resuelto**, y alguien arrancó a trabajarlo antes de verificar. En
/// este archivo eso cuesta más que en otros: `docs/paywall-alumno-suelto.md`
/// dice textualmente que «la lista al día está acá», o sea que es la fuente
/// autoritativa para decidir cuándo encender el paywall. **Una lista
/// autoritativa equivocada es peor que no tener lista.** Si cerrás un ítem,
/// moverlo a esta sección es parte de cerrarlo.
///
/// **El grandfathering**, que estuvo acá y ya no está. Eran dos problemas con
/// el mismo nombre y se cerraron por caminos distintos:
///
///   • Las **rutinas propias** fuera de tope: resuelto el 2026-09-11 con
///     `noCreceLaForma` en las reglas. El UPDATE pasa si la rutina resultante
///     no es más grande que la que ya había. Sin campo nuevo, sin fecha de
///     corte, sin migración.
///   • Las **plantillas pagas** que un alumno venía siguiendo: medido contra
///     producción el 2026-09-11, y la población es **CERO**. Ningún alumno
///     tiene una plantilla paga como rutina activa —que es literalmente lo que
///     significa seguirla: `_follow` escribe `users/{uid}.activeRoutineId` y
///     nada más—, y los 5 que alguna vez entrenaron una lo hicieron hace 31
///     días o más, tres de ellos una sola vez. Un mecanismo de exención sería
///     maquinaria permanente para nadie.
///
/// Y lo segundo no hace falta decidirlo hoy: las sesiones son un registro
/// permanente, así que el día de encender, la CF puede calcular el
/// grandfathering con los datos de ESE día. El dato no es perecedero — al
/// revés que `storeAccountToken`, que sí lo era y por eso se generó desde el
/// principio aunque no se use.
///
/// ─── Y EL ORDEN, QUE NO ES ARBITRARIO ───
///
/// **Primero el servidor, después el cliente**: encender la CF que escribe
/// `athletePaywallEnforced`, y recién ahí este flag. Al revés, el cliente gatea
/// cosas que el servidor todavía permite y el alumno ve un candado que no
/// corresponde.
///
/// Ojo con la otra mitad del cliente: `kAthletePaywallEnabled` **también existe
/// en Swift** (`ios/TreinoWatch Watch App/PaywallEntitlement.swift`), porque el
/// reloj de Apple no puede importar Dart. Hay un test que se pone rojo si los
/// dos no coinciden — `test/conformance/paywall_flag_parity_test.dart`.
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

/// Videos de ejercicio custom que puede tener subidos un alumno del plan free.
///
/// Tres, igual que [kFreeMaxOwnRoutines], y por consistencia de vocabulario: el
/// free tiene «tres de lo suyo». No hace falta otro número.
///
/// **La medición que lo justifica** (bucket `treino-dev`, 2026-09-10): en toda
/// la vida del proyecto se subieron **3** videos custom, de **un solo** usuario,
/// y ese usuario es un PF. Ningún alumno subió nunca uno. O sea que este tope
/// no le saca nada a nadie hoy — se pone ANTES de que haya costo que recortar,
/// que es la única vez que un tope no duele.
///
/// Por qué hace falta igual: sin tope de cantidad el peor caso es INFINITO.
/// 1.000 archivos de [kFreeMaxCustomExerciseVideoBytes] son 25 GB ≈ USD 0,65/mes
/// de storage — un cuarto del margen de un pagador quemado por UN abusador.
/// El tope por archivo acota el tamaño de cada pieza; sólo éste acota el total.
///
/// ⚠️  Este número NO se puede duplicar a mano en `storage.rules` como
/// `freeMaxRoutineDays()`: las reglas de Storage no tienen agregación y no
/// pueden contar objetos. El conteo lo denormaliza
/// `maintainCustomExerciseVideoQuota` en `users/{uid}.customExerciseVideoUsage`
/// y la regla lee esa conclusión — mismo patrón que `athletePaywallEnforced`.
/// El número vive en la regla Y acá; si cambiás uno, cambiá el otro.
const int kFreeMaxCustomExerciseVideos = 3;

/// Tamaño máximo de UN video de ejercicio custom en el plan free.
///
/// **25 MB, y el número sale de la medición, no del dedo.** El archivo más
/// grande que se subió alguna vez a `customExerciseVideos/` pesa **2,59 MB**, y
/// la mediana es **0,13 MB**. 25 MB es 10x el máximo real observado: headroom
/// de sobra para un tutorial de un minuto en 720p, y 4x menos que el cap
/// histórico de 100 MB, que era 39x el máximo observado — un techo decorativo.
///
/// **Es la palanca de costo más importante de las dos, y no es obvio por qué.**
/// Los videos se sirven por la URL `?alt=media&token=` que emite
/// `getDownloadURL()`: es GCS directo, sin CDN ni capa de cache adelante (ver
/// el bloque `customExerciseVideos` de `storage.rules` y `docs/security.md`
/// §3.1). Cada reproducción es egress facturado a USD 0,12/GB, contra USD
/// 0,026/GB-mes de almacenamiento — **4,6x el precio del GB guardado un mes
/// entero, cada vez que alguien le da play**. El tope por archivo es lineal en
/// las DOS líneas de costo; el de cantidad sólo en la de almacenamiento.
///
/// A [kMaxCustomExerciseVideoBytes] (el techo del PF) no se lo toca: el PF vive
/// de su videoteca y su economía es otra — paga por cupo de alumnos, no por
/// esto.
const int kFreeMaxCustomExerciseVideoBytes = 25 * 1024 * 1024;

/// Tamaño máximo de UN video de ejercicio custom, para cualquiera.
///
/// Preexistente: es el `100 * 1024 * 1024` que ya vivía suelto en
/// `storage.rules`; acá sólo se le pone nombre. NO es un límite de paywall, es
/// el techo del producto — igual que [kMaxOwnRoutines] frente a
/// [kFreeMaxOwnRoutines].
const int kMaxCustomExerciseVideoBytes = 100 * 1024 * 1024;

/// Videos de ejercicio custom que puede tener CUALQUIERA — pague o no, PF o
/// alumno.
///
/// Techo anti-abuso, no palanca de conversión. 50 × 100 MB son 5 GB ≈ USD
/// 0,13/mes: el 5% del margen de un pagador, que es un costo aceptable por la
/// videoteca de un PF real. Sin él, una cuenta `trainer` —que el paywall del
/// alumno NO gatea, y con razón— tiene subida ilimitada de 100 MB.
///
/// Nadie legítimo se acerca: el PF con más videos del proyecto tiene 3.
const int kMaxCustomExerciseVideos = 50;

// ─── Media de chat ─────────────────────────────────────────────────────────
//
// El mismo agujero que cerraron los cuatro topes de arriba, sobre el prefijo
// donde de verdad se acumula el UGC: `chatMedia/` tenía cap por archivo y
// NINGUNO de total, y ningún gate del paywall lo tocaba. Medido el 2026-09-14
// sobre `treino-dev`: 127,18 MB en 15 objetos, **45x** los bytes de
// `customExerciseVideos`. Ver `docs/costos-storage.md` §7.
//
// ⚠️ EL EJE ES DISTINTO Y NO SE PUEDE COPIAR EL DE ARRIBA. Allá el tope es de
// CANTIDAD y acá es de BYTES TOTALES, y el motivo es la forma del uso, no el
// gusto:
//
//   • `customExerciseVideos` es una BIBLIOTECA: pocos archivos, se arma una
//     vez. Ahí `cantidad × por-archivo` acota el total, y por eso el docstring
//     de [kFreeMaxCustomExerciseVideos] descarta —con razón— un tercer tope de
//     MB totales.
//   • El chat es un FLUJO CONTINUO: un PF con 30 alumnos manda cientos de
//     archivos por año legítimamente. Un tope de cantidad tendría que ser
//     enorme para no romperle el producto, y con la cantidad enorme el
//     producto `cantidad × por-archivo` deja de ser un techo útil. El total en
//     bytes sí lo es.
//
// Y el eje TAMPOCO es «por chat», aunque suene natural: `firestore.rules`
// (~1973) tiene TRES ramas de creación de chat —vínculo de Coach, social
// direccional (REQ-FOLLOW-012) e inquiry (#637, cualquier atleta a cualquier
// PF publicado)—, así que la cantidad de chats por usuario no tiene techo.
// N chats × tope-por-chat = sin techo. Medido: de 17 chats, 10 son sociales,
// 3 inquiry y 4 de Coach, y el chat que concentra el 94% de los bytes es
// SOCIAL.

/// Bytes TOTALES de media de chat que puede acumular un alumno del plan free,
/// sumando todos sus chats.
///
/// **250 MB, y el número sale de la medición.** El uploader más pesado del
/// proyecto acumuló **104,88 MB en tres meses** — y es el `trainer`, no un
/// atleta free. 250 MB es 2,4x eso: a [kFreeMaxChatVideoBytes] por video son
/// ≥10 videos, o cientos de fotos.
///
/// Costo: 0,25 GB × USD 0,026/GB-mes = **USD 0,0065/mes** almacenado, contra
/// un presupuesto de ARS 54,75/mes por usuario free
/// (`docs/costos-storage.md` §2). El resto del presupuesto es para el egress,
/// que es donde se va la plata.
///
/// ⚠️ **Es un tope de POR VIDA y hoy no tiene salida.** Los mensajes son
/// inmutables (`firestore.rules`: `allow update, delete: if false` sobre
/// `chats/{id}/messages`) y la app no tiene UI para borrar media de un chat,
/// así que quien llega al tope no puede volver atrás. Por eso 250 y no un
/// número más chico: un gate sin salida adentro tiene que ser generoso. El día
/// que exista «liberar espacio», este número se puede bajar.
const int kFreeMaxChatMediaBytes = 250 * 1024 * 1024;

/// Bytes TOTALES de media de chat para cualquiera — PF, alumno vinculado o
/// pagador.
///
/// Techo anti-abuso, no palanca de conversión: 5 GB ≈ **USD 0,13/mes**, el
/// mismo costo exacto que el techo de [kMaxCustomExerciseVideos].
///
/// Nadie real se acerca: el usuario más pesado del proyecto tiene 105 MB, o
/// sea el 2% de esto.
const int kMaxChatMediaBytes = 5 * 1024 * 1024 * 1024;

/// Tamaño máximo de UN video de chat en el plan free.
///
/// **El múltiplo se saca contra el p90, no contra el máximo — y esa es la
/// diferencia con [kFreeMaxCustomExerciseVideoBytes].** Allá el máximo real
/// (2,59 MB) era un dato sano y 25 MB era 10x eso. Acá el máximo observado
/// **ES el problema**: un solo MP4 de **90,31 MB** es el **71% de todo el
/// prefijo `chatMedia/`**, y el segundo video más grande pesa 9,25 MB — un
/// salto de 10x. Contra el p90 real de 9,12 MB, estos 25 MB son 2,7x.
///
/// Nada del lado del cliente amortigua esto: `chat_screen.dart` sube con
/// `picker.pickVideo(source: ImageSource.gallery)`, **sin `maxDuration` y sin
/// transcode**. Lo que está en la galería es lo que viaja.
const int kFreeMaxChatVideoBytes = 25 * 1024 * 1024;

/// Tamaño máximo de UN video de chat, para cualquiera.
///
/// **Baja de 100 MB a 50.** Los 100 eran el valor histórico suelto en
/// `storage.rules`, y son 11x el p90 real — un techo decorativo, igual que los
/// 100 MB que [kFreeMaxCustomExerciseVideoBytes] documenta para la videoteca.
/// 50 MB es 5,4x el p90.
///
/// Bajarlo a 50 rechaza **exactamente un archivo** de todo el bucket: el de
/// 90,31 MB. Ningún otro objeto real se acerca.
///
/// ⚠️ Este cap es **puramente preventivo**: sólo lo aplica `storage.rules`, y
/// la CF `maintainChatMediaQuota*` **no lo aplica retroactivamente**. Ver el
/// encabezado de `functions/src/storage/chat-media-quota.ts` — borrar por
/// tamaño al bajar el cap destruiría media de conversaciones ya existentes.
const int kMaxChatVideoBytes = 50 * 1024 * 1024;

/// Tamaño máximo de UNA imagen de chat, para cualquiera.
///
/// **15 MB, sin cambios, y es deliberado no tocarlo.** El máximo observado es
/// 4,98 MB y las imágenes son el 10% de los bytes del prefijo: bajarlo es
/// superficie de configuración a cambio de nada.
///
/// No lleva variante free por el mismo motivo. El eje del costo en chat son
/// los videos (89,8% de los bytes), y el tope de bytes TOTALES ya acota lo que
/// las fotos pueden acumular.
///
/// Ojo con de dónde viene ese 4,98 MB: es un PNG del Coach Hub. `image_picker`
/// **en web ignora `imageQuality`** (ver `avatar_web_uploader.dart`), así que
/// las fotos de mobile viajan comprimidas a 80 y las de web viajan crudas.
const int kMaxChatImageBytes = 15 * 1024 * 1024;
