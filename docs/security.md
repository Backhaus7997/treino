# docs/security.md

Estado de la superficie de seguridad de TREINO. Hoy contiene **dos secciones**:
la matriz de cobertura de reglas (Slice A de #680) y el inventario de datos
personales, contrastado contra el cascade de borrado y contra la Política de
Privacidad. El threat model por actor y el registro `QA-SEC-xxx` van a vivir acá
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
| ✅ | Hay test negativo **y corre en CI** (`functions/src/__tests__/*-rules.test.ts`) |
| 🟡 | Hay test negativo, pero **sólo en la suite manual** `scripts/rules_test/` — nada lo ejecuta automáticamente (ver §1.4) |
| — | No hay ningún test negativo |

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

### 1.4 Hay dos suites de reglas, y una no corre en CI

Esto es lo primero que hay que saber antes de confiar en un ✅:

| Suite | Archivos | Corre en CI | Cómo se corre |
|---|---|---|---|
| `functions/src/__tests__/*-rules.test.ts` | 24 | **Sí** — `.github/workflows/ci.yml` job *Functions Test* | `npm --prefix functions run test:rules:emulator` |
| `scripts/rules_test/*.test.js` | 8 | **No** | `bash scripts/test_rules.sh` (a mano) |

`scripts/test_rules.sh` lo dice en su propio header: *"NOT part of CI — this is
a manual PR checklist item (reconsider at Fase 6)"*. Por eso las 🟡 de la
matriz están marcadas distinto: el test existe y pasa, pero **nada garantiza
que alguien lo corra antes de mergear**. Ocho colecciones dependen hoy
exclusivamente de esa suite para alguna de sus celdas: `users/{uid}/checkIns`,
`gyms`, `appointments`, `measurements` (delete), `athlete_billing`,
`athlete_notes`, `payments` (create) y `storage:chatMedia`.

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
7. **Las 8 colecciones que dependen sólo de la suite manual** (§1.4). El
   arreglo no es escribir más tests: es meter `scripts/test_rules.sh` en CI, o
   migrar esos archivos a `functions/src/__tests__/`. Es trabajo de Slice B.
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
2. Si agregás un test negativo → la celda pasa a ✅ (o 🟡 si lo pusiste en
   `scripts/rules_test/`, cosa que conviene evitar mientras esa suite no corra
   en CI).
3. Recalculá los totales de §1.1 y §1.2. Son conteos, no impresiones.
4. Los tests de reglas se corren con:

   ```bash
   npm --prefix functions run test:rules:emulator   # requiere Java 21+
   bash scripts/test_rules.sh                       # la suite manual
   ```

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

`runDeleteAccount` (`functions/src/delete-account.ts`) ejecuta ocho pasos, cada
uno en su `try/catch`, y borra el usuario de Auth al final. Esto es lo que cada
ítem del inventario recibe.

#### 2.2.1 Cobertura, ítem por ítem

| # | Store | Estado | Paso del cascade / motivo |
|---|---|---|---|
| 1 | `users/{uid}` | ✅ | `deleteUserDocs` → `recursiveDelete` |
| 2 | `users/{uid}/notifications` | 🟡 **parcial** | El inbox propio se va con el `recursiveDelete`. **Las copias en el inbox de terceros quedan** → QA-CMP-008 |
| 3 | `exercises` | n/a | Sin PII |
| 4 | `routines` | ❌ **hueco** | **No hay paso de cascade** → QA-CMP-004 |
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
| ✅ Cubierto | **24** | 1, 7, 9, 10, 13, 16-21, 25-31 + S1-S6 |
| 🟡 Parcial (queda PII recuperable) | **4** | 2, 6, 8, 24 |
| ⚪ Retenido a propósito, con decisión escrita en el código | **5** | 14, 15, 32, 33, 35 |
| ❌ Hueco sin decisión escrita | **4** | 4, 5, 12, 34 |
| n/a para una cuenta athlete (PII de un PF) | **3** | 11, 22, 23 |

**Titular: 7 de 40 ítems dejan datos personales recuperables sin que exista
ninguna decisión escrita que lo justifique** (los 4 huecos + los 3 parciales sin
decisión escrita: `posts/*/reactions` en posts ajenos, `appointments` y
`notifications`). El parcial restante, `trainer_links`, sí tiene decisión
escrita.

Eran 8 cuando se midió por primera vez. Bajó a 7 al cerrarse QA-CMP-004b y
QA-CMP-005b: `postPhotos/` (S6) pasó de hueco a cubierto, y el ítem 8 pasó de
hueco a parcial —queda sólo la mitad QA-CMP-005, las reacciones del usuario en
posts ajenos.

`delete-account.smoke.test.ts` afirma que `deletedCollections` trae las 8
entradas esperadas, pero **ninguna aserción comprueba la ausencia de residuo en
las colecciones que el cascade no toca** — que es exactamente donde están los
ítems de arriba. El test verifica lo que el cascade dice que hizo, no lo que
quedó en la base. Es la debilidad que dejó pasar QA-CMP-004b y QA-CMP-005b, así
que los tests que los cierran (`cascade/storage.test.ts` y
`cascade/posts.test.ts`) asertan la **ausencia** de los objetos y documentos
después del cascade, no la presencia de nombres en `deletedCollections`. El
smoke test sigue como estaba.

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

**Estado:** ~~QA-CMP-004b~~ y ~~QA-CMP-005b~~ están **cerrados** ([#754](https://github.com/Backhaus7997/treino/pull/754)) — los dos
salían del mismo comentario desactualizado en `cascade/posts.ts` y se
arreglaron juntos. El diagnóstico queda escrito abajo porque explica por qué
existieron. Los otros ocho siguen **abiertos**.

---

**QA-CMP-004 — `routines` no se borra, y hay un guard que asume que sí.**
`runDeleteAccount` no tiene ningún paso sobre `routines`. Sobreviven las rutinas
con `createdBy == uid` y —peor— las privadas con `assignedTo == uid`, que son
los planes que el PF le armó a ese alumno.

Lo que lo convierte en un hueco de contrato y no en un olvido: el trigger
`cleanupAssignedPlansOnUnlink` **se saltea explícitamente** el caso, delegándolo
en un paso que no existe:

```ts
// functions/src/cleanup-assigned-plans.ts:110-113
// Guard: account-deletion cascade owns its own cleanup — don't interfere.
if (reason === "account-deleted") {
  logger.info("cleanupAssignedPlans: skipping cascade reason=account-deleted");
  return { count: 0 };
}
```

Y `"account-deleted"` es exactamente el `reason` que escribe
`terminateTrainerLinks`. O sea: el único mecanismo que habría barrido esos
planes se apaga justo cuando hace falta.

*Reparación sugerida (no aplicada):* un paso de cascade que borre
`routines where assignedTo == uid`, y que decida qué hacer con
`createdBy == uid` según `visibility` (una plantilla pública que otros usan no
es lo mismo que una rutina privada).

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
