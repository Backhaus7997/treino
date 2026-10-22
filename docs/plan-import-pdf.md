# Import de plan desde PDF (app mobile del PF)

Estado: **especificación aprobada** (2026-10-22). Fuente de verdad para
implementar el import; las decisiones de producto de acá son del dueño y no se
reinterpretan en el código.

El contrato técnico compartido entre el backend (`functions/`) y el dominio
Dart (`lib/features/coach_hub/data` y `domain`) está copiado abajo, en
«Contrato del callable» y «`PdfPlanExtraction`». Si el código y esta sección no
coinciden, se corrige uno de los dos en el mismo PR — no se deja divergir.

Depende de: el import de Excel periodizado
([plan-import-excel-periodizado.md](./plan-import-excel-periodizado.md)), cuyo
dominio (`PeriodizedPlan`, matcher, draft, mapper a `Routine`) se reusa; y de
#1455 (el matcher no adivina variantes).

## Qué resuelve

El PF ya tiene su plan armado en un PDF —su formato, no el nuestro: tablas,
semanas en columnas, superseries escritas en prosa, a veces escaneado— y hoy lo
tiene que volver a tipear en el editor. Con este import lo sube desde el
celular, un modelo de lenguaje lee el plan y lo devuelve estructurado, la app
matchea los ejercicios contra el catálogo y el PF **revisa una vista previa
antes de guardar**. Nada se asigna al alumno sin esa revisión.

Por qué un LLM y no un parser: la gramática del Excel funciona porque la
plantilla es nuestra. El PDF es formato del PF; el texto plano pierde la
geometría de las tablas y un escaneado necesita OCR. Claude recibe el PDF como
texto **e imagen** por página, así que lee tablas y escaneados con el mismo
camino.

## Alcance v1

- **Sólo app mobile, sólo PDF.** Sin Coach Hub web y sin fotos del plan.
- **Sólo entrenadores** (`role == "trainer"`), desde la ficha de un alumno: el
  alumno ya es conocido, no hace falta selector.
- **Apagado por kill switch** hasta la evaluación del rollout (abajo).

## Flujo del PF en mobile

1. En la ficha del alumno (`athlete_detail_screen.dart`), junto a «Crear plan»,
   el PF toca **«Importar de PDF»**.
2. **Pantalla de subida.** Aviso de privacidad (ver «Aviso en la pantalla de
   subida»), el cupo restante de la semana y del día, y el selector de archivo
   (`file_picker`, sólo `.pdf`). El cliente valida tamaño y extensión antes de
   llamar; el servidor vuelve a validar todo (magic bytes, tamaño, páginas).
3. **Espera.** Llamada a `parsePlanPdf` con el PDF inline en base64. La
   extracción puede tardar más de un minuto: el `HttpsCallableOptions(timeout)`
   del lado Dart acompaña al `timeoutSeconds` 300 del servidor, y la pantalla
   muestra un estado de espera explícito, no un spinner mudo.
4. **Vista previa mobile.** Reusa `PeriodizedDayPreviewCard`, el selector de
   semana y el draft del import Excel. Por ejercicio muestra el texto fuente del
   PDF (`sourceText`) para que el PF compare contra lo que escribió; las celdas
   vacías salen en rojo, igual que en el Excel. Los `warnings` del modelo se
   listan arriba con su página.
5. **Resolver ejercicios** (ver «Matcheo») — vincular con la biblioteca,
   confirmar sugerencias, o crear propios uno por uno o en bloque.
6. **Guardar.** Con todo resuelto, se asigna al alumno con
   `RoutineRepository.createAssigned`. Después el plan se edita con el editor de
   siempre: la vista previa no es un editor.

Lo que **no** pasa en ningún punto: el PDF no se sube a Storage ni se escribe en
Firestore, y subirlo no crea nada (ni rutina, ni ejercicios propios, ni
aliases). Todo se crea recién cuando el PF confirma.

## Contrato del callable `parsePlanPdf`

Region `southamerica-east1`, `timeoutSeconds` 300.

Request:

```ts
{ pdfBase64: string, fileName: string, athleteId?: string }
```

Response:

```ts
{
  plan: PdfPlanExtraction,
  quota: { usedThisWeek, limitWeekly, usedToday, limitDaily },
  model: string
}
```

Errores (`HttpsError`):

| Código | Cuándo | Cupo |
|---|---|---|
| `unauthenticated` | sin auth | no se toca |
| `permission-denied` | no es `role == "trainer"` | no se toca |
| `failed-precondition` | kill switch apagado (sin `details`); o Vertex rechaza los structured outputs por la org policy (`details: { reason: "structured_outputs_disabled" }`, ver Rollout paso 3) | no se toca / **se devuelve** |
| `invalid-argument` | no es PDF, > 5 MB, > 20 páginas o cifrado/con contraseña; `details: { reason: "not_pdf" \| "too_big" \| "too_many_pages" \| "encrypted" }` | no se toca |
| `resource-exhausted` | sin cupo; `details: { scope: "week" \| "day", resetsAt: ISO }` | — |
| `deadline-exceeded` | el LLM tardó demasiado | **se devuelve** |
| `internal` | salida del LLM inválida tras validar | **se devuelve** |

**Proveedor.** Claude en **Vertex AI** (`@anthropic-ai/vertex-sdk`,
`region: "global"`, proyecto del entorno). Auth por la service account de la
función (ADC): **sin API key ni secret nuevo**. El endpoint regional para los
modelos nuevos no existe, por eso `global` y no `southamerica-east1`.

**Modelo.** `claude-opus-5-5` por defecto, configurable **sin redeploy**
(parámetro de config). El callable devuelve en `model` cuál se usó, para poder
atribuir cada resultado de la evaluación.

**App Check.** El callable va **sin `enforceAppCheck`**: la atestación de
Android está rota y el flag no degrada, rompe. La exención se declara como
`debt` con condición de salida en
`functions/src/__tests__/appcheck-enforcement.test.ts` (si no, ese test falla).
Mitigación de costo y abuso: auth + rol + cupo + `maxInstances` + topes de
bytes, páginas y tokens de salida.

## `PdfPlanExtraction`

Salida estructurada del LLM (`output_config.format` con JSON schema).

```json
{
  "numWeeks": 4,
  "days": [
    {
      "dayNumber": 1,
      "title": "Torso A",
      "rows": [
        {
          "number": 1,
          "restSeconds": 90,
          "exercises": [
            {
              "component": 1,
              "rawName": "Press banca plano con barra",
              "note": "RIR 2, tempo 3-0-1",
              "weeks": [
                [ { "type": "normal", "weightKg": 60, "reps": null, "repsMin": 8, "repsMax": 10, "durationSeconds": null, "distanceMeters": null } ],
                []
              ],
              "candidateExerciseId": null,
              "candidateConfidence": null,
              "sourceText": "Press banca 4x8-10 @60kg RIR2"
            }
          ]
        }
      ]
    }
  ],
  "warnings": [ { "code": "ambiguous_reps", "message": "…", "page": 2 } ]
}
```

Reglas:

- `numWeeks` 1–16; `dayNumber` 1–7 único; `rows[].number` = `null` para
  calentamiento; `restSeconds` 0–600.
- `exercises.length > 1` en una fila = superserie; `component` 1..n.
- `weeks.length == numWeeks`; lista vacía = semana sin carga para ese
  ejercicio.
- Cada set mapea 1:1 a `SetSpec` (`lib/features/workout/domain/set_spec.dart`):
  `type` ∈ valores de `SetType` (`set_enums.dart`); topes reps ≤ 999,
  `weightKg` ≤ 500.
- **Prescripción: a lo sumo UNA de cuatro**, los mismos modos que soporta
  `SetSpec`: `reps`; el rango (`repsMin` + `repsMax`, siempre los dos juntos y
  `repsMin ≤ repsMax`); `durationSeconds`; o `distanceMeters`. `weightKg` es
  aparte y puede acompañar a cualquiera. **Ninguna** también es válida: un set
  al fallo (`type: failure`) o una celda sin reps, que la vista previa marca en
  rojo como en el Excel. Lo que se rechaza es mezclar dos modos (`reps` +
  `durationSeconds`, `reps` + rango).
  - El contrato compartido decía «`reps` XOR (`repsMin`,`repsMax`)». Leído
    literal rechaza todo set por tiempo o distancia (los dos van con reps y
    rango en null) y devolvería `internal` a cualquier PDF con planchas o
    trote. Esta regla lo reemplaza.
- `rawName` es **TEXTUAL** del PDF (nunca normalizado ni traducido).
  `sourceText` ≤ 300 caracteres.
- RIR/RPE/tempo/%1RM y cualquier calificador no modelado van a `note`
  (`SetSpec` no tiene esos campos; terminan en `RoutineSlot.notes`).
- `candidateExerciseId` / `candidateConfidence` (0–1) son opcionales: el
  servidor los valida contra el catálogo (id existente) y el cliente aplica el
  veto determinístico del matcher; **nunca se autoasignan**.
- El servidor valida contra estos topes y rechaza (`internal`, cupo devuelto)
  lo que no cumpla; el cliente vuelve a validar con
  `periodized_plan_json.dart`. Dos validaciones a propósito: la del servidor
  protege el cupo y el costo, la del cliente protege el modelo de datos aunque
  el servidor cambie.

**El mapper tiene que conservar peso y rangos.** El `_coerce` de
`periodized_routine_mapper.dart` heredado del Excel sólo conserva `type` y
`reps`: descarta `weightKg`, `repsMin`/`repsMax`. El Excel nunca los produce,
así que ahí no se notaba; un PDF con «8-12 @60kg» perdería la mitad del dato.
Se extiende antes de la primera UI (con `RepMode.range` en el slot).

## Cupos

Espejo Dart + TS: `kTierPdfImportLimits`.

| Tier | Semanal | Diario |
|---|---|---|
| free | 2 | 2 |
| plan1 | 7 | 7 |
| plan2 | 15 | 10 |
| plan3 | 30 | 10 |

Cómo se cuentan:

- **Semana** = lunes 00:00 a domingo 23:59 en
  `America/Argentina/Buenos_Aires`. **Día** = 00:00 a 23:59 en la misma zona.
  Los dos topes valen a la vez: se rechaza con el que se agote primero
  (`details.scope`).
- Contador en **`pdfImportUsage/{uid}`**, que escribe **sólo** el Admin SDK
  desde la función (las reglas no dejan escribir al cliente).
- Se **descuenta en una transacción ANTES de llamar al LLM**. Descontar después
  dejaría una ventana en la que N requests concurrentes pasan todos el chequeo.
- **Se devuelve** si el import falla por culpa nuestra: LLM caído, timeout
  (`deadline-exceeded`), salida inválida (`internal`).
- **No se devuelve** si el archivo es el problema: un PDF que pasó las
  validaciones de entrada pero resultó ilegible consume. El modelo ya se
  pagó.
- Las validaciones de entrada (`invalid-argument`) y el kill switch no tocan el
  contador: se rechazan antes de descontar.
- El import **no consume cupo de plantillas**: asigna una rutina
  (`trainerAssigned`), y el contador de plantillas sólo cuenta
  `source == 'trainer-template'`.

## Matcheo

Misma política que el Excel (#1455): **nada se adivina**.

| Nivel | Origen | Qué pasa |
|---|---|---|
| Exacto | nombre o alias del catálogo, o un ejercicio propio del PF con el mismo nombre normalizado | **se asigna solo** |
| Aproximado | fuzzy del `ExerciseNameMatcher` | **sólo sugiere**: el PF confirma o cambia |
| Candidato del LLM | `candidateExerciseId` | **sólo sugiere**, y sólo si pasa el veto |
| Sin candidato | — | rojo: vincular con la biblioteca o crear propio |

El candidato del LLM entra únicamente al nivel «sugerencia», y sólo si:

1. el servidor confirmó que el id **existe** en el catálogo;
2. **no hay match exacto** (el exacto siempre gana: es determinístico);
3. pasa el **veto determinístico** del matcher: el equipo canonizado y las
   variantes biomecánicas del `rawName` tienen que ser compatibles con las del
   ejercicio candidato (la misma regla que hoy filtra el fuzzy —
   `_isCompatibleLabel`, que se expone para esto). Un LLM que propone «press
   banca con mancuernas» para «press banca con barra» se descarta, no importa
   la confianza que declare.

Si el fuzzy y el LLM sugieren cosas distintas y las dos pasan el veto, se
muestra la del fuzzy (es reproducible) y la del LLM queda como alternativa en
el picker. `candidateConfidence` **no** baja ni sube ningún umbral en v1: se
loguea para la evaluación.

Sugerencias pendientes y filas sin candidato **bloquean el guardado** hasta
resolverse, igual que en el Excel.

**Aliases.** Vincular con la biblioteca registra el alias (`addAlias`) como en
el Excel. Ojo: `addAlias` tiene `enforceAppCheck: true`, así que desde mobile
sólo anda con una atestación válida. Falla en silencio y no bloquea nada: el
plan se guarda igual.

## «Crear N propios» en bloque

Un PDF de un PF con su propia nomenclatura puede traer muchos ejercicios que no
están en el catálogo. Resolverlos de a uno con un formulario cada uno es lo que
el import existe para evitar. Por eso, además de «Crear como propio» por fila
(el mismo camino que el Excel: `intentarCrearEjercicioPropio` +
`showCreateCustomExerciseDialog`), la vista previa ofrece un botón
**«Crear N propios»**:

- **N** = cantidad de nombres **distintos** sin candidato, contados por nombre
  normalizado (mayúsculas, tildes y espacios no cuentan). Tres renglones con
  «Remo Pendlay» son **un** propio, y los tres quedan resueltos con él.
- Las filas con **sugerencia pendiente no entran** en N: esas se confirman o se
  cambian. Crear un propio encima de una sugerencia sería adivinar al revés.
- Crea con el `rawName` como nombre, sin músculo ni equipo (los dos son
  opcionales y se editan después en «Mis ejercicios»).
- **Tope del plan** (Free 20 / Plan 1 60 / Plan 2 120 / Plan 3 sin tope,
  [limite-ejercicios-pf.md](./limite-ejercicios-pf.md)): antes de crear se
  chequea `restantes = tope − usados`.
  - `N ≤ restantes` → crea los N.
  - `0 < restantes < N` → avisa «Te alcanza para X de N» y crea **los primeros
    X en orden de aparición** en el plan, sólo si el PF acepta. El resto queda
    en rojo con «Vincular con la biblioteca» disponible.
  - `restantes == 0` → el mismo aviso de tope de la app; no se crea nada.
- El contador de propios lo mantiene un trigger **asíncrono**
  (`maintainCustomExerciseCount`), y la regla de Firestore lee ese contador.
  Una ráfaga de N creates puede pasarse del tope con la cuenta vieja. Por eso
  el pre-chequeo es del lado del cliente, contra la cuenta + los creados en esta
  misma ráfaga, y no se confía en que la regla frene a mitad de camino.
- **No** se llama `addAlias` para los propios: es privado del PF y el alias
  indexa contra el catálogo global.

## Límites del PDF

| Límite | Valor | Dónde |
|---|---|---|
| Tamaño | **5 MB** | cliente (antes de subir) y servidor |
| Páginas | **20** | servidor |
| Tipo | empieza con `%PDF-` (magic bytes) | servidor; el cliente filtra por extensión |
| Persistencia | **ninguna** | — |

- Viaja **inline en base64** al callable (≈ +33 % sobre el tamaño del
  archivo), así que no hace falta tocar `storage.rules` ni crear un bucket
  temporal.
- **El PDF no se persiste**: ni Storage, ni Firestore, ni logs. Lo que se guarda
  es el plan que el PF confirma, como cualquier rutina asignada.
- Los logs del callable no llevan el contenido del PDF ni el `rawName`: llevan
  uid, tamaño, páginas, modelo, tokens, duración y código de resultado.

## Kill switch

Documento **`app_config/pdf_import`** con `{ enabled: bool, allowlistUids?: string[], model?, effort? }`.

- **`allowlistUids`** es la lista de prueba: con `enabled: false`, el callable
  igual atiende a esos uids (con el rol y el cupo aplicados igual) y rechaza al
  resto. Sirve para evaluar con PDFs reales en producción sin abrirlo a todos
  los PF. Con `enabled: true` no cambia nada.
- **`model`** (`claude-opus-5-5` por defecto, `claude-sonnet-5-5`,
  `claude-haiku-5-5`) y **`effort`** (`low`, `medium` por defecto, `high`) se
  cambian sin redeploy; un valor desconocido cae al default.

- **Apagado** hasta terminar la evaluación del rollout.
- Lo lee el servidor en cada llamada (`failed-precondition` si está apagado o
  si el documento no existe: falla cerrado) y el cliente para esconder el CTA.
  El cliente es comodidad; la barrera es el servidor.
- Apagarlo no requiere deploy: es el freno de mano si el costo o la calidad se
  van de las manos.

## Aviso en la pantalla de subida

El PDF puede traer datos del alumno (nombre, lesiones, observaciones de salud).
La pantalla de subida lo dice antes del selector de archivo. Texto final,
aprobado por el dueño (2026-10-22), con `AppL10n`:

| Idioma | Texto |
|---|---|
| es-AR | Usamos IA para leer tu PDF y armar el plan. No guardamos el archivo. Subí solo los datos de tu alumno que sean necesarios. |
| en | We use AI to read your PDF and build the plan. We don't keep the file. Only include the client details you need. |

**Sin nombres técnicos a propósito** (decisión del dueño): ni Claude, ni
Anthropic, ni Google Cloud. El aviso es para el momento de subir; quién procesa
el PDF lo dice la política de privacidad, que sí nombra a los encargados
(§6.3). No se reemplazan uno al otro.

## Rollout

1. **Implementación con el flag apagado.** Slices en orden: refactor del
   dominio Dart (matchDraft fuera de `PlanImportRepository`, `_coerce` con
   peso y rangos, veto expuesto) → `periodized_plan_json.dart` → schema +
   prompt + validador en functions → callable con LLM mockeado → servicio Dart
   → controller de la vista previa → UI de subida → UI de vista previa y crear
   propios.
2. **Política publicada antes de encender.** El texto legal de este PR tiene
   que estar en `main` (y en la landing) antes de que un PF pueda subir un PDF.
3. **Habilitar Vertex AI** (Model Garden, modelo Claude) en `treino-dev`.
   **`treino-dev` ES producción** (AGENTS.md): lo hace un humano, con OK
   explícito. Deploy filtrado con `--only functions:parsePlanPdf`.

   **Permitir los structured outputs (obligatorio).** En Vertex AI están
   **denegados por defecto** para todo proyecto dentro de una organización —y
   `treino-dev` lo está— por la org policy
   `constraints/vertexai.allowedPartnerModelFeatures` (docs de Google Cloud
   «Control access to Model Garden models» y «Structured outputs with Anthropic
   Claude models», 2026-10-21). Sin este paso **todo** import falla antes de la
   inferencia: el callable lo devuelve como `failed-precondition` con
   `reason: "structured_outputs_disabled"`, devuelve el cupo y deja un log que
   nombra la policy. Strict tool use no lo esquiva: Google lo cuenta como parte
   de la misma feature.

   La policy se puede poner a nivel proyecto (la de proyecto puede pisar la de
   la organización; requiere `roles/orgpolicy.policyAdmin`). Un archivo
   `policy.yaml` con un valor por cada modelo que se vaya a usar:

   ```yaml
   name: projects/treino-dev/policies/vertexai.allowedPartnerModelFeatures
   spec:
     rules:
       - values:
           allowedValues:
             - publishers/anthropic/models/claude-opus-5-5:structured_outputs
             - publishers/anthropic/models/claude-sonnet-5-5:structured_outputs
             - publishers/anthropic/models/claude-haiku-5-5:structured_outputs
   ```

   ```bash
   gcloud org-policies set-policy policy.yaml --project=treino-dev
   gcloud org-policies describe vertexai.allowedPartnerModelFeatures --project=treino-dev --effective
   ```

   Por consola: IAM y administración → Políticas de la organización →
   `vertexai.allowedPartnerModelFeatures` → *Administrar política* sobre el
   proyecto `treino-dev` → valores permitidos personalizados, los mismos tres.
   Un `deny` explícito en un nivel superior gana sobre este `allow`: si después
   del cambio el log sigue diciendo `structured_outputs_disabled`, mirar la
   policy efectiva (el segundo comando).
4. **Evaluación con 10 a 20 PDFs reales** de PFs, variados a propósito: tablas,
   prosa, superseries, semanas en columnas y **al menos uno escaneado**. Se
   empieza con **`claude-opus-5-5`** como techo de calidad. Por cada PDF se
   mide: días y semanas correctos, ejercicios con `rawName` fiel, sets con
   reps/rango/peso correctos, cuántos matchean exacto / sugerencia / rojo,
   tokens, costo y duración.
5. **Bajar de modelo si alcanza.** Con los mismos PDFs se evalúa
   `claude-sonnet-5-5` y `claude-haiku-5-5`. Se cambia el parámetro de config
   (sin redeploy) al más barato que no pierda calidad **en lo que el PF no
   puede corregir fácil** (estructura de días y semanas); los errores de una
   celda la vista previa los muestra.
6. **Encender** `app_config/pdf_import.enabled` con OK del dueño. Hasta entonces la
   evaluación de los pasos 4 y 5 corre desde las cuentas de `allowlistUids`.

## Riesgos

- **Cifras alucinadas.** El control es la vista previa obligatoria con el texto
  fuente al lado. No hay guardado sin revisión.
- **Prompt injection dentro del PDF.** La salida está acotada por el schema y
  validada en los dos lados; lo que se escribe pasa por `createAssigned` y su
  moderación, como cualquier rutina.
- **Costo.** Lo acotan el cupo, `maxInstances`, los topes de páginas y de
  tokens de salida, y el kill switch.
- **Tiempo.** Si el p95 de la evaluación pasa de un minuto con el modelo
  elegido, el callable síncrono se reemplaza por un documento de trabajo en
  Firestore con listener (la app puede irse a background mientras espera).
