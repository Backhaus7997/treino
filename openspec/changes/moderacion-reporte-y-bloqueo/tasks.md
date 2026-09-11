# Tareas

## Reglas — el núcleo
- [ ] `notBlocked(a, b)` a scope raíz, espejando `followAccepted()`
- [ ] `match /blocks/{blockId}` — create y delete del bloqueador; read acotado al prefijo del id
- [ ] `match /reports/{reportId}` — create propio; **read cerrado a todo cliente**
- [ ] `notBlocked()` en `senderMayPost` (chat)
- [ ] `notBlocked()` en create de `posts/{id}/reactions/{uid}`
- [ ] `notBlocked()` en create de `follows`
- [ ] `notBlocked()` en create de `reviews`
- [ ] **NO tocar `posts allow read`** — rompe el feed entero, ver design

## Cloud Function
- [ ] Trigger `onCreate` sobre `blocks`: borra las aristas de follow en las dos
      direcciones. Con eso el tier `followers` queda protegido por la regla que
      ya existe. Patrón de `social/maintain-follow-counters.ts`
- [ ] Registrar en `index.ts`, región `southamerica-east1`

## Tests de reglas — negativos
- [ ] `blocks-rules.test.ts` — el nombre DEBE terminar así o el job de CI no lo levanta
- [ ] `reports-rules.test.ts`
- [ ] Casos: un tercero no lee el bloqueo · el bloqueado no confirma que lo bloquearon ·
      no se falsifica `reporterUid` ajeno · el bloqueado no escribe en el chat ·
      no reacciona · no sigue · no reseña
- [ ] Fila nueva en la matriz de `docs/security.md` §1.1

## Dominio y aplicación
- [ ] `Block` y `ContentReport` freezed en `lib/features/moderation/domain/`
- [ ] `BlockRepository`, `ReportRepository`
- [ ] Providers Riverpod: lista de bloqueados del usuario actual
- [ ] Restar bloqueados del `friendUids` antes del `whereIn` (`feed_screen_providers.dart:29`) — UX, no control
- [ ] Ocultar tarjetas de bloqueados en `public`/`gym` — cosmético, y documentarlo como tal

## Interfaz
- [ ] Tokens nuevos en `TreinoIcon`: bandera y prohibido. NUNCA `PhosphorIcons` directo
- [ ] Rama **no-dueño** en `PostCard._showPostMenu` — hoy sólo existe `if (isOwner)`
- [ ] Menú en la burbuja de chat (hoy no tiene ningún gesto)
- [ ] Menú en `ReviewTile`
- [ ] Acción en el header de `PublicProfileScreen`
- [ ] Sheet de confirmación con el molde de `UnfriendConfirmationSheet`
- [ ] Sheet de reporte con la taxonomía de `normas-de-comunidad.md` §1
- [ ] Cadenas en los tres `.arb` + `flutter gen-l10n`

## Verificación
- [ ] `flutter analyze lib test` en cero
- [ ] Tests de widget por superficie
- [ ] `npm --prefix functions run test:rules:emulator`

## Anotado, no entra
- [ ] **Bloqueos huérfanos al borrar cuenta** — la cascada borra por campo `athleteId`, y estos llevan los uids en el id
- [ ] Vista de revisión de reportes para el equipo
- [ ] Filtrado preventivo de términos vetados
- [ ] Moderación de imágenes
- [ ] `reviews` no tiene hoy NINGÚN test de reglas (`docs/security.md:99`)
