# Proposal: coach-chat — Fase B (wire-up)

**Change**: Fase 5 · Etapa 5 — Wire-up del chat al ecosistema Coach
**Parent**: [propose.md](./propose.md) (Fase A — infrastructure + screens standalone)
**Branch**: `feat/coach-chat` (continuación, post-rebase) **o** `feat/coach-chat-wireup` (rama nueva chica)
**Owner**: Dev B
**Date**: 2026-05-21 (escrita anticipadamente; ejecuta cuando Dev A mergee Etapa 4)
**Depends on**: Fase A del chat (en working tree, sin commit) + **merge de Dev A Etapa 4 (Fase 5 — Plans mobile)** a main.

---

## 1. Why

Fase A entregó toda la infra del chat (modelo, repo, providers, screens, rules, indexes, tests) **sin conectarla a la UI existente**. Hoy un user puede tener un vínculo activo con un PF y los modelos / rules permiten chatear, pero **no hay forma de abrir el chat desde la app** porque los entry points viven en `athlete_coach_view.dart` y `trainer_coach_view.dart`, que Dev A iba a tocar en Etapa 4.

Fase B cierra el loop: agrega los botones "MENSAJE" en las cards de vínculo activo (ambos lados) + las rutas en GoRouter para navegar a `ChatScreen`.

---

## 2. What

### Production deliverables

**`lib/features/coach/athlete_coach_view.dart`** — botón "MENSAJE" en el `_LinkStateCard` variante active.
- Posición: dentro de la card del PF activo, al lado o debajo del botón "Terminar vínculo".
- Tap → resuelve `chatForLinkProvider(link)` → push a `/coach/chat/:chatId`.
- Solo visible cuando `link.status == TrainerLinkStatus.active`. No aparece para `pending`.
- Loading inline mientras `chatForLinkProvider` resuelve (primer tap puede crear el doc si no existe — typically <100 ms con el `getOrCreate` idempotente).

**`lib/features/coach/trainer_coach_view.dart`** — botón "MENSAJE" en el `_ActiveAlumnoCard` (tab ALUMNOS).
- Posición: al lado o debajo del botón "TERMINAR VÍNCULO".
- Misma lógica de tap.
- En la tab DASHBOARD NO se agrega botón a las pending request cards — chat solo arranca cuando el vínculo es active.

**`lib/app/router.dart`** — nueva sub-ruta bajo `/coach`:
- `/coach/chat/:chatId` → `ChatScreen(chatId: ..., otherUid: ...)`. El `otherUid` se deriva del `chatId` (split en `_` + remover el currentUid) — no se pasa como query param.
- La ruta vive **dentro** del ShellRoute (mantiene la bottom bar visible mientras se chatea, consistente con `/coach/trainer/:uid`).
- ⚠️ Decisión: SIN ruta para `ChatListScreen` en Fase B. La lista se accede vía deep link only por ahora — el botón directo en la card cubre el flow MVP. Iteración futura si surge necesidad real (trainer con >5 alumnos activos).

### Tests adicionales

- `test/features/coach/athlete_coach_view_test.dart` — extender:
  - Tap "MENSAJE" en active link card → llama a `chatRepositoryProvider.getOrCreate(...)` con uids correctos
  - Tap navega a `/coach/chat/:chatId` (verificable via `MockGoRouter` o `find.byType(ChatScreen)` con un router de test)
  - "MENSAJE" NO aparece cuando `link.status == pending`
- `test/features/coach/trainer_coach_view_test.dart` — extender:
  - Tap "MENSAJE" en `_ActiveAlumnoCard` → push correcto
  - Múltiples active alumnos → cada card tiene su propio botón
- `test/app/router_test.dart` (o similar) — verificar que `/coach/chat/:chatId` renderiza `ChatScreen` con el chatId del path.

**Estimado**: 6-8 tests nuevos.

### Smoke test plan (pre-push gate)

1. Login como athlete A, seleccionar seed-trainer-1 desde TrainersListScreen, tap "PEDIR VÍNCULO".
2. Login como seed-trainer-1 (via Firebase Console toggle de uid, o segundo dispositivo), tap "ACEPTAR" en DASHBOARD.
3. Login como athlete A → tab Coach muestra `_LinkStateCard` active con botón "MENSAJE" visible.
4. Tap "MENSAJE" → abre ChatScreen del athlete con AppBar mostrando el PF.
5. Escribir "hola pf" + tap send → mensaje aparece como burbuja propia abajo (alineada derecha, color accent).
6. Login como seed-trainer-1 → tab Coach → tab ALUMNOS → tap "MENSAJE" en la card del athlete A → abre ChatScreen.
7. Ver "hola pf" como burbuja entrante (izquierda, surface). Escribir "hola atleta" + send.
8. Volver al athlete → la burbuja "hola atleta" aparece en real-time (sin recargar manual).
9. Pop del chat → vuelve a `_LinkStateCard` con la bottom bar persistente.

---

## 3. How

### Wire-up athlete

```dart
// dentro de _LinkStateCard, variante active:
if (link.status == TrainerLinkStatus.active)
  OutlinedButton.icon(
    onPressed: () async {
      final chat = await ref.read(chatForLinkProvider(link).future);
      if (!context.mounted) return;
      context.push('/coach/chat/${chat.chatId}');
    },
    icon: Icon(TreinoIcon.chat, color: palette.accent),
    label: Text('MENSAJE', style: GoogleFonts.barlowCondensed(...)),
  ),
```

### Wire-up trainer

```dart
// dentro de _ActiveAlumnoCard:
OutlinedButton.icon(
  onPressed: () async {
    final chat = await ref.read(chatForLinkProvider(link).future);
    if (!context.mounted) return;
    context.push('/coach/chat/${chat.chatId}');
  },
  icon: Icon(TreinoIcon.chat, color: palette.accent),
  label: Text('MENSAJE', ...),
),
```

### Router entry

```dart
// dentro del GoRoute con path: '/coach':
routes: [
  GoRoute(
    path: 'trainer/:uid',
    pageBuilder: (context, state) {
      final uid = state.pathParameters['uid']!;
      return _noAnim(TrainerPublicProfileScreen(uid: uid));
    },
  ),
  GoRoute(
    path: 'chat/:chatId',
    pageBuilder: (context, state) {
      final chatId = state.pathParameters['chatId']!;
      // otherUid se deriva del chatId + currentUid en el ChatScreen,
      // o lo computamos acá leyendo el container.
      return _noAnim(ChatScreen(
        chatId: chatId,
        otherUid: _otherUidFrom(chatId, currentUidOrThrow(context)),
      ));
    },
  ),
],
```

**Helper**: `_otherUidFrom(chatId, selfUid)` = `chatId.split('_').firstWhere((u) => u != selfUid)`.

---

## 4. Trade-offs aceptados

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Sin ChatListScreen wireado en Fase B** | Cada user tiene 1 vínculo activo (athlete) o pocos (PF). La lista es overkill para MVP — el botón directo en cada card cubre 100% del flow. Si más adelante un PF junta >5 alumnos, agregamos un tile "VER MENSAJES" arriba del listado de alumnos que lleva a ChatListScreen. Iteración futura. |
| 2 | **`otherUid` se deriva del `chatId`, no se pasa como query param** | El `chatId` ya contiene los dos uids ordenados. Reconstruir el otro es 1 línea y elimina un param redundante. Trade-off: si el `chatId` viene corrupto, fallaría — pero el path es controlado por nosotros (no externo). |
| 3 | **Chat dentro del ShellRoute** (con bottom bar visible) | Consistente con `/coach/trainer/:uid` que ya está dentro. Otros chat apps (WhatsApp, Telegram, Instagram) ocultan la tab bar al chatear, pero acá la decisión es seguir la convención TREINO de "subpáginas mantienen el chrome" — mantiene el sense of place. Si producto pide ocultarla, mover la ruta fuera del ShellRoute en 5 líneas. |

---

## 5. Out of scope

| Item | Lands en |
|---|---|
| ChatListScreen wireada con entry point | Iteración futura si el load crece |
| Indicador visual de "tenés mensajes nuevos" en la tab Coach | Fase 6 (notifications) |
| Indicador de typing / lectura | Iteración futura |
| Ocultar bottom bar al chatear | Decision producto si lo piden |

---

## 6. Success criteria

- [ ] Athlete con link active ve botón "MENSAJE" en su tab Coach
- [ ] Athlete con link pending NO ve el botón
- [ ] Trainer en tab ALUMNOS ve botón "MENSAJE" en cada card de alumno activo
- [ ] Tap "MENSAJE" abre `ChatScreen` con el `chatId` correcto (determinístico)
- [ ] Primer tap idempotente: si no existe el doc se crea, si existe se abre el mismo
- [ ] Bottom bar visible mientras se chatea
- [ ] Pop del chat vuelve a la tab Coach con la card de vínculo (no resetea estado)
- [ ] Mensaje enviado aparece en real-time del otro lado (verificado en smoke con 2 sesiones)
- [ ] Tests nuevos verdes (6-8 adicionales)
- [ ] `flutter analyze` 0 issues
- [ ] Suite full passing
- [ ] **Smoke test manual completo (9 pasos arriba) ✅ antes de push** — requisito firme per feedback memory

---

## 7. Risks

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | Etapa 4 (Dev A) reescribió `_LinkStateCard` o `_ActiveAlumnoCard` y mi parche no aplica | Esperado. Al rebasear sobre main post-merge de Etapa 4, leer el código nuevo de esos widgets, encontrar el slot natural (al lado del botón "Terminar vínculo" / "TERMINAR VÍNCULO" actuales), insertar ahí. ~30 min extra en el peor caso. |
| 2 | Etapa 4 agregó su propia ruta bajo `/coach` (ej: `/coach/plan-editor/:routineId`) | Conflict en `router.dart` — resolver manualmente, agregar nuestra `/coach/chat/:chatId` al lado de la suya. Trivial. |
| 3 | `chatForLinkProvider` tarda más de lo esperado en el primer tap (round-trip a Firestore + create) | Si supera ~500 ms, mostrar loading dentro del botón. Hoy el `getOrCreate` es 1 read + 1 write secuencial — debería ser <200 ms en buena red. Smoke test confirma. |
| 4 | Rules/indexes nuevas (de Fase A) no están deployadas en `treino-dev` cuando hagamos el smoke test | Deploy explícito ANTES del smoke: `npx firebase-tools deploy --only firestore:rules,firestore:indexes --project treino-dev`. Documentado en el checklist pre-PR. |
| 5 | Pushear sin smoke OK | Convención firme (memoria): manual test gates push. No push sin completar el smoke de 9 pasos. |

---

## 8. LOC estimate

| Bucket | LOC aprox |
|---|---|
| AthleteCoachView wire-up (botón + handler) | ~30 |
| TrainerCoachView wire-up (botón + handler) | ~35 |
| Router entry (`/coach/chat/:chatId`) | ~15 |
| Tests adicionales | ~120 |
| **Total** | **~200** |

PR chico, autocontenido, smokeable end-to-end. Razonable mergear en un solo PR sin chaining.

---

## 9. Pre-flight checklist (al retomar post-merge de Dev A)

- [ ] `git checkout feat/coach-chat`
- [ ] `git fetch origin && git rebase origin/main` (resolver conflicts si Dev A tocó archivos cercanos)
- [ ] `flutter pub get` (Dev A puede haber agregado deps)
- [ ] `flutter analyze` debe ser 0 issues sobre la Fase A pre-existente
- [ ] `flutter test` full debe pasar (953 + 41 chat + lo que Dev A agregó)
- [ ] Solo entonces empezar Fase B
