# Proposal — home-shell

**Change**: `home-shell`
**Fase / Etapa**: Fase 2 · Etapa 1
**Branch**: `feat/home-shell`
**Owner**: Dev B
**Artifact store**: `openspec` · **Execution mode**: `interactive` · **Delivery**: `ask-on-risk`
**TDD**: Strict (per `docs/workflow.md:153`) — tests first in apply phase

---

## 1. Why

Hoy `/home` es un placeholder con el texto "INICIO · Tu home base". Es la primera pantalla que ve el alumno después del login (`authRedirect` lo manda ahí cuando el perfil está completo), y no comunica nada de lo que la app va a hacer: ni la rutina del día, ni el progreso semanal, ni siquiera lo saluda por nombre. Esto degrada la primera impresión del producto y bloquea las próximas etapas de Fase 2, que asumen que el shell de Home ya está en pie.

Este PR construye el **shell visual de Home** con datos placeholder/hardcodeados, para que las etapas siguientes (wire de `Session`/`Routine` en Etapa 5, providers reales en Fase 4) tengan dónde aterrizar. Es un avance de UI puro: cero lógica de dominio nueva, cero providers nuevos. El reviewer va a poder comparar la pantalla contra los mockups de `docs/app-alumno/screens/home/` y firmar visualmente.

## 2. What — deliverables visibles

Un reviewer que ejecute `flutter run` y navegue a `/home` debe ver:

- **Header**: "HOLA, {displayName}!" en `Barlow Condensed` 700 UPPERCASE + avatar circular a la derecha (foto si `avatarUrl` existe, fallback de iniciales con gradient `accent → highlight`).
- **Card "Empezar entrenamiento"**: card oscura con label "HOY · JUEVES" en `accent`, título "PUSH" hero, subtítulo "Pecho · Hombros · Tríceps", stat row con icon barbell + "6 ejercicios" e icon clock + "~55 min", y CTA pill full-width "▶ EMPEZAR ENTRENAMIENTO" en fill `accent`. **Contenido completamente hardcodeado**. CTA `onPressed` es no-op.
- **Card "Esta semana"**: card oscura con título y mensaje placeholder tipo "Todavía no entrenaste esta semana." en `textMuted`. Sin racha, sin muscle map, sin dots — esos viven en Etapa 5.
- **3 estados de `userProfileProvider` manejados**:
  - `data(profile)` → saludo y avatar reales
  - `loading` → skeleton/shimmer suave (sin layout jump)
  - `error` / `data(null)` → saludo genérico "HOLA!" + avatar fallback con iniciales placeholder
- **Sin `Scaffold` propio, sin `AppBackground`, sin `SafeArea`** — eso ya lo provee `_ShellScaffold` en `router.dart`.

## 3. How — arquitectura (Approach B confirmado)

`HomeScreen` queda como **composer delgado** que orquesta sub-widgets:

```
lib/features/home/
├── home_screen.dart                    // ConsumerWidget — lee userProfileProvider, compone los 3 hijos
└── widgets/
    ├── home_header.dart                // greeting + avatar; recibe UserProfile? por param
    ├── empezar_entrenamiento_card.dart // 100% stateless, data hardcoded
    ├── esta_semana_card.dart           // 100% stateless, estado placeholder
    └── home_cta_button.dart            // pill CTA local — NO promover a core en este PR
```

**State flow**:

- `HomeScreen` (`ConsumerWidget`) hace `ref.watch(userProfileProvider)` una sola vez.
- Pattern matching con `.when(data, loading, error)` resuelve el `UserProfile?` que se pasa por parámetro a `HomeHeader`.
- `EmpezarEntrenamientoCard` y `EstaSemanaCard` son `StatelessWidget` puros — no leen providers, no reciben data variable. Su data está hardcoded dentro del widget hasta Etapa 5.
- `HomeCTAButton` es un `StatelessWidget` con `onPressed`, `label`, `leadingIcon` — diseñado para que el día que se promueva a `lib/core/widgets/treino_button.dart` el cambio sea mecánico.

**Theme**: todo vía `AppPalette.of(context)`. Tipografía con `GoogleFonts.barlowCondensed` (headings/labels) y `GoogleFonts.barlow` (body). Spacing sólo en `{8, 12, 14, 18, 20}`. Radii: cards `r-md=16` o `r-lg=20`, CTA `r-full`.

**Dependencias nuevas**: `cached_network_image` se suma a `pubspec.yaml`. Es la primera vez que la app muestra una imagen de Firebase Storage (`avatarUrl`), y AGENTS.md ya lo mandata como estándar.

## 4. Trade-offs aceptados

| # | Decisión | Por qué |
|---|---|---|
| 1 | **Approach B (screen + widgets/)** sobre A (monolítico) o C (módulo completo con providers) | Espeja `lib/features/profile_setup/presentation/` que ya está validado en el repo. Cada widget testeable aislado. Etapa 5 va a reemplazar bodies, no tocar `home_screen.dart`. Aproach C es prematuro — no hay dominio que modelar todavía. |
| 2 | **Agregar `cached_network_image` ahora**, no `Image.network` interim | AGENTS.md ya lo mandata. Home es el primer consumer real (avatar del header). Hacerlo interim con `Image.network` y migrarlo después es trabajo doble y deja una violación de convención en el árbol. Costo: una línea en `pubspec.yaml` + un import. |
| 3 | **`HomeCTAButton` local en `home/widgets/`**, no `TreinoButton` core | KISS. No hay segundo consumer todavía. Promover ahora sería YAGNI y agranda el scope del PR. La señal para subirlo a `lib/core/widgets/` es cuando aparezca el segundo feature que lo necesite (probablemente "Empezar sesión" en Etapa 5 o el botón de Coach). El widget se diseña con API limpia (`onPressed`, `label`, `leadingIcon`) para que la migración sea mecánica. |
| 4 | **"Esta semana" en estado placeholder** | Los assets SVG de anatomía corporal no existen en el repo y la data de racha requiere infraestructura de `Session` que es Fase 4. Renderizar el shell vacío comunica intención sin bloquear esta etapa. |
| 5 | **CTA `onPressed` es no-op** | La navegación a la sesión activa vive en Etapa 5 (wire de `Session`). Dejar el botón clickeable sin destino sería confuso; mejor no-op explícito hasta que haya destino real. |

## 5. Out-of-scope (explícito)

Lo que **NO** entra en este PR y dónde sí entra:

- **Wire real del CTA "Empezar entrenamiento" a una sesión** → Etapa 5 (Fase 2) — depende de `Session` provider
- **Data real de la rutina del día (`Routine`, ejercicios, duración)** → Fase 4 (modelado de dominio) + Etapa 5 (wire)
- **Racha de días, dots de semana, stats SEMANA/MES en "Esta semana"** → Etapa 5
- **Anatomía corporal SVG en "Esta semana"** → Etapa 5 + asset pipeline (no existen en `assets/` todavía)
- **Insights tab, Profile tab, Coach tab** → otras etapas de Fase 2 / Fase 3
- **Crear Rutina, Ranking, Retos, Missions, Bets, Gamification** → fuera del producto (ver `CLAUDE.md` Quick reference)
- **Promoción de `HomeCTAButton` a `lib/core/widgets/TreinoButton`** → cuando aparezca el 2do consumer
- **Cambios en `router.dart`, `treino_bottom_bar.dart`, modelos freezed, providers de profile** → no hacen falta acá

## 6. Success criteria

El PR está "done" cuando todas estas condiciones son verificables:

1. **Visual parity**: comparación lado-a-lado contra `docs/app-alumno/screens/home/empezar-entrenamiento.png` y `docs/app-alumno/screens/home/esta-semana.png` muestra fidelidad de layout, tipografía, colores, radios y spacing (modulo el estado placeholder declarado de "Esta semana").
2. **Los 3 estados de `userProfileProvider` se renderizan sin crashes**:
   - `data(UserProfile con displayName y avatarUrl)` → header con nombre y foto
   - `data(null)` → fallback genérico
   - `loading` → skeleton sin layout jump
   - `error` → fallback genérico (no crash, no error visible al usuario)
3. **Tests verdes**: `home_screen_test.dart`, `home_header_test.dart`, `empezar_entrenamiento_card_test.dart`, `esta_semana_card_test.dart` — todos pasan. Los tests se escriben **antes** del código de cada widget (Strict TDD).
4. **`flutter analyze`**: 0 issues nuevos. Cero warnings, cero infos introducidos por este PR.
5. **`dart format .`**: el árbol queda limpio (sin diff residual).
6. **Sin HEX literals** en código nuevo. Sin `PhosphorIcons.X` directo. Sin `Theme.of(context).textTheme.X` con tamaños custom.
7. **`pubspec.yaml`** suma `cached_network_image` con versión pin sensata; `pubspec.lock` actualizado y commiteado.
8. **No se rompe el shell**: navegar a `/home` desde tab bar sigue funcionando, no aparece doble `AppBackground`, doble `SafeArea` ni doble `Scaffold`.

## 7. Risks (priorizados, con mitigación para apply)

| # | Riesgo | Severidad | Mitigación en apply |
|---|---|---|---|
| 1 | **`userProfileProvider` emite `null` o `error`** y el header crashea o muestra texto raro | Alta | Tests cubren los 4 casos (`data(profile)`, `data(null)`, `loading`, `error`) **antes** de escribir el widget. Fallback explícito: "HOLA!" + iniciales `"?"` o `TR`. |
| 2 | **`cached_network_image` agrega dependencia y `pubspec.lock` se desfasa** | Media | Agregar la dep con versión estable conocida (latest en pub.dev al momento), correr `flutter pub get`, commitear `pubspec.lock` en el mismo commit. CI debe pasar `flutter pub get` antes de tests. |
| 3 | **Re-aplicar `Scaffold`/`AppBackground`/`SafeArea`** dentro de `HomeScreen` (el shell ya los aplica) | Media | El test de `home_screen_test.dart` debe envolver con un `MaterialApp + Scaffold` mínimo (no con el shell real) y verificar que `HomeScreen` no introduce `Scaffold` propio. Comentario en el header del archivo explicando que el shell ya hace el wrapping. |
| 4 | **Spacing no canónico (16, 24)** se cuela en padding/gaps | Media | Code review checklist + grep de constantes literales `16` y `24` en los archivos nuevos antes de mergear. Usar `const Gap(N)` o `SizedBox(height: N)` con valores del set permitido. |
| 5 | **`AuthPillButton` se reusa por inercia** aunque tiene `arrowRight` hardcoded a la derecha (el mockup quiere ▶ a la izquierda) | Baja | `HomeCTAButton` es widget nuevo. Si alguien intenta reusar `AuthPillButton`, los tests visuales/widget van a fallar el snapshot del icon position. |
| 6 | **`test/features/home/` no existe todavía** y Strict TDD requiere tests primero | Baja | Tarea explícita en `tasks.md` que diga: "crear `test/features/home/` y `test/features/home/widgets/` ANTES del primer widget de producción". El apply agent debe escribir el test (rojo) → ver fallar → escribir el widget (verde). |

---

**Next recommended**: `sdd-spec` y `sdd-design` (pueden correr en paralelo).
