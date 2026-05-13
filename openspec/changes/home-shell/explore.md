# Explore — home-shell

**Change**: `home-shell`
**Fase / Etapa**: Fase 2 · Etapa 1
**Branch**: `feat/home-shell`
**Owner**: Dev B
**Scope**: Home shell + cards "Empezar entrenamiento" + "Esta semana" con datos placeholder (sin wire real — eso es Etapa 5).

---

## Current state

`lib/features/home/home_screen.dart` es un placeholder minimalista (centered `Column` con "INICIO" + "Tu home base"). Ya es `ConsumerWidget` y usa `AppPalette.of(context)` — el scaffolding está bien.

**Routing**: `/home` vive en un `ShellRoute` en [lib/app/router.dart](lib/app/router.dart). El shell (`_ShellScaffold`) ya envuelve el child con:

```dart
Scaffold(
  body: AppBackground(child: SafeArea(child: child)),
  bottomNavigationBar: TreinoBottomBar(...),
)
```

→ `HomeScreen` **NO debe** agregar su propio `Scaffold`, `AppBackground` ni `SafeArea`. Renderiza contenido directo.

**Tab index**: Home es índice 2 de `_kTabs = ['/workout', '/feed', '/home', '/coach', '/profile']`.

**Auth guard**: `authRedirect` redirige a `/profile-setup` cuando `profile.displayName == null`. Al llegar a `/home`, `displayName` está garantizado. Pero `userProfileProvider` puede estar `AsyncLoading` transitoriamente (hot-restart, primer frame), así que los 3 estados (data/loading/error) deben manejarse.

---

## Mockup analysis

### Card "Empezar entrenamiento" (`docs/app-alumno/screens/home/empezar-entrenamiento.png`)

Card oscura (`bgCard = #0F1513`), radio `r-lg = 20`, borde 1px. De arriba a abajo:

- "HOY · JUEVES" — `Barlow Condensed` 600, ~11px, color `accent`, letter-spacing ~1.4px
- "PUSH" — `Barlow Condensed` 700, ~36–40px, UPPERCASE, `textPrimary`
- "Pecho · Hombros · Tríceps" — `Barlow` 400, ~13px, `textMuted`
- Stat row: barbell icon + "6 ejercicios" · clock icon + "~55 min" — `Barlow` 400, ~12px, `textMuted`
- Pill full-width mint: "▶ EMPEZAR ENTRENAMIENTO" — fill `accent`, texto `bg`, `Barlow Condensed` 700 UPPERCASE, `r-full`

En Etapa 1 **todo el contenido es hardcodeado**. `onPressed` del CTA es no-op o null (la navegación se cablea en Etapa 5).

### Card "Esta semana" (`docs/app-alumno/screens/home/esta-semana.png`)

El mockup completo muestra: badge "RACHA ACTUAL", número hero "12 DÍAS", siluetas de anatomía corporal en SVG, dots de días de semana, dos tiles de stats (SEMANA/MES). Requiere data real **y** assets SVG no presentes en el repo (`assets/logo/` sólo tiene el logo).

Para Etapa 1: renderizar el shell de la card en **estado vacío/placeholder** — sin número de racha, sin muscle map, sin dots de semana. Un mensaje `textMuted` tipo "Todavía no entrenaste esta semana." alcanza. La implementación completa es material de Etapa 5.

### Header del Home (inferido de convenciones de producto)

- Saludo: "HOLA, {displayName}!" — `Barlow Condensed` 700 UPPERCASE
- Avatar: circular, `avatarUrl` si existe, fallback iniciales con gradient `accent → highlight`
- Data source: `userProfileProvider` (`StreamProvider<UserProfile?>`)

---

## Affected files

| Archivo | Por qué |
|---|---|
| `lib/features/home/home_screen.dart` | Reemplazo completo del placeholder |
| `lib/features/home/widgets/home_header.dart` | Nuevo — saludo + avatar |
| `lib/features/home/widgets/empezar_entrenamiento_card.dart` | Nuevo — primera card |
| `lib/features/home/widgets/esta_semana_card.dart` | Nuevo — segunda card (estado placeholder) |
| `test/features/home/home_screen_test.dart` | Nuevo — widget test (Strict TDD: se escribe primero) |
| `test/features/home/widgets/home_header_test.dart` | Nuevo |
| `test/features/home/widgets/empezar_entrenamiento_card_test.dart` | Nuevo |
| `test/features/home/widgets/esta_semana_card_test.dart` | Nuevo |
| `pubspec.yaml` | Sumar `cached_network_image` para mostrar `avatarUrl` (ver riesgos) |

No requieren cambios: `router.dart`, `treino_bottom_bar.dart`, modelos freezed, `treino_icon.dart` (los constants ya cubren el caso).

---

## Theme tokens

Todos vía `AppPalette.of(context)`:

| Token | Uso en Home |
|---|---|
| `palette.accent` | Label "HOY · JUEVES", fill del CTA, badge de racha (Etapa 5) |
| `palette.highlight` | Gradient fallback del avatar |
| `palette.textPrimary` | Nombre de rutina, saludo, headers |
| `palette.textMuted` | Subtítulos de cards, labels de stats, placeholder text |
| `palette.bgCard` | Fill de cards (`#0F1513`) |
| `palette.border` | Borde 1px de cards |
| `palette.bg` | Color de texto del CTA |

**Tipografía**: `GoogleFonts.barlowCondensed(...)` para headings/labels, `GoogleFonts.barlow(...)` para body. **Nunca** `Theme.of(context).textTheme` con tamaños custom.

**Spacing**: sólo `8 · 12 · 14 · 18 · 20`px. **Radii**: cards `r-md=16` o `r-lg=20`; CTA `r-full=9999`.

---

## Provider integration

`userProfileProvider` es `StreamProvider<UserProfile?>` en [lib/features/profile/application/user_providers.dart](lib/features/profile/application/user_providers.dart). El `?` significa que `null` es posible aún con sesión (Firestore offline, race). Patrón:

```dart
final profileAsync = ref.watch(userProfileProvider);
profileAsync.when(
  data: (profile) => /* profile?.displayName, profile?.avatarUrl */,
  loading: () => /* skeleton/shimmer */,
  error: (_, __) => /* fallback greeting */,
);
```

No se necesitan providers nuevos para Etapa 1. Todo el contenido de las cards está hardcodeado.

Proyecto usa **Riverpod 2 manual** (sin `@riverpod` codegen). Patrones a seguir: `StreamProvider`, `NotifierProvider`, `Provider`, `StateProvider` — referencias en `user_providers.dart` y `profile_setup_providers.dart`.

---

## Test conventions

Sacadas de `test/features/auth/` y `test/features/profile/`:

1. Helper wrap: `Widget _wrap(Widget w) => MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w))`
2. Provider overrides: `ProviderScope(overrides: [userProfileProvider.overrideWith(...)], child: MaterialApp(...))`
3. Mocking con `mocktail`: `class MockUserRepository extends Mock implements UserRepository {}`
4. Naming: `testWidgets('REQ-HOME-XXX: descripción', ...)` o `testWidgets('scenario X.Y — descripción', ...)`
5. Estructura mirror: `test/features/home/widgets/`
6. **Strict TDD activado** ([docs/workflow.md:153](docs/workflow.md)) — los tests se escriben antes del código en la fase apply
7. `AppTheme.dark()` para todos los widget tests

---

## Reusable widgets

| Widget | Path | Reuso |
|---|---|---|
| `AuthPillButton` | `lib/features/auth/presentation/widgets/auth_pill_button.dart` | Cercano al CTA pero hardcodea `TreinoIcon.arrowRight` a la derecha; el mockup necesita ▶ a la izquierda |
| `AvatarPickerButton` | `lib/features/profile_setup/presentation/widgets/` | Es interactivo (picker) — Home necesita display read-only; mejor crear `HomeAvatarWidget` separado o inline |
| `ExperienceCard`/`GymCard` | `lib/features/profile_setup/presentation/widgets/` | Referencia de patrón de card (`bgCard` fill, `r-md=16`, borde `accent` cuando selected) |
| `AppBackground` | `lib/core/widgets/` | Ya aplicado por el shell — **NO re-aplicar** |
| `TreinoIcon.tabWorkout` + `TreinoIcon.clock` | `lib/core/widgets/treino_icon.dart` | Iconos del stat row — los dos existen |

`TreinoButton` y `TreinoCard` están documentados como upcoming en `docs/design-system.md` pero no implementados. Crearlos acá agranda el scope. Alternativa segura: `HomeCTAButton` dentro de `lib/features/home/widgets/`, elevar a core sólo cuando haya 2+ features que lo usen.

---

## Approaches

| Aproach | Descripción | Pros | Cons | Esfuerzo |
|---|---|---|---|---|
| **A** — Monolithic | Todo en `home_screen.dart` | Un solo archivo | Sub-partes intesteables, Etapa 5 lo va a tener que romper | Bajo |
| **B** — Screen + `widgets/` ★ | `HomeScreen` compone `widgets/{header, empezar_card, esta_semana_card}` | Mismo patrón que `profile_setup`, cada widget testeable aislado, composable para Etapa 5 | Más archivos | Bajo-medio |
| **C** — Módulo completo | Providers + domain layer ya | Future-proof | Prematuro para etapa de placeholder | Alto |

**Recomendación: Approach B**. Espeja la estructura de `lib/features/profile_setup/presentation/` que ya está validada en el repo. Cada widget tiene su archivo de test. Etapa 5 sólo va a tener que reemplazar el body de los widgets, no tocar `home_screen.dart`.

---

## Risks

1. **`cached_network_image` NO está en `pubspec.yaml`** — AGENTS.md lo mandata para imágenes de red pero no está instalado. Home es la primera pantalla que muestra `avatarUrl` (URL de Firebase Storage). Opciones: agregarlo en este PR (recomendado, scope chico) o usar `Image.network` interim (viola convención de performance). **A decidir en propose**.

2. **Assets SVG de anatomía corporal faltan** — el mockup completo de "Esta semana" los requiere, no existen en el repo. Etapa 1 evita el issue (estado placeholder), pero hay que dejarlo explícito como out-of-scope y carry-over a Etapa 5.

3. **`AuthPillButton` no matchea el CTA del mockup** — siempre pone `arrowRight` a la derecha; mockup quiere ▶ a la izquierda. Necesita widget nuevo o parametrización. Riesgo bajo pero a no olvidar.

4. **`test/features/home/` no existe** — Strict TDD significa que el apply agent crea el archivo de test ANTES de cualquier cambio en `home_screen.dart`. Hay que ser explícito sobre el orden en la fase tasks.

5. **`userProfileProvider` puede emitir `null`** — caso estructuralmente posible. El header debe mostrar fallback con gracia (saludo genérico "HOLA!", iniciales placeholder).

6. **Spacing constraint `8 · 12 · 14 · 18 · 20` sólo** — el padding interno del CTA y los gaps internos de las cards tienen que mapear a estos valores. **Nada de 16/24px**. Atención en la spec.

---

## Decisiones abiertas para propose

1. Aproach B confirmado (screen + widget decomposition)?
2. Agregar `cached_network_image` ahora o `Image.network` interim?
3. Crear `HomeCTAButton` puntual en `home/widgets/` o adelantar el `TreinoButton` core que figura en `design-system.md`?

---

**Next recommended**: `sdd-propose`
