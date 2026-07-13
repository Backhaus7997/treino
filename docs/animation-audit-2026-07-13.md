# Auditoria de animaciones — 2026-07-13

## Veredicto

La app ya tiene una base tecnica buena para movimiento: `AppMotion`,
`TreinoStateSwitcher`, `TreinoFadeSlideIn`, `TreinoTappable` y `TreinoShimmer`.
El problema no es falta de herramientas, es cobertura desigual.

Hoy TREINO se siente dinamica en zonas puntuales, especialmente Insights,
ProfileSetup, bottom bar, algunos controles de Workout y skeletons concretos.
Pero muchas pantallas principales siguen cambiando de estado con cortes secos:
spinner -> contenido, lista vacia -> lista, error -> data, seleccion -> nuevo
body. Eso hace que la app parezca menos fluida que su sistema visual.

## Evidencia rapida

- `AppMotion` centraliza duraciones, curvas, distancias y reduce-motion:
  `lib/app/theme/app_motion.dart`.
- `TreinoStateSwitcher` aparece en 6 archivos, concentrado casi todo en
  `lib/features/insights`.
- `TreinoFadeSlideIn` aparece en 4 archivos, tambien concentrado en Insights.
- `TreinoTappable` aparece en 4 archivos. Varios CTAs e icon buttons todavia
  usan `GestureDetector`, `InkWell`, `TextButton` o widgets Material directos.
- `TreinoShimmer` aparece en 8 archivos.
- `CircularProgressIndicator` aparece en 86 archivos bajo `lib/`, muchas veces
  como loading directo sin transicion ni skeleton.

## Lo que esta bien

### 1. Motion tokens bien definidos

`AppMotion` define `micro`, `fast`, `base`, `slow`, curvas semanticas,
distancias `8/12/20` y `reduceMotion`. Esto esta bien alineado con
`docs/performance.md`: implicit-first, controllers solo donde corresponde.

No hay que tirar esto. Hay que aplicarlo con disciplina.

### 2. Insights es el patron a copiar

`InsightsScreen` hace lo correcto:

- `TreinoStateSwitcher` para loading/error/data.
- `TreinoFadeSlideIn` con stagger para secciones estaticas eager.
- Comentarios que explican por que NO usarlo en builders lazy.
- Respeto por `AppMotion.stagger`.

Esta pantalla deberia ser el standard de entrada de contenido.

### 3. Bottom bar tiene movimiento de identidad

`TreinoBottomBar` anima la pill activa, texto e icono. Bien: es movimiento de
orientacion, no decoracion. Ayuda al usuario a entender donde esta.

### 4. Buen criterio de performance

Hay decisiones correctas de NO animar:

- `_noAnim` para rutas root/tab donde se usa `go()`.
- Evitar blur en la bottom bar por costo de `BackdropFilter`.
- Skeleton transparente del Home sin shimmer porque no pintaria pixeles utiles.

Esto es importante: fluidez no es meter animacion en todo. Fluidez es que cada
cambio tenga feedback sin quemar frames ni bateria.

## Hallazgos principales

### P1 — Los estados async cambian en seco en muchas pantallas

Ejemplos claros:

- `FeedScreen` usa `async.when(...)` directo con spinner/data/error.
- `ChatListScreen` usa `chatsAsync.when(...)` directo.
- `AthleteCoachView`, `TrainerCoachView`, `RoutineDetailScreen`,
  `SessionHistoryScreen`, `MyExercisesScreen`, `PublicProfileScreen`,
  pantallas del Coach Hub y varias de Workout repiten el patron.

Impacto: la app cambia de estado como web vieja: aparece/desaparece contenido
sin continuidad visual. Se nota mucho cuando Firestore resuelve rapido pero no
instantaneo.

Recomendacion:

- Crear un wrapper reusable tipo `TreinoAsyncSwitcher<T>` o estandarizar el uso
  de `TreinoStateSwitcher` alrededor de cada `.when`.
- Priorizar pantallas con carga visible: Feed, Chat, Coach, RoutineDetail,
  Workout sections, Profile public screens y Coach Hub dashboard.

Tradeoff: `TreinoStateSwitcher` suma una capa, pero anima opacity solamente y
ya respeta reduce-motion. Es barato si se usa en el nivel correcto.

### P1 — No hay patron transversal para entrada de pantallas principales

Home, Feed, Workout, Coach y Profile montan sus secciones principales sin una
entrada consistente. Insights si lo hace.

Impacto: la primera impresion visual queda irregular. El usuario siente que
una parte de la app esta pulida y otra parte es estatica.

Recomendacion:

- Usar `TreinoFadeSlideIn` en `ListView(children: [...])` eager de pantallas
  root.
- NO usarlo en `ListView.builder`/`.separated` de listas largas.
- Crear helpers simples para secciones eager:
  `TreinoStaggeredColumn` o `TreinoStaggeredListChildren`.

Primeras candidatas:

- `_AthleteHome`: header, card principal, `EstaSemanaCard`.
- `_TuEntrenoPage`: `MiPlanSection`, `TrainerTemplatesSection`,
  `MisRutinasSection`, `PlantillasSection`, `HistorialSection`.
- `_AthleteProfile`: header/avatar/stats/secciones.
- pantallas de empty state grandes.

### P1 — Feedback de tap esta incompleto

`TreinoTappable` existe y esta bien disenado, pero no esta aplicado de forma
transversal. Muchos CTAs, iconos y cards clickeables siguen con `GestureDetector`
o `InkWell`.

Impacto: la app no tiene una respuesta fisica consistente. En mobile eso se
siente enseguida, especialmente en cards grandes.

Recomendacion:

- Migrar CTAs propios y cards tappables a `TreinoTappable`.
- No envolver `ElevatedButton`, `TextButton` o `InkWell` existentes: reemplazar
  el gesture owner, como ya documenta `TreinoTappable`.
- Priorizar: Feed header buttons, `EstaSemanaCard`, `ProfileSectionTile`,
  trainer cards, routine cards y chat rows.

Tradeoff: en listas largas, aplicar scale a cada row puede sentirse ruidoso.
Para rows densas conviene scale mas sutil o solo feedback de background/color.

### P2 — Loading visual depende demasiado de spinners

Hay 86 archivos con `CircularProgressIndicator`. No todos son malos, pero hay
demasiados casos donde el spinner reemplaza una superficie que podria tener
skeleton, shimmer o preserved layout.

Impacto: el producto se siente menos premium. En fitness/social, las cards y
listas deberian sostener estructura mientras cargan.

Recomendacion:

- Skeletons para listas/cards: Feed posts, Chat rows, Coach trainer cards,
  Routine detail, Coach Hub dashboard cards.
- Spinner solo para acciones puntuales o pantallas donde no existe layout
  predecible.
- `TreinoShimmer(enabled: false)` en error/null estable, como ya se hizo bien
  en chat/profile.

### P2 — Navegacion custom limitada a reportes de Insights

El router tiene `_report` con fade + slide para Insights, pero auth usa
`_noAnim` y varias rutas full-screen dependen del default de plataforma.
La decision de conservar gestos nativos es correcta, pero falta criterio
documentado por categoria de ruta.

Recomendacion:

- Mantener roots/tabs instantaneos.
- Mantener default platform para rutas comunes con back nativo.
- Aplicar transicion TREINO a flujos inmersivos con CTA explicito:
  ProfileSetup, reports, creation/edit flows, post-workout summary.

Tradeoff: custom route puede perder swipe-back iOS. Solo usar donde el gesto
nativo no sea central o donde haya back explicito.

### P2 — Coach Hub web tiene motion funcional, no experiencial

Hay `AnimatedContainer` para sidebar, algunos TabBarViews y dialogs, pero el
dashboard/listados web usan muchos loading spinners y cambios secos.

Impacto: para trainers, que repiten tareas todos los dias, la fluidez deberia
ayudar a escanear cambios: cards que aparecen, filtros que transicionan, rows
que actualizan estado.

Recomendacion:

- `TreinoStateSwitcher` en cards del dashboard.
- Skeletons por tabla/listado.
- Animaciones de seleccion/filtro en biblioteca, alumnos, pagos y chat.

### P3 — Falta una guia de motion en el design system

`docs/design-system.md` no incluye una seccion explicita de motion, aunque el
codigo ya tiene `AppMotion`.

Impacto: cada PR futuro puede volver a inventar duraciones, curvas o decidir
a ojo cuando animar.

Recomendacion:

- Agregar una seccion "Motion" a `docs/design-system.md`.
- Definir:
  - cuando usar `TreinoStateSwitcher`;
  - cuando usar `TreinoFadeSlideIn`;
  - cuando NO animar;
  - reglas para listas lazy;
  - politica de reduce-motion;
  - duraciones permitidas.

## Plan recomendado

### PR 1 — Estandar de async transitions

Objetivo: eliminar cortes secos en pantallas de alto trafico.

Cambios:

- Introducir `TreinoAsyncSwitcher` o aplicar `TreinoStateSwitcher` en:
  Feed, ChatList, AthleteCoachView, RoutineDetail, SessionHistory,
  MyExercises.
- Tests de reduce-motion y keys de estado.

### PR 2 — Entradas staggered en roots

Objetivo: que las 5 tabs principales se sientan vivas al montar.

Cambios:

- Home, Workout, Profile: `TreinoFadeSlideIn` en secciones eager.
- Coach segun branch athlete/trainer.
- No tocar listas lazy.

### PR 3 — Feedback fisico de interaccion

Objetivo: unificar presion/tap.

Cambios:

- Migrar cards y CTAs propios a `TreinoTappable`.
- Definir excepcion para rows densas.
- Agregar widget base si hace falta: `TreinoPressableCard`.

### PR 4 — Skeletons donde hoy hay spinner

Objetivo: carga percibida mas premium.

Cambios:

- Feed post skeleton.
- Coach/trainer card skeleton.
- Routine detail skeleton mas estructural.
- Coach Hub dashboard/list skeletons.

### PR 5 — Documentar Motion en design system

Objetivo: que esto no dependa de memoria tribal.

Cambios:

- Seccion Motion en `docs/design-system.md`.
- Checklist para PRs de UI.

## No hacer

- No animar cada row de `ListView.builder` con entrada one-shot.
- No meter loops decorativos permanentes fuera de loading real.
- No usar `AnimationController` salvo caso justificado.
- No meter blur/shadow pesado para "sensacion premium" sin profile en device.
- No romper reduce-motion.

## Score

- Fundacion tecnica: 4/4
- Cobertura transversal: 1/4
- Consistencia de feedback: 2/4
- Loading perceived performance: 2/4
- Navegacion y transiciones: 2/4
- Accesibilidad/performance: 3/4

Total: 14/24.

Conclusion: la app tiene buena arquitectura de motion, pero todavia no tiene
direccion de motion aplicada a todo el producto. Hay que convertir los patrones
existentes en convenciones obligatorias y migrar por superficies de mayor uso.
