# Plan Fase 12 — Ajustes (Configuración) · rediseño Coach Hub Web

> Última sección del rediseño. Migra `lib/features/coach_hub/presentation/sections/ajustes/`
> al kit v2 + motion + dark/light impecables. Esta es la pantalla donde el
> usuario CAMBIA el tema, así que tiene que ser la vidriera del sistema de tokens.

## 1. Anatomía objetivo (mockups)

Mockups leídos como imágenes en `docs/web-trainer/screens/ajustes/`:

- **cuenta.png** — Sub-nav vertical izquierda (CUENTA · NOTIFICACIONES · FACTURACIÓN
  TREINO · DATOS Y PRIVACIDAD). Cuerpo: card «INFORMACIÓN PERSONAL» (subtítulo
  «Esta info se muestra en tu perfil público») con avatar de anillo degradé +
  CAMBIAR FOTO / QUITAR + hint «JPG o PNG · máximo 2MB · 400x400 px recomendado»,
  campos NOMBRE/APELLIDO (2 col), EMAIL, TELÉFONO, IDIOMA (dropdown). Debajo,
  card «ZONA PELIGROSA» con borde rojo: PAUSAR CUENTA (warning) + ELIMINAR CUENTA
  (danger). GUARDAR CAMBIOS aparece en el top bar del mockup.
- **notificaciones.png** — Card «NOTIFICACIONES» (subtítulo «Elegí cómo querés
  recibir cada tipo de aviso»). Matriz tipo-de-aviso × canal (EMAIL/PUSH/WHATSAPP)
  agrupada en PAGOS / ALUMNOS / CHAT, cada celda un checkbox mint.
- **facturacion-treino.png** — Card superior «PLAN ACTUAL - TREINO COACH SOLO»
  ($/mes, renovación) + CAMBIAR PLAN; fila de KPIs (28/40 alumnos con barra,
  Ilim. templates, 4.95% comisión); card «HISTORIAL DE FACTURACIÓN» con filas
  (fecha, monto, badge PAGADO, botón PDF).

Donde el mockup y el design system chocan en un token, MANDA el design system.

## 2. Censo del código actual

`lib/features/coach_hub/presentation/sections/ajustes/`
- `ajustes_screen.dart` — Scaffold «CONFIGURACIÓN» (ya usa `TreinoSectionHeader`,
  Fase 1) + subtítulo + sub-nav vertical hecha a mano (`_SubNav`/`_SubNavItem`
  con `GestureDetector`, `Colors.transparent`, `BorderRadius.circular(10)`, sin
  hover/focus/teclado ni motion) + `_TabBody` con switch. 3 tabs
  (`AjustesTab.cuenta/notificaciones/facturacion`). «Datos y privacidad» se omite
  a propósito (eliminación de cuenta vive en mobile — comentario en el enum).
- `tabs/cuenta_tab.dart` — Formulario grande. `profileAsync.when` con
  `CircularProgressIndicator()` SECO (loading). Widgets a mano: `_LabeledInput`,
  `_Field`, `_Avatar`, `_FotoEditor`, `_DangerZone`. GUARDAR CAMBIOS in-tab con
  spinner. PAUSAR/ELIMINAR usan `_soon()` (snackbar «Próximamente»). Sin motion,
  sin TreinoDialog, botones `OutlinedButton`/`ElevatedButton`/`TextButton` crudos.
  Data real: `userProfileProvider`, `userRepositoryProvider.update`,
  `trainerLinksStreamProvider` (conteo alumnos activos).
- `tabs/notificaciones_tab.dart` — `prefsAsync.when` con CircularProgressIndicator
  SECO. Matriz a mano (`_Matrix`/`_HeaderRow`/`_Row`) con `Checkbox` crudo.
  Save-on-toggle vía `userRepositoryProvider.update` + nota honesta
  («entrega email/WhatsApp próximamente»). Sin motion, sin shimmer.
- `tabs/facturacion_tab.dart` — Empty state honesto (NO backend de suscripción,
  Fase 7). Único dato real = alumnos activos (`trainerLinksStreamProvider`,
  `valueOrNull`, sin loading real). Card + empty a mano. Sin motion, sin kit.
- `tabs/avatar_web_uploader.dart` — Servicio/provider real (pick+crop+upload).
  NO tocar salvo lo mínimo.
- `tabs/notificaciones_prefs.dart` — Dominio + `webNotificationPreferencesProvider`.
  Real. NO tocar salvo lo mínimo.
- `routes.dart` — Ruta `/ajustes` + item de sidebar. YA registrados; NO se tocan.

Tests existentes (extensibles; NO prohibidos):
- `test/features/coach_hub/presentation/sections/ajustes/ajustes_screen_test.dart`
- `test/features/coach_hub/presentation/sections/ajustes/facturacion_tab_test.dart`

**Archivos PROHIBIDOS en scope:** ninguno de `ajustes/` está en la lista de
usuario. (La lista prohibida cubre `routine_editor/*` y tests puntuales ajenos a
esta sección.) No hay que crear ruta ni item de sidebar (ya existen desde W3).

## 3. Decisiones de arquitectura (ADRs)

**ADR-F12-01 — Honestidad de scope: no inventar backend.**
- *Facturación*: el mockup muestra plan/límite/historial con PDFs, pero NO existe
  backend de suscripción (monetización = Fase 7). Se mantiene empty state honesto,
  pulido con el kit. Único dato real = alumnos activos → `KpiCard`. NO se renderiza
  plan falso, CAMBIAR PLAN, historial ni PDFs.
- *Notificaciones*: solo `push` tiene canal real y las CFs aún no respetan las
  prefs; email/whatsapp sin entrega. Las prefs SÍ se persisten → matriz funcional +
  nota honesta. Sin cambios de contrato.
- *Zona peligrosa*: PAUSAR no tiene backend; ELIMINAR vive en mobile. Se mantienen
  los botones (están en el mockup) pero la confirmación se hace con `TreinoDialog`
  destructivo de copy honesto (se gestiona desde la app / próximamente), no un
  snackbar seco.

**ADR-F12-02 — Sub-nav vertical tokenizada con motion, LOCAL a ajustes (aún no al kit).**
Es el PRIMER (y único) rail de tabs vertical del hub → no se extrae al kit todavía
(regla «segundo copy-paste = extraer»). Se rediseña con tokens (`AppPalette`,
`AppRadius`, `AppSpacing`), `TreinoInteractiveState` (hover/pressed/focus + teclado
Enter/Space + `Semantics(button)`) y animación de selección (`AnimatedContainer` con
`AppMotion.resolve` + indicador de acento). Cero `Colors.*`/hex/radios crudos.
Anotado como candidato futuro a componente del kit.

**ADR-F12-03 — `.when()` → `TreinoStateSwitcher` + shimmer skeletons.**
Cuenta y Notificaciones reemplazan `CircularProgressIndicator()` seco por
`TreinoStateSwitcher` (cross-fade loading→data→error con keys por estado) y
skeletons `TreinoShimmer` que espejan el layout (formulario en Cuenta, matriz en
Notif). Facturación gana un loading real (hoy usa `valueOrNull` sin estado).

**ADR-F12-04 — Motion eager: `TreinoFadeSlideIn` staggered en las tarjetas del cuerpo.**
Stagger vía `AppMotion.stagger(i)` en secciones eager (Columns): tarjetas de Cuenta
(INFORMACIÓN PERSONAL → ZONA PELIGROSA), grupos de Notif y bloques de Facturación.
PROHIBIDO en `ListView.builder`. Respeta `reduceMotion`.

**ADR-F12-05 — Facturación: `KpiCard` (uso real) + `TreinoEmptyState` (honesto).**
El único dato real (alumnos activos) se muestra como `KpiCard`; el mensaje
«próximamente Fase 7» usa `TreinoEmptyState`. Sin datos falsos.

**ADR-F12-06 — Tema/apariencia: una sola fuente de verdad = `themeModeProvider` del top bar.**
El mockup de Ajustes NO tiene control de tema (las tabs son Cuenta/Notif/Facturación/
Datos). El top bar (Fase 1) ya es el dueño canónico del selector System/Light/Dark
vía `themeModeProvider`. **No se agrega** un selector duplicado en Ajustes: evita dos
superficies de control y una segunda fuente de verdad. *Rechazado:* añadir una fila/tab
«Apariencia» ligada a `themeModeProvider` — descartado por duplicar control fuera del
mockup. La sección igual debe verse impecable en dark Y light (es la vidriera).

**ADR-F12-07 — Deep-links solo donde el mapeo es honesto.**
En Cuenta, «tu perfil público» enlaza a `/perfil-publico` (Fase 11, ya rediseñada).
En Facturación NO se agrega deep-link: «Facturación TREINO» (suscripción del PF) no
mapea a `/pagos` (cobros a alumnos) ni a `/planes` (catálogo que el PF vende); forzar
uno sería engañoso. El empty state honesto se sostiene solo.

**ADR-F12-08 — «Datos y privacidad» permanece fuera del hub web.**
Se mantiene la decisión de W3: la 4ª tab del mockup no se agrega; la eliminación de
cuenta vive en mobile (políticas de stores). El test que lo asegura queda verde.

## 4. Work Units (atómicos, secuenciales)

- **WU-01 — Evidencia BEFORE.** Harness `test/evidence/coach_hub_ajustes_evidence_test.dart`
  (patrón pagos): monta `/ajustes` real en el shell con providers fake. Captura
  `docs/web-trainer/evidence/fase-12/before/`. Commit. Sin cambios de producción.
- **WU-02 — Scaffold + sub-nav.** Rediseña la sub-nav vertical de `ajustes_screen.dart`
  con tokens + `TreinoInteractiveState` + animación de selección + stagger. 3 tabs,
  «Datos y privacidad» sigue omitida. TDD. Dark+light.
- **WU-03 — Cuenta: estados + motion.** `TreinoStateSwitcher` + skeleton de formulario,
  error pulido, stagger de tarjetas, deep-link a `/perfil-publico`. Preserva save. TDD.
- **WU-04 — Cuenta: Zona peligrosa con `TreinoDialog`.** PAUSAR/ELIMINAR abren
  `TreinoDialog` destructivo honesto (reemplaza el snackbar `_soon`). Botones
  tokenizados. TDD.
- **WU-05 — Notificaciones: estados + motion + matriz tokenizada.** `TreinoStateSwitcher`
  + skeleton de matriz, stagger de grupos, feedback animado al togglear. Preserva
  save-on-toggle + nota honesta. TDD.
- **WU-06 — Facturación: kit honesto.** `TreinoEmptyState` + `KpiCard` (uso real),
  loading con `TreinoStateSwitcher`, stagger. Sin plan/historial falsos. TDD.
- **WU-07 — Evidencia AFTER + gates.** Regenera `after/`, FULL `flutter test` +
  `flutter analyze` (baseline 42, cero nuevos). Commitea este `plan-fase12.md` +
  commit final.

## 5. Riesgos

- El harness de evidencia a 420px muestra el `MobileBanner` (desktop-only,
  ADR-CHW-004): before/after coinciden ahí; el guard ramifica por viewport.
- El comparador del harness debe apuntar a `fase-12/` (no copiar `fase-9`).
- `ajustes_screen_test.dart` verifica textos exactos (`CONFIGURACIÓN`, `Cuenta`,
  `GUARDAR CAMBIOS`, `find.byType(TextField).first`, ausencia de «Datos y
  privacidad»): preservarlos al rediseñar o actualizarlos en el mismo WU.
- El top bar del shell lee `themeModeProvider` vía `sharedPreferencesProvider`:
  el harness DEBE override-ear `sharedPreferencesProvider` (patrón pagos) o crashea.
- `avatar_web_uploader.dart` y `notificaciones_prefs.dart` son data real: no
  cambiar contratos; solo consumir.
