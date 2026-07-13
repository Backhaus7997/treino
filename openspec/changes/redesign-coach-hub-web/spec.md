# Design System v2 — Especificación (Fase 0)

> **Cambio**: redesign-coach-hub-web · **Fase**: 0 — Design System v2
> **Scope**: tokens primitive→semantic→component + motion formalizado + docs reescritos
> **Fuera de scope**: ningún cambio visual ni de comportamiento en runtime

---

## Dominio: design-tokens (NUEVO)

Este dominio no existía en openspec. Se escribe spec completa.

---

## Propósito

Formalizar una arquitectura de tokens de 3 capas en Dart que soporte dark y light de
forma explícita, sin romper los 494 call sites existentes de `AppPalette.of(context)`,
y sin introducir ningún cambio visual observable en runtime.

---

## Capa 1 — Tokens Primitivos

### REQ-DS2-001: Archivo de primitivos de color

El sistema DEBE crear `lib/app/theme/tokens/primitives.dart` con la clase
`AppColorPrimitives` que contenga constantes `const Color` con nombres
escala-neutrales (ej. `mint500`, `ink950`, `magenta500`).
La clase NO DEBE requerir `BuildContext`.
Ningún widget DEBE referenciar `AppColorPrimitives` directamente —
es insumo exclusivo de la capa semántica.

#### Escenario: valores mínimos requeridos

- DADO que se compila el proyecto
- CUANDO se inspecciona `AppColorPrimitives`
- ENTONCES DEBE exponer al menos: `mint500` (#2CE5A2), `magenta500` (#C123E0),
  `ink950` (#0A0A0A), `ink900` (#0F1513), `ink800` (#1A1A1A), `bone` (#FFFFFF),
  `sage500` (#4F6358), `espresso500` (#3C3534), `dangerRed` (#E53935),
  `dangerRedDark` (#D32F2F), `warningAmber` (#FFB300), `warningAmberDark`
  (#FB8C00), `white` (#FFFFFF), `black` (#000000)
- Y todas las constantes DEBEN ser `static const Color`

#### Escenario: aislamiento — sin BuildContext

- DADO el entorno Dart sin Flutter widget tree
- CUANDO se accede a cualquier constante de `AppColorPrimitives`
- ENTONCES el acceso NO DEBE lanzar excepciones ni requerir `BuildContext`

---

### REQ-DS2-002: Tokens de spacing

El sistema DEBE exponer `AppSpacing` en `lib/app/theme/tokens/primitives.dart`
con las constantes `s8`, `s12`, `s14`, `s18`, `s20` como `static const double`.
NO DEBE existir ninguna constante para 4, 16 ni 24.

#### Escenario: valores de spacing

- DADO que se compila el proyecto
- CUANDO se accede a `AppSpacing`
- ENTONCES `s8 == 8.0`, `s12 == 12.0`, `s14 == 14.0`, `s18 == 18.0`, `s20 == 20.0`
- Y NO DEBE existir `s4`, `s16`, `s24` como símbolo exportado

---

### REQ-DS2-003: Tokens de radio

El sistema DEBE exponer `AppRadius` con constantes `sm` (12.0), `md` (16.0),
`lg` (20.0), `full` (9999.0) como `static const double`.

#### Escenario: valores de radius

- DADO que se compila `AppRadius`
- ENTONCES `sm == 12.0`, `md == 16.0`, `lg == 20.0`, `full == 9999.0`

---

### REQ-DS2-004: Tokens tipográficos

El sistema DEBE exponer `AppFonts` con las constantes `barlow` y
`barlowCondensed` como `static const String`.

#### Escenario: nombres de familia

- DADO que se accede a `AppFonts`
- ENTONCES `barlow == 'Barlow'` y `barlowCondensed == 'Barlow Condensed'`

---

## Capa 2 — Tokens Semánticos (AppPalette)

### REQ-DS2-010: API pública de AppPalette intacta

`AppPalette` DEBE mantener exactamente la misma firma pública:
`of(BuildContext)`, `mintMagenta`, `mintMagentaLight`, `copyWith({...})`,
`lerp(ThemeExtension?, double)`.
Los 14 campos (`accent`, `highlight`, `bg`, `bgCard`, `border`, `borderHover`,
`textPrimary`, `textMuted`, `sage`, `espresso`, `danger`, `warning`, `onDanger`,
`scrimDark`) DEBEN conservar nombres y semántica exactos.
Todos los call sites existentes DEBEN compilar sin modificación.

#### Escenario: compilación sin tocar call sites

- DADO el codebase con 494 ocurrencias de `AppPalette.of(context)`
- CUANDO se refactoriza `AppPalette` para referenciar primitivos internamente
- ENTONCES `flutter analyze` DEBE retornar 0 errores y 0 warnings relacionados
  con `AppPalette`
- Y `dart format .` NO DEBE reportar diferencias en archivos no tocados

#### Escenario: compatibilidad de tipo

- DADO un test de widget que usa `AppPalette.mintMagenta`
- CUANDO se accede al campo `.accent`
- ENTONCES el tipo es `Color` y el valor es `const Color(0xFF2CE5A2)`

---

### REQ-DS2-011: Mapeo dark explícito a primitivos

`AppPalette.mintMagenta` DEBE referenciar constantes de `AppColorPrimitives`
en lugar de literales hex.
En modo dark: `accent == AppColorPrimitives.mint500`,
`bg == AppColorPrimitives.ink950`, `bgCard == AppColorPrimitives.ink900`.

#### Escenario: trazabilidad dark

- DADO `AppPalette.mintMagenta`
- CUANDO se accede a `.accent`
- ENTONCES el valor DEBE ser idéntico a `AppColorPrimitives.mint500` (bit a bit)

---

### REQ-DS2-012: Mapeo light explícito a primitivos

`AppPalette.mintMagentaLight` DEBE referenciar constantes de `AppColorPrimitives`
donde aplique.
En modo light: `bg` DEBE ser distinto del dark `bg` (light=`#FAFAFA`, dark=`#0A0A0A`).
Dark ES el default e identidad de la marca.

#### Escenario: contraste dark vs light

- DADO `AppPalette.mintMagenta` y `AppPalette.mintMagentaLight`
- CUANDO se comparan los campos `.bg`
- ENTONCES los valores DEBEN ser distintos entre sí
- Y `mintMagenta.bg == AppColorPrimitives.ink950`

---

## Capa 3 — Tokens de Componente

### REQ-DS2-020: TreinoButtonTokens

El sistema DEBE crear `lib/app/theme/tokens/components/treino_button_tokens.dart`
con la clase `TreinoButtonTokens` que exponga al menos `background(BuildContext)`,
`foreground(BuildContext)`, `borderRadius` como `double`.
DEBE referenciar solo `AppPalette.of(ctx)` o `AppRadius` — NUNCA hex literales.

#### Escenario: acceso en widget tree

- DADO un widget con `BuildContext` válido y tema oscuro activo
- CUANDO se llama `TreinoButtonTokens.background(context)`
- ENTONCES retorna el mismo `Color` que `AppPalette.of(context).accent`

#### Escenario: prohibición de hex crudo

- DADO el archivo `treino_button_tokens.dart`
- CUANDO se busca con regex `Color\(0x[0-9A-Fa-f]{8}\)`
- ENTONCES NO DEBE existir ningún match (hex literal prohibido en capa de componente)

---

### REQ-DS2-021: TreinoCardTokens

El sistema DEBE crear `lib/app/theme/tokens/components/treino_card_tokens.dart`
con la clase `TreinoCardTokens` que exponga al menos `background(BuildContext)`,
`border(BuildContext)`, `borderRadius` como `double`.
Las cards DEBEN tener `boxShadow: []` (sin sombra).

#### Escenario: sin sombra

- DADO un tema oscuro activo
- CUANDO se consulta `TreinoCardTokens.boxShadow`
- ENTONCES retorna lista vacía `[]`

#### Escenario: borde semántico

- DADO un tema oscuro activo
- CUANDO se llama `TreinoCardTokens.border(context)`
- ENTONCES retorna el mismo `Color` que `AppPalette.of(context).border`

---

### REQ-DS2-022: Extensibilidad del patrón de componentes

El patrón `static T method(BuildContext ctx)` DEBE ser reproducible sin boilerplate
adicional para futuros tokens (CoachHubDataTableTokens, KpiCardTokens, etc.).
Un nuevo archivo de tokens de componente DEBE poder crearse sin modificar archivos
existentes.

#### Escenario: adición sin modificar existentes

- DADO que se añade `CoachHubDataTableTokens` en `components/`
- CUANDO se compila el proyecto
- ENTONCES ningún archivo existente en `components/` DEBE haber sido modificado

---

## Capa 3b — Tokens de Movimiento

### REQ-DS2-030: AppMotionTokens semántico

El sistema DEBE crear `lib/app/theme/tokens/motion_tokens.dart` con
`AppMotionTokens` que re-exporte los valores de `AppMotion` con nombres de dominio
semántico (ej. `cardEntry`, `stateSwitch`, `pageTransition`).
`AppMotion` original NO DEBE modificarse (cero ruptura de las 93 ocurrencias).

#### Escenario: valores iguales a AppMotion

- DADO `AppMotionTokens`
- CUANDO se accede a `AppMotionTokens.stateSwitch`
- ENTONCES el valor DEBE ser igual a `AppMotion.base` (240ms)

#### Escenario: AppMotion original intacto

- DADO el codebase con 93 ocurrencias de `AppMotion.*`
- CUANDO se agrega `AppMotionTokens`
- ENTONCES `flutter analyze` DEBE retornar 0 errores y 0 warnings relacionados
  con `AppMotion`

---

### REQ-DS2-031: Política reduceMotion sin cambio de comportamiento

`AppMotionTokens` DEBE delegar `reduceMotion(BuildContext)` y `resolve(BuildContext,
Duration)` a los helpers existentes de `AppMotion`.
NO DEBE introducir lógica nueva de accesibilidad.

#### Escenario: reduceMotion delegado

- DADO un `BuildContext` con `MediaQuery.disableAnimations = true`
- CUANDO se llama `AppMotionTokens.resolve(context, AppMotionTokens.cardEntry)`
- ENTONCES retorna `Duration.zero`

---

## Reglas de Prohibición

### REQ-DS2-040: Prohibición de hex literal fuera de capa primitiva

Ningún archivo fuera de `lib/app/theme/tokens/primitives.dart` y
`lib/app/theme/app_palette.dart` DEBE contener literales `Color(0x...)` o
`Color(0xFF...)`.
Esta regla DEBE poder verificarse con un test de análisis estático o un script
de CI.

#### Escenario: test detector de hex literales

- DADO el conjunto de archivos en `lib/` excluyendo `primitives.dart` y
  `app_palette.dart`
- CUANDO se ejecuta el test de lint de hex
- ENTONCES el test DEBE pasar si no existe ningún `Color(0x` fuera de esos dos archivos
- Y DEBE fallar si se agrega un `Color(0xFF...)` en un widget

---

### REQ-DS2-041: Prohibición de hex en tokens de componente

Los archivos en `lib/app/theme/tokens/components/` DEBEN referenciar solo tokens
semánticos o de primitivos — NUNCA valores hex inline.

#### Escenario: verificación en PR

- DADO un nuevo archivo `foo_tokens.dart` en `components/`
- CUANDO `flutter test` ejecuta el test de lint de hex
- ENTONCES el test FALLA si el archivo contiene `Color(0x...)`

---

## Documentación

### REQ-DS2-050: design-system.md reescrito

`docs/design-system.md` DEBE ser reescrito para reflejar:
1. Las 3 capas del sistema de tokens (primitivos → semánticos → componente)
2. Sección Motion documentada con tabla de tokens semánticos y reglas existentes
3. Dark Y light mode como realidades soportadas (dark = default e identidad)
4. Los 14 tokens de `AppPalette` documentados (actualmente solo lista 10)
5. Eliminación de la sección Electric Violet
6. Corrección de "Modo oscuro siempre" → documentar soporte de ambos modos

El cambio DEBE ser aprobado por reviewer antes del merge (gate explícito per
`workflow.md:126`).

#### Escenario: tokens completos en docs

- DADO `docs/design-system.md` después de la reescritura
- CUANDO se buscan los 14 tokens de AppPalette
- ENTONCES DEBEN aparecer: `accent`, `highlight`, `bg`, `bgCard`, `border`,
  `borderHover`, `textPrimary`, `textMuted`, `sage`, `espresso`, `danger`,
  `warning`, `onDanger`, `scrimDark`

#### Escenario: Electric Violet eliminada

- DADO `docs/design-system.md` después de la reescritura
- CUANDO se busca "Electric Violet" o "electricViolet"
- ENTONCES NO DEBE existir ninguna mención

#### Escenario: light mode documentado

- DADO `docs/design-system.md` después de la reescritura
- CUANDO se busca "oscuro siempre"
- ENTONCES NO DEBE existir — DEBE mencionarse que dark es el default pero light
  está soportado

---

### REQ-DS2-051: architecture.md corregido

`docs/architecture.md` DEBE corregir cualquier referencia incorrecta a
`electricViolet` reemplazándola por `mintMagentaLight`.

#### Escenario: corrección en architecture.md

- DADO `docs/architecture.md` después del cambio
- CUANDO se busca "electricViolet"
- ENTONCES NO DEBE existir ningún match

---

## Calidad y Gates

### REQ-DS2-060: Flutter analyze limpio

Después de todos los cambios de Fase 0, `flutter analyze` DEBE retornar 0 errores
y 0 warnings.

#### Escenario: analyze verde

- DADO el codebase con todos los cambios de Fase 0 aplicados
- CUANDO se ejecuta `flutter analyze`
- ENTONCES el código de salida es 0 y la salida no contiene "error" ni "warning"

---

### REQ-DS2-061: dart format sin diferencias

`dart format .` DEBE retornar sin diferencias en todos los archivos modificados.

#### Escenario: formato verde

- DADO el codebase con Fase 0 aplicada
- CUANDO se ejecuta `dart format --set-exit-if-changed .`
- ENTONCES el código de salida es 0

---

### REQ-DS2-062: Suite de tests verde

`flutter test` DEBE pasar con 0 failures después de Fase 0.
TDD estricto: los tests de lint (hex detector) y de tokens (valores, delegación de
motion) DEBEN escribirse ANTES de los archivos de producción correspondientes.

#### Escenario: suite verde

- DADO el codebase con Fase 0 aplicada
- CUANDO se ejecuta `flutter test`
- ENTONCES 0 tests fallan y 0 tests tienen errores

---

### REQ-DS2-063: Cero cambio visual en runtime

La app DEBE verse y comportarse de forma idéntica antes y después de Fase 0.
Ningún token semántico DEBE cambiar su valor en runtime.
`build_runner` NO DEBE ejecutarse en Fase 0 (no se tocan archivos con `freezed`).

#### Escenario: valores de AppPalette.mintMagenta invariantes

- DADO `AppPalette.mintMagenta` antes y después de Fase 0
- CUANDO se comparan todos los campos del token dark
- ENTONCES cada campo DEBE ser bit a bit idéntico al valor previo

#### Escenario: build_runner no ejecutado

- DADO la lista de archivos modificados en Fase 0
- CUANDO se verifica que ninguno tiene sufijo `.freezed.dart` o `.g.dart`
- ENTONCES NO DEBE existir ningún archivo generado modificado

---

## Resumen de artefactos nuevos (Fase 0)

| Archivo | Estado | Descripción |
|---------|--------|-------------|
| `lib/app/theme/tokens/primitives.dart` | NUEVO | `AppColorPrimitives`, `AppSpacing`, `AppRadius`, `AppFonts` |
| `lib/app/theme/tokens/motion_tokens.dart` | NUEVO | `AppMotionTokens` semántico |
| `lib/app/theme/tokens/components/treino_button_tokens.dart` | NUEVO | Tokens de botón |
| `lib/app/theme/tokens/components/treino_card_tokens.dart` | NUEVO | Tokens de card |
| `lib/app/theme/app_palette.dart` | MODIFICADO | Referencias internas a primitivos; API pública intacta |
| `docs/design-system.md` | MODIFICADO | Reescritura completa (3 capas, Motion, dark+light, 14 tokens) |
| `docs/architecture.md` | MODIFICADO | Corrección electricViolet → mintMagentaLight |
| `test/theme/` | NUEVO | Tests TDD: lint hex, valores tokens, delegación motion |
