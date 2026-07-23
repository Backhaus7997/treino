# Tasks: Design System v2 — FASE 0

> Cambio: `redesign-coach-hub-web` · Fase: 0 · Delivery: `auto-chain` (un PR) · TDD estricto
> Cada work-unit commit incluye: test en rojo → código en verde → commit. Docs con el feature.

---

## Convenciones de este documento

- **[S]** = secuencial (depende del WU anterior)
- **[P]** = paralelo (puede ejecutarse a la vez que otros del mismo nivel)
- **WU-N** = work-unit commit (una unidad de comportamiento entregable)
- **REQ-X** = requisito spec que satisface
- **Est.** = líneas de código estimadas (producción + test)

---

## FASE 0 — Design System v2 (token restructure)

### [x] WU-01 — Tokens primitivos: archivos + identidad (secuencial, inicio)

**Requisitos**: REQ-DS2-001, REQ-DS2-002, REQ-DS2-003, REQ-DS2-004

**Descripción**: Crear los archivos de tokens primitivos bajo `lib/app/theme/tokens/`
y el barrel `tokens.dart`. Escribir primero los tests de identidad de valores y
aislamiento (sin BuildContext).

**Orden TDD**:
1. Escribir `test/app/theme/tokens/primitives_test.dart` — falla (archivos no existen)
2. Crear `lib/app/theme/tokens/color_primitives.dart` → `AppColorPrimitives`
3. Crear `lib/app/theme/tokens/spacing_primitives.dart` → `AppSpacing`
4. Crear `lib/app/theme/tokens/radius_primitives.dart` → `AppRadius`
5. Crear `lib/app/theme/tokens/type_primitives.dart` → `AppType`
6. Crear `lib/app/theme/tokens/tokens.dart` (barrel de exports)
7. Test pasa → commit

**Archivos tocados**:
- `test/app/theme/tokens/primitives_test.dart` (NUEVO)
- `lib/app/theme/tokens/color_primitives.dart` (NUEVO)
- `lib/app/theme/tokens/spacing_primitives.dart` (NUEVO)
- `lib/app/theme/tokens/radius_primitives.dart` (NUEVO)
- `lib/app/theme/tokens/type_primitives.dart` (NUEVO)
- `lib/app/theme/tokens/tokens.dart` (NUEVO, barrel)

**Nota TDD**: El test verifica cada constante ARGB bit a bit, ausencia de `s4`/`s16`/`s24`,
ausencia de BuildContext en el acceso, y que todas son `static const`.

**Est.**: ~180 líneas producción + ~120 líneas test = **~300 líneas**

---

### [x] WU-02 — AppPalette rewired a primitivos + tests de compatibilidad (secuencial, después de WU-01)

**Requisitos**: REQ-DS2-010, REQ-DS2-011, REQ-DS2-012

**Descripción**: Modificar `app_palette.dart` para que los campos `mintMagenta` y
`mintMagentaLight` referencien `AppColorPrimitives` en lugar de literales hex.
API pública intacta: `of`, `copyWith`, `lerp`, los 14 campos, las dos constantes.
`AppColors` pasa a `@Deprecated` como alias a primitivos (no se borra).

**Orden TDD**:
1. Escribir `test/app/theme/tokens/palette_identity_test.dart` — congela ARGB de los
   14 campos dark+light (falla si algún valor cambia)
2. Escribir `test/app/theme/tokens/api_compat_test.dart` — verifica que `of`, `copyWith`,
   `lerp`, `mintMagenta.accent`, `mintMagentaLight.bg` compilan con los mismos tipos
3. Ambos tests pasan en verde antes del cambio (baseline)
4. Refactorizar `app_palette.dart`: hex → referencias a `AppColorPrimitives`
5. Tests siguen verdes → commit

**Archivos tocados**:
- `test/app/theme/tokens/palette_identity_test.dart` (NUEVO)
- `test/app/theme/tokens/api_compat_test.dart` (NUEVO)
- `lib/app/theme/app_palette.dart` (MODIFICADO — solo internos, API intacta)

**Nota TDD**: `palette_identity_test` es el guard anti-deriva: si algún valor ARGB cambia
por error, el test lo detecta antes de que llegue a producción. Los 494 call sites
no se tocan — `flutter analyze` verifica que compilan sin error.

**Est.**: ~165 líneas producción (app_palette refactorizado) + ~90 líneas test = **~255 líneas**

---

### [x] WU-03 — Tokens de componente: TreinoButtonTokens + TreinoCardTokens (paralelo con WU-02 si WU-01 terminó)

**Requisitos**: REQ-DS2-020, REQ-DS2-021, REQ-DS2-022

**Descripción**: Crear los dos primeros tokens de componente bajo
`lib/app/theme/tokens/components/`. Patrón `abstract final` con métodos
`static T method(BuildContext)`. Nunca hex. Solo referencian `AppPalette.of(ctx)`
y primitivos de forma (AppRadius).

**Orden TDD**:
1. Escribir `test/app/theme/tokens/component_tokens_test.dart` — widget test que
   verifica que `TreinoButtonTokens.background(ctx)` == `AppPalette.of(ctx).accent`,
   `TreinoCardTokens.boxShadow` == `[]`, etc., en dark Y light
2. Tests fallan (clases no existen)
3. Crear `lib/app/theme/tokens/components/treino_button_tokens.dart`
4. Crear `lib/app/theme/tokens/components/treino_card_tokens.dart`
5. Actualizar barrel `tokens.dart` con los exports de `components/`
6. Tests pasan → commit

**Archivos tocados**:
- `test/app/theme/tokens/component_tokens_test.dart` (NUEVO)
- `lib/app/theme/tokens/components/treino_button_tokens.dart` (NUEVO)
- `lib/app/theme/tokens/components/treino_card_tokens.dart` (NUEVO)
- `lib/app/theme/tokens/tokens.dart` (MODIFICADO — agregar exports)

**Nota TDD**: El test de componentes es un widget test con `pumpWidget` +
`MaterialApp(theme: ThemeData(extensions: [AppPalette.mintMagenta]))`.
Verificar que ningún archivo en `components/` contiene `Color(0x...)`.

**Est.**: ~120 líneas producción + ~100 líneas test = **~220 líneas**

---

### [x] WU-04 — AppMotionTokens semántico + tests de delegación (paralelo con WU-03 si WU-01 terminó)

**Requisitos**: REQ-DS2-030, REQ-DS2-031

**Descripción**: Crear `lib/app/theme/tokens/motion_tokens.dart` con `AppMotionTokens`
que re-exporta valores de `AppMotion` con nombres de dominio semántico
(`cardEntry`, `stateSwitch`, `pageTransition`, `tapFeedback`, etc.).
`AppMotion` original NO se toca. Delegar `reduceMotion` y `resolve` sin lógica nueva.

**Orden TDD**:
1. Escribir `test/app/theme/tokens/motion_tokens_test.dart` — verifica
   `AppMotionTokens.stateSwitch == AppMotion.base` (240ms),
   `AppMotionTokens.tapFeedback == AppMotion.micro` (120ms),
   `AppMotionTokens.cardEntry == AppMotion.fast` (180ms),
   `AppMotionTokens.pageTransition == AppMotion.slow` (320ms),
   y que `resolve(ctx, cardEntry)` retorna `Duration.zero` con `disableAnimations=true`
2. Test falla (clase no existe)
3. Crear `lib/app/theme/tokens/motion_tokens.dart`
4. Actualizar barrel `tokens.dart`
5. Test pasa → commit

**Archivos tocados**:
- `test/app/theme/tokens/motion_tokens_test.dart` (NUEVO)
- `lib/app/theme/tokens/motion_tokens.dart` (NUEVO)
- `lib/app/theme/tokens/tokens.dart` (MODIFICADO — agregar export)

**Nota TDD**: `AppMotion` no se modifica; el test lo importa directamente para
comparar valores. Verificar con `flutter analyze` que las 93 ocurrencias existentes
de `AppMotion.*` siguen sin warnings.

**Est.**: ~80 líneas producción + ~70 líneas test = **~150 líneas**

---

### [x] WU-05 — Test de lint no-hex (scanner estático con allowlist) (secuencial, después de WU-01..04)

**Requisitos**: REQ-DS2-040, REQ-DS2-041

**Descripción**: Crear el test de análisis estático que escanea `lib/` buscando
`Color(0x...)` fuera de la allowlist (`tokens/primitives.dart` heredado
`app_palette.dart`). El test es un RATCHET: la allowlist solo puede decrecer con
cada fase. Implementar primero el test, verificar que pasa con el codebase actual
tras WU-01..04.

**Orden TDD**:
1. Escribir `test/app/theme/tokens/no_hex_scan_test.dart` con:
   - Regex `Color\(0x[0-9A-Fa-f]{8}\)`
   - Allowlist: `lib/app/theme/tokens/color_primitives.dart`,
     `lib/app/theme/app_palette.dart` (legado hasta Fase N)
   - Escanea recursivamente `lib/`
   - Falla si encuentra match fuera de allowlist
2. Test falla si hay hex fuera de allowlist (detecta regresiones)
3. Verificar que tras WU-01..04 el test pasa
4. Commit

**Archivos tocados**:
- `test/app/theme/tokens/no_hex_scan_test.dart` (NUEVO)

**Nota TDD**: Este test es CI permanente. En cada Fase siguiente se retira una
entrada de la allowlist cuando se migra ese archivo. No agregar entradas nuevas.

**Est.**: ~0 líneas producción + ~60 líneas test = **~60 líneas**

---

### [x] WU-06 — Reescritura de docs/design-system.md (secuencial, después de WU-05)

**Requisitos**: REQ-DS2-050, REQ-DS2-051

**Descripción**: Reescribir `docs/design-system.md` completo para reflejar la
arquitectura de 3 capas, los 14 tokens de AppPalette (actualmente lista 10), la
sección Motion ampliada con tabla de tokens semánticos (`AppMotionTokens`), dark
como default + light como soportado (eliminar "Modo oscuro siempre"), eliminar
Electric Violet. Corregir `docs/architecture.md` (línea 29: `electricViolet` →
`mintMagentaLight`).

**Gate**: El PR requiere aprobación de reviewer antes del merge (workflow.md:126).
Este WU no tiene test automatizado — la verificación es la revisión humana más la
búsqueda de strings prohibidos que puede hacerse en CI si se desea.

**Archivos tocados**:
- `docs/design-system.md` (MODIFICADO — reescritura completa)
- `docs/architecture.md` (MODIFICADO — línea 29, corrección puntual)

**Nota**: No hay test de dart para docs, pero el WU-05 no-hex-scan y `flutter analyze`
siguen siendo el gate de calidad técnica. La verificación de docs es manual (reviewer).

**Est.**: ~0 líneas código + ~220 líneas docs = **~220 líneas docs**

---

### [x] WU-07 — Gates finales: analyze + format + test + build sanity (secuencial, último)

**Requisitos**: REQ-DS2-060, REQ-DS2-061, REQ-DS2-062, REQ-DS2-063

**Descripción**: Ejecutar los gates de calidad en orden. No produce archivos nuevos —
valida que todo lo anterior está correcto. Si algún gate falla, se corrige en el WU
correspondiente antes de hacer el commit final del PR.

**Pasos**:
1. `flutter analyze` — debe retornar 0 errores y 0 warnings
2. `dart format --set-exit-if-changed .` — debe retornar exit code 0
3. `flutter test` — debe retornar 0 failures (incluye las 5 suites nuevas)
4. Verificar que ningún archivo `.freezed.dart` o `.g.dart` fue modificado
5. Verificar que `AppPalette.mintMagenta` campos ARGB son bit-a-bit idénticos al baseline
6. `flutter build web --no-pub` (build sanity, no deploy) — debe compilar sin errores
7. Commit final de PR (squash o merge según convención del equipo)

**Archivos tocados**: ninguno (gate de validación)

**Est.**: ~0 líneas = **gate puro**

---

## Orden de ejecución y dependencias

```
WU-01 (primitivos)
  └── WU-02 (AppPalette rewired)       [S, después de WU-01]
  └── WU-03 (component tokens)         [P junto con WU-02, si WU-01 terminó]
  └── WU-04 (motion tokens)            [P junto con WU-02/03, si WU-01 terminó]
        └── WU-05 (no-hex scanner)     [S, después de WU-01..04]
              └── WU-06 (docs)         [S, después de WU-05]
                    └── WU-07 (gates)  [S, último]
```

WU-02, WU-03 y WU-04 pueden ejecutarse en paralelo entre sí una vez que WU-01 está completo.
La secuencia mínima crítica es: WU-01 → WU-05 → WU-06 → WU-07.

---

## Resumen de archivos por WU

| WU | Archivos nuevos | Archivos modificados | Tests nuevos |
|----|-----------------|----------------------|--------------|
| WU-01 | 6 (primitivos + barrel) | — | 1 (`primitives_test`) |
| WU-02 | — | 1 (`app_palette.dart`) | 2 (`palette_identity`, `api_compat`) |
| WU-03 | 2 (`button`, `card` tokens) | 1 (barrel) | 1 (`component_tokens`) |
| WU-04 | 1 (`motion_tokens`) | 1 (barrel) | 1 (`motion_tokens`) |
| WU-05 | — | — | 1 (`no_hex_scan`) |
| WU-06 | — | 2 (docs) | — |
| WU-07 | — | — | — (gate) |
| **Total** | **9 archivos** | **5 archivos** | **6 suites** |

---

## Review Workload Forecast

### Desglose de líneas estimadas

| Categoría | Líneas |
|-----------|--------|
| Código de producción (dart) | ~365 |
| Tests (dart) | ~440 |
| Docs (markdown) | ~220 |
| **Total código (prod + test)** | **~805** |
| **Total incluyendo docs** | **~1.025** |

### Detalle por WU

| WU | Prod | Test | Docs | Total WU |
|----|------|------|------|----------|
| WU-01 | 180 | 120 | — | 300 |
| WU-02 | 165 | 90 | — | 255 |
| WU-03 | 120 | 100 | — | 220 |
| WU-04 | 80 | 70 | — | 150 |
| WU-05 | — | 60 | — | 60 |
| WU-06 | — | — | 220 | 220 |
| WU-07 | — | — | — | 0 |

### Evaluación

| Métrica | Valor |
|---------|-------|
| Líneas de código (prod + test) | ~805 |
| Líneas de docs | ~220 |
| 400-line budget risk | **High** (805 líneas de código) |
| Chained PRs recommended | **No** — por mandato del usuario esta Fase es UN PR |
| Decision needed before apply | **No** — entregar como un PR con `size:exception` |

### Justificación de `size:exception`

La Fase 0 es una reestructuración MECÁNICA y ADITIVA:
- Cero lógica nueva de negocio
- Cero cambio visual en runtime
- La mayor parte del volumen son tests (440 líneas) y archivos de primitivos
  nuevos que son listas de constantes (no ramificaciones complejas)
- Los archivos modificados (`app_palette.dart`, barrel) son cambios de referencia
  interna, no cambios de comportamiento
- El reviewer puede validar cada WU-commit de forma aislada dentro del mismo PR

**Recomendación**: solicitar `size:exception` con la justificación de "token
restructure mecánica — 55% del diff son constantes y tests, 0 lógica nueva".

---

## Fases 1–12 — Grupos placeholder

> Detalle completo se elabora en los `sdd-tasks` de cada fase posterior.
> Los nombres de componentes siguen el patrón `TreinoXTokens` de Fase 0.

### FASE 1 — KpiCard + DataTable tokens (Coach Hub web)
Tokens de componente para `KpiCardTokens` y `CoachHubDataTableTokens`.
Refactor de los widgets existentes para consumirlos.

### FASE 2 — ListRow + FilterChips tokens
Tokens para filas de lista y chips de filtro del Coach Hub.
Migración de hex inline en esos widgets a tokens de componente.

### FASE 3 — EmptyState + StatusBadge tokens
Tokens semánticos para estados vacíos y badges de estado.

### FASE 4 — GridCard + FormDialog tokens
Tokens para tarjetas de grilla y diálogos de formulario del módulo Coach.

### FASE 5 — Migración de hex legacy en widgets de app (ratchet paso 1)
Reducir la allowlist del `no_hex_scan_test`: migrar hex de widgets de features
principales (`lib/features/`) a tokens de componente.

### FASE 6 — Migración de hex legacy (ratchet paso 2, resto de features)
Completar la migración de hex del ratchet. Al final: allowlist vacía solo
con `color_primitives.dart`.

### FASE 7 — Coach Hub web: layout y navegación responsive
Implementar sidebar responsivo, breakpoints y layout de grilla para Coach Hub web.

### FASE 8 — Coach Hub web: tabla de atletas y filtros
Pantalla de lista de atletas con DataTable, filtros, paginación y búsqueda.

### FASE 9 — Coach Hub web: perfil de atleta y KPIs
Pantalla de detalle de atleta con KPI cards y gráficos de progreso.

### FASE 10 — Coach Hub web: editor de rutinas (web variant)
Adaptación web del routine_editor para pantallas grandes.

### FASE 11 — Coach Hub web: motion y polish experiencial
Aplicar `AppMotionTokens` semánticos en todas las pantallas Coach Hub web.
Elevar de "funcional" a "experiencial" (resultado del animation-audit).

### FASE 12 — Verificación final, smoke test E2E y cierre
`sdd-verify` completo contra spec Fase 0–11. Smoke test manual en web.
`sdd-archive` del cambio `redesign-coach-hub-web`.
