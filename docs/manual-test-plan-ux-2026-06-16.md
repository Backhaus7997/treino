# Plan de pruebas manuales — Tandas UX HIGH (2026-06-16/17)

Casos para reproducir y verificar en device los 4 PRs stacked. **90 casos** derivados del diff real de cada PR.

| PR | Tanda | Casos | P0 | P1 | P2 |
|----|-------|------:|---:|---:|---:|
| #171 | Accesibilidad | 30 | 7 | 18 | 5 |
| #172 | Estados (loading/error/empty) | 20 | 6 | 12 | 2 |
| #174 | Usabilidad | 23 | 9 | 10 | 4 |
| #177 | Navegación | 17 | 6 | 8 | 3 |

## Setup (una vez)

1. **Emulador + seed**: `export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home` → `scripts/emulator.sh` → `npm --prefix scripts run seed:emulator` (3 coaches + 5 atletas con contenido).
2. **Launch pre-logueado** (dev bypass, sin tipear credenciales):
   - Atleta: `flutter run --dart-define=USE_EMULATOR=true --dart-define=DEV_AUTH=athlete`
   - Coach:  `flutter run --dart-define=USE_EMULATOR=true --dart-define=DEV_AUTH=coach`
3. App lockeada a **es-AR** → los textos esperados son los strings es-AR.
4. Para casos de **a11y**: activá **VoiceOver** (Ajustes > Accesibilidad > VoiceOver). El "resultado esperado" es lo que el lector de pantalla ANUNCIA.
5. Para casos de **error/estado**: para forzar fallos, **matá el emulador de Firestore** (o modo avión) y reintentá; reactivalo para probar el Reintentar.

> **Prioridad de revisión:** arrancá por los **P0** (behavioral / riesgo de datos), después P1. Los P2 son cosméticos/a11y menor.


# PR #171 — Accesibilidad (30 casos)


## P0

#### A11Y-01 — Auth circle back button announces "Volver" and is 44x44  `P0`

**Persona:** either · **Pantalla:** AuthCircleBackButton (Login / Register / Forgot Password)

**Setup:** Any account via dev bypass (athlete or coach). Enable VoiceOver: iOS Settings > Accessibility > VoiceOver > On. App locked to es-AR.

**Pasos:**
1. Navigate to a screen that shows the circular outlined back button at top-left (e.g. open Login or Register, or the Forgot Password screen from Login).
2. With VoiceOver enabled, swipe/drag focus onto the circular back button.
3. Listen to the announcement.
4. Then turn VoiceOver off and visually estimate / try to tap the circle: confirm the round button is comfortably tappable, not a tiny dot.

**Esperado:** VoiceOver announces "Volver" followed by the trait "botón" (button). The circle is rendered at 44x44 (bumped from 40), so it is a comfortable tap target with no accidental misses.

_Nota: This widget is shared by ForgotPassword, Login and Register, so it covers findings 0/2/3 in one place. Before this PR the InkWell+Icon had no Semantics and VoiceOver announced an unlabeled button; size was 40._

---

#### A11Y-07 — Chat: send button busy state announces "Enviando…"  `P0`

**Persona:** either · **Pantalla:** chat_screen.dart (_Composer send button)

**Setup:** Athlete in a chat thread. VoiceOver enabled. es-AR. Emulator running so a send actually round-trips.

**Pasos:**
1. Type a message into the composer.
2. Focus the send IconButton and confirm it announces "Enviar" while idle.
3. Double-tap to send and, during the brief in-flight moment, focus the spinner that replaces the icon.
4. Listen for the busy announcement.

**Esperado:** Idle: tooltip announces "Enviar" (l10n.chatScreenSendLabel). While sending: the control announces "Enviando…" (l10n.chatSendingA11y) and is reported disabled (Semantics enabled:false; tooltip also swaps to "Enviando…"). After send completes it returns to "Enviar".

_Nota: Behavioral state change made visible to AT. Before the PR the spinner had no label so the busy/disabled state was silent. The in-flight window is short — may need a slow network/emulator to catch it._

---

#### A11Y-09 — Athlete detail plan card edit/delete: labels + 44x44 targets  `P0`

**Persona:** coach · **Pantalla:** athlete_detail_screen.dart (_PlanCard)

**Setup:** Coach (DEV_AUTH=coach). Open an athlete who has at least one assigned plan (seed coaches have linked athletes with plans). VoiceOver enabled. es-AR.

**Pasos:**
1. Scroll to a plan card showing the edit (pencil) and delete (trash) icon buttons.
2. Focus the edit icon button; listen.
3. Focus the delete icon button; listen.
4. Turn VoiceOver off and try tapping each — confirm both are comfortably tappable and you do NOT accidentally hit delete when aiming for edit.

**Esperado:** Edit announces "Editar plan, botón" (l10n.athleteDetailEditPlanA11y). Delete announces "Eliminar plan, botón" (l10n.athleteDetailDeletePlanA11y). Both now have constraints minWidth:44/minHeight:44 (was BoxConstraints() which collapsed to ~18-24pt), so the adjacent destructive delete is no longer a fat-finger hazard.

_Nota: P0 because delete is destructive and the two buttons sit adjacent; the tap-target fix directly reduces data-loss risk._

---

#### A11Y-16 — Create post header: CANCELAR/PUBLICAR are labeled buttons; PUBLICAR announces "Publicando…"  `P0`

**Persona:** either · **Pantalla:** create_post_screen.dart (_CreatePostHeader)

**Setup:** Athlete on the create-post screen with enough content typed that PUBLICAR is enabled (state.canSubmit true). VoiceOver enabled. es-AR.

**Pasos:**
1. Focus CANCELAR; listen.
2. Focus the "NUEVO POST" title; confirm heading trait.
3. With the post incomplete (canSubmit false), focus PUBLICAR; listen for disabled state.
4. Complete the post so PUBLICAR enables, focus it; listen.
5. Double-tap PUBLICAR and during submit focus the spinner; listen.

**Esperado:** CANCELAR announces "Cancelar, botón" (l10n.commonCancel; visible glyph excluded). Title "NUEVO POST" announces with heading trait. PUBLICAR announces "Crear publicación, botón" and reports enabled/disabled per state.canSubmit. While submitting it announces "Publicando…" (l10n.feedPublishingA11y, liveRegion). Both header actions are wrapped to a 44pt min hit area.

_Nota: P0 because PUBLICAR is the primary submit action and its busy state was previously silent. Confirm the spinner branch doesn't change the control's tap-area size (ExcludeSemantics + ConstrainedBox keep it stable)._

---

#### A11Y-18 — Friend requests inbox: back button + ACEPTAR/RECHAZAR pills labeled and 44pt  `P0`

**Persona:** athlete · **Pantalla:** friend_requests_inbox_screen.dart + friend_request_inbox_tile.dart

**Setup:** Athlete with at least one incoming friend request (seed data). Open the friend requests inbox. VoiceOver enabled. es-AR.

**Pasos:**
1. Focus the header back control; listen, then confirm it's a comfortable tap target (now min 44x44, left-aligned).
2. Focus the RECHAZAR pill; listen.
3. Focus the ACEPTAR pill; listen.
4. Turn VoiceOver off and confirm both pills are >=44pt tall and you can hit either without overlapping the other.
5. Double-tap ACEPTAR and, while the request is in flight, focus a pill; confirm it's reported disabled.

**Esperado:** Back announces "Volver, botón" (l10n.commonBack) with a >=44pt hit box. RECHAZAR announces "RECHAZAR, botón" (l10n.dashboardRechazarLabel) and ACEPTAR announces "ACEPTAR, botón" (l10n.dashboardAceptarLabel); the visible Text is ExcludeSemantics. Pills are wrapped in ConstrainedBox(minWidth:44,minHeight:44) centered so visual size is unchanged. While _busy (onTap null) both announce as disabled.

_Nota: P0: ACEPTAR is irreversible and the two destructive/confirm pills were ~30pt tall and 8px apart (fat-finger risk). Semantics label is the localized action even though visible text is a styled literal._

---

#### A11Y-28 — Routine editor: icon-only controls labeled and 44pt (back, delete day, reorder, slot menu, set chip, set delete)  `P0`

**Persona:** either · **Pantalla:** routine_editor_screen.dart

**Setup:** Coach or athlete editing a routine (open the routine editor with at least one day, one slot with multiple sets, and multiple weeks). VoiceOver enabled. es-AR.

**Pasos:**
1. Focus the top back IconButton; listen.
2. Focus a day-header trash button; listen, then (VoiceOver off) confirm it's now a 44pt target.
3. Focus the reorder chevrons (_MoveButtons up/down); listen to each and confirm 44pt hit area.
4. Focus a slot overflow (⋮) control; listen.
5. Focus a set-type chip; listen for position + type + any warning.
6. Focus a set delete (close) button; listen.
7. Focus a week chip (Sem N), including one with a validation warning dot; listen for selected state and the warning.

**Esperado:** Back: "Volver" (tooltip commonBack). Day trash: "Eliminar día" (routineEditorDeleteDayA11y), now min 44x44 (was collapsed). Reorder chevrons: "Subir" / "Bajar" (routineEditorSlotMenuMoveUp / ...MoveDown) with 44x44 hit area, icons still 18px. Slot ⋮: "Opciones de rutina" (workoutRoutineOptionsA11y). Set chip: announces position + localized type (Normal/Calentamiento/Drop/Al fallo per routineEditorSetType*) + "Atención" when invalid, joined by ", ". Set delete: "Cerrar" (commonClose). Week chip announces as a selectable button with selected state; its warning dot announces "Atención" (commonWarning).

_Nota: Findings 24/25/26. P0 because this is the data-authoring surface with destructive (delete day / delete set) controls that were both unlabeled AND sub-44pt. Verify the move-chevron hit areas don't overlap awkwardly given they're side by side._

---

#### A11Y-29 — Session player: back, per-set check, technique info, timer, ABANDONAR labeled and 44pt  `P0`

**Persona:** athlete · **Pantalla:** session_player_screen.dart

**Setup:** Athlete in an active session (start a routine session). VoiceOver enabled. es-AR. Include at least one rep-based set and one duration-based set, and an exercise that has a technique note.

**Pasos:**
1. Focus the header back control; listen, then confirm it's a comfortable 44pt target (visual circle still 36px).
2. Focus a per-set check circle; listen, then double-tap to mark it done.
3. Focus the technique info (i) icon next to an exercise that has technique; listen.
4. On a duration set, focus the "Iniciar" timer control; listen, and confirm 44pt hit area.
5. Focus the ABANDONAR button; confirm it's tappable at >=44pt.

**Esperado:** Back: "Volver, botón" (commonBack), wrapped to min 44x44 around the 36px circle. Per-set check: "Marcar serie <n> como completada, botón" (sessionPlayerSetCompleteA11y(setNumber)), now a 44x44 box (was 32x32). Technique: "Ver técnica de <exerciseName>, botón" (sessionPlayerTechniqueA11y), now min 44x44. Timer: "Iniciar temporizador, botón" (sessionPlayerTimerStartA11y), min 44x44; visible label still "Iniciar". ABANDONAR now has minimumSize Size(0,44) (shrinkWrap removed).

_Nota: Finding 27. P0: the per-set check is the single most-tapped action in the whole flow and was both unlabeled and 32x32. Confirm the back button enlargement didn't break layout next to the title._

---


## P1

#### A11Y-02 — Login/Register top IconButton back announces "Volver"  `P1`

**Persona:** either · **Pantalla:** login_screen.dart / register_screen.dart (top IconButton)

**Setup:** Logged out is ideal, but with dev bypass start the app and from a screen push to /login or /register (e.g. Login screen's register link). VoiceOver enabled. es-AR.

**Pasos:**
1. Open the Login screen; if not visible, tap the register link to also reach Register.
2. Focus the top-left IconButton with the back chevron (the IconButton, distinct from the circle button in A11Y-01).
3. Listen to the announcement.

**Esperado:** VoiceOver announces "Volver, botón" (the tooltip l10n.commonBack is exposed as the semantic label). Activating it pops the route or goes home.

_Nota: PR added tooltip: l10n.commonBack to both screens' IconButton. Note login and register each render their own IconButton in addition to AuthCircleBackButton patterns._

---

#### A11Y-04 — Login "register" inline link is a 44pt button announced by name  `P1`

**Persona:** either · **Pantalla:** login_screen.dart (authLoginRegisterLink)

**Setup:** Login screen visible. VoiceOver enabled. es-AR.

**Pasos:**
1. Scroll to the bottom of the Login screen where the "¿No tenés cuenta? <register link>" row sits.
2. Focus the register link with VoiceOver.
3. Listen, then double-tap to activate.
4. Turn VoiceOver off and tap the link text — confirm the tappable area feels at least as tall as a finger (>=44pt), not just the glyph height.

**Esperado:** VoiceOver announces the exact visible register-link text (l10n.authLoginRegisterLink) with the trait "botón". Double-tap navigates to /register. The hit area is wrapped in a ConstrainedBox(minHeight: 44) so it is comfortably tappable.

_Nota: Previously a bare GestureDetector with glyph-height-only hit area and no button role._

---

#### A11Y-05 — Legal document title and section headings are navigable headings  `P1`

**Persona:** either · **Pantalla:** legal_document_screen.dart

**Setup:** Register screen visible. VoiceOver enabled. es-AR. Open a legal doc: tap the "Términos" link in the terms checkbox on Register (opens "Términos y Condiciones"; the "Política de Privacidad" link opens that doc).

**Pasos:**
1. With the legal document open, focus the big title at the top (e.g. "Términos y Condiciones").
2. Confirm VoiceOver announces it as a heading.
3. Use the VoiceOver rotor set to "Encabezados" (Headings) and flick down to jump between sections.
4. Confirm each bold section heading (e.g. the numbered/section headings in the doc) is reachable as a heading.

**Esperado:** The title announces "Términos y Condiciones, encabezado" (header trait). Each section.heading is also exposed as a heading, so the Headings rotor lets the user jump section-to-section through the long document instead of reading a flat paragraph run.

_Nota: Single biggest content-structure win in the PR. Use "Política de Privacidad" link for the other doc — same behavior._

---

#### A11Y-06 — Chat: back button labeled, peer avatar announced by name  `P1`

**Persona:** either · **Pantalla:** chat_screen.dart (app bar)

**Setup:** Athlete with an existing conversation (seed data: athletes/coaches with chat). Open a chat thread. VoiceOver enabled. es-AR.

**Pasos:**
1. In the chat app bar, focus the leading back IconButton.
2. Listen.
3. Then focus the peer's avatar in the app bar title.
4. Listen.

**Esperado:** Back button announces "Volver, botón" (tooltip l10n.commonBack). The avatar announces "Foto de perfil de <peer name>" with the image trait (a11yAvatarLabel(name)).

_Nota: Use the real peer display name from seed data in the expected announcement._

---

#### A11Y-10 — Trainers list: MAPA/LISTA and Presencial/Online expose selected state; disabled MAPA explains why  `P1`

**Persona:** athlete · **Pantalla:** trainers_list_screen.dart (_TogglePill, _ModeTab)

**Setup:** Athlete (DEV_AUTH=athlete). Open the trainers/coaches list screen. VoiceOver enabled. es-AR.

**Pasos:**
1. Focus the Presencial mode tab, then the Online mode tab; listen to each and note which is announced as selected.
2. Switch to Online mode.
3. Focus the MAPA toggle pill (which is disabled in Online mode); listen.
4. Switch back to Presencial; focus the MAPA and LISTA pills and listen to the selected state.

**Esperado:** Mode tabs announce as buttons with selected state ("seleccionado") for the active one. The toggle pills announce as buttons with selected state; the pill's icon is excluded from semantics and the visible label text supplies the name. When MAPA is disabled (Online mode), it announces "Mapa, no disponible en modo Online" (l10n.coachMapDisabledOnlineA11y) and is reported disabled, instead of a context-free disabled button.

_Nota: Covers finding 6. Group of toggle/tab Semantics changes verified together. Persona is athlete because athletes browse trainers._

---

#### A11Y-11 — Coach Hub login email/password offer Keychain autofill  `P1`

**Persona:** coach · **Pantalla:** coach_hub_login_screen.dart

**Setup:** Coach Hub web/login surface reachable. Best on a device/build where iOS Keychain/AutoFill is available (a saved credential helps). es-AR.

**Pasos:**
1. Open the Coach Hub login screen so the email and password TextFormFields are visible.
2. Tap into the Email field and observe the keyboard's QuickType / AutoFill bar.
3. Tap into the Contraseña (password) field and observe whether iOS offers a saved password / strong-password suggestion.

**Esperado:** The Email field advertises username/email autofill (AutofillHints.username + email) and the password field advertises password autofill (AutofillHints.password); both are inside an AutofillGroup, so iOS recognizes them as a credential pair and surfaces the AutoFill / saved-login affordance above the keyboard.

_Nota: Finding 8. Hard to assert on a bare emulator with no saved credentials — the observable is the AutoFill suggestion bar appearing. Watch for a regression: the PR added a nested AutofillGroup wrapping the Column inside the Form — confirm the form still submits and validates normally._

---

#### A11Y-12 — Coach Hub plan preview: warning icon labeled, athlete options are toggle buttons, assign target is 44pt  `P1`

**Persona:** coach · **Pantalla:** coach_hub_plan_preview_screen.dart

**Setup:** Coach uploading/previewing a plan that reaches the preview screen with at least one unmatched exercise and the athlete multi-select. VoiceOver enabled. es-AR.

**Pasos:**
1. On the unmatched warning banner, focus the warning triangle icon; listen.
2. Focus an "Asignar manualmente" control; turn VoiceOver off and confirm its vertical hit area is at least ~44pt (no longer a ~24pt sliver).
3. In the athlete selection list, focus an athlete row; listen and note the selected/unselected state, then double-tap to toggle and listen again.

**Esperado:** Warning icon announces "Atención" (semanticLabel l10n.commonWarning). The "Asignar manualmente" TextButton now has minimumSize Size(0,44) (shrinkWrap removed) so it is reliably tappable. Each athlete option (_AthleteOption) announces as a button with toggled state (MergeSemantics fuses the name; the check icon is excluded), and toggling flips the announced state.

_Nota: Covers findings 9 and 10. The athlete row uses Semantics(button:true, toggled:selected)._

---

#### A11Y-13 — Coach Hub dashboard: loading spinners and student avatars announced  `P1`

**Persona:** coach · **Pantalla:** coach_hub_dashboard_screen.dart

**Setup:** Coach with linked/pending/paused/terminated athletes (seed data). Open the Coach Hub dashboard. VoiceOver enabled. es-AR.

**Pasos:**
1. While a section is loading (or trigger a refresh), focus the section spinner; listen.
2. Focus a student tile avatar (active, paused, or terminated tile); listen.
3. On a pending request tile, double-tap Aceptar or Rechazar and, during the in-flight moment, focus the spinner that replaces the buttons; listen.

**Esperado:** Section loading spinner announces "Cargando…" (l10n.commonLoading, liveRegion). Each tile avatar announces "Foto de perfil de <name>" with the image trait. The pending-request busy spinner announces "Procesando…" (l10n.commonProcessing, liveRegion) so the action state is no longer silent.

_Nota: Group covering all four tile types (active/paused/terminated/pending) + section + inline spinners. Finding 7._

---

#### A11Y-14 — Coach Hub Alumnos roster renders (regression guard for routing change)  `P1`

**Persona:** coach · **Pantalla:** sections/alumnos/alumnos_screen.dart + routes.dart

**Setup:** Coach with linked athletes (seed data). Navigate to /alumnos in the Coach Hub. es-AR.

**Pasos:**
1. Open the Coach Hub and go to the Alumnos section (/alumnos).
2. Confirm the real roster renders (header "ALUMNOS", a "<n> en total · <n> activos" subtitle, filter chips Todos/Activos/Con deuda/Pausados/Inactivos, a search field, and a table of athlete rows).
3. Type a name into "Buscar por nombre…" and confirm the list filters.
4. Tap a filter chip and confirm counts/rows update.
5. On an active athlete row, tap the pause action and confirm the "Pausar vínculo" confirmation dialog appears.

**Esperado:** /alumnos now renders AlumnosScreen (the real roster), NOT the previous "Próximamente" placeholder. Search filters by name, chips partition the roster (Activos and Con deuda are disjoint), and the row pause/resume/terminate actions open their es-AR confirmation dialogs ("Pausar vínculo" / "Terminar vínculo").

_Nota: This is the one functional/routing change bundled into the tanda (the route swapped ProximamenteScreen for AlumnosScreen). Worth a behavioral smoke test even though strings here are flagged i18n: Fase W2. Not primarily an a11y case._

---

#### A11Y-15 — Feed header search and create-post are labeled 44pt buttons  `P1`

**Persona:** either · **Pantalla:** feed_screen.dart (_FeedHeader)

**Setup:** Athlete on the Feed tab. VoiceOver enabled. es-AR.

**Pasos:**
1. Focus the magnifier (search) icon in the feed header; listen, then double-tap.
2. Focus the round "+" create-post button; listen, then double-tap.
3. Turn VoiceOver off and tap each — confirm both feel comfortably tappable (>=44pt) even though the visible "+" circle is only 36pt.

**Esperado:** Search announces "Buscar, botón" (l10n.feedSearchA11y) and navigates to /feed/search. Create announces "Crear publicación, botón" (l10n.feedCreatePostA11y) and navigates to /feed/create. Both are wrapped in ConstrainedBox(minWidth:44,minHeight:44) with the visual icon centered inside.

_Nota: Finding 11. Both were bare GestureDetector + Icon with no label and sub-44 hit area._

---

#### A11Y-17 — Create post: privacy pills are 44pt toggle buttons; routine stub icon decorative  `P1`

**Persona:** either · **Pantalla:** create_post_screen.dart (_PrivacyPill, _RoutineTagStubChip)

**Setup:** Athlete on create-post screen. VoiceOver enabled. es-AR.

**Pasos:**
1. Focus each privacy pill; listen to its label and selected state, then double-tap to select another and re-listen.
2. Turn VoiceOver off and confirm each pill is at least ~44pt tall to tap.
3. Focus the "ETIQUETAR RUTINA" stub chip and confirm the dumbbell icon is not separately announced.

**Esperado:** Each privacy pill announces its visible label with button role and selected state ("seleccionado" for the active one), enabled per isEnabled; the visible label text is excluded so it isn't double-read. Pills are wrapped in ConstrainedBox(minHeight:44). The dumbbell icon on the routine stub is ExcludeSemantics so only "ETIQUETAR RUTINA" is announced.

_Nota: Findings 12/13. Pill visual size unchanged; only hit area expanded._

---

#### A11Y-19 — Public profile: hero avatar named, message stub disabled-labeled, load states announced  `P1`

**Persona:** athlete · **Pantalla:** public_profile_screen.dart

**Setup:** Athlete viewing another user's public profile (seed friend). VoiceOver enabled. es-AR.

**Pasos:**
1. While the profile loads, focus the spinner; listen.
2. Once loaded, focus the hero avatar; listen.
3. Focus the disabled MENSAJE button; listen.
4. To check the error path, open a profile that fails to load (e.g. invalid/blocked uid) and focus the error text; listen.

**Esperado:** Loading spinner announces "Cargando…" (l10n.commonLoading). Hero avatar announces "Foto de perfil de <displayName>" with image trait. MENSAJE stub announces "Mensaje (próximamente), botón" and is reported disabled (Semantics enabled:false, inner subtree excluded). Error state announces (liveRegion) and displays "No pudimos cargar este perfil." (l10n.publicProfileLoadErrorA11y).

_Nota: Finding 16. Error text is now both the live-region label and the visible string (previously a hardcoded literal that wasn't flagged as an alert)._

---

#### A11Y-20 — Search users: back and clear-field are labeled 44x44 buttons  `P1`

**Persona:** athlete · **Pantalla:** search_users_screen.dart

**Setup:** Athlete on the user search screen (/feed/search). VoiceOver enabled. es-AR.

**Pasos:**
1. Focus the header back control; listen, then confirm it's a comfortable tap target.
2. Type text into the search field so the clear (x) icon appears.
3. Focus the clear icon; listen, then double-tap and confirm the field clears.

**Esperado:** Back announces "Volver, botón" (l10n.commonBack) inside a 44x44 SizedBox. The clear button announces "Limpiar búsqueda, botón" (l10n.searchUsersClearA11y) inside a 44x44 box and clears the field when activated.

_Nota: Finding 17. Both were ~18-20pt unlabeled GestureDetectors._

---

#### A11Y-21 — Home header avatar announced by name (or generic when unknown)  `P1`

**Persona:** either · **Pantalla:** home_header.dart + home_screen.dart skeleton

**Setup:** Athlete or coach on the Home screen. VoiceOver enabled. es-AR.

**Pasos:**
1. While the header is still resolving (cold start), focus the 56px header skeleton area; listen.
2. Once the profile loads, focus the avatar; listen.
3. If testing an account with no display name, confirm the fallback announcement.

**Esperado:** During load the skeleton announces "Cargando…" (l10n.commonLoading, liveRegion) instead of a silent empty surface. Loaded avatar announces "Foto de perfil de <displayName>" (a11yAvatarLabel) with image trait; when displayName is null/empty it announces "Foto de perfil" (a11yAvatarLabelGeneric).

_Nota: Finding 18 (avatar) + loading skeleton. The skeleton announcement window is brief on a warm start._

---

#### A11Y-23 — Trainer home bell badge announces pending-request count  `P1`

**Persona:** coach · **Pantalla:** trainer_dashboard_tab.dart (_BellWithBadge)

**Setup:** Coach (DEV_AUTH=coach) with N pending requests (seed data). On the trainer home/dashboard header. VoiceOver enabled. es-AR.

**Pasos:**
1. Focus the bell icon with the badge in the trainer header.
2. Listen to the announcement.
3. Note the number against the visible badge count.

**Esperado:** The bell announces "<count> solicitudes pendientes" (l10n.homePendingRequestsA11y(count)) where count matches the visible badge; the inner Stack (bell icon + numeric badge) is ExcludeSemantics so the count is conveyed only once via the parent label, not as a stray visual number.

_Nota: Finding 18 (bell). The whole stack is wrapped Semantics(label:...) > ExcludeSemantics(Stack)._

---

#### A11Y-24 — Profile screen: headings, avatar identity merge, labeled tiles, decorative dividers  `P1`

**Persona:** athlete · **Pantalla:** profile_screen.dart (_AthleteProfile)

**Setup:** Athlete on the Profile tab. VoiceOver enabled. es-AR.

**Pasos:**
1. Use the VoiceOver Headings rotor and flick down: confirm the profile header block and each section title (ENTRENAMIENTO, SESIÓN) are reachable as headings.
2. Focus the avatar card; listen — confirm it reads as one identity node with the name, not an empty image node.
3. Focus the "Mis ejercicios" tile; listen and confirm button role.
4. Focus "Cerrar sesión" and "Eliminar cuenta" tiles; listen.
5. Within a stats row, focus a stat; confirm value+label read as one unit. Confirm the thin stat dividers are never focused.

**Esperado:** Header block and each section title announce with heading trait. Avatar card (MergeSemantics) announces the user's name/handle/gym as a single node. Tiles announce: "Mis ejercicios, botón"; "Cerrar sesión, botón" (l10n.authProfileSignOut); "Eliminar cuenta, botón" (l10n.eliminarCuentaSheetTitle) — each with the chevron/raw text subtree excluded so only one clean label is read. Each stat reads as one merged unit (e.g. "143 SESIONES"). Stat dividers and section hairline dividers are ExcludeSemantics and never focused.

_Nota: Finding 19. _A11ySectionGroup is a visual-identical in-file replacement for ProfileSectionGroup that allows Semantics-wrapped tiles. Watch for visual drift: padding/border/divider alphas must look byte-for-byte identical to before._

---

#### A11Y-25 — Workout back buttons (exercise detail, routine detail, my exercises, custom editor) labeled "Volver"  `P1`

**Persona:** either · **Pantalla:** exercise_detail_screen / routine_detail_screen / my_exercises_screen / custom_exercise_editor_screen

**Setup:** Athlete. VoiceOver enabled. es-AR. Reach each screen: open an exercise detail, a routine detail, My Exercises (from Profile > ENTRENAMIENTO > Mis ejercicios), and the custom exercise editor (add/edit a custom exercise).

**Pasos:**
1. On each of the four screens, focus the back affordance (floating circle on detail screens; header control on My Exercises / custom editor).
2. Listen to each announcement.
3. On My Exercises and custom editor, turn VoiceOver off and confirm the back control is a comfortable tap target (now IconButton / 44pt-constrained, not a bare 20px icon).

**Esperado:** All four announce "Volver, botón" (l10n.commonBack via tooltip on IconButton or Semantics label on the wrapped GestureDetector). My Exercises back is now an IconButton (44pt + canPop fallback to /profile); custom editor back is wrapped to min 44x44.

_Nota: Findings 15/20/21/22. Grouped representative case for the four near-identical back-button fixes._

---

#### A11Y-27 — Post-workout summary: close button labeled, mood emojis excluded  `P1`

**Persona:** athlete · **Pantalla:** post_workout_summary_screen.dart

**Setup:** Athlete who just finished a session and lands on the post-workout summary (or deep-link to it). VoiceOver enabled. es-AR.

**Pasos:**
1. Focus the top-right close (X) IconButton; listen.
2. Swipe through the mood emoji row (😞 😕 😐 🙂 😄) and observe whether each emoji is announced individually.

**Esperado:** Close announces "Cerrar, botón" (l10n.commonClose). The mood emoji row is wrapped in ExcludeSemantics, so VoiceOver does NOT read the five emoji names in sequence — the decorative, non-interactive row is skipped entirely.

_Nota: Finding 23. Previously VoiceOver read raw emoji names like "disappointed face" with no meaning._

---


## P2

#### A11Y-03 — Login TREINO logo is hidden from VoiceOver (decorative)  `P2`

**Persona:** either · **Pantalla:** login_screen.dart (TreinoLogo)

**Setup:** Login screen visible. VoiceOver enabled. es-AR.

**Pasos:**
1. On the Login screen, with VoiceOver on, swipe right repeatedly from the back button through the header area.
2. Observe whether focus ever lands on the TREINO brand mark / logo.

**Esperado:** VoiceOver SKIPS the logo entirely — it never gains focus and is not announced (wrapped in ExcludeSemantics). Focus moves from the back button straight to the headline text. The adjacent headline still reads normally.

_Nota: Decorative-icon exclusion. Logo conveys nothing the headline doesn't._

---

#### A11Y-08 — Chat empty conversation uses localized title (no hardcoded literal)  `P2`

**Persona:** either · **Pantalla:** chat_screen.dart (_ConversationEmpty)

**Setup:** Athlete opens a chat thread that has zero messages. es-AR. VoiceOver optional.

**Pasos:**
1. Open a conversation with no messages yet.
2. Read the empty-state title under the chat icon.

**Esperado:** The empty-state title renders l10n.chatListEmptyTitle (localized), NOT the previous hardcoded "Sin mensajes todavía" literal. Verify the displayed string matches the es-AR value of chatListEmptyTitle.

_Nota: PR replaced a hardcoded Spanish literal with the l10n key. Confirm copy didn't visibly change for es-AR if the key value equals the old literal._

---

#### A11Y-22 — Home decorative icons (streak flame, status dot) skipped by VoiceOver  `P2`

**Persona:** either · **Pantalla:** esta_semana_card.dart

**Setup:** Athlete on Home. To see the streak flame, reach the EstaSemana empty state (no sessions this week). VoiceOver enabled. es-AR.

**Pasos:**
1. In the EstaSemana card empty state, swipe through with VoiceOver and observe whether the large flame icon ever gets focus.
2. On the card header, swipe through and observe whether the small colored status dot gets focus.

**Esperado:** Both the 64px streak flame and the 8px status dot are wrapped in ExcludeSemantics, so VoiceOver never focuses or announces them; only the surrounding text is read.

_Nota: Decorative-exclusion group. Pairs with the trainer bell-badge label tested in A11Y-23._

---

#### A11Y-26 — My Exercises: header heading, decorative empty icon, card reads as one button  `P2`

**Persona:** either · **Pantalla:** my_exercises_screen.dart (_ExerciseCard, _EmptyState)

**Setup:** User with at least one custom exercise (and try an empty library too). VoiceOver enabled. es-AR.

**Pasos:**
1. Confirm the "MIS EJERCICIOS" header is reachable via the Headings rotor.
2. With an empty library, swipe through and confirm the sparkle icon is not focused.
3. With at least one exercise, focus an exercise card; listen.
4. If the exercise has a video, note the play icon is not separately announced.

**Esperado:** "MIS EJERCICIOS" announces with heading trait. The empty-state sparkle icon is ExcludeSemantics (skipped). Each exercise card announces as one button with label = name plus muscle group joined by ", " (e.g. "Press banca, Pecho, botón"); the inner row (texts + play/forward icons) is ExcludeSemantics so it isn't re-read.

_Nota: Card label is built as [name, if(muscleGroup) muscleGroup].join(', ')._

---

#### A11Y-30 — Workout list: routine overflow menu labeled; completed/template icons decorative  `P2`

**Persona:** athlete · **Pantalla:** mis_rutinas_section / historial_section / trainer_templates_section

**Setup:** Athlete on the Workout tab with at least one of: a user routine card (has ⋮ overflow), a completed history item, and a trainer template card. VoiceOver enabled. es-AR.

**Pasos:**
1. Focus the ⋮ overflow on a user routine card; listen, then double-tap and confirm the menu opens.
2. In Historial, swipe through a completed item and observe whether the green check icon is focused.
3. On a trainer template card, swipe through and observe whether the tinted workout-icon square is focused.

**Esperado:** The routine overflow PopupMenuButton announces "Opciones de rutina, botón" (tooltip workoutRoutineOptionsA11y) and opens its menu. The Historial completed check icon and the trainer-template tinted icon square are ExcludeSemantics, so VoiceOver skips them and reads only the surrounding routine text.

_Nota: Finding 29. Decorative-exclusion + overflow-label group._

---


# PR #172 — Estados (loading/error/empty) (20 casos)


## P0

#### STATES-01 — Failed set-write in active session shows SnackBar + Reintentar WITHOUT destroying the session  `P0`

**Persona:** athlete · **Pantalla:** Session player (session_player_screen.dart)

**Setup:** DEV_AUTH=athlete against the Firebase emulator with seed data. The athlete must have at least one routine assigned. Start a workout session from /workout so the session player is open with the timer running.

**Pasos:**
1. Begin a set: enter reps/weight for the current exercise and let the rest timer start so the elapsed timer is visibly counting.
2. Note the current SETS count and the elapsed timer value.
3. Kill the Firestore emulator (or turn the phone OFF network / enable Airplane mode) so the next write fails.
4. Tap the check/confirm icon to log the set.
5. Observe the screen for the SnackBar and confirm the session UI is intact.
6. Restore connectivity (restart the Firestore emulator / turn network back ON).
7. Tap 'Reintentar' in the SnackBar before it dismisses (it stays 6 seconds; re-trigger another failed+restored log if it disappeared).

**Esperado:** A floating SnackBar appears with the text 'No pudimos guardar la serie. Reintentá.' and an action button labelled 'Reintentar'. CRITICALLY: the session is NOT destroyed — the elapsed timer keeps running, previously logged sets remain, the stat grid stays, and the player does NOT flip to a full-screen error. The just-attempted set stays un-logged/interactive (SETS count unchanged). After connectivity returns, tapping 'Reintentar' re-dispatches the same set write; it now succeeds, the set logs, and the SETS count increments by one.

_Nota: This is the highest-risk fix. Before, logSet failures were swallowed in try/finally — the check icon silently never filled and the user believed the set was logged. The notifier deliberately emits via a separate ValueNotifier channel (NOT AsyncError) precisely so a single failed set does not route when() into its error branch and wipe the active session. Also verify editing the weight/reps of an already-done set (updateSet) under a failed write produces the same SnackBar; on retry it persists the edit._

---

#### STATES-02 — Finish session with failed write shows Reintentar and does NOT strand the user on a frozen player  `P0`

**Persona:** athlete · **Pantalla:** Session player — finish flow (session_player_screen.dart / session_notifier.dart)

**Setup:** DEV_AUTH=athlete, emulator + seed. Open the session player and log EVERY set of the routine so the session is fully completed (the finish/LISTO action becomes enabled — onPressed is gated on state.isFullyCompleted).

**Pasos:**
1. Confirm the timer is running and all sets are logged.
2. Kill the Firestore emulator (or Airplane mode ON) so the finish write fails.
3. Tap the finish button to end the session.
4. Observe the screen and the timer.
5. Restore connectivity (restart emulator / network ON).
6. Tap 'Reintentar' in the SnackBar.

**Esperado:** Navigation to the summary does NOT happen. A floating SnackBar appears: 'No pudimos finalizar la sesión. Probá de nuevo.' with a 'Reintentar' action. The player stays usable — the timer is NOT frozen-dead, the finish button is tappable again (the internal _finalized flag was reset and _isFinalizing cleared), and the user is not trapped. After connectivity returns, tapping 'Reintentar' re-runs finishSession; it succeeds and the app navigates to /workout/session-summary/<sessionId>.

_Nota: Before this fix, finishSession cancelled the timer BEFORE awaiting the Firestore write; a throw left _isFinalizing=true with no navigation → frozen timer, dead session, no recovery. The notifier now resets _finalized and rethrows on write failure, and the player catches it. Data-risk P0._

---

#### STATES-03 — Abandon session with failed write shows Reintentar and keeps the session alive  `P0`

**Persona:** athlete · **Pantalla:** Session player — abandon flow (session_player_screen.dart)

**Setup:** DEV_AUTH=athlete, emulator + seed. Open the session player with the timer running (does not need to be fully completed).

**Pasos:**
1. Trigger abandon (tap the back/close/abandon control that opens the abandon-confirm dialog).
2. Confirm abandon in the dialog.
3. With the emulator killed / Airplane mode ON beforehand so the write fails, observe the screen.
4. Restore connectivity.
5. Tap 'Reintentar' in the SnackBar.

**Esperado:** The player does NOT navigate to /workout. A floating SnackBar shows 'No pudimos finalizar la sesión. Probá de nuevo.' with a 'Reintentar' action (same copy as finish). The session/timer stays alive and the user is not stranded; _isFinalizing is reset so the controls work again. After connectivity is restored, 'Reintentar' re-runs abandonSession successfully and the app navigates to /workout.

_Nota: Set up Airplane mode / kill emulator BEFORE confirming abandon so the write fails on the first attempt. Same try/catch + _showFinishError pattern as finish; abandonSession also rethrows on write failure now._

---

#### STATES-04 — Splash surfaces an auth error with Reintentar instead of freezing on the brand screen  `P0`

**Persona:** either · **Pantalla:** Splash screen (splash_screen.dart)

**Setup:** App cold-start hitting /splash. To force the auth resolution to fail, kill the Firebase Auth emulator (or start with network OFF) so authNotifierProvider.future rejects during splash.

**Pasos:**
1. Launch the app cold so it lands on the TREINO splash.
2. With the Auth emulator down / network OFF, wait for auth resolution to fail.
3. Observe the area below the logo.
4. Restore connectivity (restart emulator / network ON).
5. Tap the 'Reintentar' button.

**Esperado:** While resolving, a small 22x22 accent-coloured CircularProgressIndicator shows below the logo (not a frozen, indicator-less brand screen). On auth failure, the spinner is replaced by the muted text 'Algo salió mal. Probá de nuevo.' and a 'Reintentar' TextButton. Tapping 'Reintentar' clears the error, re-shows the spinner, re-runs _navigate(), and once auth resolves the app hands off to the correct route (/home or /welcome).

_Nota: Before, _navigate() awaited authNotifierProvider.future with no try/catch — a rejected auth stream stranded the user on the splash forever. Hard to trigger reliably; killing the Auth emulator is the most direct lever._

---

#### STATES-05 — Publish a post shows a success SnackBar after returning to the feed  `P0`

**Persona:** athlete · **Pantalla:** Create post (create_post_screen.dart) + Feed

**Setup:** DEV_AUTH=athlete, emulator + seed, connectivity ON. Navigate to the feed and open the compose/create-post screen.

**Pasos:**
1. Write post content so the publish/submit control becomes enabled (state.canSubmit).
2. Tap the publish/submit control in the header.
3. Observe the transition back to the feed.

**Esperado:** The compose screen pops back to the feed AND a SnackBar with the text 'Post publicado.' is shown on the feed (delivered via the app-level ScaffoldMessenger captured before the await, so it survives the screen pop).

_Nota: Before, submit just popped with no confirmation, leaving the user with no trace that the post was created. The messenger + success copy are captured BEFORE the await precisely because context is unmounted after the pop._

---

#### STATES-06 — Save Datos personales and Gimnasio show success SnackBars; failed gym save shows an error instead of a silent dead-end  `P0`

**Persona:** either · **Pantalla:** Profile edit personal (profile_edit_personal_screen.dart) + Profile gym (profile_gym_screen.dart)

**Setup:** DEV_AUTH=athlete (or any account), emulator + seed, connectivity ON. Open Editar datos personales from the profile, then separately open the Gimnasio screen.

**Pasos:**
1. In Datos personales, change a field and tap save with connectivity ON.
2. Observe the SnackBar and that the screen pops.
3. Open the Gimnasio screen, pick a gym, and tap save with connectivity ON.
4. Observe the SnackBar and that the screen pops.
5. Re-open the Gimnasio screen, kill the Firestore emulator (or Airplane mode ON), pick a gym, and tap save.
6. Observe the result.

**Esperado:** Personal save (success): SnackBar 'Cambios guardados.' then the screen pops. Gym save (success): SnackBar 'Gimnasio actualizado.' then the screen pops. Gym save (failure): the screen does NOT pop, and a SnackBar shows 'No pudimos guardar el gimnasio. Probá de nuevo.' — the form stays editable so the user can retry.

_Nota: Before, both saves popped silently with no confirmation (indistinguishable from doing nothing), and the gym save had NO catch at all — a failed write left the user stranded with zero feedback and no pop. Also: if personal-save runs with no resolvable uid it now shows 'Algo salió mal. Probá de nuevo.' instead of failing silently._

---


## P1

#### STATES-07 — Feed segments show a localized load error with a working Reintentar that refetches  `P1`

**Persona:** athlete · **Pantalla:** Feed (feed_screen.dart) — AMIGOS / MI GYM / PÚBLICO segments

**Setup:** DEV_AUTH=athlete, emulator + seed. Be on the feed. Kill the Firestore emulator (or Airplane mode ON) so the feed FutureProviders fail.

**Pasos:**
1. With connectivity OFF, open (or re-enter) the feed so a segment provider errors.
2. Observe the error state on the AMIGOS segment.
3. Switch to MI GYM and PÚBLICO and confirm the same error treatment.
4. Restore connectivity (restart emulator / network ON).
5. Tap 'Reintentar'.

**Esperado:** Each errored segment shows centered muted text 'No pudimos cargar tu feed. Probá de nuevo.' with a 'Reintentar' TextButton below it. Because the feed providers are FutureProviders (they do NOT self-heal), the error persists until acted on. After connectivity returns, tapping 'Reintentar' invalidates that segment's provider (myFriendsFeedProvider / myGymFeedProvider / feedPublicProvider), the spinner shows, and the posts load.

_Nota: Before, all three error branches were a static sentence with NO retry, leaving the user permanently stuck until leaving and re-entering the tab. The three segments were de-duplicated into a shared _FeedAsyncBody._

---

#### STATES-08 — Accept/Reject friend request failure shows an error SnackBar instead of a silently unchanged row  `P1`

**Persona:** athlete · **Pantalla:** Friend requests inbox tile (friend_request_inbox_tile.dart) + Public profile follow button

**Setup:** DEV_AUTH=athlete, emulator + seed, with at least one incoming friend request in the inbox. Open the friend requests inbox.

**Pasos:**
1. Kill the Firestore emulator (or Airplane mode ON) so the accept write fails.
2. Tap ACEPTAR on an incoming request.
3. Observe the row and the screen.
4. Repeat tapping RECHAZAR on a request to confirm the same behaviour.
5. Restore connectivity and retry the action to confirm it now succeeds.

**Esperado:** On a failed accept or reject, the row stays in place (the stream emits no removal) AND a SnackBar shows 'No pudimos completar la acción. Probá de nuevo.' — the action is no longer silently swallowed. With connectivity restored, repeating the action succeeds and the row disappears.

_Nota: Before, both catch blocks were empty ('Swallow'), so a failed accept/reject left the user re-tapping a button that appeared to do nothing. The messenger is captured before the await so the SnackBar survives the tile's disposal on success._

---

#### STATES-09 — Public profile SEGUIR / ACEPTAR shows in-flight spinner and success/error SnackBars  `P1`

**Persona:** athlete · **Pantalla:** Public profile follow button (public_profile_follow_button.dart)

**Setup:** DEV_AUTH=athlete, emulator + seed. Open another user's public profile (/feed/profile/<uid>) where the pill reads 'SEGUIR' (not yet friends).

**Pasos:**
1. With connectivity ON, tap the 'SEGUIR' pill and watch the pill during the write.
2. Observe the SnackBar.
3. On a profile where you have an incoming request (pill reads 'ACEPTAR'), tap 'ACEPTAR' with connectivity ON.
4. Repeat 'SEGUIR' with the Firestore emulator killed / Airplane mode ON to force a failure.

**Esperado:** During the in-flight write the pill shows a small inline spinner in place of its leading icon and is disabled (cannot double-fire). On a successful SEGUIR, a SnackBar shows 'Solicitud enviada.' On a successful ACEPTAR, a SnackBar shows 'Ahora son amigos.' On a failed write, a SnackBar shows 'No pudimos completar la acción. Probá de nuevo.' and the pill returns to its prior state so the user can retry.

_Nota: Before, SEGUIR/ACEPTAR were fire-and-forget with no busy state and swallowed errors — a failed social write left the pill unchanged and the user assuming success. The unfriend (ELIMINAR) confirmation sheet also now surfaces the same error SnackBar on a failed delete._

---

#### STATES-10 — Coach Hub dashboard sections all surface load errors with Reintentar (pending queue no longer vanishes)  `P1`

**Persona:** coach · **Pantalla:** Coach Hub dashboard (coach_hub_dashboard_screen.dart)

**Setup:** DEV_AUTH=coach against the emulator + seed (coach with active/paused/terminated links and at least one pending request). Open the Coach Hub dashboard. Kill the Firestore emulator (or Airplane mode ON) so trainerLinksStreamProvider errors.

**Pasos:**
1. With connectivity OFF, open or refresh the dashboard so the links stream errors.
2. Inspect the ACTIVOS, PAUSADOS, HISTORIAL and the pending-requests sections.
3. Restore connectivity.
4. Tap 'Reintentar' on one of the error blocks.

**Esperado:** Every section (including the pending accept/decline queue) shows the error text 'No pudimos cargar esta sección.' with a 'Reintentar' TextButton — none of them silently collapses to empty. After connectivity returns, tapping 'Reintentar' invalidates trainerLinksStreamProvider and the sections load their data.

_Nota: Before, only ACTIVOS used full .when(); PAUSADOS/HISTORIAL/pending used maybeWhen+orElse:SizedBox.shrink(), so on a stream error they vanished entirely — the trainer saw a half-broken dashboard and the actionable pending queue disappeared with no signal._

---

#### STATES-11 — Availability editor: loading spinner, error+Reintentar, and save success/error SnackBars  `P1`

**Persona:** coach · **Pantalla:** Availability editor (availability_editor_screen.dart)

**Setup:** DEV_AUTH=coach, emulator + seed. Open the availability editor for the trainer.

**Pasos:**
1. Open the editor with connectivity ON and watch the initial load.
2. Kill the Firestore emulator (or Airplane mode ON) and re-open the editor so the rules/overrides streams error; observe the body.
3. Restore connectivity and tap 'Reintentar'.
4. With connectivity ON, open the add-rule sheet, fill it, and save; observe the SnackBar.
5. With the emulator killed mid-flow, open the add-rule (or block-day) sheet, fill it, and save; observe the SnackBar and the sheet.

**Esperado:** Initial load shows a centered accent CircularProgressIndicator (not the empty-state hints). On stream error the body shows 'No pudimos cargar los entrenadores.' with a 'Reintentar' OutlinedButton that invalidates both providers on tap. On a successful save the sheet shows SnackBar 'Horario guardado.' then pops. On a failed save the sheet STAYS OPEN and shows SnackBar 'No pudimos guardar. Probá de nuevo.' so the trainer can retry — it does NOT pop as if it succeeded.

_Nota: Before, valueOrNull ?? const [] collapsed loading AND error into the empty-state hints, and both save flows used catch(_){//ignore} then popped — the trainer believed availability was published when it was not, then athletes couldn't book. coachErrorLabel string is 'No pudimos cargar los entrenadores.'_

---

#### STATES-12 — Insights screen error shows a localized message with a working Reintentar  `P1`

**Persona:** athlete · **Pantalla:** Insights (insights_screen.dart)

**Setup:** DEV_AUTH=athlete, emulator + seed. Kill the Firestore emulator (or Airplane mode ON) so weeklyInsightsProvider errors. Open the Insights screen.

**Pasos:**
1. With connectivity OFF, open Insights so the provider errors.
2. Observe the error state.
3. Restore connectivity.
4. Tap 'Reintentar'.

**Esperado:** The error state shows centered muted text 'No pudimos cargar tus insights. Probá de nuevo.' with a 'Reintentar' TextButton beneath it. Tapping 'Reintentar' invalidates weeklyInsightsProvider; with connectivity restored the insights load.

_Nota: Before, the error branch was a static caption with no recovery affordance — a dead-end requiring the user to leave the screen._

---

#### STATES-13 — Create-post screen load error is a designed state with Reintentar (not raw 'Error: ...')  `P1`

**Persona:** athlete · **Pantalla:** Create post (create_post_screen.dart) — screen-level AsyncValue

**Setup:** DEV_AUTH=athlete, emulator + seed. Kill the Firestore emulator (or Airplane mode ON) so createPostNotifierProvider errors. Open the create-post screen from the feed.

**Pasos:**
1. With connectivity OFF, open the create-post screen so its provider errors.
2. Observe the error state, including the action buttons.
3. Tap 'CANCELAR' to confirm it returns to the feed.
4. Re-open, restore connectivity, and tap 'REINTENTAR'.

**Esperado:** The error state shows a warning icon, the message 'No pudimos abrir el editor. Probá de nuevo.', and two tappable actions: 'CANCELAR' (pops back to the feed) and 'REINTENTAR' (invalidates createPostNotifierProvider). With connectivity restored, 'REINTENTAR' loads the compose form. Loading state shows an accent spinner. No raw 'Error: <exception>' text is ever shown.

_Nota: Before, loading was a bare Material spinner and error rendered raw 'Error: $e' with no retry and no way back — a navigational dead-end. VoiceOver: the message is announced as a live region; the buttons announce 'Cancelar' and 'Reintentar' with 44x44 hit targets._

---

#### STATES-14 — Coach Hub 'not allowed' sign-out shows a spinner and an error on failure (web)  `P1`

**Persona:** either · **Pantalla:** Coach Hub not-allowed screen (coach_hub_not_allowed_screen.dart)

**Setup:** Coach Hub web build, signed in as an athlete (role != trainer) so the not-allowed screen is shown. Kill the Auth emulator (or network OFF) so signOut fails.

**Pasos:**
1. Tap the sign-out button ('Cerrar sesión') and watch the button.
2. With the Auth emulator down, observe the result after the failed sign-out.
3. Restore connectivity and tap sign-out again.

**Esperado:** While signing out, the button is disabled and shows an 18x18 spinner in place of its icon (no double-tap possible). On failure, an inline danger-coloured message 'No pudimos cerrar sesión. Probá de nuevo.' appears below the button and it becomes tappable again. On success (connectivity restored) the router redirects to /login. The button label reads 'Cerrar sesión'.

_Nota: Before, sign-out was fire-and-forget with no loading/disabled/error state — a slow or failing sign-out gave zero feedback and the user could tap repeatedly. Web-only screen; observable in the Coach Hub web target rather than on iPhone._

---

#### STATES-15 — Welcome screen surfaces social sign-in failures and shows a per-button spinner  `P1`

**Persona:** either · **Pantalla:** Welcome screen (welcome_screen.dart)

**Setup:** App on the Welcome screen (logged out). Use the Google or Apple social sign-in. To force an error, kill the Auth emulator / network OFF, or cancel the OAuth sheet.

**Pasos:**
1. Tap the Google (or Apple) social button and watch that button during the OAuth round-trip.
2. Cancel the OAuth sheet, or have the Auth emulator down so the call fails.
3. Observe the screen after the failure.

**Esperado:** While the tapped provider's OAuth call is in flight, that specific button swaps its brand glyph for a small spinner and the other auth controls (incl. the primary CTA) are disabled. On failure or cancellation, an AuthFailureBanner renders above the buttons (the error is no longer swallowed). On success the app navigates to /home.

_Nota: Before, social sign-in had NO error state and NO in-flight feedback — the user tapped Google and the UI did nothing visible, silently swallowing AuthFailure. Only the tapped provider shows the spinner (_pendingProvider scoping)._

---

#### STATES-16 — Forgot-password generic failure now renders the AuthFailureBanner  `P1`

**Persona:** either · **Pantalla:** Forgot password (forgot_password_screen.dart)

**Setup:** On the forgot-password screen (reachable from login). Kill the Auth emulator (or network OFF) so a non-AuthFailure error is thrown by sendPasswordResetEmail.

**Pasos:**
1. Enter an email address.
2. With the Auth emulator down / network OFF, tap 'ENVIAR LINK'.
3. Watch the spinner and the area where the banner renders.

**Esperado:** The spinner stops AND an AuthFailureBanner renders showing the generic failure (driven by AuthFailure.unknown('reset-failed')) — the form no longer looks idle as if nothing happened.

_Nota: Before, the generic catch(_) only reset _isLoading=false with no _failure set — the user tapped ENVIAR LINK, the spinner vanished, and there was zero feedback (silent dead-end). Verify the banner copy matches the AuthFailureBanner's rendering of an unknown failure._

---

#### STATES-17 — Post-workout summary disables COMPARTIR and shows a spinner while sharing  `P1`

**Persona:** athlete · **Pantalla:** Post-workout summary (post_workout_summary_screen.dart)

**Setup:** DEV_AUTH=athlete, emulator + seed. Complete a session so the post-workout summary (/workout/session-summary/<id>) is shown.

**Pasos:**
1. Tap the 'COMPARTIR' button.
2. Immediately watch the COMPARTIR button, the 'LISTO' button, and the close (X) control during the share.
3. Try tapping COMPARTIR again while it is in flight.

**Esperado:** While sharing (postWorkoutNotifierProvider.isLoading), the COMPARTIR button is disabled and shows a 16x16 accent spinner next to the text 'Cargando…'. The 'LISTO' button and the close (X) control are also disabled during the share, so the user cannot navigate away or double-submit. Once sharing completes the controls return to normal.

_Nota: Before, the screen never watched postWorkoutNotifierProvider — COMPARTIR stayed fully enabled with no feedback and could be tapped repeatedly, creating duplicate posts. LISTO label is 'LISTO', COMPARTIR is 'COMPARTIR', loading text is 'Cargando…'._

---

#### STATES-18 — Routine editor gives a SPECIFIC message for the first unmet requirement and scrolls to it  `P1`

**Persona:** either · **Pantalla:** Routine editor (routine_editor_screen.dart)

**Setup:** DEV_AUTH=athlete (self-creating) or coach. Open the routine editor for a NEW single-week routine.

**Pasos:**
1. Leave the name empty, add a day with no exercises, and tap the save/create button.
2. Read the SnackBar.
3. Type a routine name, then tap save again (a day still has no exercise).
4. Read the SnackBar and observe scrolling.
5. Add an exercise to that day but leave its set reps/duration blank, then tap save again.
6. Read the SnackBar.

**Esperado:** The save button is always tappable and the SnackBar names the FIRST unmet requirement in form-fill order: (1) no name → 'Poné un nombre a la rutina.' (no scroll); (2) name present but a day lacks an exercise → 'Agregá al menos un ejercicio al Día N.' and the editor expands and scrolls to that day; (3) exercise present but incomplete sets → 'Completá los sets de "<exercise>" antes de guardar.' (or 'Completá las reps de los sets antes de guardar.' when no exercise name is available), scrolling to the offending day.

_Nota: Before, single-week self-routines always got the generic incomplete-sets feedback regardless of the actual cause (name/exercise/sets), and the per-week warning only fired for non-selected weeks. Confirm the {dayNumber} placeholder resolves to a real number and {exerciseName} to the real exercise name._

---


## P2

#### STATES-19 — Empty states render where a screen previously looked half-rendered  `P2`

**Persona:** either · **Pantalla:** Athlete agenda (athlete_agenda_screen.dart) + Session detail (session_detail_screen.dart)

**Setup:** Emulator + seed. (a) DEV_AUTH=athlete with an account that has NO upcoming/booked sessions → open the agenda. (b) Open a past session detail (/workout/session/<id> or via Historial) for a session that has zero set logs.

**Pasos:**
1. Open the athlete agenda for an athlete with no upcoming sessions and look below the calendar.
2. Open a session detail for a session with zero logged sets and scroll past the stat grid.

**Esperado:** Agenda: below the calendar a centered calendar icon + muted text 'Tu PF todavía no te agendó sesiones.' is shown (no longer a blank tail). Session detail: where the exercise blocks would be, a centered muted message 'Esta sesión no tiene sets registrados.' is shown beneath the header/stats instead of an abruptly truncated screen.

_Nota: Both were missing empty states and read as broken/half-rendered screens. Lower risk (cosmetic correctness), hence P2; needs specific seed states to observe._

---

#### STATES-20 — Custom exercise editor (edit mode) shows loading/error states instead of degrading to a blank new form  `P2`

**Persona:** coach · **Pantalla:** Custom exercise editor (custom_exercise_editor_screen.dart)

**Setup:** DEV_AUTH=coach (trainer with at least one custom exercise), emulator + seed. Open an existing custom exercise in EDIT mode (so customExercisesForTrainerStreamProvider is read).

**Pasos:**
1. Kill the Firestore emulator (or Airplane mode ON) and open the editor in edit mode so the stream errors.
2. Observe the screen body (it should NOT be a blank editable form).
3. Restore connectivity and tap the retry button.
4. Separately, open in edit mode with connectivity ON and observe the brief loading state.

**Esperado:** In edit mode while loading: a centered accent spinner inside the editor scaffold (not empty fields with 'EDITAR/GUARDAR CAMBIOS' chrome). On error: an inline error state with a visible message 'No pudimos cargar esta sección.' and a 'Reintentar' button (routed through coachHubSectionLoadError + plantillasRetryLabel because coachError/coachRetry are blank in the English locale — but in es-AR both render). Tapping retry invalidates the stream and, with connectivity restored, hydrates the form.

_Nota: Before, edit mode read valueOrNull ?? [] so a loading/errored stream silently rendered an empty 'new' form, risking accidental overwrite/duplication. P2 because it requires trainer seed data and a forced error to observe; the retry label in es-AR is 'Reintentar'._

---


# PR #174 — Usabilidad (23 casos)


## P0

#### USABILITY-01 — Login bloquea email con formato invalido antes de la llamada de red  `P0`

**Persona:** either · **Pantalla:** lib/features/auth/presentation/login_screen.dart

**Setup:** App en pantalla de login (no usar el dev-bypass: lanzar con USE_EMULATOR=true SIN DEV_AUTH, o cerrar sesion para llegar al login). Locale es-AR.

**Pasos:**
1. En el campo de email escribir un texto sin arroba ni dominio, p.ej. 'tincho'.
2. En el campo de password escribir cualquier cosa, p.ej. '123456' (para que el boton no este deshabilitado por vacio).
3. Tocar el boton ENTRAR.

**Esperado:** El submit se BLOQUEA sin disparar ninguna llamada a Firebase (no aparece spinner de red ni el banner de error de servidor). Debajo del campo de email aparece el mensaje de validacion inline de EmailPasswordValidator.validateEmail. El foco permanece en el formulario.

_Nota: Antes del fix el login NO validaba formato: 'tincho' se mandaba a Firebase y el usuario solo se enteraba del error tras el round-trip (banner invalidEmail). El _formKey existia pero nunca se llamaba validate(). OJO: el campo de password sigue SIN validator propio (solo se gatea por vacio via _fieldsEmpty), asi que un password corto NO se bloquea client-side; solo el email._

---

#### USABILITY-04 — Setup de perfil paso 1: username ya tomado bloquea SIGUIENTE con 'Ese username ya esta en uso'  `P0`

**Persona:** athlete · **Pantalla:** lib/features/profile_setup/presentation/steps/step_1_username_avatar.dart

**Setup:** Atleta NUEVO (cuenta recien registrada, sin perfil completado) en el flujo de Profile Setup, paso 1 (Username + Avatar). IMPORTANTE: los handles seed tienen espacios/acentos (p.ej. 'Sofia Ramirez') y el validador de formato (^[a-zA-Z0-9_.]+$, 3-20 chars) los rechaza ANTES del chequeo de disponibilidad. Para forzar el estado 'taken' hay que crear previamente un usuario con un handle de un solo token ascii (p.ej. 'tincho') y luego intentar reclamarlo con otra cuenta nueva.

**Pasos:**
1. Con una cuenta nueva, en el campo username escribir un handle de formato valido que YA exista en la base (p.ej. 'tincho' previamente reclamado por otro usuario).
2. Esperar ~0.5s (debounce de 450ms) a que termine la verificacion async.

**Esperado:** Mientras consulta aparece la fila inline 'Verificando disponibilidad…' con spinner. Al resolver, aparece la fila roja (palette.danger) con icono de warning y el texto exacto 'Ese username ya esta en uso'. El boton SIGUIENTE queda DESHABILITADO (canGoNext es false para step 0 cuando availability != available/error).

_Nota: Feature nueva (finding 5/uniqueness). canGoNext de step 0 ahora exige draft.isStep1Valid Y (availability == available || error). Verificacion via UserPublicProfileRepository.isDisplayNameTaken (match exacto sobre displayNameLowercase). LIMITACION de test importante: ningun handle seed es reproducible por el campo porque todos tienen espacio; hay que sembrar un handle de un token para este caso._

---

#### USABILITY-05 — Setup de perfil paso 1: username libre muestra 'Username disponible' y habilita SIGUIENTE  `P0`

**Persona:** athlete · **Pantalla:** lib/features/profile_setup/presentation/steps/step_1_username_avatar.dart

**Setup:** Atleta nuevo en Profile Setup paso 1. Locale es-AR.

**Pasos:**
1. Escribir un username de formato valido y que NO exista en la base, p.ej. 'martin_test_99'.
2. Esperar a que termine la verificacion (debounce 450ms + query).

**Esperado:** Aparece 'Verificando disponibilidad…' con spinner y luego la fila en color accent con icono check y el texto exacto 'Username disponible'. El boton SIGUIENTE queda HABILITADO. Al tocarlo, avanza al paso 2.

_Nota: Happy-path de la feature de disponibilidad. Confirma que un handle libre es aceptado y desbloquea la navegacion._

---

#### USABILITY-08 — Home first-run: atleta sin rutina ve la tarjeta 'Arranca tu entrenamiento' en vez del workout falso  `P0`

**Persona:** athlete · **Pantalla:** lib/features/home/home_screen.dart

**Setup:** Atleta SIN rutina propia y SIN plan asignado. NOTA: la cuenta dev-bypass (seed-athlete-001) NO sirve: tiene vinculo activo con coach y una rutina asignada (assignedTo seed-athlete-001). Hay que usar una cuenta nueva/atleta seed sin rutinas ni assignments (userCreatedRoutines vacio Y assignedRoutines vacio).

**Pasos:**
1. Loguearse como el atleta sin rutina y llegar a Home.
2. Observar la tarjeta principal debajo del header de bienvenida.

**Esperado:** En lugar de la EmpezarEntrenamientoCard hardcodeada (que mostraba 'HOY · JUEVES', 'PUSH', '6 ejercicios', '~55 min'), se ve la _AthleteFirstRunCard con: titulo 'Arranca tu entrenamiento', cuerpo 'Crea tu primera rutina o busca un entrenador para empezar.', un CTA primario 'CREAR RUTINA' (con icono +) y un CTA secundario 'Buscar entrenador' (con icono de busqueda).

_Nota: Finding 6: era el mayor quiebre de credibilidad. hasNoRoutine solo es true cuando AMBOS providers (userCreatedRoutinesProvider y assignedRoutinesProvider) resolvieron a lista vacia; mientras cargan o erran, se sigue mostrando la card existente (sin flash de spinner). Verificar tambien que un atleta CON rutina o plan asignado sigue viendo la EmpezarEntrenamientoCard (no-regresion)._

---

#### USABILITY-11 — Editor de rutina: editar y tocar back muestra '¿Descartar cambios?'  `P0`

**Persona:** either · **Pantalla:** lib/features/workout/presentation/routine_editor_screen.dart

**Setup:** Abrir el editor de rutina (atleta: crear rutina nueva desde Home/Workout; coach: asignar/template). Editor recien abierto, sin tocar nada todavia.

**Pasos:**
1. Escribir un nombre en el campo de nombre de la rutina (esto marca _isDirty).
2. Opcional: agregar un dia o ejercicios.
3. Tocar la flecha de back del AppBar.

**Esperado:** Aparece un AlertDialog con titulo exacto '¿Descartar cambios?', cuerpo 'Si salis ahora vas a perder los cambios sin guardar.' y dos acciones: 'Cancelar' (textMuted) y 'Descartar' (en color danger). 'Cancelar' cierra el dialogo y mantiene al usuario en el editor con los cambios intactos. 'Descartar' sale del editor (pop o go a /workout o /coach segun el modo).

_Nota: Finding: era el paso mas danino (perdia minutos de trabajo sin aviso). _markDirty se dispara por el listener del nombre/split y por cada mutacion estructural (addDay, addWeek, removeSlot, reorder, replaceExercise, etc.). Verificar tambien que SIN editar nada, el back sale directo sin dialogo (_isDirty false)._

---

#### USABILITY-12 — Editor de rutina: gesto de swipe-back (iOS) tambien dispara el guard de descarte  `P0`

**Persona:** either · **Pantalla:** lib/features/workout/presentation/routine_editor_screen.dart

**Setup:** iPhone. Editor de rutina abierto con al menos un cambio (nombre escrito o dia agregado).

**Pasos:**
1. Hacer el gesto de swipe desde el borde izquierdo de la pantalla (edge-swipe-back nativo de iOS).

**Esperado:** El PopScope intercepta el pop implicito (canPop = !_isDirty) y, en vez de salir, aparece el mismo dialogo '¿Descartar cambios?'. Si se elige 'Cancelar', permanece en el editor; si 'Descartar', sale.

_Nota: Antes el swipe-back descartaba TODO sin aviso porque no habia PopScope/WillPopScope. onPopInvokedWithResult enruta el back de sistema por el mismo _confirmDiscard._

---

#### USABILITY-16 — Log de medicion: valor no numerico se rechaza inline (no se descarta en silencio)  `P0`

**Persona:** coach · **Pantalla:** lib/features/measurements/presentation/log_measurement_screen.dart

**Setup:** Coach (DEV_AUTH=coach) en el detalle de un atleta seed -> 'Nueva medicion' (log measurement). Locale es-AR.

**Pasos:**
1. En 'Peso (kg)' intentar escribir '7o' (siete + letra o) o '12.3.4'.
2. Observar que el teclado/formatter bloquea letras (FilteringTextInputFormatter permite solo [0-9.,]).
3. Forzar un valor que parsea mal (p.ej. '12.3.4', que el formatter deja pero double.tryParse rechaza) y tocar GUARDAR.

**Esperado:** Las letras no se pueden tipear (se filtran al ingresar). Para un valor con multiples separadores como '12.3.4', al tocar GUARDAR aparece el error inline bajo el campo: 'Ingresa un numero valido' (logFieldInvalidNumber) y el guardado se BLOQUEA. El valor no se descarta en silencio ni se muestra 'Medicion guardada'.

_Nota: Antes _parseDouble devolvia null silenciosamente y el SnackBar de exito mentia. Ahora hay Form + _validateMetric por campo._

---

#### USABILITY-19 — Log de medicion: GUARDAR deshabilitado con formulario vacio; no se persiste record nulo  `P0`

**Persona:** coach · **Pantalla:** lib/features/measurements/presentation/log_measurement_screen.dart

**Setup:** Coach en log measurement de un atleta seed, formulario recien abierto, todos los campos vacios.

**Pasos:**
1. Observar el boton GUARDAR sin cargar ningun dato.
2. Cargar un valor en cualquier campo (p.ej. Peso = '70') y observar GUARDAR.
3. Borrar ese valor y volver a observar GUARDAR.

**Esperado:** Con todos los campos vacios, GUARDAR esta DESHABILITADO (canSave = trainerUid != null && !_saving && _hasValue, y _hasValue es false). Al cargar un valor se habilita en vivo; al borrarlo vuelve a deshabilitarse. Si por carrera se intentara guardar vacio, aparece el SnackBar 'Completa al menos un dato antes de guardar' (logEmptyRecordWarning).

_Nota: Antes se podia guardar un record con todos los metrics null, que luego contaba como '1 medicion registrada' vacia. _hasValue se recomputa por listeners en todos los controllers._

---

#### USABILITY-20 — Log de evaluacion de rendimiento: valor invalido se rechaza inline y vacio deshabilita Guardar  `P0`

**Persona:** coach · **Pantalla:** lib/features/performance/presentation/log_performance_test_screen.dart

**Setup:** Coach (DEV_AUTH=coach) en el detalle de un atleta seed -> 'Nueva evaluacion' (log performance test). Locale es-AR.

**Pasos:**
1. Con el formulario vacio, observar el boton de Guardar.
2. En un campo (p.ej. CMJ) escribir '12.x.3' — confirmar que letras se filtran al tipear; forzar '12.3.4' (multiples separadores).
3. Tocar Guardar.

**Esperado:** Con el formulario vacio, Guardar esta DESHABILITADO (canSave = ... && _hasAnyMetric; _hasAnyMetric false). Las letras se filtran al ingresar (FilteringTextInputFormatter [0-9.,]). Un valor no parseable o <= 0 muestra inline 'Ingresa un numero valido' (profileEditPersonalWeightInvalidNumber) por la autovalidacion onUserInteraction, y el guardado se bloquea. Nunca se persiste una evaluacion sin metricas.

_Nota: Antes tryParse descartaba el valor en silencio y se guardaba 'Evaluacion guardada' con todo null. El Form usa AutovalidateMode.onUserInteraction, asi que el error aparece a medida que se escribe. _validateMetric rechaza tambien valores no positivos (<= 0)._

---


## P1

#### USABILITY-02 — Login con email valido + password no vacio pasa la validacion y procede  `P1`

**Persona:** either · **Pantalla:** lib/features/auth/presentation/login_screen.dart

**Setup:** Pantalla de login. Usar credenciales seed validas, p.ej. el email/password de un atleta seed (seed-athlete-001).

**Pasos:**
1. Escribir un email con formato valido (el del atleta seed).
2. Escribir el password correcto.
3. Tocar ENTRAR.

**Esperado:** La validacion de formato pasa (no aparece error inline bajo el email) y el login procede normalmente (spinner y luego Home). El cambio no rompe el happy-path.

_Nota: Caso de no-regresion del fix de validacion en login._

---

#### USABILITY-03 — Olvidaste tu contrasena bloquea email invalido antes de enviar el link  `P1`

**Persona:** either · **Pantalla:** lib/features/auth/presentation/forgot_password_screen.dart

**Setup:** Pantalla de login. Locale es-AR.

**Pasos:**
1. Tocar el enlace para recuperar contrasena y abrir la pantalla de forgot-password.
2. En el campo de email escribir un formato invalido, p.ej. 'tincho@' o 'abc'.
3. Tocar el boton ENVIAR LINK.

**Esperado:** El submit se BLOQUEA por la validacion inline (EmailPasswordValidator.validateEmail) y NO se dispara la llamada de reset. No aparece el estado de exito (_sent). El mensaje de validacion se muestra debajo del campo.

_Nota: Antes el estado de exito podia incluso enmascarar el error. Ahora _submit() hace `if (!(_formKey.currentState?.validate() ?? false)) return;` antes de la red. El form se envolvio en un Form con _formKey nuevo._

---

#### USABILITY-06 — Setup de perfil paso 1: formato invalido resetea disponibilidad a oculto y no consulta  `P1`

**Persona:** athlete · **Pantalla:** lib/features/profile_setup/presentation/steps/step_1_username_avatar.dart

**Setup:** Atleta nuevo en Profile Setup paso 1.

**Pasos:**
1. Escribir un username valido y libre y esperar a ver 'Username disponible'.
2. Agregar un caracter no permitido o un espacio, p.ej. 'martin test' o 'ab' (menos de 3 chars).

**Esperado:** La fila de estado de disponibilidad DESAPARECE (vuelve a SizedBox.shrink, estado unknown) en cuanto el formato es invalido, y aparece el error de formato del validator del campo (p.ej. 'Solo letras, numeros, "_" y "."' o 'Minimo 3 caracteres'). No se dispara consulta a Firestore. SIGUIENTE queda deshabilitado.

_Nota: updateUsername resetea a unknown cuando validateUsername != null e incrementa el token para descartar checks en vuelo (evita estado verde/rojo viejo)._

---

#### USABILITY-09 — Home first-run: CTA 'CREAR RUTINA' navega al editor de rutina  `P1`

**Persona:** athlete · **Pantalla:** lib/features/home/home_screen.dart

**Setup:** Atleta sin rutina viendo la _AthleteFirstRunCard en Home (ver USABILITY-08).

**Pasos:**
1. Tocar el boton 'CREAR RUTINA'.

**Esperado:** Navega (push) al editor de rutina propia, ruta '/workout/my-routine-editor'. Como es push, el back vuelve a Home.

_Nota: onPressed: () => context.push('/workout/my-routine-editor'). Antes el unico CTA (de la card falsa) iba a context.go('/workout') y no iniciaba nada real._

---

#### USABILITY-10 — Home first-run: CTA 'Buscar entrenador' navega a la pestana Coach  `P1`

**Persona:** athlete · **Pantalla:** lib/features/home/home_screen.dart

**Setup:** Atleta sin rutina viendo la _AthleteFirstRunCard en Home (ver USABILITY-08).

**Pasos:**
1. Tocar el boton 'Buscar entrenador'.

**Esperado:** Navega a la pestana/seccion Coach, ruta '/coach' (via context.go), donde el atleta explora y pide un entrenador.

_Nota: onPressed: () => context.go('/coach'). Es la segunda mitad del requisito de first-run: ambos CTAs deben navegar._

---

#### USABILITY-13 — Editor de rutina: guardar exitoso NO dispara el dialogo de descarte  `P1`

**Persona:** either · **Pantalla:** lib/features/workout/presentation/routine_editor_screen.dart

**Setup:** Editor de rutina con datos validos completos (nombre + al menos un dia con ejercicios), listo para guardar.

**Pasos:**
1. Tocar GUARDAR.
2. Esperar a que termine el guardado.

**Esperado:** El guardado persiste y el editor se cierra DIRECTAMENTE (pop/go) SIN mostrar '¿Descartar cambios?'. No hay falso positivo del guard tras un guardado exitoso.

_Nota: _submit() pone _isDirty = false al inicio para que el pop posterior no sea interceptado por el PopScope. Si el guardado FALLA (o se llega al cap de 10 rutinas), _isDirty se re-arma a true para reactivar el guard (probar la rama de error por separado si es posible)._

---

#### USABILITY-14 — Feed: pull-to-refresh recarga el segmento con contenido  `P1`

**Persona:** either · **Pantalla:** lib/features/feed/feed_screen.dart

**Setup:** Atleta seed con posts visibles en el feed (seed-athlete-001 tiene posts/amigos/gym). Estar en cualquier segmento con lista no vacia (Amigos, Mi Gym o Publico).

**Pasos:**
1. Con la lista de posts visible, deslizar hacia abajo desde el tope (pull-to-refresh).
2. Observar el indicador.

**Esperado:** Aparece un RefreshIndicator en color accent (palette.accent) y al soltar se re-ejecuta la query (ref.refresh del FutureProvider del segmento). La lista se actualiza al completar.

_Nota: Antes no habia ninguna forma in-screen de refrescar (los feeds son FutureProviders one-shot). Aplica a los tres segmentos: myFriendsFeedProvider, myGymFeedProvider, feedPublicProvider._

---

#### USABILITY-17 — Log de medicion: valor fuera de rango (>500) se rechaza con 'El valor esta fuera de rango'  `P1`

**Persona:** coach · **Pantalla:** lib/features/measurements/presentation/log_measurement_screen.dart

**Setup:** Coach en log measurement de un atleta seed.

**Pasos:**
1. En 'Peso (kg)' escribir un valor absurdo, p.ej. '9999'.
2. Tocar GUARDAR.

**Esperado:** Error inline bajo el campo: 'El valor esta fuera de rango' (logFieldOutOfRange) y el guardado se bloquea. El limite superior es 500 (_kMaxMetricValue) y el piso es 0; valores negativos tambien se rechazan.

_Nota: Guard de error-prevention, no rango clinico. Un peso/circunferencia real queda holgadamente bajo 500._

---

#### USABILITY-21 — CTA de PF: atleta con vinculo a OTRO entrenador ve la linea de ayuda explicando el bloqueo  `P1`

**Persona:** athlete · **Pantalla:** lib/features/coach/presentation/widgets/trainer_contact_cta_stub.dart

**Setup:** Atleta con un vinculo ACTIVO (o pending) con un entrenador (seed-athlete-001 tiene vinculo activo con seed-coach-001 'Lautaro P.'). Navegar al perfil/CTA de un entrenador DISTINTO del actual.

**Pasos:**
1. Abrir la ficha de un entrenador que NO sea el vinculado actual.
2. Observar el boton de contacto/CTA y el texto debajo.

**Esperado:** El boton primario aparece deshabilitado con el label 'YA TENES UN PF', y AHORA debajo hay una linea de ayuda (textMuted, centrada, con liveRegion para VoiceOver) con el texto: 'Solo podes tener un PF activo. Termina tu vinculo actual con {nombre} para pedir uno nuevo.' donde {nombre} es el displayName del PF actual (p.ej. 'Lautaro P.'); si no resolvio el nombre, usa el fallback 'tu Personal Trainer'.

_Nota: Finding: antes el CTA quedaba como boton deshabilitado 'YA TENES UN PF' sin explicacion ni salida. La linea solo aparece cuando blockedByOtherTrainer (existingLink.trainerId != trainerId que se mira). Si el atleta mira a SU propio PF vinculado, el label sigue siendo el de estado del vinculo sin la linea extra._

---

#### USABILITY-22 — Coach Hub preview de plan: salir tras mapear ejercicios manualmente pide confirmacion  `P1`

**Persona:** coach · **Pantalla:** lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart

**Setup:** Coach Hub (web/coach). Subir un plan que tenga ejercicios 'sin match' para llegar a la pantalla de preview con filas a resolver. (Si se prueba en iPhone aplica al back de sistema; en web al boton header).

**Pasos:**
1. En la preview, resolver al menos un ejercicio 'sin match' eligiendo uno en el bottom sheet (esto setea _hasManualMappings = true).
2. Tocar la flecha de back del header (o el back de sistema).

**Esperado:** Aparece un AlertDialog con titulo '¿Salir sin guardar el plan?', cuerpo 'Vas a perder los ejercicios que mapeaste manualmente.', accion 'Cancelar' (textMuted) y accion 'Salir igual' (danger). 'Cancelar' mantiene en la preview; 'Salir igual' navega a '/upload-plan'.

_Nota: Antes el back hacia context.go('/upload-plan') y se perdian todos los mapeos manuales (el plan vive en un provider autoDispose). El PopScope (canPop = !_hasManualMappings) enruta el back de sistema por el mismo _confirmDiscard. Si NO se mapeo nada manualmente, el back sale directo sin dialogo._

---


## P2

#### USABILITY-07 — Setup de perfil paso 1: al volver al paso con username precargado, la disponibilidad se re-verifica (no queda bloqueado)  `P2`

**Persona:** athlete · **Pantalla:** lib/features/profile_setup/presentation/steps/step_1_username_avatar.dart

**Setup:** Atleta nuevo en Profile Setup. Completar paso 1 con un username valido y avanzar al paso 2.

**Pasos:**
1. Desde el paso 2, tocar VOLVER para regresar al paso 1 (el campo ya viene precargado con el username).
2. Observar la fila de estado sin tocar el campo.

**Esperado:** Al re-entrar con username precargado se dispara la verificacion automaticamente (postFrameCallback -> updateUsername(initial)): se ve brevemente 'Verificando disponibilidad…' y luego 'Username disponible'. SIGUIENTE arranca habilitado en vez de quedar bloqueado en estado unknown.

_Nota: Sin este disparo, volver al paso dejaria canGoNext en false (unknown) aunque el handle sea valido. Es el fix del initState en step_1._

---

#### USABILITY-15 — Feed: pull-to-refresh funciona tambien sobre el estado vacio  `P2`

**Persona:** either · **Pantalla:** lib/features/feed/feed_screen.dart

**Setup:** Un segmento del feed en estado vacio. P.ej. el segmento Publico/Amigos sin posts, o una cuenta sin amigos para 'Amigos'.

**Pasos:**
1. Estando en el estado vacio (p.ej. 'Aun no hay posts de tus amigos'), deslizar hacia abajo desde el tope.

**Esperado:** El estado vacio es desplazable (envuelto en _scrollableEmptyState con AlwaysScrollableScrollPhysics) y el pull-to-refresh dispara el RefreshIndicator igual que con contenido. Los textos de vacio exactos son: 'Aun no hay posts de tus amigos' (Amigos), 'Todavia no estas en un gym' / 'Tu gym todavia no tiene posts' (Mi Gym), 'Aun no hay posts publicos' (Publico).

_Nota: Antes el FeedEmptyState era const y no scrollable, por lo que no se podia tirar para refrescar una lista vacia._

---

#### USABILITY-18 — Log de medicion: error en circunferencia colapsada fuerza apertura de la seccion  `P2`

**Persona:** coach · **Pantalla:** lib/features/measurements/presentation/log_measurement_screen.dart

**Setup:** Coach en log measurement. La seccion 'CIRCUNFERENCIAS' arranca colapsada.

**Pasos:**
1. Expandir la seccion de circunferencias, escribir un valor invalido en un campo (p.ej. 'Cintura' = '12.3.4').
2. Colapsar de nuevo la seccion.
3. Tocar GUARDAR.

**Esperado:** El guardado detecta el valor invalido en la seccion colapsada (_isMetricInvalid sobre los _circumferenceCtrls), fuerza la expansion de la seccion para que el error inline sea visible, y luego bloquea el guardado mostrando el error bajo el campo correspondiente. El error nunca queda renderizado fuera de pantalla.

_Nota: Los campos colapsados estan desmontados y Form.validate() los saltea; por eso el _save expande primero y espera un frame antes de validar._

---

#### USABILITY-23 — Feed: anuncio de accesibilidad del pull-to-refresh con VoiceOver  `P2`

**Persona:** either · **Pantalla:** lib/features/feed/feed_screen.dart

**Setup:** iPhone con VoiceOver ACTIVADO. Atleta seed con feed con contenido.

**Pasos:**
1. Activar VoiceOver.
2. Enfocar la lista del feed (el contenedor del RefreshIndicator).

**Esperado:** VoiceOver anuncia la etiqueta semantica 'Desliza para actualizar' (feedPullToRefreshA11y) sobre la region del RefreshIndicator.

_Nota: El RefreshIndicator quedo envuelto en Semantics(label: l10n.feedPullToRefreshA11y). Representa la cobertura a11y de este cambio; no hace falta un caso por cada segmento._

---


# PR #177 — Navegación (17 casos)


## P0

#### NAVIGATION-01 — Messages icon in feed header opens the chat inbox (MENSAJES)  `P0`

**Persona:** athlete · **Pantalla:** Feed header → ChatListScreen

**Setup:** Launch as athlete (--dart-define=USE_EMULATOR=true --dart-define=DEV_AUTH=athlete) against the seeded emulator. Land on the Feed tab (Inicio/social feed).

**Pasos:**
1. Look at the top-right of the Feed header row, to the left of the search (lupa) and create (+) icons.
2. Locate the chat/message icon (speech-bubble, TreinoIcon.chat).
3. Tap the chat icon.

**Esperado:** A new screen pushes in with a transparent AppBar titled 'MENSAJES' (uppercase, condensed font) and a back arrow on the left. The body shows either the list of the user's chats (avatar + name + last message preview + relative time per row) or, if the seed account has no chats, the empty state: icon + title 'Sin mensajes todavía' + body 'Cuando tengas un vínculo activo con un PF, vas a poder chatear desde acá.'

_Nota: Before this tanda ChatListScreen was registered nowhere and had NO in-app entry point — this is the fix for the dead-feature finding. The route is /feed/messages. Tapping a chat row pushes the 1-1 ChatScreen._

---

#### NAVIGATION-04 — Friend-requests bell with pending badge opens the inbox  `P0`

**Persona:** athlete · **Pantalla:** Feed header bell → Friend-requests inbox

**Setup:** Athlete who has at least one PENDING incoming friend request in seed data (e.g. another seeded athlete sent a request). Launch as athlete and land on Feed.

**Pasos:**
1. Look at the Feed header. Locate the bell icon (TreinoIcon.bell) — it is the first of the three header actions (bell, then chat, then search/lupa, then +).
2. Confirm a small accent-colored badge with a number sits at the top-right of the bell.
3. Tap the bell.

**Esperado:** The badge shows the pending count (or '9+' if more than 9). Tapping pushes the friend-requests inbox. Header reads 'Solicitudes de amistad' (the inbox header), and the list shows the pending request tile(s) with accept/reject affordances. The empty state, if reached, reads 'No hay solicitudes pendientes'.

_Nota: Before this tanda the inbox was only reachable via Profile → CUENTA → 'Solicitudes de amistad' tile; the send→receive→act loop from the social surface was broken. Route is /profile/friend-requests. VoiceOver announces 'Solicitudes de amistad, N pendientes' when count > 0 (feedFriendRequestsWithCountA11y)._

---

#### NAVIGATION-06 — Public profile (from search) now has a back button that returns  `P0`

**Persona:** athlete · **Pantalla:** SearchUsersScreen → PublicProfileScreen back

**Setup:** Athlete on Feed. Seed data has other users discoverable by search.

**Pasos:**
1. Tap the search (lupa) icon in the Feed header to open 'Buscar' users.
2. Type a query that matches a seeded user and tap a result row.
3. On the opened public profile, locate the back arrow (TreinoIcon.back) in the top-left AppBar.
4. Tap the back arrow.

**Esperado:** The public profile opens inside a transparent Scaffold+AppBar with a visible back arrow (tooltip 'Volver'). Tapping it pops back to the search results screen with the previous query intact. The profile content (hero avatar, follow + message-stub row, stats row, tab pills) still composites over the app background.

_Nota: Before this tanda public_profile_screen had NO Scaffold/AppBar and no back affordance — it was a navigational dead-end relying solely on the iOS edge-swipe. Route is /feed/profile/:uid pushed from search row._

---

#### NAVIGATION-09 — 'Ver todo' in the history section opens the full HISTORIAL list  `P0`

**Persona:** athlete · **Pantalla:** WORKOUT tab HistorialSection → SessionHistoryScreen

**Setup:** Athlete account that has at least one fully-completed finished session in seed data. Go to the Workout/Entreno tab and scroll to the bottom 'HISTORIAL' section.

**Pasos:**
1. In the HISTORIAL section header row, locate the accent-colored 'Ver todo' text button on the right of the 'HISTORIAL' heading.
2. Tap 'Ver todo'.

**Esperado:** A full-screen list pushes in with its own back arrow and header 'HISTORIAL' (uppercase). It lists ALL completed sessions (uncapped), each row showing a check icon, the routine name, the formatted date, the volume (e.g. '1200 kg') and duration (e.g. '45 min'). This is more entries than the 5-item cap shown inline.

_Nota: Before this tanda there was no /workout/historial list route — history was buried as the last inline section capped at 5. New screen: SessionHistoryScreen. Suffix strings are ' kg' and ' min'._

---

#### NAVIGATION-12 — 'Mis horarios' button in the coach AGENDA tab opens the availability editor  `P0`

**Persona:** coach · **Pantalla:** Coach AGENDA tab → availability editor

**Setup:** Launch as coach (--dart-define=USE_EMULATOR=true --dart-define=DEV_AUTH=coach) against the seeded emulator. Open the Coach module and select the 'AGENDA' tab (the second tab, next to 'ALUMNOS').

**Pasos:**
1. In the AGENDA tab, find the top action row: a wide 'NUEVA SESIÓN' button and, to its right, a circular outlined icon button with a clock icon (TreinoIcon.clock).
2. Long-press (or VoiceOver-focus) the clock button to confirm its tooltip reads 'Mis horarios'.
3. Tap the clock button.

**Esperado:** The availability editor pushes in, titled 'Mis horarios'. The trainer can configure bookable hours without leaving the AGENDA surface.

_Nota: Before this tanda the availability editor had NO entry point inside the AGENDA flow — the only path was Profile → 'Disponibilidad'. Route pushed is /coach/availability-editor?trainerId={uid}. The tooltip text comes from agendaEditorTitle ('Mis horarios')._

---

#### NAVIGATION-14 — Coach Hub web: browser Back from preview returns to upload with file state intact  `P0`

**Persona:** coach · **Pantalla:** Coach Hub web upload → preview navigation stack

**Setup:** Coach Hub is desktop-first WEB. Run the web build against the emulator and log in as a coach. Land on the Coach Hub dashboard (/dashboard).

**Pasos:**
1. Click 'IMPORTAR PLAN DESDE EXCEL' on the dashboard.
2. On the upload screen, pick/parse a valid seed Excel plan so it advances to the preview step (/upload-plan/preview).
3. Press the browser Back button (or trigger pop).

**Esperado:** The app returns to the upload step (/upload-plan) with the previously picked file still in state (the upload step shows the parsed file, not a blank picker). The dashboard→upload→preview transitions now use context.push, so Back pops one step at a time rather than replacing the location.

_Nota: Before this tanda the whole flow used context.go (no stack), so the browser Back button mid-flow was a dead-end / data-loss trap. This is the highest-risk behavioral change in the tanda — verify there is NO data loss and the back step is exactly the previous step, not a jump to dashboard._

---


## P1

#### NAVIGATION-02 — Chat inbox back arrow returns to the Feed  `P1`

**Persona:** athlete · **Pantalla:** ChatListScreen back affordance

**Setup:** Athlete on Feed; tap the messages (chat) icon in the header to open the 'MENSAJES' inbox.

**Pasos:**
1. On the MENSAJES screen, tap the back arrow in the top-left of the AppBar.

**Esperado:** The inbox closes and the user returns to the Feed tab with the feed scroll position intact. The bottom tab bar is back on the Feed tab.

_Nota: Back uses Navigator.maybePop(). The icon-only messages button itself has VoiceOver label 'Mensajes' (feedMessagesA11y)._

---

#### NAVIGATION-03 — Chat inbox row opens the 1-1 chat thread  `P1`

**Persona:** athlete · **Pantalla:** ChatListScreen → ChatScreen

**Setup:** Athlete account that has at least one existing chat in the seed data (a chat with their linked coach). Open Feed → messages icon → MENSAJES inbox showing at least one row.

**Pasos:**
1. Tap a chat row (avatar + name).
2. Observe the thread screen.
3. Tap back.

**Esperado:** The 1-1 ChatScreen for that conversation pushes over the inbox. Tapping back returns to the MENSAJES inbox (not directly to the Feed), because the row uses a nested Navigator.push.

_Nota: If the other user's profile was deleted, the row shows 'Usuario eliminado'. If a chat has never had a message it shows 'Iniciá la conversación' as the preview._

---

#### NAVIGATION-05 — Friend-requests bell shows NO badge when there are zero pending requests  `P1`

**Persona:** either · **Pantalla:** Feed header bell (empty state)

**Setup:** Account with NO pending incoming friend requests (e.g. a seeded account whose requests were already actioned, or a fresh state). Land on Feed.

**Pasos:**
1. Inspect the bell icon in the Feed header.
2. Tap the bell.

**Esperado:** No numeric badge is rendered on the bell (badge only appears when pendingRequestCount > 0). Tapping still opens the friend-requests inbox, which shows 'No hay solicitudes pendientes'.

_Nota: VoiceOver label with zero pending is the plain 'Solicitudes de amistad' (feedFriendRequestsA11y), not the count variant._

---

#### NAVIGATION-07 — Public profile back button returns to Feed when opened from a post author  `P1`

**Persona:** athlete · **Pantalla:** Feed post author → PublicProfileScreen back

**Setup:** Athlete on Feed with at least one post from another user visible in the seeded feed.

**Pasos:**
1. Tap a post author's name/avatar in the feed.
2. On the opened public profile, tap the AppBar back arrow.

**Esperado:** Public profile opens with the back arrow visible. Tapping back returns the user to the Feed. Note the feed author tap uses context.go (not push), so the back arrow falls back to context.go('/feed') rather than a pop — the observable result is still that the user lands back on the Feed surface.

_Nota: Edge case worth verifying: because the entry was a go() (no pushed stack), back uses the canPop()?pop():go('/feed') fallback. Confirm it does NOT leave the user stranded._

---

#### NAVIGATION-10 — 'Ver todo' is hidden when there is no completed history  `P1`

**Persona:** athlete · **Pantalla:** WORKOUT tab HistorialSection (empty)

**Setup:** Athlete account with ZERO fully-completed sessions (fresh seed athlete or one with only in-progress/abandoned sessions). Open the Workout tab and scroll to the HISTORIAL section.

**Pasos:**
1. Inspect the HISTORIAL section header row.

**Esperado:** Only the 'HISTORIAL' heading is shown; the 'Ver todo' button is NOT rendered (it appears only when completedCount > 0). The empty state for the section stays clean.

_Nota: Guards against an entry point to an empty list. If you force-navigate to /workout/historial directly with no completed sessions, the full screen shows the empty state: 'Todavía no entrenaste.' + a 'Empezar entrenamiento' text button._

---

#### NAVIGATION-11 — Full HISTORIAL list: back arrow returns and a row opens session detail  `P1`

**Persona:** athlete · **Pantalla:** SessionHistoryScreen back + row → detail

**Setup:** Athlete with completed sessions. Open Workout → HISTORIAL → 'Ver todo'.

**Pasos:**
1. Tap a session row in the full HISTORIAL list.
2. Observe the session detail screen, then tap back.
3. Back on the HISTORIAL list, tap the top-left back arrow (TreinoIcon.back, tooltip 'Volver').

**Esperado:** Tapping a row pushes the session detail (/workout/historial/{sessionId}). Back from detail returns to the HISTORIAL list. The list's back arrow then pops to the Workout tab (or falls back to /workout if no stack).

_Nota: Verifies the new screen's back affordance and that rows route to the existing :sessionId detail. The literal /workout/historial is declared before /workout/historial/:sessionId so the list resolves correctly._

---

#### NAVIGATION-13 — Availability editor back returns to the AGENDA tab  `P1`

**Persona:** coach · **Pantalla:** Availability editor back (push origin)

**Setup:** Coach in the AGENDA tab; tap the 'Mis horarios' clock button to open the availability editor.

**Pasos:**
1. On the availability editor ('Mis horarios'), tap the AppBar back arrow.

**Esperado:** The editor pops and the coach returns to the AGENDA tab (not to Profile), with the monthly calendar and the 'NUEVA SESIÓN' + clock action row still in place. This keeps 'configure when I'm bookable' and 'see/book my agenda' on one coherent surface.

_Nota: Because the editor is opened with context.push from the tab, pop returns to AGENDA. 'NUEVA SESIÓN' button still works as before (opens the new-session sheet) — confirm it was not broken by the new Row layout._

---

#### NAVIGATION-15 — Coach Hub web: preview 'Volver' and upload back arrow pop the stack  `P1`

**Persona:** coach · **Pantalla:** Coach Hub web in-app back buttons

**Setup:** Web build, coach logged in, dashboard → 'IMPORTAR PLAN DESDE EXCEL' → upload → parse file → preview step.

**Pasos:**
1. On the preview screen, trigger the in-app back action (the screen's volver/cancel affordance). If a leave-confirmation dialog appears, confirm leaving.
2. Back on the upload screen, click the header back arrow (tooltip 'Volver').

**Esperado:** The preview's back pops to the upload step (picked file retained), and the upload header back arrow pops to the dashboard. Both use canPop() ? pop() : go(fallback), so a normal in-flow back is a pop; only a deep-link with no stack falls back to go('/upload-plan' or '/dashboard').

_Nota: Confirm the preview back does NOT skip straight to dashboard, and that the upload header arrow returns to dashboard. If a 'leave' guard dialog shows, the navigation only happens after confirming._

---


## P2

#### NAVIGATION-08 — Public profile reachable from a friend-request tile and back works  `P2`

**Persona:** athlete · **Pantalla:** Friend-request tile → PublicProfileScreen back

**Setup:** Athlete with a pending incoming friend request (same seed as NAVIGATION-04). Open the friend-requests inbox via the bell.

**Pasos:**
1. Tap the avatar/name of a pending request tile (opens the requester's public profile).
2. Tap the back arrow on the public profile.

**Esperado:** The requester's public profile opens with a visible back arrow; tapping back pops to the friend-requests inbox.

_Nota: Tile pushes /feed/profile/{requesterId}; verifies the back button works regardless of entry surface._

---

#### NAVIGATION-16 — Coach Hub web: successful import still lands on the dashboard (terminal go)  `P2`

**Persona:** coach · **Pantalla:** Coach Hub web preview → dashboard on success

**Setup:** Web build, coach logged in. Dashboard → upload → parse a valid plan → preview. Select at least one athlete to assign.

**Pasos:**
1. Complete the assignment/import action on the preview screen.
2. Wait for the success transition.

**Esperado:** On success the app navigates to the dashboard (/dashboard). This terminal transition intentionally still uses context.go (not push), so the back stack does not contain the just-completed upload/preview steps.

_Nota: Verifies the tanda kept go() only for terminal transitions (login→dashboard, success→dashboard) while converting the in-flow steps to push. After success, browser Back should NOT re-enter the completed preview._

---

#### NAVIGATION-17 — VoiceOver announces the new feed header icon-only actions  `P2`

**Persona:** athlete · **Pantalla:** Feed header accessibility (bell + messages)

**Setup:** iPhone with VoiceOver ON. Athlete on Feed; use a state with at least 2 pending friend requests to exercise the count label.

**Pasos:**
1. Swipe to focus the bell icon in the Feed header and listen to the announcement.
2. Swipe to focus the messages (chat) icon and listen.
3. Double-tap each to confirm it activates as a button.

**Esperado:** The bell announces 'Solicitudes de amistad, 2 pendientes' (count variant) when there are pending requests, or 'Solicitudes de amistad' when none. The messages icon announces 'Mensajes'. Both are exposed as buttons (Semantics button: true) and have ≥44x44 hit targets.

_Nota: Collapses the new Semantics labels (feedFriendRequestsA11y, feedFriendRequestsWithCountA11y, feedMessagesA11y) into one representative a11y case. The only human-observable for a11y is what VoiceOver announces._

---
