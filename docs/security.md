# docs/security.md

Estado de la superficie de seguridad de TREINO. Hoy contiene **cuatro
secciones**: la matriz de cobertura de reglas (Slice A de #680), el inventario
de datos personales contrastado contra el cascade de borrado y contra la
Política de Privacidad, la decisión escrita sobre las lecturas amplias de
Storage, y el threat model por actor con el registro `QA-SEC-xxx` (Slice E).

Las cuatro responden preguntas distintas y se leen en ese orden:

| Sección | Pregunta que responde |
|---|---|
| [§1](#1-matriz-de-cobertura-de-reglas) | ¿Qué colección × operación no tiene un test que compruebe que el denegado se deniega? |
| [§2](#2-inventario-de-datos-personales) | ¿Qué dato personal guardamos, dónde, y qué pasa con él cuando el usuario se va? |
| [§3](#3-lecturas-amplias-en-storage--decisión-path-por-path) | Los tres `read` amplios de Storage, ¿son deliberados o son un agujero? |
| [§4](#4-threat-model-por-actor) | Para cada actor del producto: qué puede leer, qué puede escribir, y qué **no debería** poder. |

---

## 1. Matriz de cobertura de reglas

### Por qué existe

`firestore.rules` (2195 líneas) y `storage.rules` (143) se endurecieron de forma
**reactiva**: cada agujero se tapó cuando alguien lo vio. El trabajo está bien
hecho, pero hasta ahora nadie podía responder *"¿qué colección × operación no
tiene un test que compruebe que el denegado se deniega?"*. Sin esa respuesta,
"estamos cubiertos" es una impresión, no un dato.

Esta matriz es esa respuesta. **Sólo cuenta tests NEGATIVOS** — un test que
afirma que una operación es RECHAZADA. Un test positivo (`assertSucceeds`)
demuestra que el producto funciona; no demuestra nada sobre lo que la regla
tiene que impedir. Una celda en verde acá significa: existe al menos una
aserción que, si la regla se aflojara, se pondría roja.

### Cómo leerla

| Marca | Significado |
|---|---|
| ✅ | Hay test negativo en `functions/src/__tests__/*-rules.test.ts` (job *Functions Test*) |
| 🟡 | Hay test negativo en la otra suite, `scripts/rules_test/*.test.js` (job *Rules Test*) |
| — | No hay ningún test negativo |

**Las dos marcas valen lo mismo.** El 🟡 nació distinguiendo "hay test pero
nada lo corre"; desde #680 Slice B las dos suites corren en CI y lo único que
separa las marcas es en qué archivo vive la cobertura — dato útil para saber
dónde tocar, no un nivel de confianza menor. Ver §1.4.

> ⚠️ **`main` no tiene branch protection** (`GET /repos/.../branches/main/protection`
> → 404, verificado 2026-08-24). Ningún job de CI **impide** mergear hoy — ni
> éstos ni `Analyze & Test`: fallan en rojo y el botón de merge sigue
> disponible. `ci.yml` ya lo dice entre paréntesis ("con branch protection
> activada"), pero conviene que esté acá: mientras eso siga así, todo ✅ de
> esta matriz garantiza *"esto se ejecuta y alguien ve el rojo"*, no *"esto no
> puede entrar a main"*. Activarla, y decidir qué checks son obligatorios, es
> parte pendiente de Slice B.

Las operaciones son las cinco de Firestore (`read` se abre en `get` + `list`
porque son permisos distintos: `get` protege un documento, `list` protege la
enumeración, y una regla puede tapar uno y dejar el otro abierto). En Storage
son `get` / `list` / `write` / `delete`.

### 1.1 Firestore — 34 paths declarados en `firestore.rules`

| Colección | get | list | create | update | delete |
|---|---|---|---|---|---|
| `users/{uid}` | — | — | ✅ | ✅ | — |
| `users/{uid}/notifications` | ✅ | — | ✅ | ✅ | ✅ |
| `users/{uid}/sessions` | ✅ | ✅ | ✅ | — | — |
| `users/{uid}/sessions/{sid}/setLogs` | ✅ | ✅ | ✅ | — | — |
| `users/{uid}/checkIns` | 🟡 | — | 🟡 | — | — |
| `users/{uid}/customExercises` | — | — | — | — | — |
| `exercises` | — | — | — | — | — |
| `routines` | ✅ | ✅ | ✅ | ✅ | — |
| `routines/{id}/ratings` | — | ✅ | ✅ | ✅ | ✅ |
| `trainer_links` | ✅ | ✅ | — | ✅ | — |
| `posts` | ✅ | — | ✅ | ✅ | — |
| `posts/{id}/reactions` | ✅ | — | ✅ | — | ✅ |
| `userPublicProfiles` | — | — | ✅ | ✅ | — |
| `trainerPublicProfiles` | — | — | ✅ | ✅ | — |
| `gyms` | — | — | 🟡 | 🟡 | — |
| `friendships` | ✅ | — | ✅ | ✅ | ✅ |
| `follows` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `chats` | ✅ | ✅ | ✅ | ✅ | — |
| `chats/{id}/messages` | ✅ | ✅ | ✅ | — | — |
| `session_shares` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `profile_shares` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `coach_availability_rules` | — | — | — | — | — |
| `coach_availability_overrides` | — | — | — | — | — |
| `appointments` | — | — | 🟡 | — | — |
| `measurements` | ✅ | ✅ | ✅ | ✅ | 🟡 |
| `performance_tests` | — | — | ✅ | ✅ | — |
| `athlete_billing` | ✅ | — | 🟡 | 🟡 | — |
| `athlete_notes` | ✅ | — | 🟡 | 🟡 | — |
| `athlete_files` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `follow_up_entries` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `nutrition_plans` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `payments` | ✅ | ✅ | 🟡 | ✅ | ✅ |
| `reviews` | — | — | ✅ | — | — |
| `mail_queue` | — | — | — | — | — |

**98 de 170 celdas** tienen test negativo (57%). Por operación:

| Operación | Paths con test negativo |
|---|---|
| `get` | 21 / 34 |
| `list` | 15 / 34 |
| `create` | 28 / 34 |
| `update` | 22 / 34 |
| `delete` | 12 / 34 |

Cinco paths siguen **sin una sola aserción negativa**:
`users/{uid}/customExercises`, `exercises`, `coach_availability_rules`,
`coach_availability_overrides`, `mail_queue`.

> **QA-SEC-010 (oráculo de existencia) no mueve los totales, y conviene que se
> entienda por qué.** `existence-oracle-rules.test.ts` agregó 8 negativos
> nuevos sobre `chats`, `friendships`, `follows` y `athlete_notes`, pero las
> cuatro celdas `get` ya estaban marcadas: lo que faltaba no era *una* aserción
> negativa, era la **segunda dirección** de la misma celda. Los negativos que
> había probaban "el doc existe y no es tuyo → DENY"; ninguno probaba "el doc
> no existe → DENY", que es justo el estado que respondía la pregunta. La
> celda `get` de `athlete_notes` sí cambia de marca (🟡 → ✅) porque su
> cobertura pasó a vivir también en `functions/`.
>
> Lección para §1.8: una celda en ✅ dice que existe **al menos un** negativo,
> no que la operación esté agotada. Cuando una regla tiene un disyunto que
> cambia el resultado según el estado del documento, el test tiene que
> recorrer los dos estados o la celda miente por omisión.

### 1.2 Storage — 7 paths declarados en `storage.rules`

| Path | get | list | write | delete |
|---|---|---|---|---|
| `avatars/{file}` | ✅† | ✅ | ✅ | ✅ |
| `temp/uploads/{uid}/**` | ✅ | ✅ | ✅ | ✅ |
| `customExerciseVideos/{uid}/**` | ✅† | ✅ | ✅ | ✅ |
| `chatMedia/{chatId}/{uid}/**` | 🟡 | 🟡 | — | — |
| `athleteFiles/{pairId}/**` | ✅ | ✅ | ✅ | ✅ |
| `postPhotos/{uid}/{file}` | ✅ | ✅ | ✅ | ✅ |
| `sessionFeedback/{uid}/{sid}/{file}` | ✅ | ✅ | ✅ | ✅ |

**26 de 28 celdas** (93%). Las dos que faltan son `write` y `delete` de
`chatMedia`. Hay además un octavo bloque, el catch-all
`match /{allPaths=**} { allow read, write: if false; }`, que sólo se ejercita
de refilón: el caso "listar `postPhotos/`" de
`post-photos-storage-rules.test.ts` cae en él, pero nada lo testea de frente.

> **Nota de recuento (#804).** La fila de `sessionFeedback` y el header
> ("7 paths", 28 celdas) los agrega este PR, pero el path no es suyo: lo
> introdujo **#801**, que sumó el `match` a `storage.rules` y su
> `session-feedback-storage-rules.test.ts` sin actualizar esta tabla. Se
> corrige acá porque el total de §1.2 es un conteo global: dejarlo en "6 paths
> / 24 celdas" habría hecho que el número de **este** PR también fuera falso.
> Las cuatro celdas se marcaron leyendo el archivo de test, no por inferencia:
> `get` (dueño, PF con grant, PF sin grant, PF ajeno, autenticado cualquiera,
> revocado y anónimo), `list` (los tres niveles), `write` (dueño, ajeno, PF,
> content-type y anónimo) y `delete` (dueño, PF, tercero y anónimo).

> **† — cobertura de piso, no de fondo. Leer esas dos celdas como "cubierto"
> sería un error.** El único negativo que existe sobre ellas es el del usuario
> **anónimo**. El caso que importa —un autenticado cualquiera leyendo el objeto
> de otro— está **abierto en las dos** y **sin testear a propósito**: los dos
> `get` son un permiso amplio **deliberado** (§3.2, §3.3), y pinear un permiso
> amplio congela el status quo (§1.6 regla 1). Si mañana se decide apretarlos,
> el test habría que borrarlo en vez de que guíe.
>
> Las dos celdas `list` **ya no llevan †**: eran los leaks **QA-SEC-007**
> (`avatars/`) y **QA-SEC-008** (`customExerciseVideos/`), y las dos quedaron
> cerradas con `allow list: if false`. Los `assertFails` que las pinean cubren
> al ajeno **y al dueño** —la regla es `if false`, no owner-only— y en
> `customExerciseVideos` cubren además la **raíz**, que era el directorio de
> qué PFs tienen contenido. Viven en `avatars-storage-rules.test.ts` y
> `custom-exercise-videos-storage-rules.test.ts`.
>
> La celda `delete` de `avatars` estuvo en `—` por un motivo distinto: el
> borrado se denegaba **hasta para el dueño**, y por un null deref en la línea
> `&& request.resource.size < 5 * 1024 * 1024` del `write`, no por falta de
> permiso. Cualquier test ahí habría pasado por el motivo equivocado, que §1.8
> prohíbe. Era **QA-SEC-009** y **cerró en #765** con un `allow delete` propio.
> Por eso el archivo de test trae el **positivo del dueño** además de los
> negativos: es el que distingue "deniega por permiso" de "deniega porque la
> regla explota", y es el único que se pone rojo si alguien saca el
> `allow delete`.
>
> Los tres tickets están medidos contra el emulador y explicados en §3.

> **La fila de `temp/uploads` pasó de cuatro `—` a cuatro ✅ de una sola vez**,
> y no por haber escrito cuatro tests sobre una regla que seguía igual: el
> bloque se **cerró entero** (QA-SEC-015, §4.9). Las cuatro operaciones son
> ahora `if false`, así que cada celda se pinea con el negativo del **dueño**
> además del ajeno y el anónimo — no hay ningún permiso amplio que un
> `assertSucceeds` pudiera congelar, que es lo que §1.6 regla 1 prohíbe. Las
> celdas no llevan † por el mismo motivo: acá no hay "cobertura de piso", el
> piso y el fondo son la misma denegación.

### 1.3 De dónde salen estos números

No son una estimación. Para el relevamiento se leyeron **los 28 archivos** de
test de reglas que existían antes de este change (20 en `functions/`, 8 en
`scripts/rules_test/`) y se clasificó **cada una de sus 509 aserciones** por
`(path, operación, positiva/negativa)`: 302 negativas y 207 positivas. El total
reconcilia exactamente contra el conteo mecánico — 296 `assertFails(` + 202
`assertSucceeds(` en las suites que usan el SDK, más 6 `toBe(403)` y 5
`toBe(200)` en las dos suites REST del reloj, que ejercitan las mismas reglas
por HTTP crudo en vez de por SDK.

Para recontar (los números cambian a medida que se agregan tests):

```bash
rg -c 'assertFails\(' functions/src/__tests__/*rules*.ts scripts/rules_test/*.test.js
rg -n 'toBe\(403\)|toBe\(200\)' functions/src/__tests__/watch-rest-*-rules.test.ts
```

Cuidado al replicarlo: `rg -c` cuenta **líneas que contienen el token**, no
llamadas — la línea del `import { assertFails, assertSucceeds }` suma uno de
cada, y hay comentarios en prosa que nombran `assertSucceeds` sin llamarlo. Los
números de arriba son call sites reales, no líneas.

### 1.4 Hay dos suites de reglas, y las dos corren en CI

Esto es lo primero que hay que saber antes de tocar una regla:

| Suite | Archivos | Job de CI | Cómo se corre a mano |
|---|---|---|---|---|
| `functions/src/__tests__/*-rules.test.ts` | 34 | *Functions Test* | `npm --prefix functions run test:rules:emulator` |
| `scripts/rules_test/*.test.js` | 8 | *Rules Test* | `bash scripts/test_rules.sh` |

La segunda entró en CI con **#680 Slice B**. Hasta ahí era un ítem de checklist
de PR — `scripts/test_rules.sh` lo decía en su propio header — y ocho
colecciones dependían de que alguien se acordara: `users/{uid}/checkIns`,
`gyms`, `appointments`, `measurements` (delete), `athlete_billing`,
`athlete_notes`, `payments` (create) y `storage:chatMedia`.

**Lo que costó ese hueco, medido:** al meter la suite en CI estaba **roja**.
Cuatro aserciones de `rules.test.js` habían quedado obsoletas contra cambios
deliberados de las reglas, sin que nadie se enterara:

| Escenario | Qué cambió en la regla | Desde |
|---|---|---|
| SCENARIO-608a | `routines` UPDATE path 2 — el dueño puede editar `name`/`level`/`days` (REQ-USR-018) | 2026-06-09 |
| SCENARIO-270 inv. | `userPublicProfiles` create pinea `gymId` con `getAfter(users/{uid})` — el test no seedeaba el doc privado | 2026-07-06 |
| SCENARIO-602 | `routines` CREATE branch 2 acepta `visibility: 'public'` (#297) | 2026-07-07 |
| SCENARIO-132 inv. | `friendships` congelada, `update: if false` (ADR-FOLLOW-012) | 2026-08-07 |

Ninguna era un agujero: en los cuatro casos la regla se movió a propósito y el
test se quedó atrás. Pero eso **es** el problema. Una suite que nadie corre no
distingue "la regla cambió porque quisimos" de "la regla se rompió" — las dos
se ven igual, que es como se ven las cuatro de arriba. Y tres de ellas ya
estaban rojas el 2026-07-21, la última vez que alguien editó ese archivo: ni
siquiera quien lo tocaba lo estaba corriendo.

Existe además `functions/src/__tests__/rules-read-isolation.test.ts`, que no es
un test de emulador sino un **scanner estático** sobre el texto de
`firestore.rules`: congela qué cláusulas pueden conocer el paywall y verifica
que ninguna cláusula de lectura lo mire. Corre en CI (`npm test` lo levanta) y
no aporta celdas a esta matriz porque no ejercita permisos.

### 1.5 Huecos cerrados en esta pasada

Se priorizó lo que toca **datos de terceros**: información que una persona
escribe sobre otra, que la segunda no puede ver o no puede modificar.

| Path | Antes | Ahora | Archivo |
|---|---|---|---|---|
| `athlete_files` | 0 celdas | 5/5 | `coach-private-collections-rules.test.ts` |
| `follow_up_entries` | 0 celdas | 5/5 | `coach-private-collections-rules.test.ts` |
| `nutrition_plans` | 0 celdas | 5/5 | `coach-private-collections-rules.test.ts` |
| `session_shares` | 0 celdas | 5/5 | `share-grants-rules.test.ts` |
| `profile_shares` | 0 celdas | 5/5 | `share-grants-rules.test.ts` |
| `payments` update / delete | 0 celdas | 2/2 | `payments-update-rules.test.ts` |
| `storage:athleteFiles` | 0 celdas | 4/4 | `athlete-files-storage-rules.test.ts` |

Firestore pasó de **71/170 a 98/170** celdas; Storage de **6/24 a 10/24**.

Por qué esos siete y no otros:

- **`athlete_files` + `storage:athleteFiles`** eran el peor par de la matriz.
  El doc de Firestore guarda un `downloadUrl` con token y el objeto de Storage
  guarda los bytes: un agujero en cualquiera de los dos entrega el mismo PDF.
  Los dos estaban en cero.
- **`session_shares` / `profile_shares`** no son documentos comunes, son
  **capabilities**. Otras reglas les hacen `get()` y reparten acceso según lo
  que digan: el historial completo de entrenamiento (`users/{uid}/sessions/**`,
  `setLogs/**`) y las medidas corporales auto-registradas (`measurements` con
  `recordedBy == athleteId`, que exige que AMBOS grants nombren al mismo PF).
  Una regla que dejara escribir esos docs a alguien que no sea el alumno no
  filtraría un documento: acuñaría el permiso de leer todo lo anterior.
- **`payments` update** era el hueco más engañoso. Tenía 14 negativos de
  `create` (`scripts/rules_test/payments-field-validation.test.js`) y cero de
  `update`, que es la regla más estricta del archivo — la que decide si una
  deuda se puede reescribir después de creada. El único artefacto que nombraba
  ese camino, `test/firestore/payments_rules_test.dart`, tiene los **dos
  cuerpos vacíos** y `skip: 'emulator required'`: viene reportando "skipped",
  nunca "failed", desde que se escribió.
- **`follow_up_entries` / `nutrition_plans`** comparten el idioma
  squat/hijack que ya se arregló para `athlete_notes` (QA-2026-07-30 C1) y
  nunca se testeó acá: doc id determinístico y enumerable
  (`{trainerId}_{athleteId}`), identidad fijada al pre-image en `update`.

Los 79 negativos nuevos se verificaron por **mutación**, no sólo por verde: se
aflojó la regla correspondiente en el archivo real y se comprobó que la
aserción se pone roja. Cinco mutaciones, en cinco reglas distintas:

| Mutación aplicada | Rojos esperados | Rojos obtenidos |
|---|---|---|
| `athlete_files` read → `if request.auth != null` | 4 | 4 |
| `follow_up_entries` update: se quitan los pins de identidad y `recordedAt` | 3 | 3 |
| `session_shares` write: se quita `uid == athleteId` | 5 (y **cero** en `profile_shares`) | 5, y cero |
| `payments` update: se quitan los pins de `dueAt` y `lastOverdueNotifiedAt` | 4 | 4 |
| `storage:athleteFiles` read → `if request.auth != null` | 4 | 4 |

La tercera es la que más dice: aflojar `session_shares` dejó `profile_shares`
en verde. Los tests están atados a la colección que dicen testear, no pasando
por un denegado genérico.

### 1.6 Huecos que quedan abiertos, y por qué

Ordenados por lo que me preocuparía primero:

1. ~~**`storage:avatars`, `customExerciseVideos`, `postPhotos` permiten lectura
   a cualquier autenticado**~~ — **DECIDIDO** por #680 Slice E: la decisión
   path por path vive en **§3**. Resumen: `postPhotos` es deliberado y correcto;
   el `get` de `avatars` y `customExerciseVideos` es defendible pero redundante;
   y el `list` de esos dos **no era deliberado — es un leak**, medido contra el
   emulador, con ticket propio (QA-SEC-007 y QA-SEC-008). Se documenta acá y se
   arregla aparte: aflojar o apretar una regla de lectura de Storage puede
   romper avatares o videos en producción y merece su propio PR con su propia
   verificación. Slice E también dejó tests para las celdas que **sí** estaban
   decididas (§3.7). **Los dos leaks ya cerraron: QA-SEC-008 en #763 y
   QA-SEC-007 en #764.**
2. ~~**`storage:temp/uploads` y el catch-all `{allPaths=**}`**: cero tests.~~
   — **`temp/uploads` CERRADO en #804**; el catch-all sigue sin test de frente.
   El texto original decía que ahí "van los Excel que sube el PF": era falso.
   **Nunca hubo un writer en `lib/`** —`git log -S "temp/uploads" --all --
   lib/` devuelve cero commits— y el import de planes es 100% client-side en
   memoria. Con eso, QA-SEC-015 no se cerró poniéndole allowlist + cap al
   `write` sino **eliminando el camino de escritura**: las cuatro operaciones
   son `if false` y las cuatro celdas de §1.2 quedaron cubiertas por
   `temp-uploads-storage-rules.test.ts`. Ver §4.9.
3. **`users/{uid}` get/list**: la regla es owner-only y no hay ni un negativo
   que compruebe que un tercero no lee el doc de otro. Cubierto de refilón por
   los tests de subcolecciones, nunca de frente. El threat model **lo midió**
   (§4.3: get y list de un tercero, los dos DENY) pero la celda sigue en `—`
   a propósito: medir con una sonda no es lo mismo que dejar una aserción que
   se ponga roja sola. Sigue pendiente y sigue siendo barato.
4. **`chats` delete y `chats/{id}/messages` update+delete** son `if false`
   (mensajes inmutables en MVP). Cero tests. Barato.
5. **`trainer_links` create y `reviews` update/delete**: `reviews` delete es
   `if false` (sólo la CF de borrado de cuenta), sin test.
6. **`exercises`, `mail_queue`, `coach_availability_*`,
   `users/{uid}/customExercises`**: cero. `mail_queue` es `read, write: if
   false` y su comentario dice por qué importa (relay de spam con nuestra
   reputación de remitente + emails de otros usuarios) — es el más barato de
   todos de cerrar. `coach_availability_*` dejó de ser sólo un hueco de
   cobertura: el threat model midió que su `create` no tiene gate de rol ni
   allowlist de campos, en una colección mundo-legible → **QA-SEC-013** (§4.9).
7. ~~**Las 8 colecciones que dependen sólo de la suite manual**~~ — **CERRADO**
   por #680 Slice B: `scripts/test_rules.sh` es el job *Rules Test* de CI
   (§1.4). Queda pendiente, como deuda de consolidación y no
   como hueco de cobertura, **unificar las dos suites**: hoy son dos árboles de
   dependencias (`@firebase/rules-unit-testing` ^3 en `scripts/rules_test/`
   contra ^5 en `functions/`), dos lockfiles y dos jobs para el mismo tipo de
   test. Portar los 8 `.js` a TS bajo `functions/src/__tests__/` los dejaría
   bajo un solo runner, pero es un diff grande y mecánico que no aporta
   cobertura — vale la pena hacerlo solo, no colgado de otro cambio.
8. **`test/firestore/payments_rules_test.dart`** sigue en el repo con los dos
   cuerpos vacíos. Los escenarios que describe (SCENARIO-VENC-14 y -15) ahora
   están cubiertos de verdad en `payments-update-rules.test.ts`; el stub
   debería borrarse o apuntar ahí, pero eso es un cambio a un archivo que no
   toca este slice.

### 1.7 Observaciones sobre las reglas mismas

No son agujeros, pero salieron al leer y conviene que estén escritas:

- **`athlete_files` create no ata el docId al par.** `athlete_notes`,
  `follow_up_entries` y `nutrition_plans` verifican
  `docId == trainerId + '_' + athleteId`; `athlete_files` sólo pide
  `trainerId == auth.uid`. No es explotable (el gate de lectura mira
  `resource.data.trainerId`, no el docId), pero es una inconsistencia dentro
  de la misma familia de reglas.
- **`session_shares` / `profile_shares` no validan la forma del doc** más allá
  de `trainerId is string`. El alumno puede guardar campos arbitrarios en su
  propio grant. Sin impacto de seguridad; sin `keys().hasOnly()` tampoco hay
  contrato.
- **El gate de `storage:athleteFiles` es `pairId.split('_')[0] == uid`.** Es
  correcto porque los uid de Firebase Auth son alfanuméricos de 28 caracteres
  y nunca traen `_`. Si alguna vez entra un id con guión bajo (un uid
  sintético, un id de test), el prefijo deja de ser único y la regla se rompe
  en silencio.

  **Al cerrar QA-SEC-010 ese idiom dejó de estar en un solo lugar.** Cuatro
  bloques de `firestore.rules` —`chats`, `friendships`, `follows` y
  `athlete_notes`— ahora acotan su disyunto `resource == null` con
  `split('_')` sobre el doc id, así que la premisa "los uid no traen guión
  bajo" pasó de sostener una regla a sostener cinco. Sigue siendo cierta y
  sigue sin estar verificada en ningún lado: no hay nada que impida sembrar
  un uid sintético con `_` desde el Admin SDK. Si algún día se agrega un
  guard, va acá y no en cada bloque.

### 1.8 Cómo mantener esta matriz

**Todo change que toque `firestore.rules` o `storage.rules` actualiza esta
sección en el mismo PR.** Concretamente:

1. Si agregás un `match` nuevo → fila nueva en la tabla que corresponda, con
   todas las celdas en `—` salvo las que traigas testeadas.
2. Si agregás un test negativo → la celda pasa a ✅, o a 🟡 si lo pusiste en
   `scripts/rules_test/`. Para tests nuevos preferí `functions/src/__tests__/`:
   no porque el otro job valga menos (los dos corren igual en cada PR), sino
   porque ahí está TypeScript y es donde las dos suites van a converger algún
   día (§1.6, punto 7).
3. Recalculá los totales de §1.1 y §1.2. Son conteos, no impresiones.
4. Los tests de reglas se corren con:

   ```bash
   npm --prefix functions run test:rules:emulator   # requiere Java 21+
   npm --prefix scripts/rules_test ci               # una vez
   bash scripts/test_rules.sh                       # la otra suite
   ```

   Los dos levantan y bajan su propio emulador. Si `java -version` dice menos
   de 21, exportá uno que sirva antes de correrlos
   (`export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"` en macOS).

Un test negativo que pasa por el motivo equivocado es peor que no tenerlo:
antes de dar por cerrada una celda, aflojá la regla y comprobá que el test se
pone rojo.

---

## 2. Inventario de datos personales

Inventario de datos personales de TREINO, y el contraste de ese inventario
contra las dos cosas que tienen que coincidir con él: **el borrado de cuenta**
(`functions/src/delete-account.ts`) y **la Política de Privacidad** que el
usuario acepta (`lib/features/auth/presentation/legal/legal_content.dart`).
Cubre el hueco 4 de [#680](https://github.com/Backhaus7997/treino/issues/680)
(Slice C, parte documental). El Slice A —matriz de cobertura de reglas— vive en
[security.md](./security.md); este archivo es su complemento: aquella responde
*"¿qué operación no tiene test negativo?"*, ésta responde *"¿qué dato personal
guardamos, dónde, y qué pasa con él cuando el usuario se va?"*.
---

### 2.0 Por qué existe y cómo se midió

La app maneja datos de terceros sobre terceros: medidas antropométricas,
tests de rendimiento, archivos privados que el PF sube **sobre** un alumno,
notas de seguimiento, planes de nutrición, chats privados con media, pagos y
gimnasio. Antes de ir a stores (#629) hay que poder afirmar **con evidencia**
que el borrado de cuenta se lleva todo eso, y que la política dice la verdad.

**Método.** Nada acá sale de memoria ni de suposición:

1. El universo de stores se enumeró con `rg '^\s*match /' firestore.rules` →
   **34 paths** (el mismo número que reporta §1.1),
   más `audit_log/{uid}`, que **no tiene bloque `match`** —lo escribe sólo el
   Admin SDK y por default-deny ningún cliente lo alcanza— y por eso no aparece
   en aquella matriz pero sí guarda un dato personal.
2. Storage: `storage.rules` declara **6 paths** + el catch-all `deny`.
3. Los campos salen de las `keys().hasOnly([...])` de `firestore.rules` y, donde
   la regla no tiene allowlist, de los modelos `freezed` en `lib/**/domain/`.
4. La cobertura de borrado sale de leer `functions/src/delete-account.ts` y los
   ocho módulos de `functions/src/cascade/` línea por línea, no de los nombres
   que el cascade se auto-reporta en `deletedCollections`.

**Alcance del borrado.** `deleteAccount` **rechaza a los trainers**
(`delete-account.ts` → guard `role === 'trainer'`, REQ-ACCDEL-CF-003). O sea:
todo este análisis es sobre el borrado de una cuenta **athlete**. Un PF no tiene
hoy ninguna vía de supresión de sus propios datos — ver
[§2.4, QA-CMP-011](#24-huecos-de-borrado-detectados).

---

### 2.1 Inventario de PII

Leyenda de la columna **De quién**:

| Marca | Significado |
|---|---|
| 👤 | Dato **del propio usuario**, cargado por él |
| 🫱 | Dato **sobre el usuario, escrito por un tercero** (típicamente su PF) |
| 🔗 | Dato **del usuario que vive dentro del documento de otra persona** (denormalización) |

#### 2.1.1 Firestore — 35 stores (34 con `match` + `audit_log`)

| # | Path | Datos personales que contiene | De quién | Quién lo lee |
|---|---|---|---|---|
| 1 | `users/{uid}` | `email`, `displayName`, `firstName`, `lastName`, `phone`, `bornAt`, `gender`, `heightCm`, `bodyWeightKg`, `experienceLevel`, `avatarUrl`, `gymId`, `fcmTokens[]`, `termsAcceptedAt`, `subscription`, `paymentAlias`, `trainerLocations[]`/`trainerGeohashes[]`/`trainerLatitude`/`trainerLongitude` | 👤 | Sólo el dueño (`allow read` owner-only) |
| 2 | `users/{uid}/notifications/{id}` | `title`, `body` (**el `body` lleva el `displayName` del actor en texto libre**), `actorUid`, `deepLink` | 👤 + 🔗 | Sólo el dueño del inbox |
| 3 | `exercises/{id}` | — (catálogo global; `aliases[]` no guarda autor) | — | Cualquier autenticado |
| 4 | `routines/{id}` | `createdBy`, `assignedBy`, `assignedTo`, `name`, notas de días/ejercicios | 👤 + 🫱 | Público si `visibility=='public'`; si no, las 3 partes |
| 5 | `routines/{id}/ratings/{userId}` | **doc id = uid del que puntúa**, `rating`, `comment` (≤500 chars, texto libre) | 👤 (dentro de la rutina de otro) 🔗 | Cualquier autenticado |
| 6 | `trainer_links/{id}` | `trainerId`, `athleteId`, estado y fechas del vínculo | 👤+🫱 | Las dos partes |
| 7 | `posts/{id}` | `authorUid`, `authorDisplayName`, `authorAvatarUrl`, `authorGymId`, `text`, `photoUrl`, `workoutSnapshot`, `workoutStats` | 👤 | Según `privacy`: `public` / `friends` / `gym` |
| 8 | `posts/{id}/reactions/{reactorUid}` | **doc id = uid del que reacciona**, `type` | 👤 (dentro del post de otro) 🔗 | Quien pueda leer el post |
| 9 | `userPublicProfiles/{uid}` | `displayName`, `displayNameLowercase`, `avatarUrl`, `gymId`, **`gymName`**, `workoutsCount`, `racha`, `followersCount`, `followingCount`, `lifetimeVolumeKg`, `bestSquatKg`/`bestBenchKg`/`bestDeadliftKg` | 👤 | **Cualquier autenticado** (mundo-legible) |
| 10 | `trainerPublicProfiles/{uid}` | Perfil comercial del PF + agregados (`ratingAvg`, `activeLinks`) | 👤 (PF) | Cualquier autenticado |
| 11 | `gyms/{id}` | `createdBy` (uid del PF que lo dio de alta), `lat`, `lng`, `geohash` | 👤 (PF) | Cualquier autenticado |
| 12 | `friendships/{id}` **(legacy, congelado)** | `members[]` (los dos uids), estado | 👤 | Los dos miembros |
| 13 | `follows/{id}` | `members[]`, dirección, estado | 👤 | Los dos miembros |
| 14 | `chats/{id}` | `members[]`, `lastMessageText` (**preview del texto real**), `lastRead{}`, `linkId` | 👤 | Los dos miembros |
| 15 | `chats/{id}/messages/{id}` | `senderId`, `text`, `mediaUrl`, `mediaType` | 👤 | Los dos miembros |
| 16 | `session_shares/{athleteId}` | doc id = uid; `trainerId` al que se le concede el historial | 👤 | Alumno + PF concedido |
| 17 | `profile_shares/{athleteId}` | doc id = uid; **snapshot denormalizado** de `phone`, `bornAt`, `heightCm`, `bodyWeightKg`, `gender`, `experienceLevel` (lo mantiene `syncSharedProfile`) | 👤 | Alumno + PF concedido |
| 18 | `users/{uid}/sessions/{id}` | Sesiones de entrenamiento con fecha, duración, rutina | 👤 | Dueño + PF con `session_shares` |
| 19 | `users/{uid}/sessions/{id}/setLogs/{id}` | Series: peso, reps, RPE | 👤 | Ídem |
| 20 | `users/{uid}/checkIns/{date}` | Asistencia diaria | 👤 | Dueño |
| 21 | `users/{uid}/customExercises/{id}` | Ejercicios propios + URL de video | 👤 | Dueño |
| 22 | `coach_availability_rules/{id}` | Agenda semanal del PF | 👤 (PF) | **Cualquier autenticado** (get y list) — deliberado, `firestore.rules:1810`; corregido en §4.11 |
| 23 | `coach_availability_overrides/{id}` | Excepciones de agenda del PF | 👤 (PF) | **Cualquier autenticado** (get y list) — ídem |
| 24 | `appointments/{id}` | `athleteId`, **`athleteDisplayName` (nombre denormalizado)**, `startsAt`, `noteBefore`, `noteAfter` (notas de coaching), `paymentId` | 🫱 + 🔗 | Alumno + PF |
| 25 | `measurements/{id}` | **Antropometría completa**: `weightKg`, `fatPercentage`, `muscleMassKg` y 18 circunferencias (hombros, pecho, cintura, cadera, glúteos, bíceps L/R y flexionados, antebrazos, muslos alto/medio L/R, gemelos L/R), `notes` | 👤 o 🫱 (`recordedBy`) | Alumno + PF vinculado |
| 26 | `performance_tests/{id}` | `cmjCm`, `squatJumpCm`, `abalakovCm`, `broadJumpCm`, sprints 10/20/30/40 m, 1RM de sentadilla/banco/peso muerto/press/dominadas, `vo2maxMlKgMin`, course navette, Cooper | 👤 o 🫱 | Alumno + PF vinculado |
| 27 | `athlete_billing/{id}` | `trainerId`, `athleteId`, `amountArs`, `cadence` | 🫱 | **PF + el alumno del par** (`firestore.rules:2119`); corregido en §4.11 |
| 28 | `athlete_notes/{id}` | `note` (texto libre del PF **sobre** el alumno) | 🫱 | Sólo el PF |
| 29 | `athlete_files/{id}` | `fileName`, `contentType`, `sizeBytes`, `storagePath`, `downloadUrl` de archivos privados del PF sobre el alumno (PDF/imágenes) | 🫱 | Sólo el PF |
| 30 | `follow_up_entries/{id}` | `text` (≤5000 chars), `tag`, `recordedAt` — bitácora privada del PF | 🫱 | Sólo el PF |
| 31 | `nutrition_plans/{id}` | `title`, `meals[]` — plan alimentario | 🫱 | Sólo el PF |
| 32 | `payments/{id}` | `trainerId`, `athleteId`, `amountArs`, `concept`, `status`, `periodKey`, fechas | 🫱 | Alumno + PF |
| 33 | `reviews/{id}` | `athleteId`, `trainerId`, `rating`, `comment` (≤500 chars, texto libre del alumno) | 👤 | **Cualquier autenticado** |
| 34 | `mail_queue/{id}` | `toUid`, `kind`, `params{}` (parámetros de plantilla: montos, nombres), `status` | 👤 | Nadie (`read, write: if false`; sólo Admin SDK) |
| 35 | `audit_log/{uid}` | `uid`, `provider` (método de login), `startedAt`, `completedAt`, `deletedCollections[]`, `errors[]` | 👤 | Nadie (sin bloque `match` → default deny) |

**34 de los 35 stores contienen datos personales.** El único que no es
`exercises` (catálogo global, sin autor). `gyms` está al borde: lo único
personal que guarda es el uid del PF que lo dio de alta.

#### 2.1.2 Storage — 6 paths

| # | Path | Contenido | De quién | Lectura |
|---|---|---|---|---|
| S1 | `avatars/{uid}.{ext}` | Foto de perfil | 👤 | Cualquier autenticado |
| S2 | `temp/uploads/{uid}/**` | ~~Excel de planes que sube el PF~~ → **nada nuevo**: el bloque quedó cerrado a la escritura (QA-SEC-015, §4.9). Nunca hubo un writer en `lib/`; lo que haya en reposo es de antes | 👤 | Nadie (`get`/`list` `if false`) |
| S3 | `customExerciseVideos/{uid}/**` | Videos tutoriales | 👤 | Cualquier autenticado |
| S4 | `chatMedia/{chatId}/{uid}/**` | Fotos y videos de chats 1-1 | 👤 | `get` sólo miembros del chat; `list` cerrado |
| S5 | `athleteFiles/{trainerId}_{athleteId}/**` | PDFs e imágenes del PF **sobre** el alumno | 🫱 | Sólo el PF del par |
| S6 | `postPhotos/{uid}/{postId}.{ext}` | Foto del post de share-a-workout | 👤 | `get` cualquier autenticado; `list` cerrado |

**Total inventariado: 34 stores de Firestore con PII + 6 paths de Storage = 40
ítems.**

#### 2.1.3 Agregados y denormalizaciones

Lo que más fácil sobrevive a un borrado es el dato copiado adentro del documento
de otro. Los cuatro agregados que menciona #680, verificados uno por uno:

| Agregado | Escribe en | ¿Sobrevive al borrado del athlete? |
|---|---|---|
| `ranking-aggregate.ts` | `userPublicProfiles/{uid}` | **No** — ese doc se borra entero. |
| `review-aggregate.ts` | `trainerPublicProfiles/{trainerId}` | No lleva identidad del alumno, sólo promedio y conteo. Pero **la review de origen sí queda** (ítem 33). |
| `link-aggregate.ts` | `trainerPublicProfiles/{trainerId}` | Sólo conteos. |
| `template-rating-aggregate.ts` | `routines/{routineId}` (`ratingAvg`, `ratingsCount`) | **Sí, y sigue contando la puntuación del usuario borrado** — ver QA-CMP-006. |
| `maintain-follow-counters.ts` | `userPublicProfiles/*` | **No** — recomputa en cada write, y el barrido de `follows` dispara el recálculo en los perfiles que quedan. Correcto. |
| `maintain-reaction-counters.ts` | `posts/{id}.reactionCounts` | **Sí** — porque la reacción de origen tampoco se borra (QA-CMP-005). |

Además de los agregados, hay **cuatro copias de identidad** dentro de documentos
de terceros: `posts.authorDisplayName`/`authorAvatarUrl` (se van con el post),
`appointments.athleteDisplayName` (**no se va**), `users/*/notifications.body`
(**no se va**) y `userPublicProfiles.gymName`.

---

### 2.2 Contraste contra el cascade de borrado

`runDeleteAccount` (`functions/src/delete-account.ts`) ejecuta nueve pasos, cada
uno en su `try/catch`, y borra el usuario de Auth al final. Esto es lo que cada
ítem del inventario recibe.

#### 2.2.1 Cobertura, ítem por ítem

| # | Store | Estado | Paso del cascade / motivo |
|---|---|---|---|---|
| 1 | `users/{uid}` | ✅ | `deleteUserDocs` → `recursiveDelete` |
| 2 | `users/{uid}/notifications` | 🟡 **parcial** | El inbox propio se va con el `recursiveDelete`. **Las copias en el inbox de terceros quedan** → QA-CMP-008 |
| 3 | `exercises` | n/a | Sin PII |
| 4 | `routines` | ✅ | `deleteAthleteRoutines` (PR #753) — `assignedTo == uid` + `createdBy == uid`, con `recursiveDelete`. `assignedBy` queda afuera a propósito, ver QA-CMP-004 |
| 5 | `routines/*/ratings/{userId}` | ❌ **hueco** | Sin paso; `allow delete: if false` (`firestore.rules:494`) → QA-CMP-006 |
| 6 | `trainer_links` | 🟡 parcial | `terminateTrainerLinks` marca `status:'terminated'`, `reason:'account-deleted'`. Los uids quedan. Deliberado. |
| 7 | `posts` | ✅ | `deletePosts` → `recursiveDelete` (borrado real desde la decisión de producto 2026-07-16). Se va el doc **y su subcolección `reactions`** — QA-CMP-005b arreglado |
| 8 | `posts/*/reactions/{reactorUid}` | 🟡 **parcial** | Las de terceros en los posts del usuario se van con el `recursiveDelete` de `deletePosts` (QA-CMP-005b arreglado). **Las del usuario en posts ajenos quedan** → QA-CMP-005 |
| 9 | `userPublicProfiles/{uid}` | ✅ | `deleteUserDocs` |
| 10 | `trainerPublicProfiles/{uid}` | ✅ | `deleteUserDocs` (defensivo) |
| 11 | `gyms` | n/a athlete | `createdBy` sólo lo escribe un PF, y un PF no puede autoborrarse → QA-CMP-011 |
| 12 | `friendships` (legacy) | ❌ **hueco** | `sweepFollows` barre **sólo** `follows` → QA-CMP-007 |
| 13 | `follows` | ✅ | `sweepFollows` (una sola query gracias a `members`) |
| 14 | `chats` | ⚪ retención deliberada | `athlete-data.ts:20-21`: "thread RETAINED for the other participant" |
| 15 | `chats/*/messages` | ⚪ retención deliberada | Ídem. **Pero su media sí se borra** → ver §2.2.3 |
| 16 | `session_shares/{uid}` | ✅ | `deleteAthleteOwnedData` (doc id = uid) |
| 17 | `profile_shares/{uid}` | ✅ | Ídem — se lleva el snapshot de teléfono/nacimiento/peso |
| 18-21 | `users/{uid}/sessions`, `setLogs`, `checkIns`, `customExercises` | ✅ | `recursiveDelete` |
| 22-23 | `coach_availability_*` | n/a athlete | Sólo del PF → QA-CMP-011 |
| 24 | `appointments` | 🟡 **parcial** | `cancelFutureAppointments` sólo toca los **futuros** y sólo cambia `status`/`reason`. `athleteDisplayName` y las notas quedan en **todos** → QA-CMP-009 |
| 25 | `measurements` | ✅ | `deleteAthleteOwnedData` (`where athleteId ==`) |
| 26 | `performance_tests` | ✅ | Ídem |
| 27 | `athlete_billing` | ✅ | Ídem |
| 28 | `athlete_notes` | ✅ | Ídem |
| 29 | `athlete_files` | ✅ | Ídem (QA-507 lo agregó) |
| 30 | `follow_up_entries` | ✅ | Ídem |
| 31 | `nutrition_plans` | ✅ | Ídem |
| 32 | `payments` | ⚪ retención deliberada | Fiscal/contable. Sólo `athleteId`, sin nombre |
| 33 | `reviews` | ⚪ retención deliberada | **Pero el alcance escrito no coincide con el código** → §2.3.2 |
| 34 | `mail_queue` | ❌ **hueco** | Sin paso, sin TTL → QA-CMP-010 |
| 35 | `audit_log/{uid}` | ⚪ retención deliberada | Sin período de retención definido |
| S1 | `avatars/` | ✅ | `deleteAvatar` (cualquier extensión, QA-CMP-002) |
| S2 | `temp/uploads/{uid}/` | ✅ | `deleteAthleteStorage` |
| S3 | `customExerciseVideos/{uid}/` | ✅ | `deleteAthleteStorage` |
| S4 | `chatMedia/{chatId}/{uid}/` | ✅ | `deleteAthleteStorage`, resolviendo los chats desde Firestore |
| S5 | `athleteFiles/{tid}_{uid}/` | ✅ | `deleteAthleteStorage`, filtrando por sufijo del `pairId` |
| S6 | `postPhotos/{uid}/` | ✅ | `deleteAthleteStorage` — QA-CMP-004b arreglado |
| — | Firebase Auth | ✅ | `admin.auth().deleteUser` — último, por diseño (REQ-ACCDEL-CF-012) |

#### 2.2.2 El número

De los **40 ítems** del inventario (34 Firestore con PII + 6 Storage), midiendo
sobre el borrado de una cuenta **athlete**:

| Estado | Ítems | Cuáles |
|---|---|---|
| ✅ Cubierto | **25** | 1, 4, 7, 9, 10, 13, 16-21, 25-31 + S1-S6 |
| 🟡 Parcial (queda PII recuperable) | **4** | 2, 6, 8, 24 |
| ⚪ Retenido a propósito, con decisión escrita en el código | **5** | 14, 15, 32, 33, 35 |
| ❌ Hueco sin decisión escrita | **3** | 5, 12, 34 |
| n/a para una cuenta athlete (PII de un PF) | **3** | 11, 22, 23 |

**Titular: 6 de 40 ítems dejan datos personales recuperables sin que exista
ninguna decisión escrita que lo justifique** (los 3 huecos + los 3 parciales sin
decisión escrita: `posts/*/reactions` en posts ajenos, `appointments` y
`notifications`). El parcial restante, `trainer_links`, sí tiene decisión
escrita.

Eran **8** cuando se midió por primera vez. Bajó a 6 en dos pasos: **#753** cerró
`routines` (ítem 4, QA-CMP-004), y **#754** cerró `postPhotos/` (S6, QA-CMP-004b)
y la mitad de las reacciones (QA-CMP-005b) — el ítem 8 pasó de hueco a parcial,
porque queda pendiente QA-CMP-005, las reacciones del usuario en posts ajenos.

`delete-account.smoke.test.ts` afirma que `deletedCollections` trae las
entradas esperadas, pero **ninguna aserción comprueba la ausencia de residuo en
las colecciones que el cascade no toca** — que es exactamente donde están los
seis ítems de arriba. El test verifica lo que el cascade dice que hizo, no lo
que quedó en la base. Es la debilidad que dejó pasar QA-CMP-004b y QA-CMP-005b,
así que los tests que los cierran (`cascade/storage.test.ts` y
`cascade/posts.test.ts`) asertan la **ausencia** de los objetos y documentos
después del cascade, no la presencia de nombres en `deletedCollections`. El
smoke test sigue como estaba.

La única excepción, y el patrón a copiar para los que quedan, es
`__tests__/cascade/routines.test.ts` (PR #753): afirma sobre `exists === false`
del documento y sobre la desaparición de su subcolección, no sobre el string
`"routines"` en `deletedCollections`.

#### 2.2.3 Inconsistencia interna que conviene mirar

El chat se retiene entero ("thread RETAINED for the other participant") **pero
su media se borra** (`deleteAthleteStorage` barre `chatMedia/{chatId}/{uid}/`).
El resultado es un hilo donde el otro participante conserva el texto y ve
mensajes con `mediaUrl` roto. No es un hueco de privacidad —va en la dirección
correcta— pero las dos mitades de la misma decisión no coinciden, y eso no está
escrito en ningún lado. Merece decisión explícita: o se retiene el hilo completo
(y entonces la media también), o se anonimiza el hilo entero.

---

### 2.3 Contraste contra la Política de Privacidad

⚠️ **La política no vive en `legal/privacy-policy.html`.** #680 la ubica ahí;
ese archivo **no existe en el repo**. El texto vigente es
`lib/features/auth/presentation/legal/legal_content.dart` → `kPrivacySections`
(11 secciones, `kLegalLastUpdated = '12 de junio de 2026'`), renderizado por
`LegalDocumentScreen`. El propio archivo se declara **borrador sin revisión
legal profesional**.

#### 2.3.1 Lo que el código guarda y la política no declara

La §1 ("Qué datos recolectamos") enumera: datos de cuenta (email, nombre de
usuario, avatar), datos de entrenamiento, ubicación aproximada opcional,
analítica y datos técnicos del dispositivo. Contra el inventario, **falta
declarar**:

| Dato guardado | Dónde | Gravedad |
|---|---|---|
| **Antropometría y composición corporal**: peso, % de grasa, masa muscular, 18 circunferencias | `measurements` (25), `users.bodyWeightKg` | **Alta** — dato de salud |
| **Tests de rendimiento fisiológico**: VO2max, 1RM, Cooper, course navette | `performance_tests` (26) | **Alta** — dato de salud |
| **Fecha de nacimiento, teléfono, nombre y apellido reales, género, altura** | `users` (1), `profile_shares` (17) | Alta |
| **Contenido de chats privados y su media** | `chats`, `messages` (14, 15), `chatMedia` (S4) | Alta |
| **Archivos, notas, bitácora de seguimiento y planes de nutrición que el PF escribe sobre el alumno** | 28-31, `athleteFiles` (S5) | Alta — el alumno **nunca los ve** y la política no le avisa que existen |
| **Pagos, facturación y suscripción** | `payments` (32), `athlete_billing` (27), `users.subscription` | Media |
| **Tokens de dispositivo (FCM)** | `users.fcmTokens[]` | Media |
| **Gimnasio al que asiste** | `users.gymId`, `userPublicProfiles.gymId`/`gymName` | Media — ver §2.3.3 |

Los dos primeros bloques son los que más pesan: bajo la **Ley 25.326** los datos
referidos a la salud son **datos sensibles** (art. 2) con un régimen de
tratamiento propio (art. 7-8). La política los trata como si no existieran: los
mete dentro de "tus datos de entrenamiento" y los ampara en el consentimiento
genérico de la §3. Esto no es una omisión cosmética.

#### 2.3.2 Lo que la política promete y el código no cumple

**§6 Conservación** — *"Si la eliminás, borramos tus datos personales, salvo
aquello que debamos conservar por obligación legal."*

Es la divergencia más grande del documento. El código retiene, además de lo
fiscal:

- **`reviews` completo, incluido el `comment` de texto libre del alumno.** La
  justificación escrita en `athlete-data.ts:21` es *"rating RETAINED for the
  trainer's aggregate"* — pero para el agregado sólo hace falta el `rating`, no
  el comentario ni el `athleteId`. El alcance del código es más ancho que el de
  su propia decisión, y ninguna de las dos cosas es "obligación legal".
- **`chats` y `messages`** — decisión de producto (el otro participante conserva
  su conversación). Legítima, pero no es obligación legal.
- **`audit_log/{uid}`** — el uid y el método de login del usuario borrado quedan
  para siempre, sin período de retención definido.
- **Los 4 huecos y los 3 parciales sin decisión escrita de §2.2.2**, que no
  tienen ni siquiera decisión.

Además, la §6 **no declara ningún plazo**: ni de la cuenta activa, ni de lo que
se retiene después del borrado. "Mientras mantengas tu cuenta" no es un período
de conservación.

**§7 Tus derechos** — *"Podés acceder, rectificar, actualizar y solicitar la
supresión de tus datos... desde la app."*

La supresión existe (`deleteAccount`) y la rectificación también. **El acceso no
está implementado**: no hay ninguna función de exportación ni de descarga de
datos en `functions/src/` ni en `lib/`. El derecho de acceso del habeas data
sólo se puede ejercer por email.

**§5 Con quién compartimos** — nombra a Google Firebase y a los entrenadores.
**No nombra** a los encargados de tratamiento que el código sí usa:

- **Resend** — email transaccional (`functions/src/mail/send-queued-mail.ts`,
  secret `RESEND_API_KEY`)
- **Google Places API** — `functions/src/places-search.ts`
- **Firebase Crashlytics** y **Firebase Analytics** (`pubspec.yaml:20-21`) —
  técnicamente son Google, pero son productos distintos con su propio
  tratamiento; la §1 declara "analítica" sin decir de quién

#### 2.3.3 Divergencia de ubicación (las dos direcciones)

**§4 Ubicación** — *"Tu ubicación no es visible para otros usuarios."*

Es literalmente cierto para las coordenadas del `geolocator` (nunca se
persisten para el alumno), pero **`userPublicProfiles/{uid}` guarda `gymId` y
`gymName` y lo lee cualquier autenticado**. El gimnasio al que alguien asiste es
una ubicación habitual, y encima los rankings son *por gym*. La frase, tal como
está escrita, le da al usuario una expectativa que el modelo de datos no
sostiene. Y para el PF es más directo: `trainerLocations[]` y
`trainerGeohashes[]` se publican en `trainerPublicProfiles`.

#### 2.3.4 Declarado pero no guardado

Buscado a propósito, porque una política que promete de más también es un
problema: **no encontré ninguna categoría declarada que el código no guarde**.
`firebase_analytics` y `firebase_crashlytics` están en `pubspec.yaml`, así que
la "analítica" y los "datos técnicos del dispositivo" de la §1 son reales.

Nota aparte: #680 menciona *"fotos de progreso"* entre los datos sensibles.
**No existe ese path** — `measurements` no tiene campo de foto y `storage.rules`
no declara nada parecido. Lo más cercano son `postPhotos` (fotos de posts) y las
imágenes que el PF sube a `athleteFiles`.

---

### 2.4 Huecos de borrado detectados

Tocar un cascade de borrado es una operación destructiva: cada uno necesita su
propio change, su propio test contra el emulador y su propia revisión. Acá
quedan documentados con precisión para que cada uno salga como ticket.

Se numeran siguiendo la convención `QA-CMP-xxx` que ya usan
`cascade/storage.ts` (QA-CMP-002) y `cascade/athlete-data.ts` (QA-CMP-003).
Los que se cierren después quedan **tachados acá con la referencia al PR que
los cerró**, no borrados — la §2.6 regla 3 lo pide así, y el historial de qué
se decidió y por qué es la mitad del valor de esta lista.

**Estado:** ~~QA-CMP-004b~~ y ~~QA-CMP-005b~~ están **cerrados** ([#754](https://github.com/Backhaus7997/treino/pull/754)) — los dos
salían del mismo comentario desactualizado en `cascade/posts.ts` y se
arreglaron juntos. El diagnóstico queda escrito abajo porque explica por qué
existieron. Los otros ocho siguen **abiertos**.

---

~~**QA-CMP-004 — `routines` no se borra, y hay un guard que asume que sí.**~~
**CERRADO — PR #753.**

~~`runDeleteAccount` no tiene ningún paso sobre `routines`. Sobreviven las
rutinas con `createdBy == uid` y —peor— las privadas con `assignedTo == uid`,
que son los planes que el PF le armó a ese alumno.~~

~~Lo que lo convierte en un hueco de contrato y no en un olvido: el trigger
`cleanupAssignedPlansOnUnlink` **se saltea explícitamente** el caso,
delegándolo en un paso que no existe (`cleanup-assigned-plans.ts:110-113`), y
`"account-deleted"` es exactamente el `reason` que escribe
`terminateTrainerLinks`. O sea: el único mecanismo que habría barrido esos
planes se apagaba justo cuando hacía falta.~~

El paso existe: `cascade/routines.ts` → `deleteAthleteRoutines`, step 8d del
cascade. La disposición quedó escrita en la cabecera del módulo, con las tres
decisiones separadas:

- `assignedTo == uid` → **borra**. Son los planes que el PF armó para ese
  alumno; es literalmente lo que el guard de `cleanupAssignedPlansOnUnlink`
  venía delegando.
- `createdBy == uid` → **borra**. El caso que la reparación sugerida marcaba
  como dudoso —"una plantilla pública que otros usan"— resultó no ser
  alcanzable por este predicado: las plantillas se llavean por `assignedBy`,
  no por `createdBy`, y un PF ni siquiera entra al cascade (guard de rol). Una
  rutina `user-created` con `visibility: 'public'` sí es legible por cualquier
  autenticado que tenga el id, pero la única superficie que las lista es
  `publicRoutinesByUserProvider`, la solapa RUTINAS PÚBLICAS del perfil
  público **de ese mismo usuario**, y `userPublicProfiles/{uid}` se borra en el
  mismo cascade. El catálogo tampoco las ve: `listSystemTemplates` filtra
  `source == 'system'` y `listPublishedTemplates` filtra
  `source == 'trainer-template'`.
- `assignedBy == uid` → **no se toca, a propósito**. El guard de rol lee
  `users/{uid}`; en un re-run idempotente posterior a un fallo parcial ese doc
  ya no existe y el guard **no puede dispararse**. Un barrido por `assignedBy`
  borraría entonces la biblioteca entera del PF y todos los planes de todos
  sus alumnos. El residuo que esto deja —una `trainer-template` forjada por un
  atleta, privada e impublicable— no justifica ese radio de daño. Hay un test
  que fija la no-eliminación para que nadie ensanche el predicado sin darse
  cuenta.

Usa `recursiveDelete`, no `batch.delete`, así que se lleva la subcolección
`ratings` del documento borrado. La otra mitad de QA-CMP-006 —las
puntuaciones que el usuario borrado dejó en plantillas **ajenas**— sigue
abierta: necesita un barrido `collectionGroup`, no estas dos queries.

---

**~~QA-CMP-004b — `postPhotos/{uid}/` queda huérfano en Storage.~~ CERRADO.**
`deletePosts` borraba los documentos; `deleteAthleteStorage` barría cinco
prefijos y **`postPhotos/` no estaba entre ellos**. Los objetos quedaban en el
bucket, con su download token vivo y `get` abierto a cualquier autenticado.

La causa raíz de los dos huecos es el comentario de cabecera que tenía
`cascade/posts.ts:5-6`, que afirmaba lo contrario:

> "Posts are flat documents with no subcollections and no Storage-backed media
> fields, so deleting the document is sufficient — there are no orphaned
> resources to chase."

Era cierto cuando se escribió y **había quedado falso en las dos mitades**. La
de Storage: `photoUrl` está en la allowlist de `firestore.rules:638` y `:675`, y
`post_photo_upload_service.dart:135` construye `postPhotos/{uid}/{postId}.{ext}`.
La de subcolecciones, en QA-CMP-005b.

*Arreglado en [#754](https://github.com/Backhaus7997/treino/pull/754):* `deleteAthleteStorage` barre ahora `postPhotos/{uid}/` como un
prefijo más, y el comentario de `posts.ts` quedó reescrito con las dos mitades
que se le habían quedado viejas. Cubierto por
`__tests__/cascade/storage.test.ts`, que asegura que **no queda ningún objeto**
bajo el prefijo y que la foto de otro atleta sobrevive.

---

**~~QA-CMP-005b — Las reacciones ajenas quedan huérfanas bajo el post
borrado.~~ CERRADO.**
`deletePosts` usaba `batch.delete(doc.ref)` sobre `posts/{postId}`, y **en
Firestore borrar un documento NO borra sus subcolecciones**. `posts` sí tiene
una: `posts/{postId}/reactions/{reactorUid}` (`firestore.rules:693`) — la otra
mitad falsa del comentario citado arriba.

O sea: cuando se borra la cuenta, cada reacción que **otras personas** dejaron
en los posts de ese usuario queda como documento huérfano bajo un padre que ya
no existe. Su doc id es el uid del que reaccionó, así que es dato personal de un
tercero que ningún borrado va a alcanzar nunca. Quedan además ilegibles desde el
cliente —`reactionPostReadable()` hace `get()` sobre el post inexistente y la
evaluación falla → deny— pero siguen en la base.

Es el hueco menos visible de todos, justamente porque no se puede leer.

*Arreglado en [#754](https://github.com/Backhaus7997/treino/pull/754):* `cascade/posts.ts` usa `db.recursiveDelete(doc.ref, bulkWriter)` en
lugar de `batch.delete(doc.ref)`, con un único `BulkWriter` compartido entre
todos los posts del usuario. Se perdió el batching manual de 400 docs y no pasa
nada: el `BulkWriter` del Admin SDK batchea y throttlea internamente.
`recursiveDelete` hace `flush()` del writer que recibe pero **no lo cierra**,
así que el `close()` final es lo que garantiza que los deletes bajaron.
Cubierto por `__tests__/cascade/posts.test.ts`, que lee la subcolección con el
Admin SDK —que saltea las reglas, justamente porque desde el cliente estos
huérfanos son invisibles— y verifica que no quede ni un documento ni la
subcolección misma.

---

**QA-CMP-005 — Reacciones en posts ajenos.** `posts/{postId}/reactions/{uid}`
usa el uid del que reacciona **como doc id**, dentro del post de otra persona.
El `recursiveDelete` de `deletePosts` sólo alcanza las reacciones que cuelgan de
los posts **del usuario borrado** (QA-CMP-005b); las que ese usuario dejó en
posts ajenos cuelgan de documentos que el cascade no toca, y no hay ningún paso
que las busque. Queda el uid publicado, legible por cualquiera que pueda leer el
post, y `maintainReactionCounters` lo sigue contando. `allow delete` sólo lo
permite al propio `reactorUid`, que ya no existe.

---

**QA-CMP-006 — Puntuaciones de plantillas.** `routines/{id}/ratings/{userId}`:
uid como doc id, `comment` de texto libre de hasta 500 caracteres, `allow read`
a cualquier autenticado y **`allow delete: if false`** (`firestore.rules:494`).
Ni el usuario ni el cascade pueden borrarlo; sólo el Admin SDK. Y
`templateRatingAggregate` lo sigue promediando.

---

**QA-CMP-007 — `friendships` legacy.** `sweepFollows` barre `follows`. La
colección anterior, `friendships`, está **congelada pero intacta**: la decisión
`ADR-FOLLOW-012` conserva el `read` y los datos a propósito, para poder revertir
la migración (`firestore.rules:1088-1123`). Mientras esos documentos existan,
cada uno guarda `members[]` con el uid del usuario borrado y el otro miembro los
sigue leyendo. El cascade no los toca.

*Nota:* el impacto real depende de si quedan documentos en producción. Hay que
medirlo antes de decidir — si la migración ya está consolidada, el arreglo
correcto probablemente sea retirar la colección, no agregarle un barrido.

---

**QA-CMP-008 — Historial de notificaciones en el inbox de terceros.**
`sendFcm` escribe una copia en `users/{destinatario}/notifications` con
`actorUid` y con el nombre del actor **interpolado en el texto del `body`**:

```ts
// functions/src/notifications/notify-friendship.ts:151
return `${displayName} empezó a seguirte`;
```

El `recursiveDelete` se lleva el inbox propio del usuario borrado, pero no las
copias que ese usuario generó en los inboxes ajenos. No hay TTL —
`send-fcm.ts:16` lo dice de frente:

```ts
// TODO(notification-retention): configure Firestore TTL or scheduled cleanup
```

El destinatario sigue viendo el nombre de una cuenta que ya no existe.

---

**QA-CMP-009 — `appointments.athleteDisplayName` sobrevive en todos los turnos.**
`cancelFutureAppointments` filtra por `startsAt > now()` y sólo escribe
`status` y `reason`. Consecuencias:

1. Los turnos **pasados** no se tocan nunca (integridad histórica, deliberado).
2. Ni los pasados ni los futuros pierden `athleteDisplayName` —el nombre real
   denormalizado (`appointment.dart:44`)— ni `noteBefore` / `noteAfter`.
3. `allow read` sigue habilitado para `resource.data.trainerId`, y
   `allow delete: if false` (`firestore.rules:1649`).

O sea: después del borrado, el PF sigue viendo el nombre completo del alumno y
las notas de coaching en su agenda, indefinidamente. Es el residuo más visible
de todos, porque tiene una UI que lo muestra.

---

**QA-CMP-010 — `mail_queue` sin barrido ni TTL.** Cada fila guarda `toUid` y un
mapa `params` con los datos que la plantilla necesita (montos, nombres,
conceptos). El cascade no la toca y no hay job de limpieza. La dirección de
email no queda —se resuelve desde Auth al enviar, y Auth ya no tiene al
usuario— pero el uid y los parámetros sí.

---

**QA-CMP-011 — No existe ninguna vía de supresión para una cuenta trainer.**
`deleteAccount` rechaza `role === 'trainer'` con `permission-denied`, y no hay
ningún otro camino, ni de cliente ni de servidor. Un PF tiene en el sistema:
`users/{uid}` (con teléfono, alias de pago, ubicaciones), `trainerPublicProfiles`,
`coach_availability_rules`/`overrides`, `gyms.createdBy`, y es el `recordedBy` /
`trainerId` de decenas de documentos sobre sus alumnos. Hoy nada de eso se
puede suprimir a pedido. No es un bug del cascade: es una funcionalidad que no
existe, y la §7 de la política no la excluye.

---

### 2.5 Retención

No hay ninguna política de retención implementada en el repo. Ni un TTL de
Firestore configurado, ni un job programado de limpieza (el único `onSchedule`
es `sweepEntitlements`, que es de suscripciones, no de retención).

| Dato | Retención de hecho hoy | Retención declarada |
|---|---|---|
| Todo lo del §1 mientras la cuenta vive | Indefinida | "mientras mantengas tu cuenta" (§6) |
| `payments` post-borrado | Indefinida | No declarada |
| `reviews` (con `comment`) post-borrado | Indefinida | No declarada |
| `chats` / `messages` post-borrado | Indefinida | No declarada |
| `audit_log/{uid}` | Indefinida | No declarada |
| `users/*/notifications` | Indefinida — TODO abierto | No declarada |
| `mail_queue` | Indefinida | No declarada |

Definir plazos es una decisión de producto y legal, no de ingeniería, así que
este documento no propone números. Sí deja anotado que **hoy no hay ninguno**.

---

### 2.6 Cómo mantener este inventario

Mismo contrato que la matriz de §1.8: **el PR que
cambia el dato actualiza el documento**.

1. **Campo nuevo con PII en una colección existente** → fila actualizada en §2.1.1
   o §2.1.2, y revisar si el cascade que ya cubre esa colección lo alcanza.
2. **Colección o path de Storage nuevo** → fila nueva en §2.1, fila nueva en la
   tabla de cobertura de §2.2.1 y **recalcular los conteos de §2.2.2**. Son
   conteos, no impresiones.
3. **Paso nuevo en el cascade** → mover el ítem a ✅ en §2.2.1 y, si cierra un
   `QA-CMP-xxx`, tacharlo en §2.4 dejando la referencia al PR.
4. **Retención o categoría nueva** → si cambia lo que se declara al usuario,
   el mismo PR toca `kPrivacySections` en
   `lib/features/auth/presentation/legal/legal_content.dart` y sube
   `kLegalLastUpdated`.

Verificación mínima antes de dar un ítem por cubierto: correr el borrado contra
el emulador y comprobar la **ausencia** del documento o del objeto, no la
presencia de su nombre en `deletedCollections`. La diferencia entre las dos
cosas es exactamente lo que este documento encontró.

```bash
npm --prefix functions run test          # incluye delete-account.smoke + cascade/*
npm --prefix functions run test:rules:emulator   # requiere Java 21+
```

---

## 3. Lecturas amplias en Storage — decisión path por path

### 3.0 Por qué existe y cómo se midió

`storage.rules` declara tres bloques que permiten lectura a **cualquier usuario
autenticado**: `avatars/`, `customExerciseVideos/` y `postPhotos/`. Es el punto
5 del issue #680, y §1.6 lo dejó abierto a propósito: *testear un permiso amplio
antes de decidir si es deliberado congela el status quo*. Esta sección es la
decisión que faltaba.

La pregunta no es "¿el nombre del path suena sensible?" sino cuatro preguntas
concretas, respondidas **path por path**: quién puede leer hoy exactamente, qué
se expone si un autenticado enumera o adivina, si eso es coherente con lo que el
producto le promete al usuario, y —la que decide todo— si el permiso es
deliberado o es un agujero.

**Cómo se midió.** Nada de esta sección sale de leer la regla y deducir. Se
escribió una suite-sonda temporal que ejecuta cada combinación
`(actor × operación × path)` contra el **emulador de Storage** y reporta
ALLOW/DENY en vez de afirmar, de modo que una sola corrida imprime la matriz
entera. Los actores fueron: dueño del objeto, otro usuario autenticado, anónimo,
y un uid que es *prefijo estricto* del uid dueño. La matriz resultante está en
§3.5 y es la fuente de todo lo que sigue. La sonda no quedó en el repo — lo que
quedó son los tests de §3.7, que pinean sólo lo ya decidido.

> Requiere Java 21. Si `java -version` dice menos, exportá uno que sirva antes
> de correr nada: `export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"`.

### 3.1 El hallazgo que reordena la pregunta: la URL con token no pasa por las reglas

Antes de juzgar los tres bloques hay que corregir una premisa que está escrita
en los comentarios de `storage.rules` y que resultó **falsa**.

El comentario de `customExerciseVideos` dice que cualquier autenticado puede
leer *"so the trainer's athletes can play them inline"* — es decir, presenta la
lectura amplia como un requisito funcional del reproductor. **No lo es.**

Medición, contra el emulador:

| Caso | Resultado |
|---|---|
| `GET` de la URL `?alt=media&token=…`, **sin ningún header de auth** | **HTTP 200**, devuelve los bytes |
| La misma URL con el `&token=` sacado, sin auth | HTTP 403 |

La URL de descarga que emite `getDownloadURL()` es una **credencial al portador**:
lleva su propio token y **no evalúa `storage.rules`**. Y así es exactamente como
la app renderiza: los **8** call sites de `getDownloadURL()` en `lib/` son
`task.ref` / `snapshot.ref`, o sea el **dueño inmediatamente después de subir**.
Ninguno resuelve el objeto de otro usuario. La URL resultante se persiste en
Firestore y de ahí la leen los consumidores:

| Path | Dónde vive la URL | Quién lee ese doc |
|---|---|---|
| `avatars/` | `users/{uid}.avatarUrl` + `userPublicProfiles/{uid}.avatarUrl` (y `trainerPublicProfiles` cuando corresponde) | `userPublicProfiles`: cualquier autenticado (`firestore.rules:780`) |
| `customExerciseVideos/` | `users/{tid}/customExercises/{id}.videoUrl` | cualquier autenticado (`firestore.rules:1575`) |
| `postPhotos/` | `posts/{postId}.photoUrl` | según `posts.privacy` (`firestore.rules:624-633`) |

Los widgets (`TreinoAvatar` → `NetworkImage`, `PostCard` → `CachedNetworkImage`,
`ExerciseVideoPlayer`) reciben ese string HTTPS y lo bajan. **Nunca**
reconstruyen un `ref()` ni un `gs://` para leer.

Dos consecuencias que mandan sobre toda la sección:

1. **El `allow read` amplio no es lo que hace andar la app.** Se podría apretar
   a owner-only y el renderizado no se enteraría: el que sube igual puede mintear
   su URL (lo hace como dueño), y el que mira nunca consulta la regla. El permiso
   amplio es superficie de ataque que no compra funcionalidad.
2. **Por lo tanto, el `get` amplio no se justifica "porque si no se rompe la
   app".** Si se lo quiere conservar, hay que justificarlo por otra cosa. Es lo
   que se hace path por path abajo.

> ⚠️ Corolario incómodo, fuera del alcance de este slice: como el token es una
> credencial al portador y no caduca, **cualquiera que haya visto una URL de
> `postPhotos` alguna vez la sigue pudiendo bajar aunque después el post pase a
> privado o se borre el doc**. Apretar las reglas de lectura no lo arregla; lo
> único que lo corta es rotar el token del objeto o borrarlo. Vale como entrada
> del threat model, no como acción de esta sección.

### 3.2 `avatars/{uid}.{ext}`

```
match /avatars/{fileName} {
  allow get: if request.auth != null;
  allow list: if false;                                      // ← QA-SEC-007, #764
  allow write: if request.auth != null
              && fileName.matches(request.auth.uid + '\\..+')
              && request.resource.size < 5 * 1024 * 1024
              && request.resource.contentType.matches('image/.*');
  allow delete: if request.auth != null                      // ← QA-SEC-009, #765
                && fileName.matches(request.auth.uid + '\\..+');
}
```

> **Estado:** este bloque tenía los dos huecos de `avatars/`. El `list` abierto
> era el leak QA-SEC-007, **cerrado en #764**; el `delete` roto era QA-SEC-009,
> **arreglado en #765**. Lo que sigue es la medición **previa** a esos
> arreglos, que es lo que los justifica; el estado actual está en la fila
> re-medida de §3.5.

**Quién leía, exactamente.** `read` en Storage es `get` **+** `list`, y acá
no había nada que los separara. Medido **antes de #764**: un autenticado
cualquiera hacía `get` del avatar de otro (ALLOW) **y también
`listAll('avatars/')` (ALLOW)**, que devolvió la lista completa de objetos del
prefijo. El anónimo quedaba afuera en ambos casos.

> Ojo con la intuición del match: `match /avatars/{fileName}` pide dos
> segmentos, así que uno esperaría que listar el prefijo `avatars/` —un solo
> segmento— cayera en el catch-all, como pasa con `postPhotos/` (§3.4). No es
> así: para un `list`, el motor evalúa el prefijo **más un segmento comodín**,
> o sea `avatars/{fileName}`, que es exactamente este bloque. Por eso el
> `allow list: if false` de acá **sí** cierra la enumeración de la raíz, y por
> eso en `postPhotos` hace falta el catch-all para el mismo efecto. Está
> pineado por test en los dos archivos.

**Qué expone la enumeración.** El nombre del archivo **es el uid**
(`avatars/{uid}.{ext}`). Enumerar `avatars/` no devuelve "unas fotos": devuelve
el **padrón de uids que alguna vez subieron avatar**, en una sola llamada.

- *Atenuante:* `userPublicProfiles/{uid}` ya es `allow read: if request.auth != null`
  para `get` **y** `list` (`firestore.rules:776-780`, deliberado: habilita la
  búsqueda por prefijo de `searchByDisplayName`). Los uids **ya son enumerables**
  hoy por Firestore. El comentario de `chatMedia` en `storage.rules` lo dice con
  todas las letras. O sea: `avatars/` list **no** es la primera puerta.
- *Agravante:* no es la misma puerta. `avatars/` enumera una población
  **distinta** — la de objetos que **existen en el bucket**, que incluye a los
  usuarios que "quitaron" su foto (ver el bug de abajo: nunca se borra) y a
  cuentas cuyo `userPublicProfiles` haya cambiado. Y es un canal que sobrevive a
  cualquier endurecimiento futuro de `userPublicProfiles`: si mañana se cierra
  el `list` de Firestore, `avatars/` lo sigue filtrando y nadie se va a acordar.

**¿Coherente con lo que promete el producto?** La Política de Privacidad
(`kPrivacySections` §1, `legal_content.dart:119-125`) declara la
*"foto/avatar si la cargás"* entre los datos de cuenta, y el avatar se muestra
en feed, chat, reviews y rankings a cualquier autenticado. **Que el contenido
del avatar sea legible por cualquier autenticado no contradice nada.** Que el
*directorio* sea enumerable no está declarado ni es necesario — pero tampoco
agrega una categoría de dato que la política no cubra.

**Veredicto:**

| Operación | Veredicto |
|---|---|
| `get` | **Deliberado y defendible**, pero **redundante** (§3.1): el avatar ya viaja por `userPublicProfiles` a la misma audiencia. Se conserva; no se justifica por necesidad técnica sino porque no expone nada nuevo. |
| `list` | ~~**NO deliberado — leak.**~~ Ningún comentario lo mencionaba, ningún cliente lo usa, y los dos bloques vecinos que sí lo pensaron (`chatMedia`, `postPhotos`) lo cierran explícitamente. Severidad **baja** por el atenuante de arriba, pero era un canal de enumeración gratuito. → **QA-SEC-007 — CERRADO en #764** con `allow list: if false`. |
| `write` | **Deliberado y correcto.** Owner-only, anclado, sólo imágenes, 5 MB. Pineado en §3.7. |
| `delete` | ~~**ROTO**~~ — ver abajo. → **QA-SEC-009 — ARREGLADO en #765** con un `allow delete` propio, anclado al uid igual que el `write` y sin tocar `request.resource`. |

#### 3.2.1 El `delete` de avatars estaba roto, y fallaba en silencio

> **Arreglado en #765.** Esta sub-sección se conserva como diagnóstico: es la
> evidencia de por qué la regla 3 de §3.8 existe, y el motivo por el cual el
> test del bloque trae un **positivo del dueño** y no sólo negativos.

El bloque **no declaraba `allow delete`**. En Storage, `delete` cae bajo
`write`, cuya condición dereferencia `request.resource.size` — y en un `delete`
**`request.resource` es null**. El emulador lo decía con el dedo en la línea:

```
EvaluationException: Error: storage.rules line [13], column [22]. Null value error.
```

Esa línea 13 era exactamente `&& request.resource.size < 5 * 1024 * 1024` (hoy
está más abajo en el archivo: los comentarios que documentan `get`/`list`/
`delete` la corrieron).

Medido: **el dueño no podía borrar su propio avatar** (DENY). No era un agujero
—fallaba cerrado— pero sí era un bug de producto, y tenía una víctima concreta:

- `avatar_web_uploader.dart` (`deleteStored()`) borraba
  `avatars/{uid}.jpg` **best-effort, dentro de un `catch (_) {}` vacío**.
- Lo llama `cuenta_tab.dart` (`_removePhoto`, el botón "Quitar foto" de
  Coach Hub), con el comentario *"no dejar el objeto huérfano en
  `avatars/{uid}.jpg`"*.

El `delete` se denegaba **siempre**, el `catch` se lo comía, el usuario veía el
toast *"Foto quitada"*, y el objeto **seguía en el bucket**: bajable por su URL
con token (que es una credencial al portador, §3.1) y enumerable por cualquier
autenticado (el leak de arriba). La única limpieza real que existía era
`deleteAvatar` del cascade de borrado de cuenta, que corre con **Admin SDK** y
por eso no pega contra esta regla — y que barre *"cualquier extensión"*
(QA-CMP-002) justamente porque sabe que quedan huérfanos.

Dicho de otra forma: **la app no tenía forma de borrar un avatar salvo borrando
la cuenta entera**. Contra la §7 de la política (*"podés... solicitar la
supresión de tus datos... desde la app"*), era una divergencia real, del mismo
tipo que las de §2.3.2.

El arreglo fue chico y conocido — separar el `delete` del `write`, como ya
hacen `customExerciseVideos`, `chatMedia`, `athleteFiles` y `postPhotos`:

```
allow delete: if request.auth != null
              && fileName.matches(request.auth.uid + '\\..+');
```

**Aplicado en #765**, junto con las dos mitades que hacían falta para que el
arreglo sea visible:

- **La regla**, arriba. Anclada con el mismo `matches()` full-match que el
  `write`, así que un uid que es prefijo estricto del dueño tampoco borra.
- **El cliente.** `deleteStored()` dejó de tener el `catch (_) {}` vacío: ahora
  tolera sólo `object-not-found` —que no haya objeto ES el estado deseado del
  usuario— y **propaga cualquier otro error**, que es el idiom que ya usaban
  `PostPhotoUploadService`, `ChatMediaUploadService`, `AthleteFileRepository` y
  `CustomExerciseVideoUploadService`. `_removePhoto` borra el objeto **antes**
  de limpiar `avatarUrl`, así que si el borrado falla de verdad el usuario ve
  *"No se pudo quitar la foto"* y no una referencia limpia sobre un objeto
  huérfano.
- **El test**, que es la parte que §1.8 vuelve obligatoria: el **positivo del
  dueño**. Los negativos (ajeno, prefijo, anónimo) ya denegaban antes del
  arreglo, pero por el crash, no por el gate — habrían pasado *por el motivo
  equivocado*. El positivo es el único caso que separa las dos cosas.

### 3.3 `customExerciseVideos/{uid}/**`

```
match /customExerciseVideos/{userId}/{file=**} {
  allow get: if request.auth != null;
  allow list: if false;                                   // ← QA-SEC-008, #763
  allow write: if ... uid == userId ... 100 MB ... video/*
  allow delete: if request.auth != null && request.auth.uid == userId;
}
```

> **Estado:** el `list` de este bloque estaba abierto y es el leak QA-SEC-008.
> **Cerrado en #763.** Lo que sigue describe cómo se midió y por qué se
> decidió así; la columna "medido" de la tabla de abajo es el estado **previo**
> al arreglo, que es lo que justifica el cambio. El estado actual está en la
> fila re-medida de §3.5.

**Quién leía, exactamente.** Igual que avatars, `read` no separaba `get` de
`list`. Pero acá el wildcard es `{file=**}`, así que la enumeración era peor.
Medido **antes de #763**, con un autenticado cualquiera (**no** el dueño,
**no** un alumno vinculado):

| Operación | Resultado medido |
|---|---|
| `getBytes(customExerciseVideos/{otro}/clip.mp4)` | ALLOW |
| `listAll(customExerciseVideos/{otro})` | **ALLOW** — devolvió `items=[clip.mp4]` y `prefixes=[…/nested]` |
| `listAll(customExerciseVideos/)` ← **la raíz** | **ALLOW** — devolvió `prefixes=[customExerciseVideos/{uid}]` |
| lo mismo, anónimo | DENY |

**Qué expone.** Dos cosas distintas, y las dos son peores que en avatars:

1. **Listar la raíz devuelve el uid de cada PF que subió videos.** Es un
   directorio de "qué entrenadores tienen contenido propio" que no existe en
   ninguna otra parte del producto.
2. **Listar la carpeta de un PF devuelve su videoteca entera**, recursivamente.
   No hace falta adivinar nombres de archivo ni conocer un solo
   `customExercises/{id}`: se enumera y se baja. Para un PF, esos videos son el
   activo que lo diferencia. Un competidor con una cuenta de atleta gratis se
   lleva la biblioteca completa de otro PF.

Y la enumeración alcanza **más** que Firestore: `users/{tid}/customExercises/{id}`
sólo apunta a los videos **vigentes**. El `list` del bucket ve también los
huérfanos — ejercicios borrados cuya limpieza best-effort
(`custom_exercise_repository.dart:97-113`) falló.

**¿Coherente con lo que promete el producto?** El comentario de la regla dice
que la lectura amplia existe para que *"the trainer's athletes"* puedan
reproducir inline. Dos problemas: (a) el reproductor **no usa la regla**
(§3.1), y (b) aunque la usara, la regla no dice "los alumnos del PF" — dice
**cualquier autenticado**. El `get` amplio sí es coherente con la postura de
Firestore (`customExercises` es legible por cualquier autenticado,
`firestore.rules:1575`), así que el **contenido** de un video no es más secreto
que el doc que lo referencia. El **inventario** sí lo es: no hay ningún doc de
Firestore que lo publique.

**Veredicto:**

| Operación | Veredicto |
|---|---|
| `get` | **Deliberado.** El motivo escrito en el comentario era incorrecto y **se corrigió en #763**. Consistente con `firestore.rules:1575`. Se conserva. |
| `list` | ~~**NO deliberado — leak, y el peor de los tres.**~~ Exfiltración de la videoteca completa de un PF + directorio de qué PFs tienen contenido. Ningún cliente llama `list`. → **QA-SEC-008 — CERRADO en #763** con `allow list: if false`. |
| `write` | **Deliberado y correcto.** Owner-only a cualquier profundidad, sólo video, 100 MB. Pineado en §3.7. |
| `delete` | **Deliberado y correcto.** Tiene su propio `allow delete` — por eso funciona. Es el bloque que sirvió de modelo para arreglar `avatars` en #765 (§3.2.1). Pineado en §3.7. |

### 3.4 `postPhotos/{uid}/{postId}.{ext}` — el modelo a seguir

```
match /postPhotos/{userId}/{fileName} {
  allow get: if request.auth != null;
  allow list: if false;
  allow write: if ... uid == userId ... 15 MB ... image/*
  allow delete: if request.auth != null && request.auth.uid == userId;
}
```

Medido: `get` cruzado ALLOW; `listAll(postPhotos/{uid})` **DENY**;
`listAll(postPhotos/)` **DENY** (esta última no la cubre el `allow list: if false`
—ese match pide dos segmentos— sino el catch-all `{allPaths=**}`).

**Veredicto: deliberado, correcto y ya documentado en el propio archivo.** Este
bloque hace explícito lo que los otros dos dejan implícito: separa `get` de
`list`, cierra `list` incondicionalmente, y explica *por qué* el `get` amplio
está bien — la visibilidad real del post la gobierna `firestore.rules` sobre
`posts/`, y la URL con token sólo viaja dentro del doc del post. Esa afirmación
quedó **confirmada** por la medición de §3.1.

Es el patrón al que hay que llevar `avatars` y `customExerciseVideos`.

Única mejora aplicada en este PR: el test del bloque cubría
`listAll(postPhotos/{uid})` pero no la **raíz** `postPhotos/`. Se agregó, porque
si alguien introdujera un `match /postPhotos/{p=**}` descuidado, la enumeración
de uids se abriría y ningún test se pondría rojo.

### 3.5 La matriz medida

Todo lo de arriba, en una tabla. **ALLOW/DENY son resultados del emulador**, no
lecturas de la regla. Actor = usuario autenticado que **no** es el dueño, salvo
donde se aclara.

| Path | `get` ajeno | `list` (carpeta) | `list` (raíz) | `write` ajeno | `delete` dueño | `delete` ajeno |
|---|---|---|---|---|---|---|
| `avatars/` | ALLOW | ~~ALLOW~~ → **DENY** ✅ | n/a (un nivel) | DENY | ~~DENY 🐛~~ → **ALLOW** ✅ | DENY |
| `customExerciseVideos/` | ALLOW | ~~ALLOW~~ → **DENY** ✅ | ~~ALLOW~~ → **DENY** ✅ | DENY | ALLOW | DENY |
| `postPhotos/` | ALLOW | DENY | DENY | DENY | ALLOW | DENY |
| `chatMedia/` | DENY (no miembro) | DENY | DENY | DENY | — | DENY |
| `temp/uploads/` | DENY | DENY | DENY | DENY | ~~—~~ → **DENY** ✅ | DENY |
| catch-all `/` | — | — | DENY | — | — | — |

Anónimo: **DENY en todas las celdas de todos los paths**. El piso está bien.

⚠️ = leak sin decisión previa. 🐛 = deniega, pero por un null deref, no por
falta de permiso. ~~Tachado~~ = valor medido **antes** del PR que cerró la
celda; el valor después de la flecha es la re-medición contra el
`storage.rules` actual, como pide §3.8 regla 5. Las celdas `list` de
`customExerciseVideos/` se re-midieron en **#763** y la de `avatars/` en
**#764**: las tres son ahora DENY también para el **dueño** (la regla es
`if false`, no owner-only). La celda `delete dueño` de `avatars/` se re-midió
en **#765**: pasó de DENY-por-crash a ALLOW-por-permiso, que es el punto del
ticket — el 🐛 no era un permiso mal puesto sino una evaluación que explotaba.

`chatMedia` y `temp/uploads` se midieron sólo como control — están fuera del
alcance de este slice y salieron cerrados en todos los casos probados, lo que
confirma que el endurecimiento de `chatMedia` (Slice A / AD-2) hace lo que dice.

**Re-medición de `temp/uploads` (#804, QA-SEC-015).** Como pide la regla 5 de
§3.8, la fila se volvió a medir cuando el bloque cambió, no se heredó. Las cinco
celdas que ya eran DENY siguen DENY, pero **por otro motivo**: antes el ajeno
rebotaba contra `request.auth.uid == userId` y el `read: if false`; ahora rebota
contra un bloque cerrado en las cuatro operaciones. La celda `delete dueño` sale
de `—` a DENY —y deniega **por permiso**, no por el null deref de QA-SEC-009:
este bloque no dereferencia `request.resource`—.

Ojo con leer esta fila como "acá no cambió nada". **El hallazgo de QA-SEC-015
nunca estuvo en esta tabla**: el actor de §3.5 es el que **no** es dueño, y lo
que estaba abierto era el `write` del **dueño sobre su propia carpeta**. Esa
celda vive en la tabla de §4.9, y ahí es donde se ve el ALLOW → DENY.

### 3.6 Veredicto y tickets

**Dos de los tres paths tienen un leak real, y ninguno de los dos se arregla en
el PR que escribió esta sección (#680 Slice E).** Cambiar una regla de lectura
de Storage puede romper avatares o videos en producción; cada uno necesita su
propio change, su test y su verificación.

| ID | Qué | Path | Severidad | Arreglo propuesto |
|---|---|---|---|---|
| ~~**QA-SEC-007**~~ | `list` abierto a cualquier autenticado; enumera el padrón de uids con avatar | `avatars/` | Baja — los uids ya son enumerables por `userPublicProfiles` (`firestore.rules:780`), pero es un canal paralelo que sobrevive a cerrar aquél | **CERRADO en #764** (issue #764): `read` separado en `get` + `list`, `allow list: if false` |
| ~~**QA-SEC-008**~~ | `list` abierto en carpeta **y raíz**; exfiltra la videoteca entera de un PF y el directorio de qué PFs tienen contenido | `customExerciseVideos/` | **Media-alta** — no hay ninguna otra vía para obtener el inventario, y el contenido es el activo del PF | **CERRADO en #763** (issue #763): `read` separado en `get` + `list`, `allow list: if false`, comentario del bloque corregido (justificaba la lectura amplia con un motivo falso — §3.1) |
| ~~**QA-SEC-009**~~ | `delete` denegado hasta para el dueño por null deref en el `write`; "Quitar foto" miente y el objeto queda huérfano | `avatars/` | Media — no es un agujero (falla cerrado) pero incumple la §7 de la política y deja objetos legibles que el usuario cree borrados | **CERRADO en #765** (issue #765): `allow delete` propio como en los otros cuatro bloques (§3.2.1), `catch (_) {}` de `deleteStored()` acotado a `object-not-found`, y test positivo del dueño además de los negativos |

Los tres son chicos y bien acotados. **QA-SEC-008 es el que yo haría primero.**
Y así se hizo: cerró en #763, seguido de QA-SEC-007 (#764) y QA-SEC-009 (#765).
**Los tres están cerrados.**

Nota de alcance: cerrar `list` en los dos paths es **seguro para el cliente** —
no existe ni una llamada a `listAll()` / `list()` del SDK de Storage en todo
`lib/`. Lo único que enumera el bucket es `functions/src/cascade/storage.ts`,
con `bucket.getFiles({ prefix })` del **Admin SDK**, que ignora estas reglas por
completo (ADR-ACCDEL-013). O sea: el cascade de borrado no se ve afectado.

### 3.7 Qué se testeó en este PR, y qué NO — a propósito

Se agregaron `avatars-storage-rules.test.ts` y
`custom-exercise-videos-storage-rules.test.ts`, más un caso a
`post-photos-storage-rules.test.ts`. **29 tests, todos verdes.**

**Sí se pinea** lo que ya estaba decidido y es correcto: el gate de escritura de
los dos bloques (owner-only, tipo de contenido, y en `avatars` el anclaje del
regex), el `delete` owner-only de `customExerciseVideos`, y el piso anónimo de
`get` y `list` en ambos.

**No se pinea, a propósito:**

- **El `list` autenticado de `avatars` y `customExerciseVideos`.** Es el leak.
  Un `assertSucceeds` ahí congelaría el status quo, que es exactamente lo que
  §1.6 regla 1 dice que no hay que hacer. Cuando QA-SEC-007 y -008 cierren, esos
  `assertFails` van en los archivos que este PR dejó preparados con el comentario
  correspondiente.
  → **Al día de hoy los dos cerraron**: -008 en #763 y -007 en #764. Los
  `assertFails` viven en `custom-exercise-videos-storage-rules.test.ts`
  (carpeta y raíz, ajeno y dueño) y en `avatars-storage-rules.test.ts`
  (prefijo, ajeno y dueño).
- **El `delete` de `avatars`, en cualquier dirección.** Hoy "el ajeno no puede
  borrar" es **verdad por accidente**: se deniega por el null deref de
  `storage.rules:13`, no por un gate de dueño. Un test así pasaría *por el motivo
  equivocado*, y §1.8 lo prohíbe explícitamente. El test entra junto con
  QA-SEC-009, cuando la denegación sea por permiso.
  → **Al día de hoy: -009 cerró en #765.** El test entró con las dos
  direcciones y —lo que importa— con el **positivo del dueño** adelante: es el
  único caso que se pone rojo si alguien saca el `allow delete` y devuelve el
  bloque al null deref. Los negativos solos no lo detectarían.
- **Los bounds de tamaño (5 MB / 100 MB).** Empujar esos cuerpos por el emulador
  en cada corrida es lastre de CI puro, y es el mismo idiom
  `request.resource.size` que ya corre en los otros bloques. Mismo criterio que
  ya había tomado `post-photos-storage-rules.test.ts`.

**Verificación de mutación.** §1.8 pide que, antes de dar una celda por cerrada,
se afloje la regla y se compruebe que el test se pone rojo. Se hizo, con dos
mutaciones simultáneas:

1. `fileName.matches(request.auth.uid + '\\..+')` → `fileName.matches('.+\\..+')`
   (la escritura deja de estar atada al uid del caller).
2. `allow delete: if request.auth != null && request.auth.uid == userId;` →
   `allow delete: if request.auth != null;` (las tres ocurrencias).

Resultado: **exactamente 6 tests en rojo, y ninguno más** — los tres negativos
de escritura de `avatars`, los dos de `delete` ajeno de `customExerciseVideos`
(incluido el anidado) y el de `postPhotos`. Los 23 restantes siguieron verdes.
Cada negativo nuevo falla cuando —y sólo cuando— se afloja la regla que
custodia.

### 3.8 Cómo mantener esta sección

Mismo contrato que §1.8 y §2.6: **el PR que cambia la regla actualiza el
documento**.

1. **Bloque nuevo en `storage.rules` con lectura más amplia que el dueño** →
   entrada nueva acá con las cuatro preguntas de §3.0 respondidas **antes** de
   mergear. Un bloque con `allow read: if request.auth != null` y sin párrafo en
   §3 es, por definición de esta sección, un hueco.
2. **Nunca `allow read` a secas en un bloque nuevo.** Escribir `get` y `list` por
   separado, aunque los dos terminen con la misma condición. `read` esconde que
   `list` es un permiso distinto, y es la causa raíz de los dos leaks de §3.6.
3. **Toda regla con `request.resource.<algo>` necesita su `allow delete` propio**,
   o el borrado se rompe en silencio (§3.2.1). Es la lección de QA-SEC-009 y
   aplica a cualquier bloque futuro.
4. **Si se cierra un QA-SEC-00x de §3.6** → tacharlo ahí con la referencia al PR,
   no borrarlo (misma regla que §2.4), agregar el `assertFails` al archivo de
   test correspondiente y actualizar la celda en la matriz de §1.2.
5. **La medición no se hereda.** Los ALLOW/DENY de §3.5 valen para el
   `storage.rules` del día que se escribieron. Si tocás un bloque, volvé a correr
   la sonda; es media hora y evita razonar sobre reglas por su nombre.

```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"   # Java 21, macOS
npm --prefix functions run test:rules:emulator          # incluye los 3 de Storage
```

---

## 4. Threat model por actor

### 4.0 Por qué existe y cómo se midió

§1 dice qué operación no está testeada. §2 dice qué dato guardamos. §3 decide
tres bloques de Storage. Ninguna de las tres responde la pregunta que un
atacante se hace primero: **"soy X, ¿hasta dónde llego?"**.

Esta sección es esa respuesta, actor por actor. Los actores **no salen de un
template genérico** — salen del código: son las siete formas distintas en que
`firestore.rules` y `storage.rules` pueden ver a quien llama. Cada uno tiene su
apartado con tres columnas fijas: **qué puede leer**, **qué puede escribir**, y
**qué NO debería poder**.

**El valor de la sección no es el documento — es el cruce.** Escribir "el PF no
vinculado no ve nada del alumno" no vale nada si nadie lo probó. Lo que sigue
está medido.

**Cómo se midió.** Una sonda temporal —mismo método que §3.0— que ejecuta cada
combinación `(actor × operación × path)` contra el emulador de Firestore y de
Storage y **reporta ALLOW/DENY en vez de afirmar**, de modo que una sola corrida
imprime la matriz entera. **166 pruebas en tres corridas**: 110 de Firestore, 33
de Firestore + Storage, y 23 de re-verificación de los siete hallazgos y de los
pisos de control. Siete contextos de auth distintos. Todo lo que sigue está
medido contra `firestore.rules` y `storage.rules` en **`6149c6a6`** (2026-08-24).
La sonda no quedó en el repo; lo que queda es esta sección y los siete tickets
de §4.9.

> Requiere Java 21. Si `java -version` dice menos, exportá uno que sirva antes
> de correr nada: `export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"`.

Una aclaración de alcance, porque cambia cómo se leen las tablas: **las reglas
no son la única puerta.** §3.1 midió que la URL de descarga que emite
`getDownloadURL()` es una **credencial al portador** que no evalúa
`storage.rules`. Todo lo que esta sección dice sobre Storage vale para el acceso
*por referencia* (`ref()`, `list()`, `getMetadata()`); el que ya tiene una URL
con token la sigue pudiendo bajar aunque acá diga DENY.

### 4.1 Los siete actores

| # | Actor | Cómo lo ve la regla | Cómo se consigue |
|---|---|---|---|---|
| A1 | **Atleta** (dueño del dato) | `request.auth.uid == <el uid del dato>` | Signup público. Siempre nace `role: 'athlete'` (AGENTS.md regla 3, pineado por `firestore.rules:97`) |
| A2 | **Atleta ajeno / sin vínculo** | `request.auth != null` y ningún predicado de pertenencia da true | Cualquier signup. Es A1 mirando datos que no son suyos |
| A3 | **PF vinculado** | `resource.data.trainerId == uid`, o `session_shares/{aid}.trainerId == uid`, o `profile_shares/{aid}.trainerId == uid` | `role: 'trainer'` (sólo Admin SDK) **+** un `trainer_links` activo **+** el grant que corresponda |
| A4 | **PF NO vinculado** | `get(users/{uid}).data.role == 'trainer'` y nada más | `role: 'trainer'`. **El rol solo, sin vínculo, ya es un actor con permisos propios** — ver §4.5 |
| A5 | **Autenticado cualquiera** | literalmente `if request.auth != null` | Cualquier signup. **No es una persona: es el predicado.** Es el actor que encontró los leaks de §3 |
| A6 | **Anónimo / sin auth** | `request.auth == null` | Nada. Un cliente HTTP |
| A7 | **Cloud Function (Admin SDK)** | **no la ve** — bypassea las reglas por diseño (ADR-ACCDEL-013) | Deploy. Es la TCB del sistema |

A2 y A5 se parecen pero **no son el mismo actor y conviene no fusionarlos**. A2
es una persona concreta que intenta llegar al dato de otra persona concreta; A5
es la audiencia que una regla se dio a sí misma cuando escribió
`if request.auth != null`. Cada `ALLOW` de A5 es una decisión de publicar algo a
toda la base de usuarios, la haya tomado alguien o no. Las tres de §3.6 no las
tomó nadie.

Dos actores del enunciado clásico faltan a propósito:

- **"Cuenta comprometida"** no es un actor separado: es A1 con otra persona
  atrás. Su alcance es exactamente el de §4.2, y por eso ese apartado importa
  aunque suene trivial.
- **"Atleta de otro gym"** no es un actor separado tampoco: el `gymId` **no es
  un límite de autorización** en ninguna regla salvo una — el branch
  `privacy == 'gym'` de `posts` (`firestore.rules:745`). Para todo lo demás, un
  atleta de otro gym es exactamente A2. Que el gym parezca una frontera y no lo
  sea es precisamente lo que hay que tener escrito.

---

### 4.2 A1 — Atleta (dueño del dato)

**Qué puede leer.** Todo lo suyo: `users/{uid}` y sus cuatro subcolecciones
(`sessions`, `setLogs`, `checkIns`, `customExercises`, `notifications`), sus
`measurements` y `performance_tests`, sus `payments`, sus `appointments`, sus
`chats` y `messages`, sus grants (`session_shares` / `profile_shares`), sus
`follows` y sus `posts`.

**Qué NO puede leer, aunque sea sobre él.** Éste es el punto que más se olvida:
las cuatro colecciones que el PF escribe **sobre** el alumno le están vedadas al
alumno. Medido:

| Path | A1 sobre su propio dato | Regla |
|---|---|---|
| `athlete_notes/{tid}_{uid}` | **DENY** | `firestore.rules:2182` — `trainerId` only |
| `athlete_files/{id}` | **DENY** | `:2220` |
| `nutrition_plans/{tid}_{uid}` | **DENY** | `:2273` |
| `follow_up_entries/{tid}_{uid}` | **DENY** | `:2245` |
| `athlete_billing/{tid}_{uid}` | **ALLOW** | `:2119` — el alumno **sí** lo lee |

Las cuatro primeras están alineadas con el comentario de `storage.rules`
(*"El alumno NUNCA lee estos archivos"*) y con §2.1.1. La quinta **no**: §2.1.1
fila 27 dice *"Quién lo lee: Sólo el PF"* y la regla dice otra cosa. Corregido
en §4.11.

Esto tiene una consecuencia legal que §2.3.2 ya había marcado por otro camino:
el alumno no puede ejercer el derecho de acceso sobre la mitad de lo que el
sistema guarda sobre él, y encima la política no le avisa que esos documentos
existen.

**Qué puede escribir.** Su propio doc (con `uid`, `role`, `email`, `createdAt`,
`subscription`, `weightedLoad` y `blockedAthleteIds` pineados), su historial, sus
posts, sus grants, sus reacciones, sus reviews sobre un PF con el que tuvo
vínculo activo, y sus rutinas `user-created`.

**Qué NO debería poder — y no puede.** Medido, todo DENY:

| Intento | Resultado | Guard |
|---|---|---|
| `users/{self}.role` → `'trainer'` | DENY | QA-SEC-001, `:119` |
| `users/{self}.subscription` → `plan3` | DENY | pin de paywall, `:125` |
| `userPublicProfiles.lifetimeVolumeKg` forjado | DENY | CF-write-only, `:1021` |
| `userPublicProfiles.gymId` sin tocar `users` | DENY | `getAfter()`, `:1005` |
| `measurements` sobre un tercero (siendo `role: athlete`) | DENY | gate de rol, Slice C |
| `payments` contra un tercero (siendo `role: athlete`) | DENY | gate de rol, Slice C |
| `session_shares` / `profile_shares` de otro | DENY | `uid == athleteId`, `:1713` / `:1734` |
| abrir `chats` con alguien sin follow ni link | DENY | `chatCreateOk`, `:1522` |
| borrar un `follows` del que no es miembro | DENY | `:1386` |

**Qué NO debería poder, y sí puede.** Nada nuevo en este actor. El piso del
dueño está bien puesto.

---

### 4.3 A2 — Atleta ajeno / sin vínculo

Es el actor que no debería ver nada tuyo. Medido, **no ve casi nada** — y lo
poco que ve es lo que hay que mirar.

**Qué NO puede leer.** Todo DENY:

`users/{ajeno}` (get y list), `sessions`, `setLogs`, `checkIns`,
`notifications`, `measurements`, `performance_tests`, `payments`,
`athlete_billing`, `athlete_notes`, `athlete_files`, `nutrition_plans`,
`follow_up_entries`, `session_shares`, `profile_shares`, `chats` ajenos y sus
`messages`, `appointments` ajenos, `mail_queue`, `audit_log`, los `posts` con
`privacy: 'friends'` y las `routines` privadas.

**Y no puede saltar la jerarquía.** Los `collectionGroup` sobre las
subcolecciones **fallan por default-deny**, que es la propiedad que hace que el
modelo cierre: ninguna de ellas tiene un `match /{path=**}/…`, así que la query
ni siquiera encuentra una cláusula que la habilite. Medido, los seis:

```
collectionGroup(setLogs)        -> No matching allow statements
collectionGroup(sessions)       -> No matching allow statements
collectionGroup(messages)       -> No matching allow statements
collectionGroup(ratings)        -> No matching allow statements
collectionGroup(notifications)  -> No matching allow statements
collectionGroup(customExercises)-> No matching allow statements
```

Vale la pena que esté escrito: es una propiedad **frágil**. El día que alguien
agregue un `match /{path=**}/setLogs/{id}` para una pantalla nueva, las seis
tablas de arriba cambian de golpe y ningún test de los que existen hoy se pone
rojo.

**Qué SÍ puede leer.** Lo mundo-legible, que es más de lo que suena:

| Path | Contenido | ¿Decidido? |
|---|---|---|
| `userPublicProfiles/{uid}` (get **y list**) | nombre, avatar, gym, racha, workouts, seguidores, volumen de por vida, PRs de sentadilla/banco/peso muerto | Sí — habilita `searchByDisplayName` (`firestore.rules:894`) |
| `trainerPublicProfiles/{uid}` (get y list) | perfil comercial del PF | Sí |
| `gyms/{id}` (get y list) | nombre y coordenadas | Sí (`:1160`) |
| `exercises/{id}` | catálogo | Sí |
| `reviews/{id}` (get y **list**) | `athleteId` + `comment` de texto libre | Sí — §2.1.1 fila 33 |
| `routines/*/ratings/{userId}` | uid del que puntúa + `comment` de 500 chars | Sí (`:581`) |
| `users/{ajeno}/customExercises/{id}` (get y list) | ejercicios propios + URL de video | Sí — §3.3 lo apoya en `:1804` |
| `posts` con `privacy: 'public'` | el post entero | Sí |
| `routines` con `visibility: 'public'` | la rutina entera | Sí |
| `follows` con `status: 'accepted'` (get y **list**) | el grafo social entero de la plataforma | **A medias** — ver abajo |
| `coach_availability_rules` / `_overrides` (get y list) | agenda semanal de **cualquier** PF | Sí, comentado en `:1810` |
| `routines` con `visibility: 'shared'` (get y **list**) | plan del PF + `assignedBy` + `assignedTo` | **NO** → QA-SEC-012 |

Dos filas necesitan letra chica:

- **`follows` accepted es enumerable en bloque.** Medido: `follows` sin filtro
  falla (`Property members is undefined on object`), pero
  `where('status', '==', 'accepted')` devuelve **ALLOW** — o sea, el grafo
  dirigido completo de quién sigue a quién, para toda la base. Es coherente con
  el producto (las listas de seguidores son públicas, estilo Instagram) y el
  comentario de `:1275` piensa el `resource == null` a propósito. Lo que **no**
  está pensado es que eso también publica la lista de seguidores de una cuenta
  marcada como privada — ver QA-SEC-011.
- **`coach_availability_*` es mundo-legible a propósito** (*"athletes and
  trainers can read any rule (needed to compute free slots client-side)"*). El
  permiso de lectura está decidido y comentado. Lo que no está decidido es quién
  **escribe** ahí — ver QA-SEC-013.

**Qué puede escribir sobre un tercero.** Casi nada, y lo que puede es un
hallazgo:

| Intento | Resultado |
|---|---|
| cualquier doc de las colecciones privadas del alumno | DENY |
| `measurements` / `payments` sobre un tercero (rol athlete) | DENY |
| `coach_availability_rules` **propia**, con 50 KB de payload arbitrario | **ALLOW** → QA-SEC-013 |
| `trainerPublicProfiles` **propio**, sin ser trainer | **ALLOW** → QA-SEC-013 |
| `gyms/{id}` `google-places` nuevo, con campos arbitrarios | **ALLOW** → §4.10 |
| `appointments` en la agenda de **cualquier** PF, con 30 KB de texto libre | **ALLOW** → QA-SEC-014 |
| `temp/uploads/{self}/payload.exe`, sin límite de tamaño | ~~**ALLOW**~~ → **DENY** ✅ (QA-SEC-015 cerrado en #804) |

---

### 4.4 A3 — PF vinculado

Es el actor con más alcance sobre datos de terceros del producto, y el que mejor
está delimitado. El modelo tiene **tres llaves separadas** y la sonda confirma
que son separadas:

| Llave | Qué abre |
|---|---|
| `trainer_links` activo | el vínculo comercial: `payments`, `athlete_billing`, `appointments` |
| `session_shares/{aid}.trainerId == uid` | `users/{aid}/sessions/**` y `setLogs/**` |
| `profile_shares/{aid}.trainerId == uid` | el snapshot denormalizado de perfil, y **junto con** `session_shares`, las `measurements` auto-registradas |

**Qué puede leer.** Medido ALLOW: `sessions`, `setLogs`, las `measurements` con
`recordedBy == athleteId` (que exigen **los dos** grants a la vez,
`firestore.rules:1995`), lo que él mismo escribió (`athlete_notes`,
`athlete_files`, `follow_up_entries`, `nutrition_plans`, `athlete_billing`), los
`payments` del par y los `appointments` del par.

**Qué NO puede leer, y no puede.** Medido DENY:

| Path | Resultado |
|---|---|
| `users/{alumno}` — el doc privado con teléfono, email, `fcmTokens` | **DENY** |
| `users/{alumno}/checkIns` — asistencia diaria | **DENY** |
| `users/{alumno}/notifications` — el inbox | **DENY** |
| `chats/{alumno}_{tercero}` — conversaciones con otra gente | **DENY** |
| `athlete_files` de **otro** PF sobre el mismo alumno | **DENY** |

Esto vale la pena escribirlo porque es contraintuitivo y es correcto: el PF ve
el **entrenamiento**, no la **persona**. Lo personal viaja por el snapshot de
`profile_shares`, que el alumno controla, no por `users`.

**Qué NO puede escribir.** Medido DENY: no escribe `sessions` del alumno
(`:1747` es owner-only), y **no borra ni edita una `measurement` auto-registrada
por el alumno** (`:2024` / `:2029` pinean `recordedBy`). La asimetría es
deliberada y está testeada (`measurements-self-log.test.js` S19, #439): leer no
es escribir.

**Qué NO debería poder.** Nada nuevo salió acá. Es el actor mejor cubierto de la
matriz de §1 —`session_shares` y `profile_shares` pasaron de 0 a 5/5 celdas en
§1.5— y se nota.

---

### 4.5 A4 — PF NO vinculado

Es el caso de #763, y el actor donde el rol **por sí solo** ya es un permiso.

**Qué puede leer del alumno: nada.** Medido, todo DENY: `sessions`, las
`measurements` auto-registradas, `profile_shares`, `session_shares`, y los
`athlete_files` de otro PF. El gate de lectura es siempre el vínculo o el grant,
nunca el rol. **Esa mitad está bien.**

**Qué puede escribir SOBRE un alumno con el que no tiene ninguna relación.**
Acá está el alcance real, y **está decidido**: es el residuo aceptado de
`rules-hardening` Slice C (AD-1 opción b, obs #413), escrito en el encabezado de
`scripts/rules_test/coach-collections-role.test.js:13-18`. El gate es
**role-check only, NO role + active-link**, y el argumento es que el forjador
queda **atribuible** — su propio uid va en `recordedBy` / `trainerId`.

Medido, sobre un uid con el que no comparte ni un documento:

| Escritura | Resultado | Quién lo ve después |
|---|---|---|
| `measurements` (peso, circunferencias, `notes`) | **ALLOW** | el alumno, en su historial |
| `performance_tests` (VO2max, 1RM, Cooper) | **ALLOW** | el alumno |
| `payments` (deuda con monto y concepto) | **ALLOW** | el alumno, y le llega el aviso de vencida |
| `athlete_notes` (texto libre sobre él) | **ALLOW** | nadie salvo el forjador |
| `athlete_billing` | **ALLOW** | el alumno |

**Lo que la decisión no contempló, y la sonda sí midió:** la víctima **no tiene
remedio**. Sobre la medida antropométrica que un desconocido escribió sobre
ella:

```
ATLETA lee la medida forjada sobre si mismo   -> ALLOW  (exists=true)
ATLETA borra la medida forjada sobre si mismo -> DENY
ATLETA edita la medida forjada sobre si mismo -> DENY
```

`measurements` update y delete piden `resource.data.recordedBy == request.auth.uid`
(`:2024`, `:2029`), y `recordedBy` es el forjador. O sea: **un dato de salud que
otro escribió sobre vos, en tu propio historial, indeleble desde la app.** Lo
mismo con la deuda inventada — el alumno la lee y no la puede borrar.

"Atribuible" resuelve el problema del auditor; no resuelve el del titular del
dato. Bajo Ley 25.326 esto es el derecho de rectificación (art. 16) sobre un dato
sensible, y se suma a la brecha que §2.3.2 ya había medido por el lado del
derecho de acceso. **No es un permiso sin decidir** —la escritura está decidida—
así que no lleva ticket de reglas: la remediación de la víctima es una decisión
de producto, y va junto con QA-CMP-011 y con la §7 de la política.

---

### 4.6 A5 — Autenticado cualquiera, el que enumera

No es una persona: es el predicado `if request.auth != null`. Es el actor que
encontró QA-SEC-007 y QA-SEC-008 en §3, y el que encontró los siete de §4.9.

Su pregunta no es *"¿puedo leer el documento de Fulano?"* sino **"¿qué me
devuelve el sistema si pregunto por todos?"**. Y las dos superficies que
contesta son distintas:

**1. Enumeración por `list`.** Medido:

| Superficie | `list` | Qué devuelve |
|---|---|---|
| `userPublicProfiles` | **ALLOW** | el padrón de uids de la plataforma, con nombre y gym |
| `trainerPublicProfiles` | **ALLOW** | el padrón de PFs |
| `reviews` | **ALLOW** | `athleteId` + comentario de texto libre |
| `gyms`, `exercises` | **ALLOW** | catálogos |
| `follows where status == 'accepted'` | **ALLOW** | el grafo social completo |
| `routines where visibility == 'shared'` | **ALLOW** | el grafo PF↔alumno → QA-SEC-012 |
| `coach_availability_rules` / `_overrides` | **ALLOW** | todas las agendas |
| `users`, `routines` sin filtro, `appointments` | DENY (error de evaluación) | — |
| `storage:avatars/`, `storage:customExerciseVideos/` | **ALLOW** | §3.6 — QA-SEC-007 y QA-SEC-008 |
| `storage:postPhotos/`, `chatMedia/`, `temp/uploads/` | DENY | §3.5 |

Que `userPublicProfiles` sea enumerable **es una decisión tomada** (`:894`,
habilita la búsqueda por prefijo). Pero es la decisión que arma el arsenal de
todo lo demás: cualquier ataque que necesite "una lista de uids reales" ya la
tiene. El comentario de `chatMedia` en `storage.rules:43` lo dice con todas las
letras — *"uids are enumerable (userPublicProfiles is world-readable)"*— y por
eso ese bloque cerró el `get` con gate de membresía. **La misma premisa no se
aplicó del lado de Firestore.** De ahí sale QA-SEC-010.

**2. Enumeración por oráculo de existencia.** Es la superficie que nadie estaba
mirando, y la que más rindió. El patrón:

> una regla de `read` que arranca con `resource == null ||` **más** un doc id
> **determinístico** = cualquiera puede preguntar "¿existe este documento?" y
> obtener la respuesta, aunque no pueda leer ni un campo.

El mecanismo es que las dos respuestas se distinguen: si el doc **no existe**,
`resource == null` da true y la lectura devuelve un snapshot vacío; si **existe**
y no sos el dueño, la evaluación da false y devuelve `PERMISSION_DENIED`. El
`PERMISSION_DENIED` **es** la respuesta.

Medido, sobre las seis reglas del archivo que usan el idiom:

| Bloque | Doc id | Doc EXISTE | Doc NO existe | ¿Oráculo? |
|---|---|---|---|---|
| `chats` (`:1564`) | `sorted(a,b).join('_')` | DENY | **ALLOW** `exists=false` | **SÍ** |
| `friendships` (`:1252`) | par ordenado | DENY | **ALLOW** `exists=false` | **SÍ** |
| `athlete_notes` (`:2181`) | `{trainerId}_{athleteId}` | DENY | **ALLOW** `exists=false` | **SÍ** |
| `follows` (`:1315`) | `{follower}_{followee}` | DENY (si `pending`) | **ALLOW** | **SÍ**, sólo para `pending` |
| `routines` (`:256`) | auto-id de 20 chars | DENY | ALLOW | No — no enumerable |
| `trainer_links` (`:606`) | auto-id de 20 chars | DENY | ALLOW | No — no enumerable |

Los controles confirman que el idiom es la causa y no otra cosa: `session_shares`,
`profile_shares`, `athlete_files`, `payments`, `appointments` y `measurements`
—que **no** tienen el disyunto— dan **DENY en los dos estados**, así que no
distinguen nada.

Lo que hace que esto sea un hallazgo y no una observación de estilo es que
`routines:217` **razonó el caso y acertó**:

> *"El único dato que expone es 'este id no existe' vs 'existe pero es privado'
> — los auto-ids de Firestore son de 20 chars aleatorios, así que **no habilita
> enumeración**."*

Es correcto, y es correcto **porque el id es aleatorio**. En los cuatro bloques
con id determinístico la conclusión se invierte, y en dos de ellos hay un
comentario escrito que afirma lo contrario. El de `athlete_notes:2175`:

> *"El docId encodea `{trainerId}_{athleteId}` así que un attacker no puede
> fishearse leyendo docs de otro PF: **solo llegaría al doc si armara el par
> exacto** — y si existe, el segundo check bloquea el acceso."*

Las dos mitades miden falso. Armar el par exacto **es trivial**: los uids de PF
salen de `trainerPublicProfiles` y los de alumno de `userPublicProfiles`, las dos
enumerables (medido arriba). Y "el segundo check bloquea el acceso" bloquea el
**contenido**, no la **pregunta** — al atacante nunca le interesó el texto de la
nota. El de `friendships:1247` comete el mismo error más corto: *"returns empty
snapshot **without leaking data**"*.

Es el mismo tipo de defecto que §3.1: una premisa escrita en un comentario, que
nadie volvió a medir, sosteniendo un permiso. → **QA-SEC-010**.

---

### 4.7 A6 — Anónimo / sin auth

**El piso está bien puesto, y es la única fila de toda esta sección sin un solo
matiz.** Medido, DENY en las ocho pruebas de Firestore
(`exercises`, `userPublicProfiles`, `posts` público, `gyms`, `reviews`,
`routines` pública, `coach_availability_rules`, y el create de su propio
`users/{uid}`) y, en Storage, **DENY en todas las celdas de todos los paths**
(§3.5).

No hay ni un `allow` en `firestore.rules` ni en `storage.rules` que no empiece
por `request.auth != null`. Eso lo hace verificable de una: cualquier bloque
nuevo que no arranque así es, por construcción, un agujero — y es la única
invariante de este documento que se puede chequear con `rg`.

```bash
# Debe devolver 0 líneas. Cualquier resultado es un bloque sin piso.
rg -n 'allow [a-z, ]+:\s*if\s+' firestore.rules storage.rules \
  | rg -v 'if false' | rg -v 'if request\.auth'
```

Verificado el 2026-08-24: 0 líneas.

La contracara —y por eso este actor no es la buena noticia que parece— es que
**A6 no es el actor que importa**. Registrarse en TREINO es gratis y no requiere
verificación: convertirse en A5 cuesta un email. Todo lo que esta sección
encontró está del otro lado de esa línea.

---

### 4.8 A7 — Cloud Function (Admin SDK)

**Bypassea las reglas por diseño** (ADR-ACCDEL-013). No hay matriz que medir: el
Admin SDK no evalúa `firestore.rules` ni `storage.rules`, así que para este actor
las secciones §1 a §4.7 no dicen nada. Es la TCB del sistema, y todo lo que lo
protege es el código de las propias funciones.

Es el actor correcto para varias cosas del producto, y conviene tener escrito
cuáles, porque son el motivo por el que ciertos permisos de cliente están
cerrados:

| Lo que sólo A7 puede hacer | Por qué el cliente no |
|---|---|
| aprovisionar `role: 'trainer'` | QA-SEC-001 — `users` create pinea `'athlete'` |
| escribir `subscription`, `weightedLoad`, `blockedAthleteIds` | pines de paywall (`:125`, `:126`, `:146`) |
| escribir los agregados (`ratingAvg`, `averageRating`, `athleteCount`, métricas de ranking) | forjaría su propia reputación |
| borrar una cuenta (`deleteAccount`) | `users` delete es `if false` |
| escribir `users/*/notifications` y `mail_queue` | create/write `if false` |
| pasar un `trainer_links` a `'active'` | ninguna cláusula de cliente lo permite (medido: el update sólo deja `terminated` / `paused`) |
| barrer Storage en el cascade | `bucket.getFiles({prefix})` ignora `storage.rules` (§3.6) |

**Su superficie expuesta al cliente son 5 callables desplegados**, y los cinco
exigen `request.auth`:

| Callable | App Check | Estado |
|---|---|---|
| `deleteAccount` | `true` | atestado — **y rechazando clientes reales, ver más abajo** |
| `addAlias` | `true` | atestado — se llama desde web, donde nunca puede pasar (§4.10) |
| `acceptTrainerLink` | **off** | exención **decidida** y comentada (`accept-trainer-link.ts:82`) — el Coach Hub web no activa App Check |
| `resumeTrainerLink` | **off** | exención decidida y comentada (`resume-trainer-link.ts:77`) |
| `mintWatchCredential` | **off** | **deuda**, no decisión — el propio archivo lo dice (`mint-watch-credential.ts:115`) |

**El hallazgo acá no es una exención: es que el guard dejó de guardar.**
`functions/src/__tests__/appcheck-enforcement.test.ts` se presenta como *"every
DEPLOYED callable must enforce App Check… fails loudly if a callable ships — or
is edited back — without attestation"*, pero su lista `DEPLOYED_CALLABLES` está
**escrita a mano y tiene dos entradas**. Los otros tres callables se desplegaron
después y la lista nunca creció: el scanner está verde y **cubre 2 de 5**. Un
sexto callable sin atestación entraría en silencio.

Es exactamente el defecto que §1.4 midió para `rules.test.js` —un guard que no
distingue "cambió porque quisimos" de "se rompió"— con el agravante de que acá el
inventario es manual y el drift es la operación normal. → **QA-SEC-016**.

**Cerrado en [#805](https://github.com/Backhaus7997/treino/pull/805)**: el scanner
ya no tiene lista propia. La deriva de `index.ts` por AST —los callables
desplegados son los símbolos exportados ahí que resuelven a un `onCall`— y las
tres exenciones pasaron a un registry con motivo, permanencia
(`decided` / `debt`) y condición de salida obligatoria para las deudas.

#### 4.8.1 El enforcement de App Check, reconciliado (2026-08-25)

Dos lugares del repo decían cosas incompatibles, y este documento repetía la
lectura equivocada:

| Fuente | Fecha | Qué decía |
|---|---|---|
| `lib/main.dart:82-84` | 2026-07-27 | *"ENFORCEMENT ESTÁ ACTIVO para Cloud Firestore"* |
| `mint-watch-credential.ts:103-106` | 2026-08-18 | `firestore` e `identitytoolkit` → **UNENFORCED** |

Re-medido contra las dos APIs el **2026-08-25**, sin token de App Check y con un
token deliberadamente inválido. Las dos lo ignoran y siguen de largo:

```
GET  firestore.googleapis.com/v1/.../documents/exercises
     → 403 "Missing or insufficient permissions."   ← lo deniegan las REGLAS
POST identitytoolkit.googleapis.com/v1/accounts:signInWithPassword
     → 400 INVALID_LOGIN_CREDENTIALS                ← llegó a validar credenciales
```

Con enforcement activo ninguna de las dos habría llegado tan lejos. **Gana la
verificación del 2026-08-18: a nivel de proyecto está UNENFORCED.** `main.dart`
quedó desactualizado y se corrigió en el mismo PR.

**De ahí NO se sigue que "el flag no cierra ninguna puerta en ningún lado".** Esa
frase vivía acá y era falsa: `enforceAppCheck` lo aplica **la propia función**,
en su código, y es independiente del enforcement por API de la consola. Medido el
mismo día, llamando a los cinco callables desplegados sin token de auth — sin
credencial no se puede borrar ni escribir nada, así que la sonda es inocua:

| Callable | Respuesta | Lectura |
|---|---|---|
| `deleteAccount` | `"Unauthenticated"` | cortado en la capa de transporte, el handler **no corre** |
| `addAlias` | `"Unauthenticated"` | ídem |
| `acceptTrainerLink` | `"Authentication required."` | llegó al handler → sin enforcement |
| `resumeTrainerLink` | `"Authentication required."` | ídem |
| `mintWatchCredential` | `"Authentication required."` | ídem |

`"Caller is not authenticated."` es el mensaje propio de
`delete-account.ts:222`; el que vuelve es el genérico de `firebase-functions` v2.
La diferencia es la prueba de que la atestación corta antes.

#### 4.8.2 `deleteAccount` nunca devolvió 200

Consecuencia viva de lo anterior, medida sobre Cloud Logging el 2026-08-25 con
todo el histórico retenido (desde 2026-05-01):

```
resource.labels.service_name="deleteaccount" AND httpRequest.status=200
→ 0 entradas
```

Los **únicos** tres intentos autenticados que existen fueron rechazados:

```
2026-08-11T13:12:37Z  401  {"verifications":{"auth":"VALID","app":"INVALID"}}
2026-08-11T13:12:51Z  401  "AppCheck token was rejected."
2026-08-11T13:13:05Z  401  FirebaseAppCheckError: Decoding App Check token failed
ua="com.backhaus.treino/0.1.0 iPhone/17.5 hw/sim"
```

Tres toques en 28 segundos: alguien apretó ELIMINAR, no pasó nada y reintentó.
`enforceAppCheck: true` entró en `deleteAccount` el 2026-07-20 (`2bb8d1c7`).
Apple Guideline 5.1.1(v) exige que el borrado de cuenta funcione.

Ese cliente era un **simulador** (`hw/sim`), no un tester de TestFlight — pero el
modo de falla no es exclusivo del simulador. Cruzando cada verificación con su
user-agent sobre `mintWatchCredential`, que recibe tráfico real y no tiene el
flag puesto:

| Cliente | `app=VALID` | `app=INVALID` | Último |
|---|---|---|---|
| iPhone físico (`hw=iPhone17_1`, iOS 26.5.2 / 26.6) | 8 | 2 | 2026-08-21 |
| Android (`okhttp/3.12.13`) | 1 | **8** | 2026-08-24 |
| Coach Hub web (`Mozilla/… Windows`) | — | `MISSING` ×13 | 2026-08-20 |

Tres cosas que corrige esta medición:

1. **App Attest no está roto en general.** `mint-watch-credential.ts:96-98`
   generaliza de más: en un iPhone físico emitió 8 tokens válidos. Lo que falla
   ahí es intermitente.
2. **El que está roto es Play Integrity en Android** — 8 de 9 llamadas con token
   inválido, la más reciente 2026-08-24.
3. **La web manda `MISSING`, no `INVALID`**, confirmando que
   `main_coach_hub.dart` no activa App Check (cero referencias a
   `FirebaseAppCheck`) y que el PR [#704](https://github.com/Backhaus7997/treino/pull/704)
   acertó al sacar el flag de los dos callables del paywall.

**Cómo repetir la medición** — no hace falta instrumentar nada, `firebase-functions`
v2 ya loguea la verificación de cada callable:

```
jsonPayload.message:"Callable request verification"
```

El campo `jsonPayload.verifications.app` vale `VALID` / `INVALID` / `MISSING`, y
distingue *"no mandó token"* de *"mandó uno que no se pudo decodificar"* — que es
justamente la distinción entre la web y el móvil. Es la fuente de la que dependen
el plan de restore de #704 y la condición de salida de `mintWatchCredential`.

---

### 4.9 Lo que el cruce encontró — siete permisos que nadie decidió

Ninguno se arregla en este PR, por el mismo motivo que §3.6: **tocar una regla
de producción merece su propio change, su propio test y su propia verificación.**
Los siete salieron con ticket propio, igual que QA-SEC-007/008/009.

Ordenados por lo que me preocuparía primero.

| ID | Qué | Dónde | Severidad | Ticket |
|---|---|---|---|---|
| **QA-SEC-010** | `resource == null` + doc id determinístico = oráculo de existencia en 4 bloques | `firestore.rules:1564`, `:1252`, `:2181`, `:1315` | **Media-alta** | [#777](https://github.com/Backhaus7997/treino/issues/777) |
| **QA-SEC-011** | `isProfilePublic` no existe en las reglas: "Perfil privado" se aplica sólo en el cliente | `:894`, `:738`, `:256` | **Media-alta** | [#778](https://github.com/Backhaus7997/treino/issues/778) |
| **QA-SEC-012** | `visibility: 'shared'` concede lectura y enumeración mundial a una feature que el dominio declara reservada | `:259` | Media | [#779](https://github.com/Backhaus7997/treino/issues/779) |
| **QA-SEC-013** | El gate de rol de Slice C no llegó a las 3 colecciones que publican al PF | `:1111`, `:1816`, `:1826` | Media | [#780](https://github.com/Backhaus7997/treino/issues/780) |
| **QA-SEC-014** | `appointments` create sin allowlist de campos ni cap de tamaño: un desconocido escribe en la agenda de cualquier PF | `:1858` | Media | [#781](https://github.com/Backhaus7997/treino/issues/781) |
| ~~**QA-SEC-015**~~ | `temp/uploads` es el único write de Storage sin allowlist de content-type ni cap de tamaño | `storage.rules:88` | Baja | **CERRADO** en #804 ([#782](https://github.com/Backhaus7997/treino/issues/782)) |
| **QA-SEC-016** | El scanner de App Check cubre 2 de los 5 callables desplegados | `appcheck-enforcement.test.ts:18` | Baja | ~~[#783](https://github.com/Backhaus7997/treino/issues/783)~~ cerrado |

---

**QA-SEC-010 — Oráculo de existencia por doc id determinístico.**
Desarrollado en §4.6. Cuatro bloques, un solo idiom, y un comentario en dos de
ellos que afirma explícitamente que no hay leak. Lo que cada uno entrega a
cualquier autenticado, medido:

- `chats` → **¿estas dos personas se escriben?** Un bit por par, y un par
  concreto es una sola llamada. Es el más sensible de los cuatro.
- `athlete_notes` → **¿este PF tiene notas sobre este alumno?** Cruzando los dos
  padrones enumerables, reconstruye la **cartera de clientes de cada PF**.
- `friendships` → lo mismo sobre la colección legacy, que sigue intacta a
  propósito (ADR-FOLLOW-012, y ver QA-CMP-007).
- `follows` → **¿A le mandó solicitud a B y B todavía no aceptó?** Sólo aplica a
  las `pending`, o sea exactamente a las cuentas privadas.

*Arreglo propuesto:* el disyunto existe por UX (que "no hay nada" resuelva en
vez de tirar error). Se puede conservar **acotándolo a quien tiene derecho a
preguntar** — p. ej. en `athlete_notes`,
`(resource == null && docId.split('_')[0] == request.auth.uid)`, mismo idiom que
`storage.rules:athleteFiles`; en `chats`, `request.auth.uid in chatId.split('_')`.
Ojo con el `split('_')`: §1.7 ya advierte que sólo es seguro mientras los uid de
Firebase Auth no traigan guión bajo. Alternativa sin acoplamiento al id: sacar el
disyunto y que el cliente trate el `permission-denied` como "no hay".

---

**QA-SEC-011 — `isProfilePublic` no existe en las reglas.**
`UserPublicProfile.isProfilePublic` es el toggle de PRIVACIDAD del perfil. La app
promete, en el propio widget del toggle
(`profile_privacy_toggle_tile.dart:15-16`): *"Private: only the identity header
stays visible to non-followers; **detailed content is gated** until you accept
their request"*, y le muestra al visitante un candado con *"Seguí a esta persona
para ver su actividad y sus rutinas públicas"*
(`public_profile_screen.dart:206-228`).

El gate existe **sólo en el cliente**: `public_profile_screen.dart:86` calcula
`gated` y esconde `PublicProfileStatsRow` y `_ProfileTabBody`. Medido contra un
perfil con `isProfilePublic: false`, desde un desconocido:

| Lectura | Resultado | Qué entrega |
|---|---|---|
| `userPublicProfiles/{privado}` | **ALLOW** | racha, workouts, seguidores, `lifetimeVolumeKg`, `bestSquatKg`/`Bench`/`Deadlift` |
| `list userPublicProfiles` | **ALLOW** | ídem, para toda la base |
| `posts` `privacy: 'public'` del perfil privado | **ALLOW** | el post entero |
| `routines` `visibility: 'public'` del perfil privado | **ALLOW** | la rutina entera |
| `follows where status == 'accepted'` | **ALLOW** | su lista de seguidores y seguidos |
| `posts` `privacy: 'friends'` | DENY | (esto sí lo gobierna la regla) |

O sea: **todo lo que el candado esconde se sirve igual por debajo.** Y no es que
las reglas no puedan ver el flag — `follows` create ya lo consulta
(`firestore.rules:1350`) para decidir el auto-accept. La regla conoce el dato y no
lo usa para leer.

*Arreglo propuesto:* decidir primero **qué promete el producto**. Si "privado"
significa lo que dice el widget, `userPublicProfiles` read tiene que partirse en
"identity header para cualquiera" vs "métricas sólo para seguidores aceptados", y
`posts`/`routines` públicas de un autor privado tienen que caer al branch de
seguidor. Si "privado" sólo significa "aprobación manual de seguidores" —que es
lo que el modelo hace hoy— entonces hay que **corregir el copy**, que es más
barato y más honesto. Lo que no puede quedar es la brecha entre las dos cosas.

---

**QA-SEC-012 — `visibility: 'shared'` publica al mundo una feature que no existe.**
El dominio declara el valor **reservado y sin uso**
(`routine_visibility.dart:6`): *"`shared`: extensión futura (planes compartidos
entre múltiples atletas). Reservado para iteración futura — no se usa en Etapa 1"*.

Las reglas ya le dieron significado, y no el que dice esa frase. El lado de
escritura lo pensó (`:277`: *"visibility debe ser 'private' o 'shared' (no
'public')"*, `:353`: *"'shared' is trainer-assigned only"*); el lado de lectura
lo mete en el mismo disyunto que `'public'` — **sin una sola línea de comentario,
en una regla donde cada otro disyunto tiene párrafos**:

```
|| resource.data.get('visibility', 'private') == 'public'
|| resource.data.get('visibility', 'private') == 'shared'    // firestore.rules:259
```

Medido, y alcanzable hoy: un PF crea una `trainer-assigned` con
`visibility: 'shared'` (**ALLOW**), y desde un desconocido:

```
get routines/{shared de un par ajeno}          -> ALLOW  (assignedTo=athleteA…)
list routines where visibility == 'shared'     -> ALLOW  (devuelve todas)
```

O sea que el día que se implemente "planes compartidos entre múltiples atletas",
**cada plan compartido nace mundo-legible y mundo-enumerable, con el par
`assignedBy`/`assignedTo` adentro** — el grafo PF↔alumno de toda la plataforma.
Y va a parecer que funciona, porque el cliente filtra.

*Arreglo propuesto:* sacar el disyunto de la regla de lectura hasta que la
feature se diseñe, y que el diseño elija a quién abre. Un valor reservado no
debería llegar a producción con un permiso ya concedido. Riesgo de sacarlo: nulo
medible — el cliente sólo escribe `'public'`/`'private'`
(`routine_repository.dart:36`), así que no debería haber docs `shared` en la base;
**hay que confirmarlo con un conteo en producción antes de tocar la regla.**

---

**QA-SEC-013 — El gate de rol de trainer no llegó a las 3 colecciones que publican al PF.**
`rules-hardening` Slice C agregó `get(users/{uid}).data.role == 'trainer'` a
**cinco** colecciones —`payments`, `athlete_billing`, `measurements`,
`performance_tests`, `appointments`— para cerrar el vector *"un usuario con rol
athlete forja un documento nombrándose a sí mismo trainer"*. Quedaron afuera las
tres que publican la **identidad y la agenda** del PF, y en las tres el rol se
puede saltear. Medido, con una cuenta `role: 'athlete'`:

| Escritura | Resultado |
|---|---|
| `trainerPublicProfiles/{self}` con `displayNameLowercase`, especialidad y `trainerOffersOnline` | **ALLOW** |
| `coach_availability_rules/{propia}` con 50 KB de payload arbitrario | **ALLOW** |
| `coach_availability_overrides/{propia}` con 50 KB de payload arbitrario | **ALLOW** |

Y aparece en el descubrimiento: la sonda corrió la misma query que
`TrainerPublicProfileRepository.listAll()`
(`orderBy('displayNameLowercase').limit(50)`) y el doc forjado **volvió primero**,
porque el atacante elige el string por el que se ordena. Como yapa, `trainer_links`
create sólo pide `trainerId is string` — medido: un atleta puede pedir vínculo
contra otro atleta.

Dos matices que acotan el daño, y conviene tenerlos escritos para no
sobredimensionar el ticket:

- Los campos del perfil comercial son **self-attested a propósito** (AD-3,
  `firestore.rules:1098`), y los agregados que sí son trust boundary
  (`averageRating`, `reviewCount`, `athleteCount`) están pineados CF-write-only.
  El ticket es sobre **quién puede existir en el directorio**, no sobre qué dice.
- El chat de consulta no se abre contra un PF falso: `chatCreateOk` verifica
  `get(users/{other}).data.role == 'trainer'` (`:1535`).

Lo de `coach_availability_*` es un problema distinto en el mismo bloque: además
de no tener gate de rol, **no tienen `keys().hasOnly()` ni cap de tamaño**, y la
colección es mundo-legible y mundo-enumerable por decisión escrita (§4.3). Es
decir: cualquier autenticado publica documentos arbitrarios de hasta 1 MB que
todos los usuarios pueden listar. El comentario de la regla dice
*"Create/update/delete restricted to the owning trainer"* — es dueño, sí, pero de
un documento que se acuña solo.

*Arreglo propuesto:* el mismo disyunto de rol que las otras cinco, más una
allowlist de campos y un cap de longitud en `coach_availability_*`. Cuidado con
el orden de despliegue: hoy hay perfiles de PF creados antes del gate y la regla
de `update` también los tocaría.

---

**QA-SEC-014 — `appointments` create: un desconocido escribe en la agenda de cualquier PF.**
Slice C razonó **el disyunto del trainer** y dejó el del atleta explícitamente
intacto (`firestore.rules:1854`: *"the legacy athlete self-book disjunct
(`athleteId == auth.uid`) is UNCHANGED, preserving that live path"*). El
auto-booking está decidido. Lo que nadie miró es **qué se puede meter adentro del
documento**: el bloque no tiene `keys().hasOnly()`, no valida un solo campo, no
tiene cap de longitud en ninguno, y no verifica que `trainerId` sea un trainer ni
que haya vínculo.

Medido, desde una cuenta sin ninguna relación con el PF:

```
create appointments/{id} con trainerId = <cualquier PF>,
  athleteDisplayName = 30 KB de texto arbitrario,
  noteBefore         = 30 KB de texto arbitrario,
  status             = 'confirmed'                      -> ALLOW
el PF lee ese turno                                     -> ALLOW
```

Cae en la agenda del PF —que es una superficie con UI, la que §2.4/QA-CMP-009
señala como *"el residuo más visible de todos"*— con `status: 'confirmed'` y con
el texto que el atacante eligió. Y `allow delete: if false` (`:1898`): el PF
**no lo puede borrar**, sólo cancelarlo.

Peor: `startsAt` tampoco se valida, y la cancelación exige más de 24 h de
anticipación (`:1870`, `startsAt - 86400000 > request.time`). Leyendo la regla —no
lo medí— un turno forjado con `startsAt` dentro de las próximas 24 h, o en el
pasado, **no lo puede cancelar nadie y no lo puede borrar nadie**: queda fijo en
la agenda hasta que alguien entre con el Admin SDK.

La evidencia de que es un olvido y no una decisión es la comparación dentro del
mismo archivo: `athlete_notes` limita `note` a 5000 caracteres,
`follow_up_entries` su `text` a 5000, `nutrition_plans` el `title` a 200,
`payments` el `concept` a 200 y `measurements` las `notes` a 2000.
`appointments` es el único documento escribible por un tercero **sin un solo
límite**.

*Arreglo propuesto:* `keys().hasOnly()` + `optStrMaxLen()` sobre
`athleteDisplayName` / `noteBefore` / `noteAfter` —los guards compartidos del
tope de `firestore.rules` (QA #508) ya existen y son exactamente para esto—, un
rango sobre `startsAt`, y decidir aparte si el auto-booking debería exigir
`trainer_links` activo. Eso último es cambio de producto, no de regla.

---

**~~QA-SEC-015~~ — `temp/uploads` es el único write de Storage sin allowlist ni
cap. — CERRADO en #804 (issue [#782](https://github.com/Backhaus7997/treino/issues/782)).**

La regla al momento del hallazgo:

```
match /temp/uploads/{userId}/{file=**} {
  allow read: if false;
  allow write: if request.auth != null && request.auth.uid == userId;
}
```

Los otros cinco bloques del archivo declaran content-type y tamaño. Éste no
declara ninguno de los dos. Medido, con el mismo payload:

| Path | `.exe` de 4 bytes | 8 MB |
|---|---|---|
| `temp/uploads/{self}/` | ~~**ALLOW**~~ → **DENY** ✅ | ~~**ALLOW**~~ → **DENY** ✅ |
| `avatars/{self}.exe` | DENY | (cap 5 MB) |
| `postPhotos/{self}/` | DENY | (cap 15 MB) |
| `customExerciseVideos/{self}/` | DENY | (cap 100 MB) |

El piso sí está: anónimo DENY, subir a la carpeta de otro uid DENY, `list` DENY,
y el `read: if false` aguanta — medido, `getDownloadURL()` sobre lo que uno mismo
subió **también da DENY**, porque mintear el token exige leer la metadata. **No es
un file host público**, y eso es lo que baja la severidad a Baja.

Lo que quedaba era: cualquier autenticado —incluido un rol `athlete`, que no
tiene nada que hacer ahí— podía escribir bytes arbitrarios, en cantidad
arbitraria, en nuestro bucket. Sin ciclo de vida: el prefijo se llama `temp/`
pero no hay TTL ni job de limpieza; lo único que barre `temp/uploads/{uid}/` es
el cascade de borrado de cuenta (`cascade/storage.ts:67`), o sea que los bytes
vivían mientras viviera la cuenta.

*Arreglo propuesto en su momento:* content-type allowlist (los MIME de Excel) +
cap de tamaño, espejo del guard del cliente, y una regla de ciclo de vida en el
bucket. Ojo con uno solo de los dos: sin TTL, el cap sólo hace la acumulación
más lenta.

**Lo que se hizo, y por qué es otra cosa.** El arreglo propuesto arriba —y el
alcance del issue— daban por sentado que el path tenía un camino de escritura
legítimo que había que acotar. **No lo tenía.** Este párrafo y el comentario
viejo del bloque decían que ahí "van los Excel que importa el PF"; es falso, y
la comprobación es de una línea:

```bash
git log --oneline -S "temp/uploads" --all -- lib/   # → cero commits
```

Nunca existió un writer en `lib/`. No es que se removió: el bloque entró
**vestigial** en `75581f89` (#106), el commit que trajo `storage.rules` desde el
repo viejo, describiendo una arquitectura server-side que TREINO Flutter nunca
implementó. El import de planes por Excel es 100% client-side y en memoria
(`FilePicker.pickFiles(withData: true)` → `file.bytes` →
`PlanImportRepository.parseAndMatch(bytes:)` → `parseExcelBytes()`); los bytes
del `.xlsx` no salen del proceso. Y del lado servidor no hay un solo reader:
lo único que toca el prefijo es `functions/src/cascade/storage.ts:67`, con
Admin SDK, que ignora estas reglas (ADR-ACCDEL-013).

Con eso, poner allowlist + cap habría **preservado** una superficie de escritura
que ningún código usa, a cambio de nada. El bloque se cerró entero:

```
match /temp/uploads/{userId}/{file=**} {
  allow get: if false;
  allow list: if false;
  allow write: if false;
}
```

Tres consecuencias que conviene tener escritas:

1. **La regla de ciclo de vida del bucket que pedía el issue dejó de hacer
   falta.** El issue insistía —con razón, dado su supuesto— en que cap sin TTL
   sólo hace la acumulación más lenta. Sin escrituras no hay acumulación que
   expirar. Lo que ya está en reposo lo sigue barriendo el cascade de borrado
   de cuenta.
2. **No lleva `allow delete` propio, y eso es correcto acá.** La regla 3 de
   §3.8 aplica a los bloques que dereferencian `request.resource.<algo>`: ahí
   el delete explota con "Null value error" y se deniega hasta para el dueño
   (QA-SEC-009). Este bloque no dereferencia nada, así que el `write: if false`
   cubre el delete **denegando por permiso**, que es la denegación que se
   quiere. Está medido, no razonado: ver la celda `delete dueño` de §3.5.
3. **`get` y `list` van separados aunque los dos sean `if false`** (§3.8 regla
   2). No cambia el comportamiento; evita que el próximo que afloje el bloque
   escriba `read` a secas y se lleve `list` puesto sin darse cuenta.

*Si el import alguna vez se mueve a server-side*, este bloque se reabre — con el
flujo real a la vista, que es mejor que adivinar hoy un cap y un MIME para un
consumidor que no existe.

**Verificación de mutación.** Como pide §1.8, antes de dar las cuatro celdas por
cerradas se aflojó la regla y se comprobó qué se pone rojo. Tres mutaciones,
medidas contra el emulador sobre las 5 suites `*-storage-rules.test.ts` de
`functions/`, con el baseline probado primero (62 tests verdes):

| Mutación | Qué se aflojó | Rojos |
|---|---|---|
| A | La regla pre-PR (`read: if false` + `write` por dueño) | **3** — `write` del dueño (con y sin content-type de Excel) y `delete` |
| B | `get`/`list` → `if request.auth != null` | **4** — `get` dueño y ajeno, `list` de la carpeta y **de la raíz** |
| C | Bloque abierto del todo (`if true`) | **10** — el archivo entero |

En las tres, el único archivo que se pone rojo es
`temp-uploads-storage-rules.test.ts`: cero rojos en `avatars`, `athleteFiles`,
`customExerciseVideos` y `postPhotos`. La mutación C está para que ningún
negativo quede de decoración — los tres que A y B no matan (`write` ajeno,
`write` anónimo, `get` anónimo) son el piso, y C demuestra que también son
vivos.

⚠️ **La mutación desmintió un supuesto, y ese es el punto de correrla.** El test
afirmaba que listar la raíz `temp/uploads/` lo cerraba el catch-all
`{allPaths=**}` y no este bloque, copiando el razonamiento de §3.4 —donde para
`postPhotos` eso **sí** es cierto porque su `match` pide dos segmentos—. Acá no:
al aflojar el `list` de este bloque, la raíz pasó a ALLOW junto con la carpeta,
o sea que el `{file=**}` la alcanza. El comentario del test quedó corregido para
decir lo medido.

---

**QA-SEC-016 — El scanner de App Check cubre 2 de los 5 callables desplegados.**
Desarrollado en §4.8. Los tres callables fuera de la lista tienen su exención
razonada **en su propio archivo**, así que el permiso está decidido; lo que no
está decidido es que el guard afirme una propiedad que no verifica. Y una de las
tres exenciones (`mintWatchCredential`) se declara a sí misma *"deuda, no decisión
de diseño"*, con un TODO de restauración que nada vigila.

*Arreglado en [#805](https://github.com/Backhaus7997/treino/pull/805):* la lista
se deriva de `index.ts` por AST —los callables desplegados son exactamente los
símbolos exportados ahí que resuelven a un `onCall`— y las exenciones son
entradas explícitas con motivo, de modo que agregar un callable sin atestación
**y sin exención declarada** pone el test en rojo. Mismo patrón que
`rules-read-isolation.test.ts` (§1.4) usa para congelar cláusulas de
`firestore.rules`.

Se usó AST y no regex por dos defectos que el guard viejo tenía y un regex no
puede evitar: un `// export {...}` comentado parece un export (así viven
`resolveGymPlace` y los dos callables de auth), y `src.match(/enforceAppCheck:\s*true/)`
sobre el archivo **entero** le daba el visto bueno al segundo callable con la
atestación del primero — `auth/request-auth-email.ts` ya exporta dos. Los dos
casos tienen test.

El registry distingue `decided` de `debt`, y la unión discriminada de TypeScript
**obliga** a que una deuda traiga condición de salida: una deuda sin condición de
salida es una decisión disfrazada. También falla si una exención sobrevive a su
causa —el flag volvió y nadie borró la entrada— para que el registry no crezca
solo. Y pinea el set desplegado (5 hoy): si la resolución del AST se rompiera, el
inventario quedaría vacío y todo lo demás pasaría, porque *"cero callables sin
atestación"* es trivialmente cierto sobre una lista vacía.

Verificado por mutación a mano, no sólo por el caso negativo sintético: sacándole
`enforceAppCheck: true` a `delete-account.ts:219` caen exactamente los dos
asserts que corresponden y ninguno más; restaurándolo vuelve a verde. La tabla
está en el cuerpo del PR.

**Endurecido después por la review de Codex** ([#809](https://github.com/Backhaus7997/treino/pull/809)),
dos formas de evadir el guard que la primera versión dejaba abiertas:

| Evasión | Por qué pasaba | Cómo se cierra |
|---|---|---|
| Un `acceptTrainerLink` sin atestar declarado en **otro módulo** heredaba la exención del original | el registry se keyeaba sólo por el símbolo local | la clave pasó a ser `<módulo>:<símbolo>`, así una exención ampara exactamente al código para el que se escribió |
| `{ enforceAppCheck: true, ...runtimeOptions }` se leía como atestado | el scanner cortaba en la primera propiedad que matcheaba | recorre las propiedades **en orden** y gana la última escritura; un spread posterior no es demostrable, así que **falla cerrado**. `{ ...base, enforceAppCheck: true }` sigue contando como atestado, que es correcto |

La primera es la que más importa: el motivo escrito de una exención —*"lo llama
el Coach Hub web"*— sólo vale para el callable para el que se escribió, y una
clave que no distingue definiciones deja que otro se lo apropie.

---

### 4.10 Observaciones que no llegan a ticket

No son permisos sin decidir, pero salieron del cruce y conviene que estén
escritas. Mismo criterio que §1.7.

- **`gyms` `google-places` no tiene `keys().hasOnly()`.** El permiso amplio de
  update **sí está decidido y comentado** (`firestore.rules:1134-1158`: el
  resolve pasó a ser client-side porque la CF no se puede desplegar, y dos
  clientes pueden reescribir el mismo placeId a la vez), y los campos de
  identidad **sí están pineados** por QA-SEC-003. Lo que quedó abierto es todo lo
  demás: medido, cualquier autenticado agrega campos arbitrarios a un `gyms`
  ajeno (20 KB en la prueba) y setea `createdBy` a su propio uid, en una
  colección mundo-legible y mundo-enumerable. Nada lee `createdBy` en
  `google-places` hoy, así que no escala a nada; es inyección de contenido en un
  catálogo, no un leak. Si se toca `appointments` por QA-SEC-014, la allowlist
  acá cuesta lo mismo y puede ir en el mismo change.
- **Varias denegaciones de `routines` llegan por error de evaluación, no por
  permiso.** Los disyuntos del `read` dereferencian `resource.data.assignedTo`,
  `assignedBy` y `createdBy` **crudo**, sin el `.get(campo, default)` que el
  mismo bloque sí usa para `visibility`. Medido: el `get` de una
  `trainer-assigned` sin `createdBy` —que es la forma normal, el modelo no lo
  emite— devuelve *"Property createdBy is undefined on object"*, y el `list` sin
  filtro devuelve *"Property assignedTo is undefined"*. **Deniegan, que es el
  resultado correcto**, pero por el motivo equivocado, y §1.8 avisa que un
  denegado por el motivo equivocado es más frágil que uno por permiso: alcanza
  con que un doc adquiera el campo para que la evaluación deje de fallar y pase
  a decidir el disyunto. No es un agujero hoy; es una fila del `read` más
  apoyada en la forma de los datos que en la regla.
- **`addAlias` exige App Check y se llama desde el Coach Hub web, donde App
  Check nunca se activa.** O sea que falla siempre, y el error va a un
  `debugPrint`. No lo encontré yo: está escrito en
  `accept-trainer-link.ts:87-89` (*"Falla siempre y nadie se entero"*). Lo dejo
  anotado acá porque es el mismo patrón que §3.2.1 (`catch (_) {}` que se come
  una denegación y le miente al usuario) y porque, cuando se active App Check en
  web, es lo primero que hay que retestear.
  **Confirmado por sonda el 2026-08-25** (§4.8.1): `addAlias` devuelve el
  `"Unauthenticated"` genérico de la capa de transporte, no el
  `"Authentication required."` de su propio handler — la atestación corta antes
  de que el handler corra. Y `main_coach_hub.dart` no tiene una sola referencia
  a `FirebaseAppCheck`, así que desde web el token no es inválido: **no
  existe**. Su único callable hermano medido desde web
  (`acceptTrainerLink`, que ya no tiene el flag) registra 13 llamadas con
  `app=MISSING`, todas de un `Mozilla/… Windows`.
- **La jerarquía aguanta por default-deny, no por una regla.** Los seis
  `collectionGroup` de §4.3 fallan porque no existe un `match /{path=**}/…`. Es
  correcto y es gratis, pero es una propiedad que se pierde con un `match` nuevo
  y ningún test la custodia. Es candidata a un scanner estático del estilo de
  `rules-read-isolation.test.ts`.

---

### 4.11 Correcciones al inventario de §2 que salieron del cruce

Medir §2.1.1 contra el emulador encontró dos filas donde la columna *"Quién lo
lee"* no coincide con la regla. Las dos van corregidas en este mismo PR, y las
dos van en la dirección de **más lectores de los declarados**:

| Fila | Decía | Mide | Nota |
|---|---|---|---|---|
| 22-23 `coach_availability_rules` / `_overrides` | "PF" | **cualquier autenticado** | Deliberado y comentado en `firestore.rules:1810`: los alumnos lo necesitan para calcular slots libres client-side |
| 27 `athlete_billing` | "Sólo el PF" | **PF + el alumno del par** | `:2119` incluye `athleteId`. Sin comentario que lo explique, pero es coherente con que el alumno vea el precio acordado |

Ninguna de las dos es un agujero. Las dos son exactamente el motivo por el que
§2.6 pide que el PR que cambia el dato actualice el documento: se escribieron
leyendo el modelo, no la regla.

---

### 4.12 Cómo mantener esta sección

Mismo contrato que §1.8, §2.6 y §3.8: **el PR que cambia la regla actualiza el
documento.**

1. **Bloque `match` nuevo** → antes de mergear, contestar las tres columnas para
   los siete actores de §4.1. Si la respuesta para A5 (*autenticado cualquiera*)
   es "puede leer", eso es una decisión de publicar a toda la base: se escribe
   acá con su porqué, o no se mergea.
2. **`resource == null` en una regla de `read`** → sólo con doc id **aleatorio**.
   Con id determinístico es un oráculo de existencia (§4.6), y hay que acotar el
   disyunto a quien tiene derecho a preguntar. Es la lección de QA-SEC-010 y vale
   para cualquier bloque futuro.
3. **Flag de privacidad nuevo en un modelo** → si la UI lo usa para esconder
   algo, la regla tiene que aplicarlo también, o el copy tiene que dejar de
   prometerlo. Lección de QA-SEC-011.
4. **Valor de enum reservado "para más adelante"** → no darle permiso hasta que
   la feature se diseñe. Lección de QA-SEC-012.
5. **Documento que escribe un tercero** → `keys().hasOnly()` y cap de longitud en
   todo campo de texto libre, siempre. Lección de QA-SEC-014 y del contraste con
   las otras cinco colecciones que sí los tienen.
6. **Si se cierra un `QA-SEC-0xx` de §4.9** → tacharlo ahí con la referencia al
   PR, no borrarlo (misma regla que §2.4 y §3.8), y actualizar la fila que
   corresponda de §1.1 o §1.2.
7. **La medición no se hereda.** Los ALLOW/DENY de esta sección valen para el
   `firestore.rules` del día que se escribieron. Si tocás un bloque, volvé a
   correr la sonda.

```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"   # Java 21, macOS
npm --prefix functions run test:rules:emulator
npm --prefix scripts/rules_test ci && bash scripts/test_rules.sh
```

---

### 4.13 Registro `QA-SEC-xxx`

#680 pide formalizar la convención porque *"hoy los IDs existen desperdigados en
comentarios y nadie sabe cuál es el próximo libre"*. Éste es el registro.

**Convención.** `QA-SEC-xxx` numera un **hallazgo de seguridad** con su
disposición. La serie `1xx` está reservada para hallazgos de **plataforma**
(manifiestos, entitlements, configuración de build) para no mezclarlos con los de
autorización. El id se cita en el comentario de la regla o del test que lo cierra,
y se tacha acá con la referencia al PR — nunca se borra. Los hallazgos de
**borrado / cumplimiento** usan la serie paralela `QA-CMP-xxx` (§2.4).

| ID | Qué | Estado |
|---|---|---|
| QA-SEC-001 | `users` create dejaba auto-asignarse `role: 'trainer'` (privilege escalation, permanente por el pin de update) | ~~Cerrado~~ — `firestore.rules:97`, `users-role-create-rules.test.ts` |
| QA-SEC-002 | Forja de `trainer_links` | ~~Cerrado~~ — `trainer-links-forge-rules.test.ts` |
| QA-SEC-003 | `gyms`: coordenadas sin validar + campos de identidad sin pinear en el update | ~~Cerrado~~ — `firestore.rules:1203`, `rules.test.js` |
| QA-SEC-004 | — | **nunca asignado** |
| QA-SEC-005 | — | **nunca asignado** |
| QA-SEC-006 | App Check obligatorio en los callables desplegados | ~~Cerrado~~ — `appcheck-enforcement.test.ts`. Su cobertura quedó desactualizada (→ QA-SEC-016) y se **re-cerró** con inventario derivado de `index.ts` en [#805](https://github.com/Backhaus7997/treino/pull/805) |
| QA-SEC-007 | `storage:avatars/` — `list` enumera el padrón de uids con avatar | Abierto — [#764](https://github.com/Backhaus7997/treino/issues/764), §3.6 |
| QA-SEC-008 | `storage:customExerciseVideos/` — `list` exfiltra la videoteca entera de un PF | Abierto — [#763](https://github.com/Backhaus7997/treino/issues/763), §3.6 |
| QA-SEC-009 | `storage:avatars/` — `delete` denegado hasta para el dueño por null deref | Abierto — [#765](https://github.com/Backhaus7997/treino/issues/765), §3.6 |
| QA-SEC-010 | Oráculo de existencia por `resource == null` + doc id determinístico | Abierto — [#777](https://github.com/Backhaus7997/treino/issues/777), §4.9 |
| QA-SEC-011 | `isProfilePublic` no se aplica en las reglas | Abierto — [#778](https://github.com/Backhaus7997/treino/issues/778), §4.9 |
| QA-SEC-012 | `visibility: 'shared'` concede lectura mundial a una feature reservada | Abierto — [#779](https://github.com/Backhaus7997/treino/issues/779), §4.9 |
| QA-SEC-013 | El gate de rol de trainer no llegó a 3 colecciones | Abierto — [#780](https://github.com/Backhaus7997/treino/issues/780), §4.9 |
| QA-SEC-014 | `appointments` create sin allowlist ni cap de tamaño | Abierto — [#781](https://github.com/Backhaus7997/treino/issues/781), §4.9 |
| QA-SEC-015 | `temp/uploads` sin allowlist de content-type ni cap | ~~Cerrado~~ — #804 (issue [#782](https://github.com/Backhaus7997/treino/issues/782)): bloque cerrado entero, no acotado. `storage.rules:88`, `temp-uploads-storage-rules.test.ts`, §4.9 |
| QA-SEC-016 | El scanner de App Check cubre 2 de 5 callables | ~~Cerrado~~ — [#783](https://github.com/Backhaus7997/treino/issues/783) / [#805](https://github.com/Backhaus7997/treino/pull/805), `appcheck-enforcement.test.ts` + `helpers/appcheck-audit.ts`, §4.8.1 y §4.9 |
| QA-SEC-100 | Android: `allowBackup` | ~~Cerrado~~ — `test/security/android_manifest_backup_test.dart` |

**Próximo id libre: QA-SEC-017** (y `QA-SEC-1xx`: 101).
