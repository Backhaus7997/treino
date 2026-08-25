# Plan Fase 8 — Chat (redesign-coach-hub-web)

> **Sección**: `lib/features/coach_hub/presentation/sections/chat`
> **Norte visual**: `docs/web-trainer/screens/chat/chat.png`
> **Evidencia**: `docs/web-trainer/evidence/fase-8/{before,after}/`
> **Rama**: `feat/coach-hub-chat-redesign`
> **Fecha**: 2026-07-20

---

## 1. Anatomía objetivo (mockup `chat.png`)

Two-pane estilo WhatsApp Web, montado dentro del shell real (sidebar + top bar del Coach Hub). El área de la sección es todo lo que hay debajo del top bar:

**Panel izquierdo — lista de conversaciones (ancho fijo ~360px):**
- Campo de búsqueda "Buscar conversación" con ícono lupa arriba de todo.
- Rows de conversación: avatar circular con inicial coloreada, nombre (bold si unread), timestamp arriba-derecha, preview del último mensaje (con emoji), y **badge de unread** (círculo verde con número) abajo-derecha.
- Row seleccionada resaltada (fondo + borde izquierdo mint).

**Panel derecho — hilo de la conversación (se estira al resto):**
- Header: avatar + nombre + subtítulo de presencia ("Activo hace 5 min"), y a la derecha íconos de llamada + "…" (más).
- Separador de fecha centrado ("HOY - 23 ABR").
- Burbujas: recibidas = fondo oscuro (bgCard), alineadas izquierda; propias = **fondo mint SÓLIDO con texto oscuro**, alineadas derecha, con timestamp + doble-check.
- Burbuja especial "RUTINA ADJUNTA" (card de adjunto de rutina).
- Composer: botón "+" (adjuntar), campo "Escribir un mensaje…", botón circular mint de enviar.

**Léxico visual**: dark dominante, acento mint #2CE5A2, avatares coloreados, tipografía Barlow / Barlow Condensed CAPS en headers, sin sombras, radios suaves.

---

## 2. Estado actual del código (censo)

| Archivo | L | Rol | Deuda a saldar |
|---------|---|-----|----------------|
| `chat_section_screen.dart` | 55 | Root two-pane (`Row` + `selectedChatIdProvider`) | OK estructural; solo `VerticalDivider`/anchos a revisar |
| `widgets/chat_list_pane.dart` | 285 | Lista de conversaciones + `_ChatRow` + estados | `CircularProgressIndicator` seco; `GoogleFonts.*` directo; spacing 17/24; unread = dot booleano; sin skeleton; sin search; sin `TreinoStateSwitcher` |
| `widgets/chat_detail_pane.dart` | 536 | Header + lista mensajes + composer + upload media | `CircularProgressIndicator` seco; `GoogleFonts.*` directo; spacing 16/24; sin `TreinoStateSwitcher`; sin separador de fecha; composer sin estados tokenizados |
| `widgets/chat_message_bubble.dart` | 171 | Burbuja individual (texto + img + video) | `GoogleFonts.*` directo; radios 14/4/10/6 fuera de escala; own = accent@0.2 (mockup pide sólido) |
| `widgets/chat_empty_pane.dart` | 48 | Pane derecho sin selección | `GoogleFonts.*` directo; size 64; migrable a `TreinoEmptyState` |
| `routes.dart` | 32 | Ruta `/chat` + sidebar item | OK — NO tocar (ADR-CHW-002) |

**Data layer (REUSAR, NO tocar — vive en `lib/features/chat/`):**
- `chatsForCurrentUserProvider` — `StreamProvider.autoDispose<List<Chat>>` (ordenado por lastMessageAt desc).
- `messagesProvider(chatId)` — `StreamProvider.autoDispose.family<List<Message>>` (createdAt desc; lista con `reverse:true`).
- `userPublicProfileProvider(uid)` — perfil público (avatar + displayName).
- `chatRepositoryProvider.markAsRead / sendMessage`; `chatMediaUploadServiceProvider`.
- `chatHasUnread(chat, uid)` → **bool** (NO hay contador numérico de no-leídos por chat).
- `currentUidProvider`.

**Streams / dispose (CRÍTICO de la fase):** todos los streams son `autoDispose` → Riverpod cancela la suscripción cuando el widget deja de observarlos; NO hay `StreamSubscription`/`StreamBuilder` crudos hoy. `_ChatDetailPaneState` ya dispone `_composerCtrl` y re-marca leído en `didUpdateWidget`. **El rediseño DEBE preservar esto y NO introducir suscripciones nuevas ni duplicadas.**

---

## 3. Kit disponible (APIs reales verificadas)

- `TreinoStateSwitcher(child, childKey)` — crossfade loading→data→error; **exige key distinta por estado** (`ValueKey('loading'|'data'|'error')`).
- `TreinoShimmer(enabled, child)` — barrido para skeletons; `enabled:false` en error/estable.
- `TreinoEmptyState(icon, title, description?, ctaLabel?, onCtaTap?, loading?)` — ya envuelve `TreinoFadeSlideIn`.
- `TreinoListRow(title, subtitle?, leading?, trailing?, onTap?, loading?, dense?)` — row genérica con hover/pressed/skeleton. **NO calza 1:1 el row de chat** (dos-slots-trailing: timestamp + badge en líneas distintas + bold-on-unread) → el `_ChatRow` sigue siendo widget local, pero DEBE usar `TreinoInteractiveState` (hover/pressed/focus + Semantics + teclado) en vez de `InkWell`.
- `TreinoInteractiveState(onTap, builder:(ctx,states)=>...)` — resolver único (`states.hovered/pressed/focused/disabled`).
- `TreinoTappable(onTap, child)` — feedback de presión (scale 0.97) para CTAs (botón enviar).
- `TreinoSectionHeader`, `TreinoFadeSlideIn`.

**Tokens**: `AppPalette.of(context)` (accent/highlight/bg/bgCard/border/borderHover/textPrimary/textMuted/danger/…); `AppSpacing.s8/s12/s14/s18/s20/hairline`; `AppRadius.sm=12/md=16/lg=20/full`; `AppFonts.barlow/barlowCondensed`; `AppMotion`/`AppMotionTokens`.
**Íconos**: `TreinoIcon.send/attach/plus/search/chatEmpty/dotsThree/image/video`.

---

## 4. Fronteras de scope (HONESTIDAD — no inventar backend)

**FUERA de scope (requieren backend inexistente; el rediseño NO los fabrica):**
- **Presencia "Activo hace 5 min"** del header: no hay data de online-status → se omite (solo avatar + nombre).
- **Íconos de llamada / videollamada** del header: telefonía/videollamada fuera de scope → se omiten (opcionalmente un "…" con acciones existentes, o nada).
- **Doble-check / read-receipts por mensaje**: el modelo `Message` no expone estado entregado/leído por mensaje → solo timestamp en la burbuja (sin ticks fabricados).
- **Badge de unread NUMÉRICO por conversación**: `chatHasUnread` es booleano → se renderiza un **badge tokenizado (pill/dot mint) SIN número inventado**.
- **Card "RUTINA ADJUNTA"**: adjuntar rutina al chat es feature nueva → fuera de scope.
- **Media nueva (foto/video/videollamada)**: la subida de foto (V2) y render de video (V3) YA existen → se **preservan** tal cual (no se amplían).

**Archivos PROHIBIDOS**: ninguno de la lista de usuario cae en `sections/chat`. NO tocar `lib/features/chat/**` (data layer compartida con mobile), `routes.dart`, ni ningún archivo de la lista USER.

---

## 5. Reglas transversales (aplican a TODOS los WU de rediseño)

1. **TDD estricto** (`flutter test`): test que falla primero para cada comportamiento nuevo. Los 3 tests existentes (`chat_section_screen_test`, `chat_web_v2_media_test`, `chat_web_v3_video_test`) se **EXTIENDEN sin perder aserciones ni keys** (`chat_row_<id>`, `chat_composer_attach_button`, `chat_composer_attach_menu_photo/video`, `chat_composer_field`, `chat_send_button`).
2. **Cero hex / `Colors.*` crudos** (scanner: `Color(0x*)`, `fromARGB`, `fromRGBO`). Reemplazar `GoogleFonts.barlow*` directo por `AppFonts` + estilo tokenizado. Preferir quitar `Colors.transparent` por `palette.<token>.withValues(alpha:0)` donde aplique.
3. **Spacing**: solo 8/12/14/18/20 (+ hairline 4). **Radios**: 12/16/20/full.
4. **Motion**: `TreinoStateSwitcher` en CADA `.when` async visible (nada de spinner→data seco); `TreinoShimmer` para skeletons; `TreinoInteractiveState`/`TreinoTappable` en rows y CTAs. **PROHIBIDO `TreinoFadeSlideIn` dentro de `ListView.builder`** (aplica a rows de lista y a burbujas). Stagger solo en secciones eager.
5. **Streams**: seguir usando los providers `autoDispose` vía `ref.watch`; **NO** introducir `StreamSubscription`/`StreamBuilder` crudos; preservar `dispose()` de controllers y `_markAsReadBestEffort`.
6. **Dark + light** ambos pulidos; **responsive** vía `presentation/shell/responsive.dart` (Coach Hub es desktop-only <768px → banner).
7. **Commits work-unit** (test + código mismo commit); commit incremental obligatorio; conventional commits sin AI attribution.
8. **Gate durante dev**: tests targeted de la sección + `flutter analyze` sin issues nuevos (baseline 42). Al cierre de batch: FULL `flutter test`.

---

## 6. Work Units (atómicos, secuenciales)

- **WU-01** — Evidencia BEFORE (harness + captura + commit).
- **WU-02** — Empty pane (sin selección) → `TreinoEmptyState`.
- **WU-03** — List pane: rediseño del row de conversación (tokens + unread badge + selección/hover).
- **WU-04** — List pane: estados del stream (StateSwitcher + shimmer + empty/error) + búsqueda cliente.
- **WU-05** — Detail pane: header (tokens; presencia/llamada fuera de scope).
- **WU-06** — Detail pane: lista de mensajes (StateSwitcher + shimmer + empty + separadores de fecha).
- **WU-07** — Burbuja de mensaje (tokens + radios + own sólido; media preservada).
- **WU-08** — Composer (estados enabled/disabled/sending + tokens + motion; adjuntar preservado).
- **WU-09** — Evidencia AFTER + gates full + commit del plan.

(Scopes autocontenidos completos en el JSON del reporte del planner.)

---

## 7. Riesgos

| ID | Riesgo | Mitigación |
|----|--------|-----------|
| R-1 | Duplicar suscripciones Firestore al rediseñar el detail pane | Regla 5: solo `ref.watch` de providers autoDispose; test de switch de chatId sin fugas |
| R-2 | Romper aserciones/keys de los tests V2/V3 de media | Preservar keys exactas; extender, no reescribir |
| R-3 | `TreinoStateSwitcher` sin keys distintas no anima / rompe layout | Regla 4: `ValueKey` por estado |
| R-4 | Tentación de fabricar UI sin backend (presencia, ticks, contador) | Sección 4: omitir explícito, UI honesta |
| R-5 | `TreinoFadeSlideIn` colado en `ListView.builder` (rows/burbujas) | Regla 4: prohibido; stagger solo eager |
| R-6 | Harness de evidencia con fuentes/red (ruido google_fonts) | Reusar patrón `coach_hub_biblioteca_evidence_test.dart` (runZonedGuarded) |
