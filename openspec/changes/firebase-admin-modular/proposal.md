# Propuesta — migrar `firebase-admin` de la API namespaced a los subpaths modulares

**Estado:** en curso. PR 1 mergeado (`43a40af3`); PRs 2, 3 y 4 abiertos y en verde, encadenados.
**⚠️ Cómo VERIFICAR los tests, o el error se repite (bis):** `npm run lint` **NO** es prueba de que
los tests compilen. ESLint con type information reporta violaciones de sus REGLAS, no todos los
errores de `tsc` — un `TS2339` no es ninguna regla, así que el lint salió limpio con 35 archivos
rotos en el PR 5a. Y correr las suites unitarias tampoco alcanza: las que rompieron eran las de
EMULADOR. El único oráculo que type-chequea los tests sin correrlos:

```bash
npx tsc --noEmit -p tsconfig.eslint.json   # ese tsconfig existe porque tsconfig.json excluye los tests
```

**⚠️ Cómo contar, o el error se repite:** la regex `admin\.<ns>` **se pierde las cadenas
multilínea** (`await admin\n  .firestore(app)`). Con ella el PR 4b se saltó 12 sitios en 8 archivos
y —peor— la verificación reportó «cero» y se publicó como tal. Contar SIEMPRE con
`rg -oU 'admin\s*\.\s*(firestore|auth|storage|credential|app|apps|messaging|database)\b'`.

**Avance medido:** de los 620 call sites quedan **473** — `functions/src` bajó de 238 a **81** y
`admin.app.App` quedó en **cero**, o sea que la migración de TIPOS está completa. `functions/src/__tests__`
y `scripts/` siguen enteros (PRs 5 a 10).
**Origen:** el trabajo de fondo que dejó pendiente el [#971](https://github.com/Backhaus7997/treino/pull/971) (`8ee4e298`).
**Issue relacionada:** [#889](https://github.com/Backhaus7997/treino/pull/889) — el PR de dependabot que
está rojo desde el 2026-08-31. Es el **síntoma**, no la tarea. No se mergea.

---

## 1. El problema

`firebase-admin@14` borró la API namespaced entera. El root export pasó a ser once símbolos
(`initializeApp`, `getApp`, `getApps`, `deleteApp`, `applicationDefault`, `cert`, `refreshToken`,
`FirebaseError`, `FirebaseAppError`, `AppErrorCode`, `SDK_VERSION`) y `admin.apps`, `admin.app`,
`admin.credential`, `admin.firestore`, `admin.auth`, `admin.storage` y `admin.messaging` quedaron
todos `undefined`.

El repo está clavado abajo en los dos lados y no puede subir. `scripts/` en `^13.10.0` (pineado por
el #971) y `functions/` en `^12.0.0`.

---

## 2. Los números, medidos hoy sobre `8ee4e298`

**No confíes en esta tabla: corré los comandos.** Es la regla de
[AGENTS.md § 11.1](../../../AGENTS.md) — una afirmación de completitud sin un comando reproducible
al lado no cuenta.

| directorio | qué se mide | call sites | archivos | qué lo frena |
|---|---|---|---|---|
| `scripts/` | código, sin comentarios | **88** | **46** de 58 escaneados | `scripts/test/firebase_admin_superficie.test.js` + `ignore` en dependabot |
| `functions/src` | producción, sin `__tests__` | **238** | **49** de 60 | `npm run build` (tsc) en `Functions Static Checks` |
| `functions/src/__tests__` | tests | **294** | **43** de 107 | `npm run lint` (typed) + `ts-jest` |

**Total real: 620 call sites en 138 archivos.** No 327 en 97.

### Las tres correcciones a los números que veníamos usando

1. **`functions/` es más del doble de lo que decía la tabla del brief.** Los 238 son sólo
   `functions/src` sin tests. `src/__tests__/` tiene **294 más**, y no son inocuos: `tsconfig.json`
   excluye los tests del build, pero `tsconfig.eslint.json` los incluye **a propósito** (`"include":
   ["src/**/*"], "exclude": []`) porque el lint es typed, y `ts-jest` compila cada test con
   `tsconfig.json`. Por eso en el #889 fallan **los dos** jobs, `Functions Static Checks` y
   `Functions Test`.

2. **`scripts/` son 88 call sites en 46 archivos, no 89 en 48.** El número 89/48 está escrito en
   tres lugares (`scripts/package.json`, `scripts/README.md`, `.github/dependabot.yml`) y viene de
   un `rg` crudo que cuenta prosa: cinco de sus hits son comentarios que *nombran* APIs muertas.
   La cuenta que importa es la del gate, que strippea comentarios con la misma lógica que
   `frontera.test.js`.

3. **`functions/` NO tiene cero imports modulares.** Ya hay **cinco** `import { FieldValue } from
   "firebase-admin/firestore"` conviviendo con la API namespaced bajo la v12, en producción:
   `add-alias.ts`, `places-search.ts`, `mail/enqueue-mail.ts`, `mail/send-queued-mail.ts`,
   `notifications/send-fcm.ts`. Eso no es un detalle de trivia — es la prueba de campo de que las
   dos APIs conviven (§ 3).

### Los comandos

```bash
# scripts/ — la cuenta que hace fallar el gate (strippea comentarios como lo hace el test).
# Va por heredoc y no por `node -e`: la regex del gate contiene comillas simples y dobles,
# y adentro de `node -e '...'` el shell se come el string. Corrido desde la raíz del repo.
cat > /tmp/contar_admin.cjs <<'FIN'
const fs = require('node:fs'), p = require('node:path');
const R = 'scripts', X = new Set(['test', 'rules_test', 'node_modules']);
const sc = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const RE = /(?<![\w$./'"\\-])admin\.([A-Za-z_$][\w$]*)(?:\.([A-Za-z_$][\w$]*))?/g;
const f = (d = R, q = '') => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) =>
  e.isDirectory()
    ? (X.has(e.name) || e.name.startsWith('.') ? [] : f(p.join(d, e.name), q + e.name + '/'))
    : (/\.(js|mjs)$/.test(e.name) ? [q + e.name] : []));
let n = 0; const arch = new Set();
for (const x of f()) for (const _ of sc(fs.readFileSync(p.join(R, x), 'utf8')).matchAll(RE)) { n++; arch.add(x); }
console.log(`${n} call sites en ${arch.size} archivos (${f().length} escaneados)`);
FIN
node /tmp/contar_admin.cjs   # → 88 call sites en 46 archivos (58 escaneados)

# functions/ producción
rg -o 'admin\.(firestore|auth|storage|credential|app|apps|messaging|database)\b' -g '*.ts' functions/src | rg -v '__tests__|\.test\.' | wc -l

# functions/ tests — el bloque que faltaba en la cuenta
rg -o 'admin\.(firestore|auth|storage|credential|app|apps|messaging|database)\b' -g '*.ts' functions/src/__tests__ | wc -l
```

---

## 3. El hallazgo que decide la forma del trabajo

**Los subpaths modulares YA EXISTEN en las dos versiones instaladas.** Verificado contra el paquete,
no de memoria:

```
scripts/   firebase-admin = 13.10.0     functions/  firebase-admin = 12.7.0
  firebase-admin/app        ✓ initializeApp, getApp, getApps, cert, applicationDefault, deleteApp
  firebase-admin/firestore  ✓ getFirestore, Timestamp, FieldValue, FieldPath, Filter
  firebase-admin/auth       ✓ getAuth
  firebase-admin/storage    ✓ getStorage
  firebase-admin/messaging  ✓ getMessaging
  firebase-admin/database   ✓ getDatabase          (sólo probado en 13.10.0)
```

**Consecuencia: la migración se DESACOPLA del bump de versión.** Se migra sobre 12/13, todo queda
verde a cada paso, y el salto a 14 es un PR final de una línea por `package.json`. Nunca existe un
PR que cambie 300 call sites *y* el SDK al mismo tiempo — que es exactamente la forma que hizo
imposible revisar el #889.

Y no es sólo que coexistan: **devuelven los mismos objetos.** Medido con una app inicializada:

| chequeo | resultado |
|---|---|
| `admin.firestore() === getFirestore()` | `true` |
| `admin.auth() === getAuth()` | `true` |
| `admin.storage() === getStorage()` | `true` |
| `admin.firestore.Timestamp === Timestamp` | `true` (misma clase) |
| `admin.firestore.FieldValue === FieldValue` | `true` |
| `admin.credential.cert === cert` | `true` (misma función) |
| `admin.app() === getApps()[0]` | `true` |
| `admin.apps.length === getApps().length` | `true` |
| `admin.initializeApp === initializeApp` | **`false`** ← distintas funciones, mismo efecto |

Misma instancia y misma clase significa que durante una migración parcial **un archivo migrado y uno
sin migrar comparten el Firestore, y un `instanceof Timestamp` cruzado sigue dando `true`**. Esa es
la propiedad que hace seguros los PRs encadenados archivo por archivo.

### Tabla de equivalencias

| namespaced (v12/v13) | modular | subpath |
|---|---|---|
| `admin.firestore()` / `admin.firestore(app)` | `getFirestore()` / `getFirestore(app)` | `firebase-admin/firestore` |
| `admin.firestore.Timestamp` | `Timestamp` | `firebase-admin/firestore` |
| `admin.firestore.FieldValue` | `FieldValue` | `firebase-admin/firestore` |
| `admin.firestore.FieldPath` / `.Filter` | `FieldPath` / `Filter` | `firebase-admin/firestore` |
| `admin.firestore.DocumentData` *(tipo)* | `DocumentData` | `firebase-admin/firestore` |
| `admin.firestore.Query` / `.Firestore` / `.DocumentReference` / `.Transaction` *(tipos)* | homónimos | `firebase-admin/firestore` |
| `admin.auth()` / `admin.auth(app)` | `getAuth()` / `getAuth(app)` | `firebase-admin/auth` |
| `admin.storage()` / `admin.storage(app)` | `getStorage()` / `getStorage(app)` | `firebase-admin/storage` |
| `admin.messaging(app)` | `getMessaging(app)` | `firebase-admin/messaging` |
| `admin.messaging.Messaging` *(tipo)* | `Messaging` | `firebase-admin/messaging` |
| `admin.app()` | `getApp()` | `firebase-admin/app` |
| `admin.app.App` *(tipo)* | `App` | `firebase-admin/app` |
| `admin.apps` | `getApps()` | `firebase-admin/app` |
| `admin.credential.cert(x)` | `cert(x)` | `firebase-admin/app` |
| `admin.credential.applicationDefault()` | `applicationDefault()` | `firebase-admin/app` |
| `admin.initializeApp(o)` | `initializeApp(o)` | `firebase-admin/app` |

**Ojo:** `admin.initializeApp`, `admin.getApp` y `admin.getApps` **sobreviven en v14** — son parte de
los once símbolos del root. No son urgentes; se migran por consistencia, no por compatibilidad.

### ⚠️ `admin.app.App` → `App` NO es un cambio de tipo puro

Lo encontró `tsc` al implementar el PR 2, y contradice la fila de arriba leída de más:

1. **El `App` modular no tiene los accesores de conveniencia.** El `admin.app.App` namespaced
   expone `.firestore()`, `.auth()`, `.storage()`, `.messaging()` como métodos; el modular es un
   handle pelado. Renombrar el tipo rompe todo `app.firestore()` — que es un cambio de **runtime**,
   no de tipos.

2. **La asignabilidad va en UNA sola dirección** — la primera versión de esta nota decía
   «mutuamente inasignables» y era falso. `TS2345: Argument of type '…/app/core".App' is not
   assignable to parameter of type '…/firebase-namespace-api".app.App'`. O sea que **el tipo `App`
   no se puede migrar archivo por archivo si un archivo migrado le pasa su `App` a uno sin migrar**.
   Al revés SÍ anda: el namespaced tiene más miembros, así que se asigna a un `App` modular sin
   problema —hubo 29 archivos con `function getApp(): App { return admin.app(); }` compilando—. Por
   eso el PR 4b no tuvo componente conexo: con `admin.app.App` ya en cero no quedaba un solo
   parámetro namespaced al que pasarle un `App` modular.

En este repo son **4 archivos**: los tres de `src/subscriptions/mp/` (`reconcile.ts`,
`tier-mapping.ts`, `create-preapproval.ts`) y `src/notifications/notify-link-change.ts`. Se
excluyeron del PR 2 —que se define por "cero runtime"— y van al PR 4 junto con las conversiones
`app.firestore()` → `getFirestore(app)`.

**El cuarto apareció por un rebase, y esa es la parte que hay que retener.** Cuando se escribió el
PR 2, `notify-link-change.ts` tenía tres `admin.app.App` y los tres se migraron. Entre eso y el
rebase sobre el main nuevo, main incorporó `backfillChatLinkId(app: admin.app.App)` (#968), que hace
`const db = app.firestore()`. **El cherry-pick aplicó limpio** —los textos no se tocan— y el
resultado no compilaba. Es el §11.2 de AGENTS.md en su variante silenciosa: no borra trabajo ajeno,
lo **combina** en un error de tipos que ningún marcador de conflicto anuncia.

**Corolario para los PRs 4 en adelante: el escaneo por regex de los accesores NO alcanza.** Un
contador línea a línea se pierde las cadenas multilínea —`await app\n  .firestore()`, donde la línea
del `.firestore()` no tiene identificador antes del punto—, que es exactamente cómo estaba escrito
`backfillChatLinkId`. **El único oráculo confiable es `tsc`**: migrar, compilar, y dejar que el
compilador enumere el componente conexo. Y recompilar después de cada rebase, porque el componente
conexo cambia cuando main avanza.

---

## 4. El riesgo central, y está probado

**El doble de test de `scripts/` NO intercepta los subpaths modulares.** `stub_firebase_admin.js`
matchea el specifier **exacto**:

```js
if (request === 'firebase-admin') return adminStub;     // Module._load, línea ~250
```

y el hook ESM hace lo mismo (`if (specifier === 'firebase-admin')` en `esm_stub_hooks.mjs`). Medido:

```
$ cd scripts && node --require ./test/fixtures/stub_firebase_admin.js -e "..."
require('firebase-admin')            → stub? true
require('firebase-admin/firestore')  → stub? false | getFirestore REAL? true
require('firebase-admin/app')        → stub? false | cert REAL? true
```

**Por qué esto es peligroso y no sólo molesto.** Los tests de compuerta
(`storage_scripts_destination.test.js`, `npm_entrypoints_banner.test.js`,
`backfill_production_banner.test.js`, `strip_appointment_reason_gate.test.js`) prueban que un guard
corta **antes** de tocar datos, y lo prueban afirmando la **AUSENCIA** de `STUB_FIRESTORE_REACHED` /
`STUB_STORAGE_REACHED`. Ese marcador también falta cuando el stub nunca se aplicó.

O sea: el primer script que migre a `firebase-admin/firestore` sin tocar el stub deja su test de
compuerta **verde midiendo nada**, con el SDK real cargado. Es literalmente el modo de falla que el
propio fixture documenta del #846 ("verde en Node 22, decorativo en CI"), y el patrón del #826 — una
cobertura que dice estar y no está.

**La regla, no negociable:** ningún PR migra un archivo de `scripts/` sin extender, **en el mismo
commit**, la intercepción del stub a los subpaths, con un marcador afirmado en **positivo** (al
estilo de `STUB_ESM_INTERCEPTED`) que pruebe que la intercepción del subpath está viva.

El mismo agujero existe en `functions/`: los 43 tests hacen `jest.mock("firebase-admin", …)` y
**ninguno** mockea un subpath. Hoy ya conviven con los 5 imports reales de `FieldValue`, y no
explota porque `FieldValue`/`Timestamp` son fábricas puras que no necesitan app. `getFirestore()` sí
la necesita — ese es el que rompe.

**Y en `functions/` también termina en verde, no en rojo.** Era la duda razonable —en jest, un
módulo real sin mockear suele fallar ruidosamente— y la medición dice que no siempre:

- **39 aserciones por AUSENCIA** (`not.toHaveBeenCalled`) en la suite, **21 de ellas sobre
  `sendEachForMulticast`**: o sea «no se mandó la notificación».
- Los **nueve** archivos que hacen esa aserción **no espían el logger** (`warnSpy` / `errorSpy` /
  `spyOn(logger…)`: cero hits en los nueve).
- Producción tiene **`catch all → log + no rethrow` como política escrita**:
  `review-aggregate.ts:144`, `link-aggregate.ts:119`, `template-rating-aggregate.ts:109`,
  `notify-wear-workout.ts:124` («Un aviso perdido no puede hacer fallar la escritura de la sesión»).

Encadenado: archivo migrado llama al `getFirestore()` real → tira porque no hay app → el catch-all
se lo traga y loguea → nunca se llega al `sendEachForMulticast` → `expect(…).not.toHaveBeenCalled()`
**pasa**.

*(No todo caso con aserción por ausencia es de estos: `link-load-reconcile.test.ts` tiene cinco y su
módulo tiene un catch que se traga el error, pero ahí las aserciones son sobre `warnSpy`, así que el
catch **sí** se observa y el test se pondría rojo. Los nueve son los que asertan sobre el mock de
FCM.)*

---

## 5. El gate NO se achica solo del todo

`scripts/test/firebase_admin_superficie.test.js` tiene **tres** tests. Sólo uno se achica solo:

| test | ¿se achica solo? |
|---|---|
| 2 — «el `firebase-admin` instalado tiene TODA la API que usan los scripts» | **Sí.** Extrae la lista del código. A cero call sites, la lista es vacía y pasa trivialmente. |
| 1 — «el escaneo encuentra scripts y APIs» | **No.** Assertea `USOS.size >= 8` y `USOS.has('firestore')`. A migración completa, `USOS` está vacío → **rojo**. |
| 3 — «`admin.apps` es un array» | **No.** `assert.ok(Array.isArray(admin.apps))` está escrito a mano contra el SDK, sin depender del escaneo. En v14 `admin.apps` es `undefined` → **rojo para siempre**. |

Los tests 1 y 3 son correctos hoy (el 1 es la defensa contra un escaneo vacuo, el 3 es el que
reproduce el crash original) y **hay que retirarlos en el mismo PR que sube a 14**, no antes. Si se
tocan antes, se apaga la única red que hay durante la migración.

Esto contradice la premisa de que «no hay que editar el test». Hay que editarlo — una vez, al final,
y el PR que lo hace tiene que decir por qué.

---

## 6. El orden de los PRs

**Criterio: lo que no escribe en producción primero.** `functions/` corre en producción con
privilegios de Admin SDK; `scripts/` tiene ~20 backfills que escriben en `treino-dev`, que ES
producción ([AGENTS.md § Entornos](../../../AGENTS.md)).

Todos los PRs del 1 al 10 corren **sobre las versiones actuales** (12/13). El SDK no se toca hasta
el 11 y el 12.

| # | PR | dir | escribe en prod | ~líneas | por qué acá |
|---|---|---|---|---|---|
| **1** ✅ | Extender los dobles a los subpaths | `scripts/` + `functions/` | no | 661 | **Habilitante — HECHO** (`04821be4` + `2ccc3096`). Sin esto, todo lo que sigue puede salir verde sin medir. Cero cambios de producción: sólo fixtures y tests. |
| **2** ✅ | Tipos de `functions/` (`admin.app.App` → `App`, etc.) | `functions/src` + `functions/scripts` | no | 175 | **101 sitios en 46 archivos, cero riesgo runtime**: los tipos se borran al compilar y `tsc` lo prueba entero. Quedan afuera los 4 archivos que usan `app.firestore()` (los 3 de `subscriptions/mp/` + `notify-link-change.ts`) — ver el ⚠️ del § 3: ahí el rename arrastra runtime, así que van al PR 4. |
| **3** | `FieldValue` / `Timestamp` de `functions/` | `functions/src` | no | ~60 | Fábricas puras, sin app. Ya hay 5 en producción hace meses — el patrón está probado en campo. |
| **4** ✅ | El componente conexo del `App` | `functions/src` | **sí** | 133 | **HECHO** ([#985](https://github.com/Backhaus7997/treino/pull/985)). Los 4 archivos que el PR 2 no pudo tocar (`subscriptions/mp/` ×3 + `notify-link-change.ts`), 33 sitios. Hay que moverlos **enteros o nada**: los dos tipos de `App` son mutuamente inasignables. Primer PR con runtime real. |
| **4b** | El resto del idiom `ensureApp()` + los accesores | `functions/src` | **sí** | ~400 | Lo que queda de producción: **81 sitios**, con el idiom `admin.app()` repetido en **29 archivos** y 39 `admin.firestore(`. Acá entra el helper de mocks compartido, que ahora sí va a tener consumidores. Candidato seguro a partirse en dos o tres slices por subdirectorio. |
| **5** | Tests de `functions/` | `functions/src/__tests__` | no | ~350 | 294 sitios en 43 archivos. Va después de que producción esté migrada, así los mocks se escriben contra la forma final. Casi seguro se parte en 2-3 slices. |
| **6** | `scripts/lib/admin.js` + sus dobles | `scripts/` | **sí** | ~120 | La única puerta de inicialización (#834). `admin.apps` → `getApps()`, `admin.credential.cert` → `cert()`. `test/admin.test.js` inyecta un `adminFalso()` por parámetro (`{ apps, credential, initializeApp }`): **ese doble cambia de forma en el mismo commit.** No se toca `resolverContexto` ni la lógica de credenciales. |
| **7** | `backfill_*` + `cleanup_*` + `restore_*` | `scripts/` | **sí** | ~150 | 17 archivos, 20 call sites. El bloque más chato: casi todos son un `admin.firestore()` y nada más. |
| **8** | `seed_*` | `scripts/` | **sí** | ~250 | 11 archivos, **33 call sites** — el bucket más denso (`seed_posts.js` solo tiene 11). Incluye `seed_emulator_full.js`, que se niega a correr sin emulador. Candidato a partirse en dos. |
| **9** | El resto sin Storage | `scripts/` | **sí** | ~150 | 13 archivos: `import_*`, `migrate_trainer_locations`, `apply_technique`, `audit_*`, `build_catalog_proposal`, `dedup_exercise_generics`, `match_drive_videos_to_catalog`, `promote_user_to_trainer`, `accept_pending_link`, `reset_onboarding_cards`, `migrations/strip_appointment_reason.mjs`. El `.mjs` va acá porque es el único ESM y necesita la mitad ESM del stub (§ 4). |
| **10** | Los 4 que suben a Storage | `scripts/` | **sí** | ~80 | `apply_catalog_video_fill`, `extract_exercise_thumbnails`, `upload_drive_exercise_videos`, `upload_enriched_videos` — los † de AGENTS.md, 9 call sites. **Últimos a propósito: lo que escriben NO lo cubre el backup diario de Firestore.** Pasan por `exigirDestinoCoherente`; hay que verificar con el marcador del stub que el guard sigue disparando **antes** de la primera subida. |
| **11** | `scripts/` a `firebase-admin@14` | `scripts/` | no | ~40 | Retirar los tests 1 y 3 del gate (§ 5), levantar el `ignore` de dependabot, y borrar el candado documentado en `scripts/package.json` y `scripts/README.md`. |
| **12** | `functions/` a `firebase-admin@14` | `functions/` | no | ~10 | Una línea de `package.json` + lockfile. Cierra el #889, que se cierra sin mergear. |

### Por qué el criterio «read-only primero» NO se puede aplicar dentro de `scripts/`

Era el plan obvio y **no sobrevive a la medición**. Intenté clasificar los 46 archivos en «lee» y
«escribe» y el resultado fue inutilizable en las dos direcciones: `.set(` matchea `Map.set()`, así
que `build_catalog_proposal.js`, `match_drive_videos_to_catalog.js` y `audit_ranking_optin.js`
—que AGENTS.md documenta como **read-only**— salían marcados como escritores; y `.add(` / `.create(`
son tan ambiguos que sacarlos dejaba a `seed_measurements.js` y `seed_performance_tests.js`
marcados como read-only, que es absurdo para un seed.

La conclusión honesta es que **en `scripts/` casi no hay bucket read-only**: son ~44 escritores y
un puñado de excepciones que hay que confirmar leyendo cada archivo, no con un grep. Publicar un
orden basado en esa clasificación sería exactamente el cartel tranquilizador falso del § 11.1.

Entonces el orden de los PRs 7-10 usa criterios que **sí** se verifican:

1. **Los guards primero** (PR 6: `lib/admin.js`). Todo lo demás pasa por ahí.
2. **Storage último** (PR 10). Los cuatro † están enumerados en AGENTS.md, y lo que Storage escribe
   no lo cubre el backup diario de Firestore — o sea que es el único bloque cuyo error no se puede
   deshacer.
3. **El resto agrupado por prefijo**, para que cada PR entre en el presupuesto de review de 400
   líneas y el rojo apunte a un bloque.

La protección real durante la ventana de migración no es el orden: es que **nadie corra un script
de `scripts/` a mano mientras dure**. Eso va escrito en cada PR.

### Por qué `functions/` va antes que `scripts/`

Suena al revés del criterio, y no lo es. El criterio ordena por **riesgo de escritura durante la
migración**, no por criticidad del código:

- `functions/` se **deploya**, y un deploy es un evento explícito y aprobado. Migrar `functions/` no
  escribe nada hasta que alguien corra el deploy — y no hay que correrlo: los PRs 2-5 van a `main`,
  no a producción. El riesgo está gateado por `tsc` + 107 tests contra el emulador.
- `scripts/` se corre **a mano desde la máquina de alguien**, con `$TREINO_SA_KEY` apuntando a
  `treino-dev`. Un script migrado a medias que alguien ejecuta antes de que su doble esté al día
  escribe en producción sin cartel. Menos gates y más superficie humana.

Y el 60% de `functions/` (los 143 tipos) es la parte de todo el trabajo con **menos riesgo posible**:
código que no existe en runtime.

---

### Qué entregó el PR 1, y qué NO

Commits `04821be4` (scripts) y `2ccc3096` (functions). 661 líneas, ningún archivo de producción.

- `scripts/`: la intercepción de todo `firebase-admin/*` en las dos mitades (CJS y ESM), la segunda
  puerta del doble en `fixtures/firebase_admin_subpaths.js` —armada con las MISMAS piezas que
  `adminStub`, para que no puedan driftear—, el marcador positivo `STUB_SUBPATH_INTERCEPTED`, y
  `subpath_stub_interception.test.js` con control negativo. Suite: 472 → **478**, cero fallas.
- `functions/`: `firebase-admin-mock-surface.test.ts`, el trinquete que recorre el grafo de imports
  transitivo de cada test y exige el `jest.mock` del subpath cuando el grafo importa un símbolo que
  necesita app. **Verificado que no pasa en vacío**: se simuló el estado post-PR-4 agregando
  `getFirestore` al import de `send-fcm.ts` y el gate se puso rojo nombrando los dos tests, el
  símbolo y el archivo del que viene — incluido uno que llega por transitividad. Revertido.

**Lo que se decidió NO hacer en el PR 1:** el helper compartido de mocks para `functions/`. Hoy no
tendría un solo consumidor —el gate está verde y ningún test necesita mockear un subpath todavía—, y
un helper sin uso es superficie que se desactualiza sola. Va en el **PR 4**, que es donde aparece el
primer `getFirestore()` de verdad y con él la necesidad de que los 43 tests no inventen 43 fakes
distintos.

---

## 7. Lo que se levanta al terminar

Todo esto queda pendiente hasta el PR 11, y **no antes**:

- `.github/dependabot.yml` — el bloque `ignore` de `firebase-admin` en `/scripts` (dice explícito
  «se levanta este bloque el día que los 48 archivos usen los subpaths modulares»).
- `scripts/package.json` — la clave `"//  🔒 firebase-admin QUEDA EN 13.x A PROPÓSITO"`.
- `scripts/README.md` § «🔒 `firebase-admin` está clavado en 13.x, y no es por comodidad».
- `scripts/test/firebase_admin_superficie.test.js` — los tests 1 y 3 (§ 5). El test 2 se queda: pasa
  a valer cero y esa es exactamente la señal de que la migración terminó.

Los tres primeros repiten el número **89 en 48 archivos**. Al tocarlos, corregirlo a lo medido (§ 2)
o borrarlo — no propagarlo.

---

## 8. Riesgos y cómo se cierran

| riesgo | cómo se cierra |
|---|---|
| Un test de compuerta queda verde midiendo nada (§ 4) | PR 1 primero, con marcador afirmado en positivo. Es la razón de que el PR 1 exista. |
| El doble de `test/admin.test.js` deriva del SDK real | Cambia en el **mismo commit** que `lib/admin.js` (PR 6). Es el drift que dejó pasar el bug original. |
| Alguien corre un script de `scripts/` a mano durante la ventana | Es el riesgo real, y no lo cierra el orden de los PRs (§ 6): va escrito en el cuerpo de cada uno. Los guards (`lib/admin.js`, `credenciales.js`, `storage_target.js`) se migran primero y siguen en el camino. |
| Un upload a Storage migrado a medias sube a prod | PR 10 es el último y ninguno de sus 4 archivos se toca antes. Lo que Storage escribe **no** lo cubre el backup diario de Firestore. |
| Un PR pasa 400 líneas | PRs 4, 5 y 8 son los candidatos; se parten por subdirectorio o por prefijo. Regla del repo: chained PRs o `size:exception` aprobado. |
| Dependabot manda un security update de v14 mientras tanto | Ya está contemplado en `dependabot.yml`: llega igual, `scripts-test` se pone rojo, y ese rojo es «¿migraste?». La respuesta es acelerar el plan, no silenciar el test. |

---

## 9. Lo que NO se toca

- `resolverContexto` y toda la lógica de credenciales de `scripts/lib/credenciales.js` (#834).
- El PR [#889](https://github.com/Backhaus7997/treino/pull/889). Se cierra en el PR 10, sin mergear.
- Los tres literales de bucket de producción hardcodeados (`build_catalog_proposal`,
  `match_drive_videos_to_catalog`, `_video_map.js`) y el test estructural que los mantiene inertes.
- El default `demo-treino` de `.firebaserc` y todo lo del #840.
