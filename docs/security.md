# docs/security.md

Estado de la superficie de seguridad de TREINO. Hoy contiene **tres secciones**:
la matriz de cobertura de reglas (Slice A de #680), el inventario de datos
personales contrastado contra el cascade de borrado y contra la Política de
Privacidad, y la decisión escrita sobre las lecturas amplias de Storage
(Slice E). El threat model por actor y el registro `QA-SEC-xxx` van a vivir acá
también, en secciones aparte.

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
| `athlete_notes` | 🟡 | — | 🟡 | 🟡 | — |
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

### 1.2 Storage — 6 paths declarados en `storage.rules`

| Path | get | list | write | delete |
|---|---|---|---|---|
| `avatars/{file}` | ✅† | ✅ | ✅ | — |
| `temp/uploads/{uid}/**` | — | — | — | — |
| `customExerciseVideos/{uid}/**` | ✅† | ✅ | ✅ | ✅ |
| `chatMedia/{chatId}/{uid}/**` | 🟡 | 🟡 | — | — |
| `athleteFiles/{pairId}/**` | ✅ | ✅ | ✅ | ✅ |
| `postPhotos/{uid}/{file}` | ✅ | ✅ | ✅ | ✅ |

**17 de 24 celdas** (71%). Hay además un séptimo bloque, el catch-all
`match /{allPaths=**} { allow read, write: if false; }`, que sólo se ejercita
de refilón: el caso "listar `postPhotos/`" de
`post-photos-storage-rules.test.ts` cae en él, pero nada lo testea de frente.

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
> La celda `delete` de `avatars` sigue en `—` por un motivo distinto: hoy el
> borrado se deniega **hasta para el dueño**, y por un null deref en la línea
> `&& request.resource.size < 5 * 1024 * 1024` del `write`, no por falta de
> permiso. Cualquier test ahí pasaría por el motivo equivocado, que §1.8
> prohíbe. Es **QA-SEC-009**.
>
> Los tres tickets están medidos contra el emulador y explicados en §3.

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
|---|---|---|---|
| `functions/src/__tests__/*-rules.test.ts` | 24 | *Functions Test* | `npm --prefix functions run test:rules:emulator` |
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
|---|---|---|---|
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
2. **`storage:temp/uploads` y el catch-all `{allPaths=**}`**: cero tests.
   `temp/uploads` es `read: if false` + write por dueño, y ahí van los Excel
   que sube el PF. Barato de cerrar; quedó afuera por tiempo.
3. **`users/{uid}` get/list**: la regla es owner-only y no hay ni un negativo
   que compruebe que un tercero no lee el doc de otro. Cubierto de refilón por
   los tests de subcolecciones, nunca de frente.
4. **`chats` delete y `chats/{id}/messages` update+delete** son `if false`
   (mensajes inmutables en MVP). Cero tests. Barato.
5. **`trainer_links` create y `reviews` update/delete**: `reviews` delete es
   `if false` (sólo la CF de borrado de cuenta), sin test.
6. **`exercises`, `mail_queue`, `coach_availability_*`,
   `users/{uid}/customExercises`**: cero. `mail_queue` es `read, write: if
   false` y su comentario dice por qué importa (relay de spam con nuestra
   reputación de remitente + emails de otros usuarios) — es el más barato de
   todos de cerrar.
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
| 22 | `coach_availability_rules/{id}` | Agenda semanal del PF | 👤 (PF) | PF |
| 23 | `coach_availability_overrides/{id}` | Excepciones de agenda del PF | 👤 (PF) | PF |
| 24 | `appointments/{id}` | `athleteId`, **`athleteDisplayName` (nombre denormalizado)**, `startsAt`, `noteBefore`, `noteAfter` (notas de coaching), `paymentId` | 🫱 + 🔗 | Alumno + PF |
| 25 | `measurements/{id}` | **Antropometría completa**: `weightKg`, `fatPercentage`, `muscleMassKg` y 18 circunferencias (hombros, pecho, cintura, cadera, glúteos, bíceps L/R y flexionados, antebrazos, muslos alto/medio L/R, gemelos L/R), `notes` | 👤 o 🫱 (`recordedBy`) | Alumno + PF vinculado |
| 26 | `performance_tests/{id}` | `cmjCm`, `squatJumpCm`, `abalakovCm`, `broadJumpCm`, sprints 10/20/30/40 m, 1RM de sentadilla/banco/peso muerto/press/dominadas, `vo2maxMlKgMin`, course navette, Cooper | 👤 o 🫱 | Alumno + PF vinculado |
| 27 | `athlete_billing/{id}` | `trainerId`, `athleteId`, `amountArs`, `cadence` | 🫱 | Sólo el PF |
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
| S2 | `temp/uploads/{uid}/**` | Excel de planes que sube el PF | 👤 (PF) | Nadie (`read: if false`) |
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
|---|---|---|---|
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
}
```

> **Estado:** el `list` de este bloque estaba abierto y es el leak QA-SEC-007.
> **Cerrado en #764.** Lo que sigue es la medición **previa** al arreglo, que es
> lo que lo justifica; el estado actual está en la fila re-medida de §3.5.

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
| `delete` | **ROTO** — ver abajo. → **QA-SEC-009** |

#### 3.2.1 El `delete` de avatars está roto, y falla en silencio

El bloque **no declara `allow delete`**. En Storage, `delete` cae bajo `write`,
cuya condición dereferencia `request.resource.size` — y en un `delete`
**`request.resource` es null**. El emulador lo dice con el dedo en la línea:

```
EvaluationException: Error: storage.rules line [13], column [22]. Null value error.
```

`storage.rules:13` es exactamente `&& request.resource.size < 5 * 1024 * 1024`.

Medido: **el dueño no puede borrar su propio avatar** (DENY). No es un agujero
—falla cerrado— pero sí es un bug de producto, y tiene una víctima concreta:

- `avatar_web_uploader.dart:105-113` (`deleteStored()`) borra
  `avatars/{uid}.jpg` **best-effort, dentro de un `catch (_) {}` vacío**.
- Lo llama `cuenta_tab.dart:427-443` (`_removePhoto`, el botón "Quitar foto" de
  Coach Hub), con el comentario *"no dejar el objeto huérfano en
  `avatars/{uid}.jpg`"*.

El `delete` **siempre** se deniega, el `catch` se lo come, el usuario ve el
toast *"Foto quitada"*, y el objeto **sigue en el bucket**: bajable por su URL
con token (que es una credencial al portador, §3.1) y enumerable por cualquier
autenticado (el leak de arriba). La única limpieza real que existe es
`deleteAvatar` del cascade de borrado de cuenta, que corre con **Admin SDK** y
por eso no pega contra esta regla — y que barre *"cualquier extensión"*
(QA-CMP-002) justamente porque sabe que quedan huérfanos.

Dicho de otra forma: hoy **la app no tiene forma de borrar un avatar salvo
borrando la cuenta entera**. Contra la §7 de la política (*"podés... solicitar la
supresión de tus datos... desde la app"*), esto es una divergencia real, del
mismo tipo que las de §2.3.2.

El arreglo es chico y conocido — separar el `delete` del `write`, como ya hacen
`customExerciseVideos`, `chatMedia`, `athleteFiles` y `postPhotos`:

```
allow delete: if request.auth != null
              && fileName.matches(request.auth.uid + '\\..+');
```

**No se aplica en este PR.** Es un cambio de comportamiento en una regla de
producción y merece su propio ticket, su propio test y su propia verificación.

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
| `delete` | **Deliberado y correcto.** Tiene su propio `allow delete` — por eso funciona, a diferencia de `avatars` (§3.2.1). Pineado en §3.7. |

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
| `avatars/` | ALLOW | ~~ALLOW~~ → **DENY** ✅ | n/a (un nivel) | DENY | **DENY** 🐛 | DENY |
| `customExerciseVideos/` | ALLOW | ~~ALLOW~~ → **DENY** ✅ | ~~ALLOW~~ → **DENY** ✅ | DENY | ALLOW | DENY |
| `postPhotos/` | ALLOW | DENY | DENY | DENY | ALLOW | DENY |
| `chatMedia/` | DENY (no miembro) | DENY | DENY | DENY | — | DENY |
| `temp/uploads/` | DENY | DENY | DENY | DENY | — | DENY |
| catch-all `/` | — | — | DENY | — | — | — |

Anónimo: **DENY en todas las celdas de todos los paths**. El piso está bien.

⚠️ = leak sin decisión previa. 🐛 = deniega, pero por un null deref, no por
falta de permiso. ~~Tachado~~ = valor medido **antes** del PR que cerró la
celda; el valor después de la flecha es la re-medición contra el
`storage.rules` actual, como pide §3.8 regla 5. Las celdas `list` de
`customExerciseVideos/` se re-midieron en **#763** y la de `avatars/` en
**#764**: las tres son ahora DENY también para el **dueño** (la regla es
`if false`, no owner-only).

`chatMedia` y `temp/uploads` se midieron sólo como control — están fuera del
alcance de este slice y salieron cerrados en todos los casos probados, lo que
confirma que el endurecimiento de `chatMedia` (Slice A / AD-2) hace lo que dice.

### 3.6 Veredicto y tickets

**Dos de los tres paths tienen un leak real, y ninguno de los dos se arregla en
el PR que escribió esta sección (#680 Slice E).** Cambiar una regla de lectura
de Storage puede romper avatares o videos en producción; cada uno necesita su
propio change, su test y su verificación.

| ID | Qué | Path | Severidad | Arreglo propuesto |
|---|---|---|---|---|
| ~~**QA-SEC-007**~~ | `list` abierto a cualquier autenticado; enumera el padrón de uids con avatar | `avatars/` | Baja — los uids ya son enumerables por `userPublicProfiles` (`firestore.rules:780`), pero es un canal paralelo que sobrevive a cerrar aquél | **CERRADO en #764** (issue #764): `read` separado en `get` + `list`, `allow list: if false` |
| ~~**QA-SEC-008**~~ | `list` abierto en carpeta **y raíz**; exfiltra la videoteca entera de un PF y el directorio de qué PFs tienen contenido | `customExerciseVideos/` | **Media-alta** — no hay ninguna otra vía para obtener el inventario, y el contenido es el activo del PF | **CERRADO en #763** (issue #763): `read` separado en `get` + `list`, `allow list: if false`, comentario del bloque corregido (justificaba la lectura amplia con un motivo falso — §3.1) |
| **QA-SEC-009** | `delete` denegado hasta para el dueño por null deref en `storage.rules:13`; "Quitar foto" miente y el objeto queda huérfano | `avatars/` | Media — no es un agujero (falla cerrado) pero incumple la §7 de la política y deja objetos legibles que el usuario cree borrados | `allow delete` propio, como en los otros cuatro bloques (§3.2.1). Revisar además el `catch (_) {}` de `avatar_web_uploader.dart:110` |

Los tres son chicos y bien acotados. **QA-SEC-008 es el que yo haría primero.**
Y así se hizo: es el que cerró #763.

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
