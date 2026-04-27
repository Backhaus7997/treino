# Contribuir a TREINO

Guía paso a paso para que cualquier dev del equipo pueda clonar el repo en su máquina, levantar el proyecto, y mandar su primer PR.

---

## 0. Lectura obligatoria antes de empezar

1. [AGENTS.md](./AGENTS.md) — reglas y convenciones del proyecto. Es la "constitución".
2. Este archivo (CONTRIBUTING.md) — onboarding técnico.
3. [.atl/skill-registry.md](./.atl/skill-registry.md) — catálogo de skills de IA disponibles.

Toda PR que viole reglas de AGENTS.md se devuelve sin merge.

---

## 1. Requisitos de la máquina

- **macOS** (probado en 14+ con Apple Silicon).
- **Linux**: funciona, pero algunos pasos del bootstrap script asumen brew/macOS — adaptar manualmente.
- **Windows**: usar WSL2 con Ubuntu y seguir la ruta Linux.

Tools globales que usamos (todos se instalan con el bootstrap script):
- Flutter 3.22+ / Dart 3.5+
- gentle-ai 1.24+ (workflow SDD)
- engram 1.14+ (memoria persistente para agentes)
- Xcode 15+ (sólo para builds iOS — opcional al inicio)
- Android Studio (sólo para Android — opcional al inicio)

---

## 2. Bootstrap automático

```bash
git clone https://github.com/Backhaus7997/treino.git
cd treino
./scripts/bootstrap.sh
```

El script:
1. Instala Flutter via Homebrew si falta.
2. Instala gentle-ai + engram.
3. Corre `gentle-ai install` para registrar los subagentes en Claude Code (y en otros agentes que tengas).
4. Corre `flutter pub get` para resolver dependencias del proyecto.
5. Verifica que `flutter analyze` corre sin errores.

Si falla algún paso, el script imprime el error y se detiene — fixá lo que falló y volvelo a correr (es idempotente).

### Setup manual (si preferís control)

```bash
# Flutter
brew install --cask flutter

# Gentle AI ecosystem
brew tap Gentleman-Programming/homebrew-tap
brew install gentle-ai
brew install gentleman-programming/tap/engram

# Wire up gentle-ai with Claude Code (and other agents on your machine)
gentle-ai install

# Project deps
flutter pub get

# Sanity check
flutter doctor -v
flutter analyze
```

---

## 3. Correr la app

### iOS (simulador)
```bash
open -a Simulator              # bootea un simulator si no hay
flutter run                    # detecta el simulator automáticamente
```

### iOS (device físico)
```bash
flutter devices                # lista devices disponibles
flutter run -d <device-id>
```
Requiere Xcode + Apple Developer account configurada. La primera vez en un device nuevo, abrí `ios/Runner.xcworkspace` en Xcode y firmá manualmente.

### Android
```bash
flutter emulators              # lista emuladores disponibles
flutter emulators --launch <emulator-id>
flutter run
```

### Hot reload / hot restart
- `r` en consola → hot reload (cambios de UI)
- `R` → hot restart (reinicia state)
- `q` → quit

---

## 4. Configuración personal

### Identidad de Git
```bash
git config user.name "Tu Nombre"
git config user.email "tu@email.com"
```

### SSH key para GitHub
Si pushear con HTTPS te pide credenciales constantemente, configurá una SSH key:
```bash
ssh-keygen -t ed25519 -C "tu@email.com"
cat ~/.ssh/id_ed25519.pub | pbcopy   # copia al clipboard
# Pegar en GitHub → Settings → SSH and GPG keys → New SSH key
git remote set-url origin git@github.com:Backhaus7997/treino.git
```

### Permisos en el repo
Pedile al owner (Backhaus7997) que te agregue como **Collaborator** en GitHub → Settings → Manage access.

---

## 5. Workflow diario

### Antes de empezar a trabajar
```bash
git checkout main
git pull
```

### Crear una rama para tu cambio
**Una rama = un cambio**. No metas dos features en la misma rama.

```bash
git checkout -b feat/<scope>-<descripción-kebab>
```

Ejemplos:
- `feat/auth-google-signin`
- `fix/workout-rest-timer-overflow`
- `chore/upgrade-go-router`

Tipos: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`.
Scopes: `auth`, `home`, `workout`, `feed`, `coach`, `profile`, `core`, `theme`, `infra`, `deps`.

### Workflow SDD (cambios no triviales)

Para cualquier feature/refactor que toque más de un archivo, usá el ciclo SDD via gentle-ai:

```
/sdd-new <change-name>
```

Eso dispara las fases:

1. **explore** — investigás opciones y leés el código.
2. **propose** — escribís intent, scope, approach.
3. **spec** — requisitos formales con Given/When/Then (RFC 2119: MUST, SHOULD, MAY).
4. **design** — decisiones técnicas, diagramas, integración con código existente.
5. **tasks** — checklist de TODOs implementables.
6. **apply** — escribís el código (Strict TDD: test antes que código).
7. **verify** — validás que la implementación matchea specs/design/tasks.
8. **archive** — sincronizás los specs y cerrás el cambio.

Cada fase queda persistida en Engram bajo `--project treino`. Las decisiones se recuperan en sesiones futuras con:
```bash
engram search "<query>" --project treino
engram context treino
```

### Cambios triviales (skip SDD)

Para fixes de 1-2 líneas, doc updates, dependency bumps:
```bash
git checkout -b fix/<descripción>
# editar código
git commit -am "fix: corregir typo en login screen"
```
No hace falta `/sdd-new`. Sí hace falta el PR igualmente.

### Antes de cada commit

Calidad gate (no negociable):
```bash
flutter analyze        # debe estar en 0 issues
dart format .          # formato consistente
flutter test           # tests verdes (cuando haya tests)
```

Si tocaste un archivo `freezed`:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### Commit messages — Conventional Commits

```
<tipo>(<scope>): <mensaje imperativo, < 72 chars>

<cuerpo opcional con bullets explicando qué y por qué>
```

Ejemplos buenos:
```
feat(auth): add Google Sign-In flow

- Wire google_sign_in 6.2 with Firebase Auth credential
- New AuthService.signInWithGoogle() handles the credential exchange
- Reuse PendingRegistrationStore for new-user routing to ProfileSetup
```

```
fix(workout): prevent rest timer overflow on long pauses

When user pauses > 1h, timer cast to int overflowed. Use Duration
for math, format with intl in render layer.
```

### Push y PR

```bash
git push -u origin <branch>
```

Después abrí el PR. Dos formas:

**A) Via gentle-ai (recomendado):**
```
/branch-pr
```
Te crea el PR contra `main`, llena el body con el resumen del cambio, linkea issue si existe.

**B) Via GitHub CLI:**
```bash
gh pr create --base main --fill
```

**C) Via web GitHub:** entrá al repo, GitHub te ofrece "Compare & pull request" automático.

### Reglas del PR

- **Template**: se carga solo (`.github/pull_request_template.md`). Llená TODO.
- **Reviewers**: asigná a los otros 2 devs.
- **Approve mínimo**: 1.
- **Estrategia de merge**: **Squash and merge**. Nada de "Create a merge commit".
- **Auto-delete branch**: activado, no hace falta borrar manualmente.
- **CI** (cuando esté): debe pasar antes del approve.

### Cuando un PR tuyo recibe comentarios

```bash
# en tu rama, hacés los cambios pedidos
git commit -am "address review: <qué arreglaste>"
git push
```
GitHub re-dispara los reviews automáticamente. Cuando volvés a tener 1 approve, mergeás.

### Después del merge

```bash
git checkout main
git pull
git branch -d <tu-branch>     # borra local; remota ya se borró sola
```

---

## 6. Cierre de fase (taggeo)

Cuando los cambios de una fase están todos en `main`, el lead taggea:
```bash
git tag -a v0.X.0-fase<N> -m "Fase <N>: <resumen breve>"
git push origin v0.X.0-fase<N>
```

No hay rama de fase. El tag sirve como punto de referencia para `git diff v0.1.0-fase0..v0.2.0-fase1`.

---

## 7. Trabajar con Firebase (Fase 1+)

Cuando arranquemos Fase 1, cada dev necesita acceso al proyecto Firebase. **No commitear** los archivos de credenciales generados (`google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart`); ya están en `.gitignore`.

Pasos para conectar tu máquina:
1. El owner te agrega al proyecto Firebase como Editor.
2. Instalás FlutterFire CLI: `dart pub global activate flutterfire_cli`.
3. `flutterfire configure --project=<project-id>` desde la raíz del repo.
4. Eso baja `firebase_options.dart` (gitignored) y configura cada plataforma.

Más detalle cuando llegue Fase 1.

---

## 8. Troubleshooting

### `flutter doctor` da errores
- iOS: abrí Xcode al menos una vez, aceptá la licencia, instalá Command Line Tools.
- Android: abrí Android Studio, instalá Android SDK Platform 34 desde el SDK Manager.
- CocoaPods: `sudo gem install cocoapods` o `brew install cocoapods`.

### `pod install` falla en iOS
```bash
cd ios
pod repo update
pod install
cd ..
```

### Build falla por dependencias raras
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

### gentle-ai / engram no aparecen en Claude Code
Reiniciá Claude Code. Las skills se descubren al inicio de la sesión, no en runtime.

### Engram no encuentra contexto del proyecto
```bash
engram projects list           # ver si "treino" aparece
engram search "" --project treino --limit 20
```

Si está vacío, alguien tiene que correr `/sdd-init` en el repo desde su máquina y pushear. Las memorias en Engram son **locales por máquina** — sólo se comparten si hacemos `engram sync` (no implementado todavía).

---

## 9. Comunicación del equipo

- **Decisiones de producto / arquitectura**: en el PR del cambio que las introduce, o en un issue tipo "design discussion".
- **Bugs**: issue con template `bug_report.md`.
- **Ideas / features**: issue con template `feature_request.md`.
- **Coordinación día a día**: el medio que usen (Slack/Discord/WhatsApp), pero **las decisiones técnicas siempre en GitHub** (issue/PR comment) para tener trazabilidad.

---

## 10. Cambios a esta guía

Esta guía y `AGENTS.md` viven en `main` y son **el contrato del equipo**. Cualquier modificación va por PR como cualquier otro cambio. El reviewer debe aprobar **explícitamente** la modificación de las reglas en el comentario.
