# Gate de regresión visual — Coach Hub

Qué es, qué NO es, y cómo aceptar un cambio visual cuando es deliberado.

---

## 1. El problema que resuelve

`lib/features/coach_hub/` es de lo que más se mueve del repo: **306 commits en
90 días**, 135 en 30, 20 en 7. A ese ritmo una regresión visual es cuestión de
tiempo, y hasta este gate no había nada que la detectara: los cambios de UI se
revisaban mirando el diff y, con suerte, abriendo la app.

Un diff no muestra que una card creció 4 px y empujó la columna de al lado.

## 2. Qué NO es

**No es el corpus de evidencia que se borró en #723 / PR #759.** Aquel eran
capturas `before`/`after` por fase del rediseño, hechas para probar que cada
fase hizo lo que dijo. Cumplió su función y se murió: los `before` son, por
definición, de *antes* del rediseño, así que no podían coincidir nunca con el
código actual.

Este gate no lo resucita. No recicla un solo PNG de aquel corpus — están en el
historial de git si alguien los quiere, pero no son la base de esto. Las tres
decisiones que aquel no tomaba, y este sí, son las tres secciones que siguen.

## 3. Decisión 1 — lista acotada, con el porqué escrito

No "todas las secciones". Cinco, y cada una está por un motivo:

| Pantalla | Por qué entra |
|---|---|
| **Shell** | Es la única que se hereda. Sidebar, top bar y marco de contenido salen del mismo `CoachHubScaffold` para las once secciones: una regresión acá no rompe una pantalla, las rompe todas. Aporta las dos ramas de viewport (ver abajo). |
| **Dashboard** | La composición más densa: banner, welcome card con anillo, tira de KPIs, pendientes y agenda del día. Cinco bloques que se acomodan entre sí — un cambio de altura en uno reordena los otros cuatro. |
| **Ficha de alumno** | La superficie más data-bound del Hub. Tabs, métricas y estados por alumno. |
| **Chat** | El único layout de dos paneles, con lista, detalle y composer. |
| **Pagos** | Tabla + tira de KPIs + chips de estado. La superficie de plata, y donde una columna angosta se rompe primero. |

**Cuantas más pantallas, más goldens que regenerar en cada cambio visual, y más
rápido muere el gate.** Agregar una es una decisión, no un trámite: ver §8.

### La matriz — 12 goldens, no 40

```
4 secciones × 2 temas @ 1440×900 (desktop)   =  8
shell       × 2 temas @ 1024×900 (compact)   =  2
shell       × 2 temas @  420×900 (mobile)    =  2
                                               ──
                                               12
```

**El shell no tiene golden de desktop, y no es un olvido.** A `>= 1280` el
shell muestra la sección activa adentro, así que su captura sale *byte a byte
idéntica* a la de esa sección — verificado con `sha256`. El cromo de desktop ya
viaja dentro del golden de cada sección; un archivo aparte serían dos PNGs para
una sola imagen, los dos a regenerar en cada cambio del sidebar y uno de los
dos siempre desactualizado. Lo que sí es exclusivo del shell —el contrato de la
rama expandida— se afirma con aserciones, sin captura.

**Los dos temas siempre.** El mint del acento es idéntico en dark y en light,
pero `bg` no: `palette.bg` sobre `accent` da 12.10:1 en dark y **1.57:1 en
light**. Un gate de un solo tema deja sin cobertura visual justo el tema donde
el contraste se cae.

**Compact y mobile sólo en el shell.** `viewportFor()` vive en el shell:
`< 768` cambia el scaffold entero por `MobileBanner`, `768–1279` fuerza el
sidebar a colapsado, `>= 1280` respeta la preferencia guardada. Son tres ramas
de UNA decisión, y la decisión es del shell. Capturarlas por sección sumaría
dieciséis PNGs más (4 secciones × 2 temas × 2 viewports) de la MISMA rama —
dieciséis que regenerar cada vez que cambia un padding del sidebar.

## 4. Decisión 2 — un solo entorno, fijado

Esto es lo que hunde a la mayoría de los gates de goldens en Flutter: **CI corre
en ubuntu y los devs en macOS**. Distinta rasterización de fuentes, distinto
antialiasing, distinto hinting. El síntoma es siempre *"falla en CI, pasa
local"*, y a la tercera vez alguien desactiva el job.

La respuesta acá es no pretender que los píxeles sean portables:

| Eje | Fijado en | Qué pasa si no coincide |
|---|---|---|
| SO | `ubuntu-latest` (job `visual-gate`) | La suite **se saltea con motivo**. Nunca falla fuera del runner. |
| Zona horaria | `TZ=UTC` (env del job) | Test rojo **con nombre**: *"el entorno del gate está pinneado"*. |
| Flutter | `3.41.9` (mismo pin que `analyze` y `test`) | Diffs de píxeles sin causa aparente. Por eso los dos jobs y el workflow de regeneración leen el mismo número. |
| Reloj | `AppClock.freeze()` en 17/03/2026 10:30 | Ver §5. |

El interruptor es la variable de entorno `TREINO_VISUAL_GATE=1`, que sólo pone
el job. Un dev que corre `flutter test` en su Mac **no ve rojo**: ve la suite
salteada con el motivo escrito.

> Es una variable de entorno y no un `--dart-define` a propósito: el
> `--dart-define` invalida el kernel cache y obliga a recompilar toda la suite.

## 5. Decisión 3 — seed determinístico

Un golden que cambia porque cambió la fecha no es un gate, es ruido. Y el ruido
en un gate termina siempre igual.

Las cinco pantallas leen la hora en el camino de render — 12 sitios. El más
filoso es la columna derecha del dashboard, que filtra turnos con
`startsAt.isAfter(now)`: sin reloj congelado, ese golden pasa a la mañana y
falla a la tarde.

Por eso este cambio trajo **`lib/core/utils/app_clock.dart`**: el único lugar
del repo que llama a `DateTime.now()` de verdad. En producción es un
passthrough; congelado por un test, devuelve siempre el mismo instante.
`argentinaNow()` y `nowWall()` leen de ahí, así que congelar `AppClock` congela
a los dos y a todos sus call-sites.

El resto del seed (`test/visual_gate/gate_seed.dart`) deriva **todas** sus
fechas de ese instante por offsets fijos, y está **poblado, no vacío**: un gate
contra estados vacíos cubre el layout de menor riesgo — una lista sin filas no
desborda. Las regresiones visuales viven en la pantalla llena.

## 6. Qué hace que el baseline sea válido y no heredado

Un PNG solo dice *"esto fue lo que salió"*. No distingue un baseline correcto de
uno que alguien aceptó sin mirar.

Por eso cada golden va precedido de **aserciones sobre su propio fixture**: que
el seed llegó al árbol, que la paleta que resolvió es la que el test pidió, y
que no quedó ningún `RenderFlex overflowed` (la barra amarilla y negra ENTRA a
la captura). Si mañana el seed se rompe y una pantalla rinde vacía, regenerar
goldens congelaría la pantalla rota como verdad nueva — y el gate quedaría verde
para siempre sobre el defecto. Estas aserciones fallan antes de llegar a los
píxeles.

Es la misma lección que [`docs/security.md` §1.4](./security.md) midió con la
suite de reglas: *una suite que nadie corre no distingue "cambió porque
quisimos" de "se rompió" — las dos se ven igual*.

### El caso que esas aserciones NO cubrían: las tipografías

`find.text('Mateo García')` matchea el string del árbol de widgets. Si la
familia no está registrada, el texto sigue estando y sólo cambian los glifos:
**una regresión tipográfica pasa entera por el candado semántico**.

No es hipotético. Construyendo este gate, restaurar un backup viejo desarmó la
carga de fuentes y las doce capturas salieron en cajitas — con todos los tests
verdes. Lo único que lo delató fue mirar los PNG.

Por eso `gate_fonts.dart` **mide** en vez de confiar, en un test con nombre. Y
mide las dos formas en que el Coach Hub pide una fuente, porque se rompen por
separado:

| Cómo se pide | Quién la registra |
|---|---|
| `TextStyle(fontFamily: AppFonts.barlow)` — 108 call-sites | el `FontLoader` de `gate_fonts.dart`, desde `assets/fonts/` |
| `GoogleFonts.barlowCondensed(fontWeight: w700)` | `google_fonts`, **en diferido** — hay que precalentarla |

La segunda fila tiene su propia trampa: `google_fonts` registra cada variante
recién cuando alguien la pide, de forma asincrónica, así que **el primer test
de cada archivo pintaba con el fallback**. Se ve peor de lo que suena: da igual
todas las veces, así que parece determinístico. Lo cubre `_warmGoogleFonts()`,
que pide explícitamente los tres pesos de `AppFonts` sobre las dos familias y
los espera con `pendingFonts()`.

Si agregás una pantalla y su texto sale en cajitas, empezá por ahí.

## 7. Regenerar un golden cuando el cambio ES deliberado

Esta sección es la mitad que le faltaba al corpus viejo. Sin ella, el primer
rediseño legítimo choca contra un rojo que nadie sabe desbloquear.

**Los goldens se regeneran en el runner, no en tu máquina.** No es burocracia:
regenerar en macOS produce PNGs que nunca van a matchear ubuntu. Y no es sólo
el SO — el Flutter local del equipo ya viene divergiendo del pin de CI.

```bash
git commit --allow-empty -m "chore(gate): regenerar goldens [regen-goldens]"
```

Empujá eso a tu rama. El marcador `[regen-goldens]` dispara
`.github/workflows/regen-goldens.yml`, que corre en el mismo ubuntu con el mismo
Flutter y **commitea los PNGs nuevos a tu rama**. Después:

```bash
git pull
```

En el PR, contá **qué cambió y por qué** — el commit de los PNG lo firma un
bot, así que el único lugar donde queda la intención es tu descripción. El log
del job lista los archivos que cambiaron.

> **El commit del bot no dispara CI por sí solo.** GitHub deja los runs de un
> push hecho con `GITHUB_TOKEN` en `action_required`, esperando aprobación
> manual: es su guardia contra bucles de automatización. Después del `git pull`,
> tu próximo push —aunque sea el que actualiza la descripción— los corre
> normalmente. Si no tenés nada que pushear, aprobalos desde la pestaña Actions.

### Traé `main` a tu rama ANTES de regenerar

Los dos workflows no miran el mismo árbol, y la diferencia muerde:

| | Evento | Qué código corre |
|---|---|---|
| `regen-goldens.yml` | `push` | **tu rama, sola** |
| `visual-gate` (ci.yml) | `pull_request` | **el merge** de tu rama con `main` |

O sea que si `main` avanzó desde que abriste la rama, regenerás contra un árbol
y el gate valida contra otro. Los goldens salen "correctos" y el gate los
rechaza, sin que el diff del PR muestre nada raro.

```bash
git merge origin/main        # primero esto
git commit --allow-empty -m "chore(gate): regenerar goldens [regen-goldens]"
```

Pasó construyendo este gate, y con el peor disfraz posible: `main` sumó
`CoachHubTourGate` —el tour de bienvenida de #627, que se empuja a pantalla
completa sobre el shell— mientras esta rama estaba abierta. La regeneración no
lo tenía y el gate sí, así que las capturas eran de las pantallas y la
validación era del tour. Se arregló sembrando `onboardingSeen` en el perfil del
seed, con el helper `test/helpers/onboarding_test_helpers.dart` que el repo ya
tenía para esto.

Vale la pena quedarse con la otra lectura: **el gate detectó que un modal nuevo
tapaba el Coach Hub entero**. Es exactamente la clase de regresión visual que
un diff no muestra.

### Cuando el gate rompe y NO sabés si el cambio era deliberado

El job `Visual Gate (Coach Hub)` sube un artefacto **`visual-gate-failures`**
con las tres imágenes por golden roto: la esperada, la real y la máscara del
diff. Bajalas antes de decidir. Si el diff es el que buscabas, regenerá; si no,
encontraste una regresión — que es exactamente para lo que está esto.

## 8. Agregar una pantalla al gate

1. Escribí **por qué** entra, en la tabla de §3. Si el motivo es "para tener
   más cobertura", no entra: cada golden nuevo es peaje en cada cambio visual
   futuro.
2. Sembrá lo que le falte en `gate_seed.dart`, siempre derivado de `kGateNow`.
3. Copiá `coach_hub_dashboard_golden_test.dart`: las aserciones semánticas van
   **antes** del `matchesGoldenFile`, no después.
4. Desktop solamente, salvo que esa pantalla tenga un layout propio abajo de
   1280 — y entonces escribí también ese porqué.
5. Regenerá con el flujo de §7.

## 9. Prerequisito honesto: branch protection

**Hoy `main` no tiene branch protection** (`/branches/main/protection` → 404,
`/rulesets` → `[]`). El job es bloqueante en el sentido de que falla y pinta el
PR en rojo, pero **en rojo todavía se puede mergear**. Hasta que la protección
esté activa, mirar el CI antes de mergear no es opcional.

Cuando se active, `Visual Gate (Coach Hub)` tiene que entrar a la lista de
checks obligatorios. Un gate que avisa pero no frena es exactamente lo que #723
borró, con otro nombre.

---

## Dónde vive cada cosa

| Archivo | Qué es |
|---|---|
| `test/visual_gate/gate_environment.dart` | El entorno fijado: interruptor, instante congelado, motivo del skip. |
| `test/visual_gate/gate_fonts.dart` | Registra las tipografías y las **mide** (§6). Sin esto, capturas de cajitas. |
| `test/visual_gate/gate_seed.dart` | Los datos. Ninguno depende del reloj, la red ni una cuenta real. |
| `test/visual_gate/gate_harness.dart` | Monta el Coach Hub **real** (tema real, router real, scaffold real). |
| `test/visual_gate/*_golden_test.dart` | Una pantalla por archivo. |
| `test/visual_gate/goldens/` | Los PNGs. Bajo `test/`, no bajo `docs/`: son fixtures, no documentación — y el corpus viejo vivía en `docs/` justo por eso nadie lo trató como test. |
| `.github/workflows/ci.yml` → `visual-gate` | El job bloqueante. |
| `.github/workflows/regen-goldens.yml` | La regeneración (§7). |
| `lib/core/utils/app_clock.dart` | El seam de reloj (§5). |
