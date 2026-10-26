# Import de plan desde PDF — estado y traspaso

> Foto al **2026-10-26**. Para quien retome la feature. La spec (contrato,
> cupos, matcheo, rollout y riesgos) vive en
> [`plan-import-pdf.md`](./plan-import-pdf.md): este documento no la repite,
> dice **qué está hecho, dónde está y qué falta**.

## En una línea

El código está **completo y mergeado en `develop`**, con el flag **apagado**.
**No está en `main`** (la 1.2.0+60 salió sin esto) y **nada está desplegado ni
configurado en producción**. Lo que falta es rollout, evaluación con PDFs
reales y release.

## Qué está hecho

Todo en `develop`, en este orden de merge:

| PR | Qué trae |
|---|---|
| #1626 | Spec `docs/plan-import-pdf.md` + Vertex AI / Claude como procesador en la política de privacidad (las tres copias del texto legal) |
| #1627, #1628 | Dominio Dart: `matchDraft` sin depender del Excel, `_coerce` conserva peso y rangos, veto del matcher expuesto, `periodized_plan_json.dart` (valida `PdfPlanExtraction`) |
| #1629 | Cupos `kTierPdfImportLimits` (Dart + TS) y regla de `pdfImportUsage/{uid}` |
| #1630 | Schema, prompt y validador de la extracción (functions). Rechaza PDFs cifrados; el nombre del archivo **no** va al modelo (prompt injection) |
| #1631 | Callable `parsePlanPdf` con Claude en Vertex AI, kill switch con `allowlistUids`, error explícito si falta la org policy de structured outputs |
| #1635, #1636 | Candidatos del LLM como **sugerencias** (nunca autoasignan), gate del kill switch, regla de lectura de `app_config/pdf_import`, `PlanPdfImportService` |
| #1637, #1638 | `PlanImportPreviewController` compartido (el Coach Hub web lo usa también) y «Crear N propios» en bloque |
| #1639–#1641 | Pantalla de subida, errores tipados con su acción, botón «IMPORTAR DE PDF» en la ficha del alumno + cupo restante |
| #1642–#1644 | Vista previa mobile, asignación, nombre editable, y los hallazgos de la revisión independiente y de Codex |

Revisado por una revisión independiente (sin CRITICAL/HIGH) y por Codex en cada
PR; todos los hilos quedaron resueltos. Probado solo con tests (unit, widget,
reglas, functions con el LLM mockeado). **Nunca se llamó al modelo real.**

## Dónde está el código

| Capa | Archivos |
|---|---|
| Callable | `functions/src/pdf-import/` (`parse-plan-pdf.ts`, `provider.ts`, `prompt.ts`, `extraction.ts`, `pdf-check.ts`, `quota.ts`); export en `functions/src/index.ts` |
| Reglas | `firestore.rules`: `match /app_config/pdf_import` (sólo `get` de trainers) y `match /pdfImportUsage/{uid}` (lee el dueño, escribe sólo Admin SDK) |
| Cupos | `kTierPdfImportLimits` en `lib/features/coach/domain/subscription_tier.dart`, espejo **a mano** de `functions/src/subscriptions/tier-config.ts` |
| Dominio / datos | `lib/features/coach_hub/domain/periodized_plan_json.dart`, `lib/features/coach_hub/data/plan_pdf_import_service.dart`, `plan_draft_matcher.dart` |
| Estado | `lib/features/coach_hub/application/plan_pdf_import_providers.dart` (servicio + gate), `pdf_import_quota_provider.dart` (cupo; se recalcula a la medianoche ART), `plan_import_preview_controller.dart` |
| UI mobile | `lib/features/coach/presentation/plan_pdf_import_upload_screen.dart`, `plan_pdf_import_preview_screen.dart`; rutas `/workout/import-pdf/:athleteId` y `…/preview` en `lib/app/router.dart`; botón en `athlete_detail_screen.dart` |

## Qué falta (en orden)

Los pasos 1 a 6 tocan **producción** (`treino-dev` ES producción, AGENTS.md):
los hace un humano con OK explícito del dueño.

1. **Vertex AI en `treino-dev`:** habilitar Claude Opus 5.5 (y Sonnet 5.5 /
   Haiku 5.5 si se van a evaluar) en Model Garden.
2. **IAM:** rol `roles/aiplatform.user` a la service account de las functions
   (`<número-de-proyecto>-compute@developer.gserviceaccount.com`).
3. **Org policy de structured outputs** (obligatoria): YAML y comandos en la
   spec, sección *Rollout*, paso 3. Sin esto todo import da
   `structured_outputs_disabled`.
4. **Deploy** desde un worktree de `origin/develop` (el guard
   `guard_fuente_de_deploy.js` exige que sea idéntico a develop):
   - `firebase deploy --only firestore:rules --project prod`
   - `firebase deploy --only functions:parsePlanPdf --project prod`
     (el deploy de functions resuelve **todos** los secretos: si falla por un
     secret ajeno, no es de esta feature).
5. **Política publicada ANTES de cualquier allowlist** (spec, *Rollout* paso
   2). La `allowlistUids` saltea `enabled: false`, así que un PF de la lista ya
   sube PDFs reales: la política tiene que estar publicada antes de cargar el
   primer uid. Estado al 2026-10-26: la v5 (con Vertex AI / Claude) **ya está
   en `main`** (entró con #1634 y viaja en la app 1.2.0+60); falta **confirmar
   que esté publicada en la landing** (gettreino.com) y que la 1.2.0+60 esté
   disponible en las tiendas.
6. **Kill switch:** recién con el paso 5 confirmado, crear
   `app_config/pdf_import` =
   `{ "enabled": false, "allowlistUids": ["<uid del PF que evalúa>"] }`.
   Sin el documento el callable rechaza a todos.
7. **Evaluación con 10 a 20 PDFs reales** desde una cuenta de la allowlist,
   con un build de `develop` (con `--dart-define-from-file=~/.config/treino/dart_defines.json`).
   Qué medir: spec, *Rollout* paso 4.
8. **Elegir modelo:** si Sonnet o Haiku alcanzan con los mismos PDFs, cambiar
   el parámetro de config (sin redeploy).
9. **Release:** `develop` → `main` y build a las tiendas. Recién con la versión
   publicada, `enabled: true`.

Checklist manual en el iPhone (de los PRs #1641 y #1643): botón sin salto de
layout y oculto fuera de la allowlist; cupo coincide con `pdfImportUsage`; PDF
> 5 MB rechazado sin gastar cupo; atrás durante el proceso pide confirmación;
PDF con contraseña y de > 20 páginas con su error; vista previa contra «Ver
texto del PDF»; «Crear N propios» cuenta nombres distintos; ASIGNAR
deshabilitado hasta resolver todo; modo claro/oscuro y texto grande.

## Pendientes conocidos (no bloquean el rollout)

- **Cupo gastado si el cliente rechaza el plan.** El servidor descuenta antes
  de llamar al LLM y valida la salida; si igual el cliente la rechaza, el cupo
  no vuelve. Poco probable (validan los dos lados).
- **Textos en español fijos** en la card de preview que viene del Coach Hub
  («Confirmar», «sin match», «SEMANA N»): en inglés se ven en español. Los
  textos nuevos sí van por `AppL10n`.
- **Callable síncrono.** Si el p95 de la evaluación supera ~60 s, migrar a un
  documento de trabajo en Firestore con listener (spec, *Riesgos*).
- **Versión de la política de privacidad.** #1626 la dejó en v5; la sesión
  verificó que no dispara banner ni re-consentimiento. La política tiene que
  estar publicada en `main` y en la landing **antes** de encender.
- **Bug ajeno detectado en la exploración:** `addAlias` (aprendizaje de alias
  del import de **Excel** del Hub) tiene `enforceAppCheck: true` y la web
  nunca activa App Check, y el Hub se traga el error: las correcciones del PF
  no se aprenden. No es de esta feature; está anotado para un PR aparte.

## Fuera de v1 (posibles siguientes pasos)

- **Otros tipos de archivo.** El pipeline ya separa «extraer» de «matchear y
  revisar»: sumar **fotos** del plan (Claude lee imágenes) o **Excel en
  mobile** es cambiar la entrada del callable / del servicio, no el resto.
  Las fotos tienen otras reglas de tamaño, privacidad y del aviso.
- **Import de PDF en el Coach Hub web.** El controller ya es compartido; falta
  la pantalla de subida web.

## Trampas del repo que mordieron durante el desarrollo

- **Releases:** todo build de release lleva
  `--dart-define-from-file=/Users/martinbackhaus/.config/treino/dart_defines.json`.
  Sin eso salen rotos la búsqueda de gimnasios y el mapa (pasó con el build 59).
- **Fechas en tests:** el CI corre en UTC. Usar `DateTime.utc(...)` y
  `AppClock.freeze(DateTime.utc(...).toLocal())`, y barrer `TZ`. En
  `lib/features/coach` está prohibido `DateTime.now()` / `.toLocal()` crudo
  (`no_raw_clock_scan_test.dart`): usar `argentina_time.dart`.
- **PRs encadenados con squash:** retargetear el hijo a `develop` antes de
  mergear el padre y rebasearlo con `--onto` sobre el head del padre en el que
  se construyó; si se reescribe un padre, rebasear toda la cadena de arriba.
- **Codex comenta inline** recién cuando corre el CI de cada PR, y
  `gh pr view` no lo muestra: leer los `reviewThreads` por GraphQL antes de
  mergear.
