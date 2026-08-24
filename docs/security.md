# docs/security.md

Estado de la superficie de seguridad de TREINO. Hoy contiene **una sola
sección**: la matriz de cobertura de reglas (Slice A de #680). El threat model
por actor, el inventario de PII y el registro `QA-SEC-xxx` (Slices C y E) van a
vivir acá también, en secciones aparte.

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
| `avatars/{file}` | — | — | — | — |
| `temp/uploads/{uid}/**` | — | — | — | — |
| `customExerciseVideos/{uid}/**` | — | — | — | — |
| `chatMedia/{chatId}/{uid}/**` | 🟡 | 🟡 | — | — |
| `athleteFiles/{pairId}/**` | ✅ | ✅ | ✅ | ✅ |
| `postPhotos/{uid}/{file}` | ✅ | ✅ | ✅ | ✅ |

**10 de 24 celdas** (42%). Hay además un séptimo bloque, el catch-all
`match /{allPaths=**} { allow read, write: if false; }`, que no se testea en
ningún lado.

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

1. **`storage:avatars`, `customExerciseVideos`, `postPhotos` permiten lectura a
   cualquier autenticado** (punto 5 del issue #680). No hay test porque **no
   hay decisión escrita**: testear un permiso amplio antes de decidir si es
   deliberado congela el status quo. Va con Slice E, no acá.
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
   por #680 Slice B: `scripts/test_rules.sh` es el job *Rules Test* de CI y
   bloquea el merge (§1.4). Queda pendiente, como deuda de consolidación y no
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
   no porque el otro job valga menos (los dos bloquean el merge), sino porque
   ahí está TypeScript y es donde las dos suites van a converger algún día
   (§1.6, punto 7).
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
