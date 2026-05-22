# Exploration: feed-friend-requests-inbox

**Phase**: Fase 3 Etapa 6 (re-opens Fase 3; same convention used for sub-fase 5.5)
**Owner**: Dev C
**Status**: explored — pending propose

---

## Goal

Cerrar la UX gap descubierta durante el smoke de `wire-real-stats` PR#3 (2026-05-21): el athlete que recibe una friend request no tiene cómo enterarse ni aceptarla salvo navegando al profile del requester desde search. Resultado: la mayoría de las solicitudes quedarían sin atender porque el receptor no las ve.

Construir una pantalla in-app dedicada de "Solicitudes pendientes" que liste las requests recibidas con avatar + nombre + gym + botones ACEPTAR / RECHAZAR, accesible desde un entry point claro en el Profile.

## Background

Documentado en:
- `openspec/changes/wire-real-stats/archive-report.md` §7 (Follow-ups), §4.1 (REQ-WRX-004 partial)
- Engram observation `decision/follow-up-friend-requests-inbox-screen-own-sdd-after-wire-real-stats-archive`

Decisión 2026-05-21: hacerlo como SDD propio post-wire-real-stats, no inflado dentro de ese cycle.

## Current state audit

### Infrastructure CONFIRMED working (zero gaps en data layer)

| Pieza | Path | Status |
|---|---|---|
| `FriendshipRepository.pendingRequestsFor(uid)` | [friendship_repository.dart:110](lib/features/feed/data/friendship_repository.dart#L110) | ✅ Funciona, testeado (SCENARIO-127). Query: `members arrayContains uid` + `status == pending` + filtra `requesterId != uid`. **One-shot `.get()`**, no stream. |
| `FriendshipRepository.accept(id, myUid)` | [friendship_repository.dart:58](lib/features/feed/data/friendship_repository.dart#L58) | ✅ Funciona + self-refresh `followingCount` (ADR-WRS-12). |
| `FriendshipRepository.delete(id, myUid)` | [friendship_repository.dart:125](lib/features/feed/data/friendship_repository.dart#L125) | ✅ Funciona + self-refresh decrement. Misma op para "rechazar request" que para "unfriend amistad aceptada". |
| `pendingRequestsProvider` | [friendship_providers.dart:19](lib/features/feed/application/friendship_providers.dart#L19) | ✅ Existe — `FutureProvider.family<List<Friendship>, String>`. **Zero consumers** en todo el codebase (grep confirmed). |
| `userPublicProfileProvider` | `lib/features/profile/application/user_public_profile_providers.dart:23` | ✅ Devuelve `{displayName, avatarUrl, gymId}` — exactamente lo que la row del inbox necesita. |

### Lo que falta (lista exhaustiva)

1. `FriendshipRepository.watchPendingRequestsFor(uid)` → `Stream<List<Friendship>>` (vía `snapshots()`)
2. `pendingRequestsStreamProvider` — `StreamProvider.family` wrapping el método anterior
3. `pendingRequestCountProvider` — derivado del stream, devuelve `int` (para tile count / badge)
4. `FriendRequestsInboxScreen` widget
5. `FriendRequestInboxTile` widget (avatar + nombre + gym + ACEPTAR/RECHAZAR)
6. Ruta `/profile/friend-requests` en [router.dart](lib/app/router.dart)
7. Entry tile en [profile_screen.dart](lib/features/profile/profile_screen.dart)
8. Empty state (reusar `FeedEmptyState`)

---

## Cache-staleness investigation

`friendshipByPairProvider` ([public_profile_providers.dart:22](lib/features/feed/application/public_profile_providers.dart#L22)) y `userPublicProfileProvider` son ambos `FutureProvider.family`. Single consumer cada uno: `publicProfileViewProvider`.

**Costo de conversion a Stream** (Option II):
- Ambos repos necesitan `watch*()` method retornando `Stream`
- `publicProfileViewProvider` compone los dos — al convertir a Stream, no se puede `await` adentro, hay que restructurar a `StreamProvider` con `Rx.combineLatest` o equivalente manual
- `AsyncValue.when()` en `PublicProfileScreen` es agnóstico Future/Stream → cero impacto en widget
- Net: medium complexity, 3 files + tests

**Decisión recomendada**: el inbox propio usa `StreamProvider` desde día uno (live updates from the start). La conversion de `friendshipByPairProvider` y `userPublicProfileProvider` queda como follow-up SDD separado de 30 min — son problemas reales pero aislados a un screen específico y no son data-loss-critical.

---

## Scope options comparison

| Criterio | **Option I (Inbox only)** | Option II (Inbox + live providers) | Option III (+ REQ-WRX-004 dual-side counters) |
|---|---|---|---|
| UX gap closed | Inbox visible + live | + public profile live | + counters correctos ambos lados |
| LOC estimado | ~250 | ~350 | ~430 |
| PR strategy | Single PR | Chained (2) o 1 con `size:exception` | Chained (3) |
| 400-line budget risk | Low | Medium | High |
| Risk level | Low | Medium | High |
| Tests existentes a tocar | Ninguno | `publicProfileViewProvider` tests | + Firestore rules tests |
| **Recomendado** | **Sí — empezar acá** | Buen fast-follow después | Defer a Fase 6 Cloud Function |

---

## UX entry point options

| Opción | Descripción | Pros | Cons |
|---|---|---|---|
| **A — Profile tile** | Row tappable "Solicitudes de amistad (N)" en ProfileScreen debajo del stats row. Ruta `/profile/friend-requests`. | Semánticamente correcto (perfil → mis cosas); cero cambios estructurales | Menos discoverable que badge |
| B — Feed header icon | Icono +person en `_FeedHeader`. Ruta `/feed/friend-requests`. | Más visible desde Feed | 3er icono en header de 2; mismatch semántico (Feed = contenido) |
| C — Bottom bar badge | `Badge` overlay sobre PERFIL tab. | Máxima visibilidad | `TreinoBottomBar` no tiene infrastructure de badges; surgery non-trivial |

**Recomendación: A.** Placement correcto, cero risk estructural, footprint mínimo.

---

## N+1 query analysis

Por cada inbox open: 1 stream subscription para la pending list + N `userPublicProfileProvider(uid).family` reads (uno por requester). Cada family member está cacheado individualmente por Riverpod. Para tamaños realistas (0–10 requests), aceptable. No hace falta batch-fetch API.

---

## Out of scope (defer explícito)

- Push notifications (FCM) — Fase 6 polish
- Inbox para otros eventos sociales (likes, comments) — fuera de scope, este SDD es friend-requests-only
- Counterparty-side counter updates (REQ-WRX-004 follow-up de wire-real-stats) — flag como follow-up, posiblemente Fase 6 Cloud Function
- Live updates de `friendshipByPairProvider` + `userPublicProfileProvider` — SDD separado de 30 min después

---

## Open questions for sdd-propose (decision-shaped)

1. **Entry point**: A (Profile tile) / B (Feed header icon) / C (Bottom bar badge)?
2. **Tile visibility**: siempre visible con count "(0)" o oculto cuando no hay requests?
3. **RECHAZAR UX**: tap inmediato (la request desaparece) o dialog de confirmación?
4. **Scope final**: Option I (recomendado) vs Option II (incluye live providers)?
5. **Dismiss-without-action**: si user abre inbox y cierra sin actuar, la request queda pending indefinidamente — aceptable?
6. **Empty state copy**: "No hay solicitudes pendientes" vs hide tile vs "(0)"?
7. **RECHAZAR vs ELIMINAR semantics**: el repo op (`delete`) es idéntico para rechazar request vs unfriend amistad aceptada. Copy debe distinguir explícitamente — propose decidirá.

---

## Recommendation

**Option I + Entry Point A**. Single PR, low risk, no regressions en providers existentes. La conversion de los pair/profile providers a Stream es un follow-up SDD chiquito que se hace bien después.
