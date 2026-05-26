# Proposal: coach-excel-import

**Change**: Fase 5 · Etapa 8 — Excel import de planes (Coach Hub web)
**Branch**: `feat/coach-excel-import`
**Owner**: Dev B
**Date**: 2026-05-26
**Depends on**: Etapa 1 (`Routine` con `assignedBy`/`assignedTo`), Etapa 4 (`createAssigned`), Etapa 7 (Coach Hub shell + routing + login).

---

## 1. Why

Etapa 7 dejó el Coach Hub vivo en `coach-treino-dev.web.app` con un dashboard de solo lectura. Hoy el PF no puede crear ni asignar planes desde el hub. Etapa 8 cubre eso: importa el plan desde un Excel (formato libre del PF), lo previsualiza con match contra el catálogo, y lo asigna a uno o varios atletas vinculados.

Sin Etapa 8, el Coach Hub es una landing read-only — los PFs siguen dependiendo de mobile o de scripts manuales para asignar planes. Con Etapa 8 el hub gana valor real para el día a día del PF.

---

## 2. What

### Approach: parser client-side (sin Cloud Functions)

**Decisión pivotada durante implementación** (originalmente el propose pedía Cloud Functions). Razón del pivot: el deploy de Cloud Functions 2nd Gen requirió permisos IAM (`iam.serviceAccounts.actAs` sobre la default compute SA + Compute Engine API habilitada) que el owner del proyecto no tenía sin activar GCP free trial (con tarjeta). Bajar a 1st Gen tampoco resolvió (mismo issue con `Storage Object Viewer` sobre `gcf-sources` bucket). En vez de bloquear el PR esperando activación de GCP, se movió el parseo al cliente Dart.

Justificación de seguridad: las **Firestore rules** son la verdadera defensa — `routines/{id}` requiere `assignedBy == request.auth.uid` con `role == 'trainer'`, y `assignedTo` debe ser un atleta con `trainer_links` activo al PF. Eso corre en server side siempre, no importa quién llama. El parser solo hace UX: leer xlsx, matchear contra `exercises` catalog, mostrar preview. No es un punto de seguridad.

Una Cloud Function sigue siendo necesaria a futuro cuando metamos AI generativa (Gemini API key no puede vivir en el cliente). Eso queda como Etapa 8.5 o futura fase.

### Trabajo de código

#### Domain
- `lib/features/coach_hub/domain/parsed_plan.dart`: `ParsedPlan`, `ParsedPlanDay`, `ParsedPlanItem`, `ParsedPlanUnmatched` (freezed).
- `lib/features/workout/domain/exercise.dart`: nuevo campo `aliases: List<String>` (default `[]`), regenerado con build_runner.

#### Data
- `excel_parser.dart`: lee `.xlsx` (package `excel`), parsea hoja "Plan" + hojas "Día N", valida (nombre, días/semana 1–7, duración 1–52, nivel ∈ {principiante, intermedio, avanzado}, headers exactos, mínimos por fila). Devuelve `RawParsedPlan` con días sin matchear.
- `exercise_matcher.dart`: indexa cada `Exercise` por su `name` + cada `alias`. Match exacto (normalizado) + fuzzy fallback por tokens ≥3 chars. Devuelve `ParsedPlan` + lista de `unmatched`.
- `template_builder.dart`: genera xlsx en memoria con hoja "Plan" + 3 hojas día prellenadas (ejemplo). El PF lo descarga, lo edita, lo sube.
- `plan_import_repository.dart`: orquesta `parseExcelBytes` → `exerciseRepository.listAll` → `matchExercises`. Mapea errores a `PlanImportException`.

#### Infrastructure
- `browser_download.dart` + `_stub.dart` + `_web.dart`: conditional import (`dart.library.js_interop`) para que el `package:web` Blob/Anchor download trigger solo se compile en web. Tests VM no rompen.

#### Presentation
- `coach_hub_upload_plan_screen.dart` (ruta `/upload-plan`):
  - File picker (`file_picker`) restringido a `.xlsx`.
  - Botón "Descargar template" → `buildPlanTemplateBytes()` + `triggerBrowserDownload`.
  - Botón "PROCESAR PLAN" → `parseAndMatch` → set `parsedPlanProvider` → go `/upload-plan/preview`.
- `coach_hub_plan_preview_screen.dart` (ruta `/upload-plan/preview`):
  - Meta del plan (días/semana, duración, nivel via `displayNameEs`).
  - Warning si hay unmatched.
  - Cards por día con cada item; los unmatched muestran badge "sin match" + botón "Asignar manualmente" que abre `_ExercisePickerSheet` (modal con search + filtrado por name/muscleGroup/aliases).
  - Selector de atletas **multi** (checkbox circular): el PF puede asignar el mismo plan a varios alumnos vinculados a la vez. El botón cambia el copy según count ("ASIGNAR PLAN" / "ASIGNAR PLAN A N ATLETAS").
  - Loop `createAssigned` por cada athleteId seleccionado. Si fallan algunos, reporta cuántos ok vs fallidos.
- `coach_hub_dashboard_screen.dart`: botón principal "IMPORTAR PLAN DESDE EXCEL" que navega a `/upload-plan`.
- `coach_hub_router.dart`: 2 rutas nuevas (`/upload-plan` y `/upload-plan/preview`).

#### Theme + iconos
- `lib/app/theme/app_palette.dart`: nuevo campo `warning` (ámbar) — usado por badge "sin match" + warning del preview. Mantiene la regla "no HEX literals".
- `lib/core/widgets/treino_icon.dart`: `arrowLeft`, `download`, `upload`, `fileXls`, `warning` (mapeos a Phosphor).

#### Scripts (one-shot)
- `scripts/backfill_exercise_aliases.js`: idempotente. Aplica `aliases` (5–8 sinónimos español por ejercicio) a los 25 docs en `exercises/`. Para que `Sentadilla con barra` matchee con `back-squat`.
- `scripts/promote_mateo_to_public_trainer.js`: helper para smoke. Recibe email, busca uid, crea `users/{uid}` con `role: trainer` + `trainerPublicProfiles/{uid}`. Reemplaza el flujo UI de completar perfil público (que llega en otra etapa).
- `scripts/accept_pending_link.js`: helper para smoke. Acepta el último `trainer_links` pendiente del trainer dado. Reemplaza el flujo UI de aceptar vínculo.

#### Seed catalog
- `scripts/seed_workout_catalog.js`: agregado `aliases: [...]` inline en los 25 ejercicios. Future seeds quedan alineados con el backfill.

#### Tests
- `test/features/coach_hub/data/excel_parser_test.dart`: 8 tests (happy + validations + template-roundtrip).
- `test/features/coach_hub/data/exercise_matcher_test.dart`: 6 tests (match exacto, normalize, fuzzy, alias en español).
- `test/features/coach_hub/data/plan_import_repository_test.dart`: 4 tests (orquestación + unmatched + bytes corruptos).

**Suite total**: 1217/1217 passing. `flutter analyze`: 0 issues.

---

## 3. Trade-offs lockeados

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Parser client-side en lugar de Cloud Functions** | Sin permisos IAM para deploy. La seguridad real está en Firestore rules. AI generativa futura (cuando llegue) sí va a vivir server-side por la API key. |
| 2 | **Aliases en `exercises` + dropdown manual** | Cubrir variaciones comunes con aliases es lo más adoption-friendly (PFs hablan español). El dropdown manual es el escape hatch para nombres raros (ej: "Sentadilla con cinta pause 3s"). |
| 3 | **Multi-asignación** (vs single) | Un PF típicamente tiene varios alumnos haciendo el mismo programa. Single-assign forzaría re-importar el mismo Excel N veces. Loop `createAssigned` por athleteId crea N routines independientes (cada uno editable por atleta a futuro). |
| 4 | **`package:web` + conditional imports** | El hub es web-only. El stub no-web evita que tests VM y el target mobile (`lib/main.dart`) rompan al importar el screen. |
| 5 | **Templates: ejemplos prellenados, sin instrucciones inline** | Para MVP. Iteración futura: anchos de columna correctos, header bold, dropdown de nivel, instrucciones en una hoja "Instrucciones". |

---

## 4. Out of scope (follow-ups)

| Item | Lands en |
|---|---|
| AI generativa (Gemini) para parsing semántico | Etapa 8.5 o Fase 6 |
| Marcar el plan más reciente como "ACTUAL" en la pantalla "Mi Plan" mobile | PR follow-up chico |
| UI para que el PF complete su `trainer_public_profile` desde la app | Pendiente Fase 5 |
| Aceptar/declinar vínculos desde el Coach Hub web | Futura iteración del hub |
| Polish del template: anchos de columna, dropdown de nivel, instrucciones | Iteración cuando producto valide |
| Storage server-side de los xlsx originales (auditoría) | Solo necesario si producto pide histórico |
| Aliases dinámicos (aprende del catálogo a medida que PFs mapean manual) | Optimización futura |

---

## 5. Risks

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | `package:excel` puede tener bugs parseando xlsx exóticos (.xlsm, planillas con macros, cells merged) | El parser falla con mensaje claro. El PF puede usar el template descargado como base segura. |
| 2 | Catálogo de 25 ejercicios es chico; alias coverage limitado | Dropdown manual cubre los gaps. Cada vez que un PF mapee manual, podemos sumarlo como alias en un PR follow-up. |
| 3 | Multi-asignación crea N routines duplicados — si el PF se equivoca, duplica para todos | Aceptable: el PF puede borrar el routine erróneo desde la app mobile (próxima iteración: undo en el hub). |

---

## 6. Success criteria

- [x] `flutter analyze` 0 issues
- [x] 1217/1217 tests passing
- [x] Build web limpio
- [x] Deploy a `coach-treino-dev.web.app` OK
- [x] Smoke end-to-end: PF importa Excel → preview con match (aliases) → unmatched resueltos vía dropdown → multi-asignación → atleta ve el plan en mobile en "MI PLAN"
- [x] Backfill de aliases corrido en `treino-dev` (25 exercises actualizados)

---

## 7. Manual ops corridas durante smoke

| # | Comando | Resultado |
|---|---|---|
| 1 | `node scripts/backfill_exercise_aliases.js` | 25 exercises actualizados con aliases |
| 2 | `node scripts/promote_mateo_to_public_trainer.js <email>` | Mateo creado como public trainer en `trainerPublicProfiles/{uid}` |
| 3 | `node scripts/accept_pending_link.js <email>` | Vínculo pending → active para el atleta nuevo |
