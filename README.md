# TREINO

Plataforma fitness que conecta **alumnos** con **Personal Trainers** (PF): entrenamiento, seguimiento, comunidad y la gestión del negocio del PF, en el teléfono, en la web y en el reloj.

> **¿Nuevo en el equipo?** Empezá por [CONTRIBUTING.md](./CONTRIBUTING.md) y después leé [AGENTS.md](./AGENTS.md): son las reglas que siguen tanto las personas como los agentes de IA que trabajan en el repo.

> [!WARNING]
> **`treino-dev` es el proyecto de PRODUCCIÓN.** No hay un entorno de desarrollo
> separado — el nombre dice "dev" por razones históricas (el project ID de Firebase
> no se puede cambiar). Cualquier comando con `--project treino-dev` toca datos de
> usuarios reales. Para desarrollo local usá el emulador (`./scripts/emulator.sh`).
> Detalle en [AGENTS.md § Entornos](./AGENTS.md#-entornos--leer-antes-de-correr-cualquier-comando) y [#826](https://github.com/Backhaus7997/treino/issues/826).

## Qué hay en este repo

Un solo código Flutter genera varias superficies, más un backend de Cloud Functions:

| Superficie | Para quién | Entrypoint | Dónde corre |
|---|---|---|---|
| **App móvil** | Alumnos y PF | `lib/main.dart` | iOS (`com.backhaus.treino`) y Android (`com.treino.app`) |
| **Coach Hub** | PF | `lib/main_coach_hub.dart` | Flutter Web en Vercel → [app.gettreino.com](https://app.gettreino.com/) |
| **Wear OS** | Alumnos | `lib/main_wear.dart` | Android, flavor `wear` |
| **Apple Watch** | Alumnos | `ios/TreinoWatch Watch App/` | watchOS, Swift nativo (Firestore por REST) |
| **Backend** | — | `functions/` | Cloud Functions (Node 22) |
| **Páginas estáticas** | Público | `web/` | Legales, deep links (`/abrir/*`), `.well-known` |

## Producto

La app móvil tiene **5 tabs, con Inicio al medio**: `Entrenar · Feed · Inicio · Coach · Perfil`.

- **Entrenar** — rutinas propias y asignadas por el PF, editor de rutinas, sesión en vivo, historial e insights de progreso por ejercicio.
- **Feed** — red social (amigos, mi gym, público) y **rankings por gym** con opt-in del alumno (racha, volumen, sentadilla, banca, peso muerto).
- **Inicio** — resumen del día, rutina de hoy, notificaciones.
- **Coach** — para el alumno: descubrir PF, vincularse, chat, turnos, planes. Para el PF: alumnos, agenda, detalle de cada alumno.
- **Perfil** — perfil, gym, mediciones y ajustes de la cuenta.

**Coach Hub** es la herramienta de escritorio del PF: dashboard, alumnos, agenda, planner y rutinas, plantillas y biblioteca de ejercicios, nutrición (recetas, suplementos, hábitos), cuestionarios, reportes, pagos, facturación del plan, invitaciones, perfil público y moderación.

Roles: `athlete` y `trainer`, inmutables. El registro público siempre crea `athlete`; los PF se dan de alta desde el equipo. Naming y alcance en [docs/product.md](./docs/product.md).

### Suscripciones

**Mercado Pago es el único proveedor de cobro**, para el PF (`users/{uid}.subscription`) y para el alumno (`users/{uid}.athleteSubscription`). El flujo vive en `functions/src/subscriptions/mp/`: alta del checkout, webhook, reconciliación (más un barrido diario), cambio de plan, baja y **botón de arrepentimiento** por mail.

## Stack

- **Flutter** — CI y el deploy web compilan con **3.41.9** (`pubspec.yaml` declara el mínimo, `>=3.22.0`; Dart `^3.5.0`).
- **Riverpod 2** para estado de negocio · **go_router** · **freezed** + **json_serializable** para modelos.
- **Firebase**: Auth (email, Google, Apple), Firestore, Storage, Functions, Messaging, App Check, Crashlytics, Analytics.
- **Cloud Functions** en TypeScript sobre Node 22 (`firebase-functions` 7). Mails transaccionales con **Resend** a través de una cola en Firestore.
- Diseño: paleta Mint Magenta (dark y light), Barlow / Barlow Condensed, íconos Phosphor detrás de `TreinoIcon`. Ver [docs/design-system.md](./docs/design-system.md).

## Estructura

```
lib/
├── main.dart                # app móvil
├── main_coach_hub.dart      # Coach Hub (web)
├── main_wear.dart           # companion de Wear OS
├── app/                     # routers (móvil y Coach Hub), tema, tokens
├── core/                    # widgets y utilidades compartidas
├── l10n/                    # textos traducibles
└── features/                # un directorio por dominio: auth, workout, feed,
                             # gym_rankings, home, coach, coach_hub, chat,
                             # measurements, notifications, payments, paywall,
                             # profile, watch, …
functions/src/               # Cloud Functions: subscriptions/mp, mail,
                             # notifications, cascade, retention, moderation, …
ios/TreinoWatch Watch App/   # app de Apple Watch
web/                         # páginas estáticas que sirve Vercel
scripts/                     # emulador, seeds, deploy de reglas, utilidades
firestore.rules · storage.rules · firestore.indexes.json
docs/ · openspec/            # documentación y specs (SDD)
```

## Setup

```bash
git clone https://github.com/Backhaus7997/treino.git
cd treino
./scripts/bootstrap.sh       # Flutter, herramientas y dependencias de Dart
npm --prefix functions ci    # dependencias de Functions (Node 22): sin esto el emulador no arranca
```

Cada worktree nuevo necesita su propio `npm --prefix functions ci`: `node_modules` no se comparte.

Instalación manual y detalles en [CONTRIBUTING.md](./CONTRIBUTING.md).

## Cómo correr

Desarrollo local **contra el emulador**:

```bash
./scripts/emulator.sh        # Firestore, Auth, Functions y UI del emulador

# iOS
flutter run --dart-define=USE_EMULATOR=true
# Android: el flavor es obligatorio (hay dos, `phone` y `wear`)
flutter run --flavor phone --dart-define=USE_EMULATOR=true
```

> [!CAUTION]
> Sin `--dart-define=USE_EMULATOR=true` **cualquier** superficie arranca contra
> `treino-dev`, que es producción. **Y con el flag, no todo queda aislado**:
>
> | Servicio | App móvil | Coach Hub | Wear OS |
> |---|---|---|---|
> | Firestore y Auth | emulador | emulador | emulador |
> | Functions (callables) | emulador | **producción** | **producción** |
> | Storage | **producción** | **producción** | **producción** |
> | Analytics y Crashlytics | **producción** | **producción** (Analytics) | — |
>
> Las callables del Coach Hub (checkout, bajas, moderación…) fallan contra
> producción con un usuario del emulador de Auth, y subir archivos escribe en el
> bucket real. Medido en los `main*.dart`: qué servicio llama a `use*Emulator`.

Las otras superficies:

```bash
flutter run -d chrome -t lib/main_coach_hub.dart --dart-define=USE_EMULATOR=true

flutter run -d <reloj> --flavor wear -t lib/main_wear.dart \
  --dart-define=USE_EMULATOR=true \
  --dart-define=EMULATOR_HOST=10.0.2.2 \
  --dart-define=APPCHECK_DEBUG=true
```

El detalle del reloj (host del emulador, App Check de debug) está en la cabecera de `lib/main_wear.dart`. Para cargar datos de prueba: `scripts/seed_emulator_full.js` ([README del seed](./scripts/seed_emulator_full_README.md)).

## Calidad

Antes de cada commit:

```bash
flutter analyze
dart format .                # lo verifica el CI
flutter test <tests afectados>
```

La suite completa es grande: ~900 archivos de tests de Flutter, ~170 de Functions (jest; los que tocan Firestore de verdad necesitan el emulador), tests de reglas y de scripts. Corré lo que toca tu cambio; el CI corre esas suites completas. Los 5 flujos end-to-end de `integration_test/` (registro, login, chat, rutinas, entrenamiento) **no** corren en el CI: se corren a mano en un dispositivo.

El CI (`.github/workflows/`) corre:

- **Flutter**: análisis, formato, tests en shards y un **gate visual** con goldens del Coach Hub ([docs/visual-gate.md](./docs/visual-gate.md)).
- **Functions**: build, lint y tests.
- **Reglas de Firestore y Storage**.
- **Reloj**: tests y conformance Swift.
- **Chequeos de seguridad**: gitleaks, CodeQL, shellcheck, npm audit, y que el default de `.firebaserc` no apunte a producción.

Reglas completas en [AGENTS.md § Calidad](./AGENTS.md#7-calidad-gates-antes-de-cada-commit).

## Workflow

- **Una rama por cambio**: `<tipo>/<scope>-<descripción>` (`feat/`, `fix/`, `docs/`, …). Conventional commits.
- **PR a `main`** con 1+ approve, **squash and merge**; la rama se borra al mergear.
- Antes de mergear se leen los comentarios de los bots (Codex, CodeQL).
- Cambios no triviales: ciclo **SDD** (`/sdd-new <cambio>`: explore → propose → spec → design → tasks → apply → verify → archive), con artefactos en `openspec/`.
- Varios agentes trabajan en paralelo en worktrees (`.claude/worktrees/`): anotate en `./scripts/agent-ledger.sh` antes de empezar.

Detalle en [AGENTS.md § Branching](./AGENTS.md#8-branching-y-prs) y [docs/workflow.md](./docs/workflow.md).

## Documentación

| Archivo | Para qué sirve |
|---|---|
| [AGENTS.md](./AGENTS.md) | **Constitución** del proyecto: reglas críticas, entornos, verificación. La leen Claude Code, Codex, Cursor y compañía. |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Onboarding técnico paso a paso. |
| [docs/](./docs/) | Producto, design system, arquitectura, performance, seguridad, workflow, roadmap, legales y runbooks. |
| [openspec/](./openspec/) | Specs y cambios del ciclo SDD. |
| [scripts/README.md](./scripts/README.md) | Scripts, credenciales y cuáles tocan producción. |

## Estado

Las fases 0 a 6 del [roadmap](./docs/roadmap.md) están completas: auth, home, workout, feed, Coach y Coach Hub, notificaciones, App Check. La **Fase 7, monetización y lanzamiento**, está en curso: cobros con Mercado Pago, legales, stores y relojes. Versión actual: `0.1.0+53`.
