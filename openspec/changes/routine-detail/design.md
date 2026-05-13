# Design — routine-detail

**Change**: `routine-detail`
**Fase / Etapa**: Fase 2 · Etapa 4
**Branch**: `feat/routine-detail`
**Owner**: Dev C
**Artifact store**: `hybrid`
**TDD**: Strict — tests preceden implementación en apply.
**Depends on**: `propose.md`, `explore.md`. Spec (`spec.md`) y este documento se generan en paralelo.

Este documento es el contrato de implementación para el sub-agente `sdd-apply`. Dos devs implementando desde acá deben producir código casi idéntico. Las shapes mostradas son normativas.

Orden de lectura recomendado para apply: `propose.md` → `spec.md` → este archivo → mockups (`docs/app-alumno/screens/entrenamiento/expandir-plantilla.png` y `docs/app-alumno/screens/detalle-rutina/detalle-ejercicio.png`).

---

## 1. Architecture summary

Capa de presentation pura sobre infraestructura ya existente. Cero cambios en `domain/`, `data/` o `application/` del feature `workout`: dos pantallas (`RoutineDetailScreen`, `ExerciseDetailScreen`) más tres widgets reutilizables (`ExerciseSlotRow`, `StatTile`, `TechniqueInstructionItem`) que se montan como composers delgados sobre `routineByIdProvider.family` y `exerciseByIdProvider.family` (lookups O(1) memoizados que derivan de `routinesProvider` / `exercisesProvider`). El único impacto fuera de `lib/features/workout/presentation/` es agregar dos sub-`GoRoute` dentro del `ShellRoute` existente en `lib/app/router.dart` y un símbolo nuevo (`TreinoIcon.timer`) en `lib/core/widgets/treino_icon.dart`. Cero Firestore reads nuevos, cero providers nuevos, cero dependencias nuevas en `pubspec.yaml`.

---

## 2. File map

Convención: source bajo `lib/features/workout/presentation/`, tests en mirror exacto bajo `test/features/workout/presentation/`. Todos los paths son absolutos desde la raíz del repo (`/Users/martinbackhaus/treino/`).

### Archivos nuevos

| Path | Propósito | LOC aprox. |
|---|---|---|
| `lib/features/workout/presentation/routine_detail_screen.dart` | `ConsumerStatefulWidget` orquestador. Watch `routineByIdProvider(routineId)`, `selectedDayIndex` local, compone hero + day selector + lista de slots + bottom CTA bar. | ~280 |
| `lib/features/workout/presentation/exercise_detail_screen.dart` | `ConsumerWidget`. Watch `exerciseByIdProvider(exerciseId)`, compone hero + breadcrumb + stats placeholder + sección Técnica + empty state historial. | ~220 |
| `lib/features/workout/presentation/widgets/exercise_slot_row.dart` | Fila tappeable por `RoutineSlot`. Thumb + nombre + sets×reps + muscle group + badge "ÚLTIMO" placeholder. | ~140 |
| `lib/features/workout/presentation/widgets/stat_tile.dart` | Tile reutilizable label + value (acepta `value: String?` → dash placeholder). | ~70 |
| `lib/features/workout/presentation/widgets/technique_instruction_item.dart` | Cue numerada — número en círculo accent + texto. | ~60 |
| `test/features/workout/presentation/routine_detail_screen_test.dart` | SCENARIO-071..074: loading, render con day+slots, slots vacíos, not-found. | ~180 |
| `test/features/workout/presentation/exercise_detail_screen_test.dart` | SCENARIO-075..078: loading, render técnica, técnica nula, not-found. | ~160 |
| `test/features/workout/presentation/widgets/exercise_slot_row_test.dart` | SCENARIO-079..080: render de campos + tap callback. | ~90 |
| `test/features/workout/presentation/widgets/stat_tile_test.dart` | SCENARIO-081..082: render value + render dash placeholder. | ~60 |

### Archivos modificados

| Path | Cambio |
|---|---|
| `lib/app/router.dart` | Agregar 2 `GoRoute` anidados dentro del `ShellRoute.routes`. `WorkoutScreen` no se toca. |
| `lib/core/widgets/treino_icon.dart` | Agregar `TreinoIcon.timer = PhosphorIconsRegular.timer` en la sección "Stats / tiempo". |

### Archivos explícitamente NO modificados

`lib/features/workout/workout_screen.dart`, `lib/features/workout/domain/*`, `lib/features/workout/data/*`, `lib/features/workout/application/*`, `lib/app/theme/app_palette.dart`, `firestore.rules`, `pubspec.yaml`, `pubspec.lock`. Tocar cualquiera de estos está fuera de scope (ver propose §5).

**Diff total estimado**: ~900 LOC. Producción ~770, tests ~490 (algunos comparten fixtures). Bien dentro del budget de PR.

---

## 3. Widget tree

Notación: `[shell]` = provisto por `_ShellScaffold` en `router.dart` — **ya presente**, no re-agregar (`Scaffold`, `AppBackground`, `SafeArea`, `TreinoBottomBar`). `[screen]` = construido dentro del `build` de la pantalla.

### 3.1 `RoutineDetailScreen`

```
[shell] Scaffold
[shell]   body: AppBackground
[shell]     SafeArea
[shell]       (bottomNavigationBar: TreinoBottomBar permanece visible)
[screen]       CustomScrollView (slivers — necesario para hero strip de ancho completo sobre padding horizontal del contenido)
[screen]         SliverToBoxAdapter — _HeroStrip(imageUrl: routine.imageUrl)
[screen]         SliverPadding (horizontal: 20)
[screen]           SliverList
[screen]             SizedBox(height: 18)
[screen]             _DayChipBadge(text: '${routine.split.toUpperCase()} · DÍA ${day.dayNumber}')
[screen]             SizedBox(height: 8)
[screen]             _DayTitle(text: day.name.toUpperCase())
[screen]             SizedBox(height: 14)
[screen]             _StatRow(
[screen]               tiles: [
[screen]                 StatTile(label: 'EJERCICIOS', value: '${day.slots.length}'),
[screen]                 StatTile(label: 'SETS',       value: '${_totalSets(day)}'),
[screen]                 StatTile(label: 'MINUTOS',    value: _minutesValue(day, routine)),
[screen]               ],
[screen]             )
[screen]             SizedBox(height: 18)
[screen]             // Day selector — sólo si routine.days.length > 1
[screen]             if (routine.days.length > 1)
[screen]               _DaySelector(
[screen]                 days: routine.days,
[screen]                 selectedIndex: selectedDayIndex,
[screen]                 onSelect: (i) => setState(() => selectedDayIndex = i),
[screen]               ),
[screen]             SizedBox(height: 20)
[screen]             _SectionHeader(text: 'EJERCICIOS')
[screen]             SizedBox(height: 12)
[screen]             // Lista de slots — o empty state
[screen]             if (day.slots.isEmpty)
[screen]               _EmptyState(message: 'No hay ejercicios en este día.')
[screen]             else
[screen]               ...day.slots.expand((slot) => [
[screen]                 ExerciseSlotRow(
[screen]                   slot: slot,
[screen]                   onTap: () => context.push('/workout/exercise/${slot.exerciseId}'),
[screen]                 ),
[screen]                 SizedBox(height: 12),
[screen]               ]),
[screen]             SizedBox(height: 20)
[screen]             _DisabledCTABar()   // bottom non-sticky: 2 botones EDITAR / EMPEZAR al 40% opacity
[screen]             SizedBox(height: 18)
```

**Rationale `CustomScrollView`**: el hero strip debe llegar a edge-to-edge (sin padding lateral) mientras que el resto del contenido tiene `horizontal: 20`. `ListView` + `Padding` no permite eso sin envolver cada child manualmente. `CustomScrollView` con un `SliverToBoxAdapter` (hero) seguido de `SliverPadding > SliverList` resuelve el patrón con un solo scroll view. Esto difiere de `home_screen.dart` (`ListView` con padding uniforme) porque `home` no tiene hero edge-to-edge.

**Loading/error/null tree** (envuelve TODO el `CustomScrollView`, ver §5):

```
routineAsync.when(
  data: (routine) => routine == null
      ? _NotFoundState(label: 'Rutina no encontrada')
      : <árbol de arriba>,
  loading: () => _RoutineLoadingSkeleton(),         // hero placeholder + 4 filas grises
  error: (_, __) => _ErrorState(onRetry: () => ref.invalidate(routineByIdProvider(routineId))),
)
```

### 3.2 `ExerciseDetailScreen`

```
[shell] Scaffold > AppBackground > SafeArea (idem)
[screen]       CustomScrollView
[screen]         SliverToBoxAdapter — _HeroPlaceholder()  // solid color + centered icon
[screen]         SliverPadding (horizontal: 20)
[screen]           SliverList
[screen]             SizedBox(height: 18)
[screen]             _Breadcrumb(text: '${exercise.muscleGroup.toUpperCase()} · ${exercise.category.toUpperCase()}')
[screen]             SizedBox(height: 8)
[screen]             _ExerciseTitle(text: exercise.name.toUpperCase())
[screen]             SizedBox(height: 14)
[screen]             _StatRow(
[screen]               tiles: [
[screen]                 StatTile(label: '1RM',       value: null),  // dash placeholder
[screen]                 StatTile(label: 'SESIONES', value: null),
[screen]                 StatTile(label: 'PROGRESO', value: null),
[screen]               ],
[screen]             )
[screen]             SizedBox(height: 20)
[screen]             _SectionHeader(text: 'TÉCNICA')
[screen]             SizedBox(height: 12)
[screen]             if (exercise.techniqueInstructions == null || exercise.techniqueInstructions!.isEmpty)
[screen]               _EmptyState(message: 'Sin instrucciones disponibles.')
[screen]             else
[screen]               ...exercise.techniqueInstructions!.asMap().entries.expand((e) => [
[screen]                 TechniqueInstructionItem(index: e.key + 1, text: e.value),
[screen]                 SizedBox(height: 12),
[screen]               ]),
[screen]             SizedBox(height: 20)
[screen]             _SectionHeader(text: 'HISTORIAL')
[screen]             SizedBox(height: 12)
[screen]             _HistoryEmptyState(message: 'Todavía no entrenaste este ejercicio.')
[screen]             SizedBox(height: 20)
[screen]             // No CTA inferior. Si exercise.videoUrl != null → _VideoComingSoon() entre stats y técnica.
```

Loading/error/null se envuelven igual que en RoutineDetailScreen.

### 3.3 Shared widgets API

#### `ExerciseSlotRow`

```dart
class ExerciseSlotRow extends StatelessWidget {
  const ExerciseSlotRow({
    super.key,
    required this.slot,
    required this.onTap,
    this.lastWeightDisplay,  // null → renders dash inside ÚLTIMO badge (Fase 2 estado)
  });

  final RoutineSlot slot;
  final VoidCallback onTap;
  final String? lastWeightDisplay;
}
```

**Tree interno**:

```
Material (color: transparent)
  InkWell(onTap: onTap, borderRadius: r-md=16)
    Container(decoration: bgCard + r-md=16 + border 1)
      Padding(EdgeInsets.all(14))
        Row(crossAxisAlignment: center)
          // Thumb 48×48 con icon placeholder
          Container(
            width: 48, height: 48,
            decoration: bgColor: palette.bgCard, border 1 palette.border, r=12,
            alignment: center,
            child: Icon(TreinoIcon.tabWorkout, size: 24, color: palette.textMuted),
          )
          SizedBox(width: 14)
          Expanded(
            Column(crossAxisAlignment: start)
              Text(slot.exerciseName.toUpperCase(),  // Barlow Condensed w700 16, textPrimary, letterSpacing 0.5
              SizedBox(height: 8)
              Row(
                Text('${slot.targetSets} · ${slot.targetRepsMin}–${slot.targetRepsMax}', // Barlow w400 13, textMuted
                SizedBox(width: 12)
                Text('·', textMuted)
                SizedBox(width: 12)
                Text(slot.muscleGroup.toUpperCase(),  // Barlow Condensed w600 11, textMuted, letterSpacing 1.2
              )
              SizedBox(height: 8)
              // Rest indicator (usa TreinoIcon.timer nuevo)
              Row(
                Icon(TreinoIcon.timer, size: 14, color: palette.textMuted),
                SizedBox(width: 8),
                Text('${slot.restSeconds}s descanso', // Barlow w400 12, textMuted
              )
          )
          SizedBox(width: 12)
          _UltimoBadge(value: lastWeightDisplay)   // siempre dash en Fase 2
)
```

Semantics: `Semantics(button: true, label: 'Ejercicio ${slot.exerciseName}, ${slot.targetSets} series de ${slot.targetRepsMin} a ${slot.targetRepsMax} repeticiones', child: …)`. Tap target altura total ≥ 48 px (thumb 48 + padding 14×2 = 76, holgado).

#### `StatTile`

```dart
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,  // String? — null renderiza "—"
  });

  final String label;
  final String? value;
}
```

**Tree**: `Column(crossAxisAlignment: center, children: [Text(value ?? '—', Barlow Condensed w700 22, textPrimary), SizedBox(height: 4), Text(label.toUpperCase(), Barlow Condensed w600 10, textMuted, letterSpacing 1.2)])`. Wrap externo del consumer envuelve cada tile en `Expanded` dentro del `_StatRow`.

#### `TechniqueInstructionItem`

```dart
class TechniqueInstructionItem extends StatelessWidget {
  const TechniqueInstructionItem({
    super.key,
    required this.index,   // 1-based para display
    required this.text,
  });

  final int index;
  final String text;
}
```

**Tree**: `Row(crossAxisAlignment: start, children: [Container(28×28, decoration: gradient accent→highlight, shape: circle, child: Text('$index', Barlow Condensed w700 14, color: palette.bg)), SizedBox(width: 12), Expanded(Text(text, Barlow w400 14, textPrimary, height: 1.4))])`.

#### Privados a las pantallas (NO van a `widgets/`)

`_HeroStrip`, `_HeroPlaceholder`, `_DayChipBadge`, `_DayTitle`, `_StatRow`, `_DaySelector`, `_SectionHeader`, `_EmptyState`, `_DisabledCTABar`, `_NotFoundState`, `_ErrorState`, `_RoutineLoadingSkeleton`, `_ExerciseLoadingSkeleton`, `_Breadcrumb`, `_ExerciseTitle`, `_HistoryEmptyState`, `_UltimoBadge`, `_VideoComingSoon` viven como `class _Xxx extends StatelessWidget` privados dentro del archivo de su screen. Razón: ninguno se reusa fuera de la pantalla; promoverlos a `widgets/` sería YAGNI y duplicaría tests sin valor. Sólo `ExerciseSlotRow`, `StatTile`, `TechniqueInstructionItem` se promueven porque (a) se reusan entre pantallas o (b) tienen suficiente complejidad propia para merecer test aislado.

---

## 4. Routing changes

### 4.1 Diff exacto sobre `lib/app/router.dart`

Sólo cambia el bloque `routes:` del `ShellRoute`. Mostrado el patch contextual:

```diff
       ShellRoute(
         builder: (context, state, child) => _ShellScaffold(
           location: state.uri.toString(),
           child: child,
         ),
         routes: [
           GoRoute(
             path: '/workout',
             pageBuilder: (_, __) => _noAnim(const WorkoutScreen()),
+            routes: [
+              GoRoute(
+                path: 'routine/:routineId',
+                pageBuilder: (context, state) {
+                  final routineId = state.pathParameters['routineId']!;
+                  return _noAnim(RoutineDetailScreen(routineId: routineId));
+                },
+              ),
+              GoRoute(
+                path: 'exercise/:exerciseId',
+                pageBuilder: (context, state) {
+                  final exerciseId = state.pathParameters['exerciseId']!;
+                  return _noAnim(ExerciseDetailScreen(exerciseId: exerciseId));
+                },
+              ),
+            ],
           ),
           GoRoute(
             path: '/feed',
             ...
```

Y al tope del archivo agregar los imports:

```dart
import '../features/workout/presentation/exercise_detail_screen.dart';
import '../features/workout/presentation/routine_detail_screen.dart';
```

### 4.2 Notas de routing

- **Sub-rutas relativas**: `routine/:routineId` (sin slash inicial) es relativo a `/workout`, resultando en `/workout/routine/:routineId`. Esa es la convención de `go_router` para anidación dentro de un parent `GoRoute`. Verificar en el primer test que `context.push('/workout/routine/foo')` matchea (no `/workout//routine/foo`).
- **Bottom bar visible**: la `_currentIndex` de `_ShellScaffold` usa `location.startsWith('/workout')` → cualquier sub-ruta de workout queda con el tab "ENTRENAR" highlighted. Sin cambios en `_kTabs` ni en `_ShellScaffold`.
- **Extracción de params**: `state.pathParameters['routineId']!` con bang. **Justificación**: go_router garantiza que el builder no se invoca con el param ausente — si el path no matchea, `GoRouter` redirige a no-match o invoca un `errorBuilder`. No hace falta defensive null-check ni `if (id.isEmpty) return …`. **Validación de "id no existe en seed"** vive en el provider (`routineByIdProvider` retorna `null`), no en el router. Esto matchea el patrón ya usado en `'/forgot-password'` (sin params) y es consistente con cómo otros features usarían pathParams. Si en el futuro queremos error explícito por id inválido (ej. caracteres no alfanuméricos), agregar `redirect` por sub-ruta — fuera de scope.
- **No usar `name:` en GoRoute**: el repo no usa nombres todavía, mantenemos consistencia.

---

## 5. State strategy

### 5.1 Providers ya existen — se reusan tal cual

Ambos providers son `FutureProvider.family<T?, String>` (ver `lib/features/workout/application/routine_providers.dart` y `exercise_providers.dart`):

```dart
final routineByIdProvider  = FutureProvider.family<Routine?,  String>(...);
final exerciseByIdProvider = FutureProvider.family<Exercise?, String>(...);
```

**Notar**: son `FutureProvider.family`, NO `AsyncNotifierProvider.family`. Esto importa para el override pattern en tests (ver §8). Ambos derivan de `routinesProvider` / `exercisesProvider` (catálogo eager-loaded auth-gated) — segunda lectura en la misma sesión no hace Firestore I/O.

### 5.2 `selectedDayIndex` — state local del ConsumerStatefulWidget

```dart
class RoutineDetailScreen extends ConsumerStatefulWidget {
  const RoutineDetailScreen({super.key, required this.routineId});
  final String routineId;

  @override
  ConsumerState<RoutineDetailScreen> createState() => _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen> {
  int selectedDayIndex = 0;  // <-- presentation-only

  @override
  Widget build(BuildContext context) { … }
}
```

**Por qué NO un provider**:

1. **Scope**: el valor vive durante la sesión de scroll de UNA pantalla. No se comparte con otros widgets. No sobrevive al pop del route — esa es la semántica deseada (volver a entrar al detail empieza de nuevo en día 1).
2. **Naturaleza**: es índice de selección puramente visual, sin side-effects, sin persistencia, sin lectura cruzada.
3. **Ceremony cost**: un `StateProvider.family<int, String>(routineId)` agregaría 3+ líneas de boilerplate y obligaría a `ref.read` + `ref.watch` en lugar del directo `setState`. Sin beneficio compensatorio.
4. **Reset behaviour**: el provider habría que disponerlo en `dispose` o usar `.autoDispose` con keepAlive correcto. `setState` es cero ceremony para el mismo resultado.

Regla a respetar: cualquier state futuro que (a) deba compartirse con otra pantalla, (b) deba sobrevivir a navegación, o (c) tenga side effects (network, persist) → promover a Riverpod. Hoy ninguno aplica.

### 5.3 Patrón `AsyncValue.when` — shape normativo

`RoutineDetailScreen.build` (dentro del `State`):

```dart
@override
Widget build(BuildContext context) {
  final palette = AppPalette.of(context);
  final routineAsync = ref.watch(routineByIdProvider(widget.routineId));

  return routineAsync.when(
    data: (routine) {
      if (routine == null) {
        return const _NotFoundState(label: 'Rutina no encontrada');
      }
      // Clamp para soportar mutaciones de days (no debería pasar, defensivo)
      final dayIndex = selectedDayIndex.clamp(0, routine.days.length - 1);
      final day = routine.days.isEmpty ? null : routine.days[dayIndex];
      if (day == null) {
        return const _EmptyState(message: 'Esta rutina no tiene días configurados.');
      }
      return _RoutineDetailContent(
        routine: routine,
        day: day,
        selectedDayIndex: dayIndex,
        onSelectDay: (i) => setState(() => selectedDayIndex = i),
      );
    },
    loading: () => const _RoutineLoadingSkeleton(),
    error: (err, _) => _ErrorState(
      message: 'No pudimos cargar la rutina.',
      onRetry: () => ref.invalidate(routineByIdProvider(widget.routineId)),
    ),
  );
}
```

`ExerciseDetailScreen.build` mismo shape, sin `selectedDayIndex` (no hay state local):

```dart
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(exerciseId));
    return exerciseAsync.when(
      data: (exercise) => exercise == null
          ? const _NotFoundState(label: 'Ejercicio no disponible')
          : _ExerciseDetailContent(exercise: exercise),
      loading: () => const _ExerciseLoadingSkeleton(),
      error: (_, __) => _ErrorState(
        message: 'No pudimos cargar el ejercicio.',
        onRetry: () => ref.invalidate(exerciseByIdProvider(exerciseId)),
      ),
    );
  }
}
```

**Invariantes**:

| Branch | Renderiza | Notas |
|---|---|---|
| `data(routine)` con routine != null | árbol completo §3.1 | Path feliz |
| `data(null)` | `_NotFoundState` + back | `routineId` no existe en seed o no se autorizó |
| `loading()` | `_RoutineLoadingSkeleton` (hero box + 4 filas grises) | Cubre AsyncLoading inicial + invalidate-induced |
| `error(_, _)` | `_ErrorState` con retry → `ref.invalidate(…)` | No exponemos el `Object` al usuario |

**Performance**: las 4 ramas se evalúan en cada rebuild pero sólo una construye widgets. Es el patrón estándar de Riverpod.

---

## 6. Theming / typography

### 6.1 Tokens — uso por superficie

Sourceados estrictamente desde `AppPalette.of(context)`. Cualquier HEX literal en los archivos nuevos es **defecto** (regla de `AGENTS.md` reafirmada en `CLAUDE.md`).

| Elemento | Color token | Notas |
|---|---|---|
| Background general | `palette.bg` | Provisto por `AppBackground` del shell — no re-aplicar |
| Hero strip gradient | `palette.accent` → `palette.bg` | `LinearGradient(begin: topLeft, end: bottomRight, colors: [accent.withValues(alpha: 0.85), bg])` |
| Hero placeholder solid | `palette.espresso` | Color elevated. Centrado icon en `palette.textMuted` |
| Card / fila slot bg | `palette.bgCard` | r-md=16, border 1 px `palette.border` |
| Card border | `palette.border` | Translúcido por design system (`0x1AFFFFFF`) |
| Badge `SPLIT · DÍA N` | bg `palette.accent.withValues(alpha: 0.16)`, text `palette.accent` | Pill r-full |
| Badge `ÚLTIMO` | bg `palette.bgCard`, text `palette.textMuted` | r=8, border 1 px `palette.border` |
| Headings primarios | `palette.textPrimary` | Hero day title, exercise title |
| Labels secundarios | `palette.textMuted` | Breadcrumb, muscle group, stat labels, rest indicator |
| Number badge (técnica) | gradient `palette.accent` → `palette.highlight` | shape circle, text `palette.bg` |
| Disabled CTA EDITAR (ghost) | border `palette.border`, text `palette.textPrimary.withValues(alpha: 0.4)` | `onPressed: null` |
| Disabled CTA EMPEZAR (pill) | bg `palette.accent.withValues(alpha: 0.4)`, text `palette.bg` | `onPressed: null`. Match con `AuthPillButton` pattern (`disabledBackgroundColor`). |

**`.withValues(alpha:)` vs `.withOpacity()`**: usar `.withValues(alpha: x)` (Flutter ≥ 3.27). `.withOpacity` está deprecated.

### 6.2 Tipografía

`GoogleFonts.barlowCondensed` para headlines, badges, labels SHORT (UPPERCASE en el string del literal — no usar `TextCapitalization`). `GoogleFonts.barlow` para body multilinea y stats.

| Elemento | Family | Weight | Size | Letter-spacing | Notas |
|---|---|---|---|---|---|
| `_DayTitle` (hero "PUSH") | Barlow Condensed | w700 | 36 | 0.5 | UPPERCASE literal |
| `_ExerciseTitle` (hero) | Barlow Condensed | w700 | 32 | 0.5 | UPPERCASE literal — un poco más chico que routine title porque suele tener más caracteres |
| `_DayChipBadge` ("PPL · DÍA 1") | Barlow Condensed | w600 | 11 | 1.4 | accent |
| `_Breadcrumb` ("PECHO · COMPOUND") | Barlow Condensed | w600 | 11 | 1.4 | textMuted |
| `_SectionHeader` ("EJERCICIOS" / "TÉCNICA" / "HISTORIAL") | Barlow Condensed | w700 | 14 | 1.4 | textPrimary |
| `StatTile` value | Barlow Condensed | w700 | 22 | 0 | textPrimary (o "—" placeholder) |
| `StatTile` label | Barlow Condensed | w600 | 10 | 1.2 | textMuted |
| `ExerciseSlotRow` nombre | Barlow Condensed | w700 | 16 | 0.5 | textPrimary |
| `ExerciseSlotRow` sets·reps + muscle | Barlow / Barlow Condensed | w400/w600 | 13/11 | 0/1.2 | textMuted |
| `ExerciseSlotRow` rest text | Barlow | w400 | 12 | 0 | textMuted |
| `_UltimoBadge` text | Barlow Condensed | w600 | 10 | 1.2 | textMuted |
| `TechniqueInstructionItem` number | Barlow Condensed | w700 | 14 | 0 | `palette.bg` (sobre gradient) |
| `TechniqueInstructionItem` text | Barlow | w400 | 14 | 0 (line-height 1.4) | textPrimary |
| Disabled CTA labels | Barlow Condensed | w700 | 16 | 1.0 | UPPERCASE literal |
| `_EmptyState` / `_NotFoundState` body | Barlow | w400 | 14 | 0 | textMuted |

**Regla**: no usar `Theme.of(context).textTheme.X` para nada de lo anterior — sizes están fijados explícitamente porque la jerarquía visual depende de los gaps entre headlines. La excepción del repo está documentada en CLAUDE.md.

### 6.3 Spacing — allowed set `{8, 12, 14, 18, 20}`

Todo gap, padding, margin en este PR mapea a uno de esos valores. **No introducir 16 ni 24**. Tabla:

| Posición | Valor |
|---|---|
| Padding horizontal de las secciones (post-hero) | 20 |
| Hero strip altura | 180 (control size — fuera del allowed set, ver excepción §6.4) |
| Gap hero → badge | 18 |
| Gap badge → title | 8 |
| Gap title → stat row | 14 |
| Gap stat row → day selector / section header | 18–20 |
| Gap section header → primera fila | 12 |
| Gap entre `ExerciseSlotRow` | 12 |
| Padding interno de `ExerciseSlotRow` | 14 (EdgeInsets.all) |
| Thumb 48×48 → texto | 14 |
| Gap interno de `ExerciseSlotRow` (nombre → reps row) | 8 |
| Padding interno de `_DisabledCTABar` | 18 (vertical) |
| Gap entre los 2 CTAs | 12 |
| Gap section → siguiente section | 20 |

### 6.4 Excepciones de allowed-set

Sizes de control (no gaps): hero strip altura 180, thumb 48×48, number badge 28×28, day chip altura 28, CTA pill height 56, avatar gradient circle (no aplica acá). Estos NO violan la regla allowed-set — la regla rige spacing/gaps, no dimensiones de widgets de control. Precedente: `HomeCTAButton.height = 56`, `_AvatarFallback` 56×56 (ver `home-shell/design.md` §6).

---

## 7. Asset placeholders

### 7.1 `Routine.imageUrl == null` (todos los seeds)

Hero strip placeholder = `Container(height: 180, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [palette.accent.withValues(alpha: 0.85), palette.bg])))`. Sin imagen, sin icono — el gradient solo carga la jerarquía visual.

Cuando `imageUrl != null` (Fase futura), reemplazar el `Container` por `CachedNetworkImage(imageUrl: routine.imageUrl!, fit: BoxFit.cover, placeholder: _HeroGradient(), errorWidget: _HeroGradient())`. **Hoy no se agrega** porque todos los seeds son `null` y agregar `cached_network_image` ya está hecho desde Etapa 1. Tener el `_HeroGradient` privado deja el cambio futuro como one-liner.

### 7.2 `Exercise` no tiene `photoUrl` en el modelo

Hero placeholder = `Container(height: 180, decoration: BoxDecoration(color: palette.espresso), alignment: Alignment.center, child: Icon(TreinoIcon.tabWorkout, size: 56, color: palette.textMuted.withValues(alpha: 0.5)))`. Color sólido `palette.espresso` (token "elevated surfaces") con `TreinoIcon.tabWorkout` (mancuerna Phosphor) centrado al 50% de opacity para que se lea como "asset pendiente".

Cuando Fase 4 agregue `photoUrl: String?` al `Exercise`, mismo patrón que routine: reemplazar `Container` por `CachedNetworkImage`.

### 7.3 `_UltimoBadge` (siempre dash hoy)

```
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: palette.bgCard,
    border: Border.all(color: palette.border, width: 1),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    value ?? 'ÚLTIMO  —',
    style: GoogleFonts.barlowCondensed(...),
  ),
)
```

Cuando Fase 4 traiga session history, `lastWeightDisplay` se pasa por `ExerciseSlotRow` desde un nuevo provider. El widget no cambia; sólo el caller.

---

## 8. New `TreinoIcon` addition

Agregar UN símbolo en `lib/core/widgets/treino_icon.dart`, dentro de la sección "Stats / tiempo" (línea ~39, después de `clock`):

```dart
  // Stats / tiempo
  static const IconData chartBar = PhosphorIconsRegular.chartBar;
  static const IconData calendar = PhosphorIconsRegular.calendarCheck;
  static const IconData clock = PhosphorIconsRegular.clock;
  static const IconData timer = PhosphorIconsRegular.timer;
```

**Uso único**: `ExerciseSlotRow` para el indicador de descanso (`Icon(TreinoIcon.timer, size: 14, …)` junto a `${slot.restSeconds}s descanso`). Si hubiera otro lugar que necesite indicador de tiempo cronómetro vs hora del día, reusar (`clock` = hora, `timer` = stopwatch/duración).

**Assumption (verificar en apply)**: `PhosphorIconsRegular.timer` existe en `phosphor_flutter ^2.1.0`. El icono `ph-timer` es estándar de Phosphor desde 1.x y la versión locked es 2.1.0 — alta confianza. Si por algún motivo no compila, fallback: `PhosphorIconsRegular.stopwatch` o `PhosphorIconsRegular.hourglass`. Documentar deviation en `apply-progress`. **No** caer de vuelta a `clock` — sería ambiguo respecto a "hora del día".

---

## 9. Test strategy

Mirror estructural exacto bajo `test/features/workout/presentation/`. Sigue patrones de `home-shell` (`_wrap`, `_wrapWithOverrides`, sin goldens — el proyecto no los configura).

```
test/features/workout/presentation/
├── routine_detail_screen_test.dart
├── exercise_detail_screen_test.dart
└── widgets/
    ├── exercise_slot_row_test.dart
    └── stat_tile_test.dart
```

### 9.1 Helpers (per-file, no compartidos al inicio — extract en futuro PR si aparece duplicación)

```dart
Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

Widget _wrapWithOverrides(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );
```

### 9.2 Override pattern para `FutureProvider.family`

`routineByIdProvider` es `FutureProvider.family<Routine?, String>`. Para overridear UNA family instance específica:

```dart
routineByIdProvider('test-routine').overrideWith(
  (ref) async => _makeRoutine(id: 'test-routine'),
)
```

**Para AsyncLoading**:

```dart
routineByIdProvider('test-routine').overrideWith(
  (ref) => Completer<Routine?>().future, // never completes
)
```

**Para AsyncError**:

```dart
routineByIdProvider('test-routine').overrideWith(
  (ref) async => throw Exception('boom'),
)
```

**Para data(null)** (rutina no existe):

```dart
routineByIdProvider('test-routine').overrideWith(
  (ref) async => null,
)
```

Mismo patrón para `exerciseByIdProvider`. **No** overridear `routinesProvider` ni `routineRepositoryProvider` — sería más complejo y haría tests acoplados a internals del provider derivation chain.

### 9.3 Fixture helpers

```dart
Routine _makeRoutine({
  String id = 'r1',
  String name = 'PPL Beginner',
  String split = 'PPL',
  List<RoutineDay>? days,
  String? imageUrl,
}) => Routine(
      id: id,
      name: name,
      split: split,
      level: ExperienceLevel.beginner,
      days: days ?? [_makeDay()],
      estimatedMinutesPerDay: 60,
      imageUrl: imageUrl,
    );

RoutineDay _makeDay({int dayNumber = 1, List<RoutineSlot>? slots}) =>
    RoutineDay(
      dayNumber: dayNumber,
      name: 'Push',
      slots: slots ?? [_makeSlot()],
      estimatedMinutes: 55,
    );

RoutineSlot _makeSlot({
  String exerciseId = 'bench-press',
  String exerciseName = 'Bench Press',
}) => RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      muscleGroup: 'chest',
      targetSets: 4,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    );

Exercise _makeExercise({
  String id = 'bench-press',
  List<String>? techniqueInstructions = const ['Cue 1', 'Cue 2', 'Cue 3'],
}) => Exercise(
      id: id,
      name: 'Bench Press',
      muscleGroup: 'chest',
      category: 'compound',
      techniqueInstructions: techniqueInstructions,
    );
```

Mantener factory helpers locales al archivo de test hasta que aparezca un 2do consumer. Si en spec ya hay un helper en `test/features/workout/domain/...`, **NO** reusar — esos viven en otra capa con seed-Firestore-shape distinto.

### 9.4 Per-file test budget

| File | Scenarios | Tests |
|---|---|---|
| `routine_detail_screen_test.dart` | 071, 072, 073, 074 | loading (skeleton renderiza, no crash); render con day+slots (encuentra nombre rutina, badge día 1, primer slot por finder); slots vacíos (empty state texto); data(null) (NotFound texto + back implícito por router) |
| `exercise_detail_screen_test.dart` | 075, 076, 077, 078 | loading; render técnica (encuentra los 3 cues numerados); técnica nula (empty state); data(null) (NotFound) |
| `exercise_slot_row_test.dart` | 079, 080 | render de nombre + reps + muscle group (3 asserts); tap dispara onTap callback (verifica con `bool tapped` flag) |
| `stat_tile_test.dart` | 081, 082 | render value normal (encuentra "12"); render dash placeholder cuando value == null (encuentra "—") |

Total: ~12 widget tests. Todos `testWidgets`, sin `golden`. Cobertura sobre TODO branch de `AsyncValue.when` y todos los empty states.

### 9.5 Router test (en file de pantalla)

Dentro de `routine_detail_screen_test.dart` agregar un test pequeño que arme un `GoRouter` con sólo la ruta target y verifique `context.push('/workout/routine/test-id')` aterriza:

```dart
testWidgets('deep link /workout/routine/:id aterriza en la pantalla', (tester) async {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, __) => const Text('START')),
      GoRoute(
        path: '/workout/routine/:routineId',
        builder: (ctx, state) =>
            RoutineDetailScreen(routineId: state.pathParameters['routineId']!),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      routineByIdProvider('test-id').overrideWith((ref) async => _makeRoutine(id: 'test-id')),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  router.push('/workout/routine/test-id');
  await tester.pumpAndSettle();
  expect(find.text('PPL · DÍA 1'), findsOneWidget);
});
```

**No** se testea el `_ShellScaffold` desde acá — eso lo cubrirían tests del router más generales (fuera de scope de esta PR).

### 9.6 No repository tests (intocados)

Repos no cambian. Spec no agrega scenarios de data/domain. Si `flutter analyze` o `flutter test` indica regresión en tests existentes, es bug propio — no es responsabilidad de este PR.

---

## 10. Performance / a11y

### 10.1 Performance

- **Sin Firestore reads adicionales**: `routinesProvider` y `exercisesProvider` ya están cacheados como `FutureProvider`. `routineByIdProvider(id)` y `exerciseByIdProvider(id)` son lookups O(n) sobre listas de ~6 y ~25 elementos respectivamente — efectivamente O(1) por el tamaño constante del catálogo. Navegar Detail→ExerciseDetail→back→otro slot dentro de la misma sesión es ZERO I/O.
- **Re-renders**: `setState(() => selectedDayIndex = i)` rebuildea sólo el subtree del `ConsumerStatefulWidget`. `ref.watch(routineByIdProvider(widget.routineId))` retorna el mismo `AsyncValue.data` cacheado tras el primer fetch — no re-evalúa el provider.
- **Lista de slots**: `CustomScrollView` + `SliverList` con `expand` produce hasta ~8 filas por día en el seed (real upper bound). No hace falta `SliverList.builder` lazy — el costo de construir 8 widgets de una vez es nulo y simplifica el código.
- **`CachedNetworkImage` no se usa todavía**: sin imágenes reales no hay decode ni network. La dep ya está en pubspec (Etapa 1) — disponible para futuras imágenes.

### 10.2 Accessibility

- **Semantics en `ExerciseSlotRow`**: wrap `InkWell` en `Semantics(button: true, label: 'Ejercicio ${slot.exerciseName}, ${slot.targetSets} series de ${slot.targetRepsMin} a ${slot.targetRepsMax} repeticiones, descanso ${slot.restSeconds} segundos')`. Permite screen readers anunciar el contenido completo sin que TalkBack/VoiceOver lea cada `Text` por separado.
- **Tap targets ≥ 48 px**: `ExerciseSlotRow` total es 48 (thumb) + 14×2 padding = 76 px de altura. CTA EDITAR/EMPEZAR son 56 px (heredan `HomeCTAButton`). Day selector chips son 28 px de altura — debajo de 48 px, **agregar `padding` invisible** (`padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)` dentro de un `InkWell` con `borderRadius: r-full`) para ampliar el hit area sin alterar el rendering. Patrón ya usado en `treino_bottom_bar.dart` (verificar).
- **Contrast**: `palette.textMuted` (`0x8CFFFFFF` = ~55% white sobre `palette.bg` `0xFF0A0A0A`) tiene contraste WCAG AA para texto ≥ 14px. `_UltimoBadge` text size 10 está al límite — uso intencional para "metadata secundaria", no falla AA porque es complementario, no contenido principal.
- **Reduced motion**: no introducimos animations custom. Cualquier animation (ej. el future shimmer) debe respetar `MediaQuery.disableAnimations`.

---

## 11. Rollout

### 11.1 Sin entry point en producción todavía

Este PR agrega `/workout/routine/:routineId` y `/workout/exercise/:exerciseId` al router. **Ningún screen de producción los enlaza todavía** — Etapa 3 (`feat/routines-list`, Dev B) introduce la lista de plantillas con `onTap → context.push('/workout/routine/$id')`. Hasta que esa PR mergee, las rutas son **deep-link only** (alcanzables desde el debugger o desde un test, no desde un user flow normal).

**Implicación**: zero user-facing risk de mergear esto antes de Etapa 3. La regression surface es nula porque nadie navega ahí.

### 11.2 QA manual del dev/reviewer

Para verificar localmente:

1. `flutter run` (iOS/Android/Web — cualquiera).
2. Login con cuenta athlete normal.
3. Desde DevTools o un hot-reload temporal, ejecutar `context.push('/workout/routine/ppl-beginner')` desde algún sitio (CONSOLA DEBUG, NO un botón en el código). El seed de Etapa 2 garantiza `ppl-beginner`.
4. Verificar:
   - Bottom bar visible y tab "ENTRENAR" highlighted.
   - Hero gradient renderiza (no imagen).
   - Día 1 seleccionado por default.
   - Lista de slots tiene los ~6 ejercicios del seed.
   - Tappear un slot → `/workout/exercise/bench-press` (o el id que toque) navega a `ExerciseDetailScreen`.
   - Back vuelve al detail con día 1 (state local reset).
   - Navegar a otro tab y volver a `/workout` muestra el placeholder `WorkoutScreen`, no el detail (consistente con el shell pattern).
5. **No commitear ningún botón temporal de entry**: la propose decision 4.6 lo deja explícito.

### 11.3 Rollout note para `go_router` deep-links

`http://127.0.0.1:<port>/workout/routine/<id>` **no funciona** en mobile (eso es para web/go_router con URL strategy). El testing manual usa la API de Dart (`context.push(...)`) o un test programático. En web build sí funcionaría — fuera de scope hoy.

### 11.4 Sin migraciones, sin feature flags

- No hay datos persistidos nuevos.
- No hay flags de feature (el PR es 100% additive sobre routes).
- No hay rules de Firestore tocadas.
- `pubspec.lock` intacto.

Rollback: `git revert` de la merge commit. Cero efectos colaterales en collections ni en otras pantallas (lo único que se modifica fuera del feature `workout/presentation/` es `router.dart` y `treino_icon.dart`, ambos additive).

---

## 12. ADR-style decisions log

| ID | Decisión | Alternativas rechazadas | Por qué esta |
|---|---|---|---|
| ADR-RD-1 | Pantallas como composers delgados sobre providers existentes (Approach A) | B (monolíticas), C (promover widgets a `core/widgets/` desde día 1) | Mirrors `home-shell`. Cada leaf testeable aislado. Fase 4 wirea slot-row sin tocar la pantalla. Per propose decision 4.1. |
| ADR-RD-2 | Sub-rutas `routine/:routineId` y `exercise/:exerciseId` anidadas bajo `/workout` dentro del `ShellRoute` | Rutas top-level fuera del shell | Bottom bar visible — coherente con browsing de catálogo. Fase 4 session player pushea full-screen como decisión de UX cuando llegue. Per propose decision 4.2. |
| ADR-RD-3 | `selectedDayIndex` como `int` local del `ConsumerStatefulWidget`, NO Riverpod | `StateProvider.family<int, String>`, `Provider.autoDispose` | Pure presentation state, scope = una pantalla, no sobrevive a nav. Provider sería ceremony sin beneficio. Per propose decision 4.3. |
| ADR-RD-4 | CTAs EDITAR/EMPEZAR como stubs con `onPressed: null` y opacity al 40% | Ocultarlas, mostrarlas activas con `_showSnackbar('próximamente')` | Preserva paridad visual con `expandir-plantilla.png`. Wiring de Fase 4 = one-line change. Esconderlas rompería la jerarquía visual del bottom layout. Per propose decision 4.4. |
| ADR-RD-5 | Cero Firestore reads nuevos — reusar `routineByIdProvider.family` / `exerciseByIdProvider.family` | Crear `routineDetailProvider` derivado | YAGNI. Los providers ya cachean. Cualquier indirección agrega test surface sin valor. Per propose decision 4.5. |
| ADR-RD-6 | `CustomScrollView` + `SliverToBoxAdapter` para hero edge-to-edge + `SliverPadding > SliverList` para contenido con padding lateral | `ListView` con padding uniforme + `Padding.zero` en hero hack; `Column + SingleChildScrollView` | `CustomScrollView` es el patrón canon de Flutter para mezclar edge-to-edge con padded content en un solo scroll. `ListView` no permite hero edge-to-edge sin envolver cada child manualmente. `SingleChildScrollView` pierde la performance de `Sliver*` y rompe a11y de focus traversal. |
| ADR-RD-7 | Helpers de fixture (`_makeRoutine`, `_makeSlot`, etc.) locales por test file, NO compartidos en `test/_fixtures/` | Extract inmediato a `test/_fixtures/workout_fixtures.dart` | YAGNI hasta que aparezca el 3er consumer. Cada file declara lo que necesita. Si Fase 4 o tests cross-feature lo justifican, refactorizamos. |
| ADR-RD-8 | `_DaySelector` se renderiza condicionalmente sólo si `routine.days.length > 1` | Renderizar siempre, atenuado cuando hay un solo día | Routines con un solo día (ej. Full Body 1×week) son válidos por modelo. Mostrar un selector inutil rompe la economía visual. La paridad con `expandir-plantilla.png` se mantiene porque el mockup muestra un PPL con varios días. |
| ADR-RD-9 | `_NotFoundState` reemplaza el árbol completo en branch `data(null)`, NO se muestra "encima" del shell | Snackbar + back automático; redirect a `/workout` | Da feedback explícito de "este id no existe", deja al usuario decidir cuándo volver, y se testea trivialmente. Auto-redirect dispara loop si el id viene de un push externo. |
| ADR-RD-10 | `ExerciseSlotRow` recibe `RoutineSlot` por valor (no `exerciseId` para que mire `exerciseByIdProvider`) | Pasar `slot.exerciseId` y dejar que la fila resuelva nombre/muscle group desde `exerciseByIdProvider` | El modelo denormaliza `exerciseName` + `muscleGroup` en `RoutineSlot` precisamente para evitar N joins en lista (ADR-2 de Etapa 2). Hacer joins en la presentation contradice el seed contract. La fila debe leer del slot, no del exercise. |

---

## 13. Open questions

Ninguna bloqueante. Las assumptions a confirmar en apply (no son blockers):

1. **`PhosphorIconsRegular.timer` existe en `phosphor_flutter ^2.1.0`.** Confianza alta (icono estándar Phosphor `ph-timer` desde 1.x). Verificar en el primer `flutter analyze` post-merge del símbolo. Fallback: `stopwatch` o `hourglass`. **No** caer a `clock`.
2. **`AppTheme.dark()` registra `AppPalette` como `ThemeExtension`.** Ya confirmado en `home-shell/design.md` §11 — los tests usan el mismo wrap helper.
3. **`go_router` ^x.y.z** (versión del repo) maneja sub-rutas relativas (`routine/:routineId` sin slash inicial). Confianza alta — es la API estándar desde la versión 6. Si la versión locked no soporta el patrón relativo, fallback es declarar paths absolutos (`/workout/routine/:routineId`) fuera del padre — funciona pero rompe la convención de anidamiento.

Confirmar (1) y (3) durante el primer commit de apply. Documentar deviation en `apply-progress` si alguna asume falla.

---

**Next recommended**: `sdd-tasks` (mecánico — generar la lista de scenarios SCENARIO-071..082 y los TDD steps a partir de este design + spec).
