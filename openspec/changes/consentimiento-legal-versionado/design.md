# Design: consentimiento-legal-versionado

**Input**: [proposal.md](./proposal.md) · **Branch**: `feat/consentimiento-legal-versionado` ·
**Delivery**: single-PR + `size:exception`

---

## La respuesta corta

**R3 se resuelve con la opción (c) + una escritura puntual de despublicación, y
la clave es que `users/` NUNCA queda en estado inválido: sólo se vacía el
espejo público.** El guard `_assertTrainerLocationStateIsValid` protege
`users/{uid}`, y la revocación no toca ninguna clave de ubicación de `users/`.
No hay `ArgumentError`, no hay pérdida de datos, y **no hay que forzar
`trainerOffersOnline: true`**.

**R4 se resuelve con un cuarto campo, `trainerLocationConsentPromptedAt`**, que
responde una pregunta distinta a la de `trainerLocationConsentAt`: una es
"¿consintió?" (evidencia legal), la otra es "¿ya se lo preguntamos?" (UX). El
sheet se muestra **una vez**; el registro de que no consintió sigue siendo
`trainerLocationConsentAt == null`.

> ⚠️ **Cruce que el propose no vio**: su lean de R4 (gatear por
> `trainerLocations.isNotEmpty`) es **incompatible** con su propio lean de R3.
> La opción (c) **no vacía** `trainerLocations` en `users/`, así que después de
> revocar la lista sigue llena y el sheet volvería en cada arranque — el loop
> exacto que R4 quería evitar. `isNotEmpty` sirve como filtro de *relevancia*,
> nunca como cortacircuito.

---

## Decisiones de arquitectura

### D-A · Constantes (`legal_content.dart`)

| Decisión | Detalle |
|---|---|
| **Nombres** | `kTermsVersion` / `kPrivacyVersion` (`int`, ambas `= 1`) |
| **Rechazado** | `kPrivacyPolicyVersion` — rompe la simetría con el par `kTermsLastUpdated`/`kPrivacyLastUpdated` que ya existe a tres líneas |
| **Extra** | `kPrivacyV1PublishedAt = DateTime.utc(2026, 9, 3)` — el puente de una sola vez de D3, machine-comparable. `kPrivacyLastUpdated` es un string de display: no se parsea nunca |

### D-B · Modelo (`user_profile.dart`) — **4 campos, no 3**

| Campo | Tipo | Pregunta que contesta |
|---|---|---|
| `acceptedTermsVersion` | `int?` | ¿qué T&C aceptó? |
| `acceptedPrivacyVersion` | `int?` | ¿qué Política aceptó? |
| `trainerLocationConsentAt` | `DateTime?` | ¿consintió publicar su ubicación, y cuándo? (**evidencia**) |
| `trainerLocationConsentPromptedAt` | `DateTime?` | ¿ya se lo preguntamos? (**anti-loop**) |

Tabla de estados — es el contrato, va en el dartdoc:

| `consentAt` | `promptedAt` | Significado | ¿Sheet? | Ubicación publicada |
|---|---|---|---|---|
| `null` | `null` | nunca preguntado / legacy | **sí** | sí (status quo) |
| set | set | otorgado | no | sí |
| `null` | set | preguntado y no otorgado (cerró o apagó) | no | según el espejo |
| set | `null` | imposible por construcción — tratar como otorgado | no | sí |

**Rechazado: reusar `onboardingSeen`.** El mecanismo de flag es idéntico, pero
"visto" ≠ "consentido", y `allSurfacesSeen()`
(`test/helpers/onboarding_test_helpers.dart`) itera `values` — el sheet quedaría
auto-suprimido en toda la suite de widgets. Un flag de tour no puede ser
evidencia legal.

### D-C · Repositorio (`user_repository.dart`) — el consentimiento gatea el subset

Tres cambios en el único choke point por el que pasa todo write:

```dart
// 1. El subset filtra las claves de ubicación cuando no hay consentimiento.
//    `trainerOffersOnline` NO es una clave de ubicación: sigue fluyendo.
Map<String, Object?>? _trainerPublicSubsetFromPartial(
  Map<String, Object?> partial, {
  required String uid,
  required bool hasLocationConsent, // ← nuevo
});

// 2. Consentimiento efectivo = partial sobre lo guardado. Sólo cuando el
//    partial trae trainerLocations/trainerGeohashes → un `get` extra por
//    submit de form (raro), nunca en camino caliente.

// 3. Los dos actos del dominio, explícitos:
Future<void> grantTrainerLocationConsent(String uid);   // sella + RE-espeja
Future<void> revokeTrainerLocationConsent(String uid);  // limpia + vacía espejo
```

`grant` **tiene que re-espejar**: un partial de sólo-consentimiento no lleva
claves de ubicación, el subset devolvería `null`, no habría write al doc público
y el PF quedaría consentido pero invisible. Simétrico y explícito le gana a que
`update()` lo adivine.

### D-D · Provider + gate

Copia la estructura de `onboarding_providers.dart`, que ya resolvió estos
problemas:

| Pieza | Espejo | Por qué |
|---|---|---|
| `trainerLocationConsentDismissedProvider` (session, uid-scoped) | `onboardingDismissedProvider` | si el write falla offline, el sheet no reaparece dentro de la sesión |
| `shouldAskTrainerLocationConsentProvider` | `shouldShowTourProvider` | `role == trainer && consentAt == null && promptedAt == null && trainerLocations.isNotEmpty` |
| espera a `onboardingBlocksProvider` | ya lo hacen `PermissionGate` y `TrainersListScreen` | **dos modales en un frame es el bug que ese provider existe para evitar, y no lo agarra ningún widget test** |

Usar `select()` (AGENTS.md §6) — el provider depende de 4 campos, no del perfil
entero.

### D-E · Sheet

Mismo patrón exacto que `custom_exercise_onboarding_gate.dart:123-155`:
`isDismissible: false` (bloquea el tap accidental en el scrim) + `enableDrag:
true` (permite la salida deliberada) + persistencia en el `finally`. Ese archivo
ya es la respuesta del proyecto a esta tensión; un modal sin salida deja al
usuario atrapado si el write falla offline.

Tres salidas, todas sellan `promptedAt`:

| Salida | Escribe |
|---|---|
| **ACEPTAR** | `grantTrainerLocationConsent` |
| **APAGAR LA PUBLICACIÓN** | `revokeTrainerLocationConsent` |
| cerrar (arrastre / back) | sólo `promptedAt` — sin consentimiento, sin despublicar |

Diseño (AGENTS.md §2): `AppPalette.of(context)`, `TreinoIcon.*`, spacing
8·12·14·18·20, heading Barlow Condensed 700 UPPERCASE. Copy = producto/legal
(§8), placeholder en `AppL10n`.

### D-F · Segundo punto de entrada — **obligatorio, no scope creep**

La 25.326 exige consentimiento **revocable**. Si el único lugar donde se revoca
es un sheet que se muestra una vez, el consentimiento **no** es revocable. Va una
fila de estado en `profile_edit_trainer_screen.dart`, que además resuelve dos
agujeros:

1. Tras revocar, el form sigue listando las ubicaciones — sin la fila, **miente**
   sobre si están publicadas.
2. Un PF recién promovido no tiene ubicaciones ⇒ el sheet no aplica. Cuando
   guarda la primera, el subset la descartaría **en silencio** (invisible sin
   explicación: exactamente R2). El form pide consentimiento **antes** de
   guardar; el gate del subset queda como red de seguridad, no como trampa.

### D-G · Promoción — **`promote_user_to_trainer.js` NO se toca**

El script corre con Admin SDK, server-side, sin la persona presente: no puede
recolectar un consentimiento. Estampar algo ahí sería **fabricar evidencia de un
consentimiento que nunca ocurrió** — peor que no tener evidencia (§11.1). Como no
hay backfill (D3), el promovido ya tiene los dos campos en `null` y el gate
dispara solo en su próximo arranque. Cierra el caso (C) sin tocar producción.

---

## R3 — por qué (c), con el fundamento completo

| Opción | Veredicto |
|---|---|
| **(a)** vaciar `trainerLocations` en `users/` | **Descalificada.** Destruye datos al ejercer un derecho — re-consentir obliga a recargar cada dirección. Y para pasar el guard hay que forzar `trainerOffersOnline: true`, o sea **publicar en su perfil una afirmación falsa** ("doy clases virtuales") para satisfacer un invariante interno. Arreglar privacidad mintiendo no es arreglar |
| **(b)** tocar sólo `trainerPublicProfiles` | **Descalificada, verificado.** `profile_edit_trainer_screen.dart:197-199` reenvía **siempre** las tres claves ⇒ el próximo guardado re-publica en silencio |
| **(c)** el consentimiento gatea el subset **+ despublicación puntual** | **Elegida** |

Por qué (c) no cae en R1 ni en R2:

- `revokeTrainerLocationConsent` escribe **un solo batch**: a `users/{uid}` va
  `{trainerLocationConsentAt: null, trainerLocationConsentPromptedAt: now}` —
  **cero claves de ubicación**. El guard es un no-op **correcto**: el invariante
  que protege no cambió. R1 (excepción en la cara) no puede pasar.
- El partial de una sola clave de R2 **no existe en este camino**: la
  despublicación nunca pasa por el partial de ubicación de `users/`. Y el gate
  del subset es una propiedad del choke point, no un supuesto sobre el caller —
  no depende del dartdoc que dice "asumimos que el caller maneja el estado
  consistente".
- A `trainerPublicProfiles/{uid}` va
  `{trainerLocations: [], trainerGeohashes: [], trainerLatitude: null, trainerLongitude: null, trainerGeohash: null}`.
  `trainerOffersOnline` **queda intacto**, con su valor real.

**Consecuencia asumida, no bug**: un PF que revoca y no ofrece online deja de
aparecer en la búsqueda por cercanía. Eso es lo que pidió. El guard existe para
atajar un estado inválido **accidental**; una elección informada y confirmada no
es el caso que protege — siempre que el copy lo diga **antes** de confirmar.

**Rechazado: borrar `trainerPublicProfiles/{uid}`.** Se llevaría puestos
`averageRating`, `reviewCount` y `athleteCount`, que son CF-write-only
(ADR-RV-005): sólo un Cloud Function podría reconstruirlos.

---

## Data flow

```
                    ┌── ACEPTAR ──→ grantTrainerLocationConsent ──┐
                    │               users: consentAt+promptedAt   │
  gate (4 campos)   │               tPP:   locations re-espejadas │
       │            │                                             ├─→ 1 batch
       ├─→ sheet ───┼── APAGAR ───→ revokeTrainerLocationConsent ─┤
       │            │               users: consentAt=null (0 claves de ubicación)
       │            │               tPP:   locations = []         │
       │            └── cerrar ───→ update({promptedAt})  ────────┘
       │
       └─(sin sheet)→ el form guarda → update() → subset SIN claves de ubicación
                                                   si consentAt == null
```

---

## Archivos

| Archivo | Acción | Qué |
|---|---|---|
| `lib/features/auth/presentation/legal/legal_content.dart` | Modify | `kTermsVersion`, `kPrivacyVersion`, `kPrivacyV1PublishedAt` + dartdoc |
| `lib/features/profile/domain/user_profile.dart` | Modify | 4 campos + tabla de estados |
| `user_profile.freezed.dart` / `.g.dart` | Regen | `dart run build_runner build --delete-conflicting-outputs` — **commit propio** (R5) |
| `lib/features/profile/data/user_repository.dart` | Modify | subset gateado, consentimiento efectivo, `grant`/`revoke`, `getOrCreate` estampa versiones |
| `lib/features/auth/data/auth_service.dart` | Modify | versiones en signup email |
| `lib/features/profile_setup/application/profile_setup_notifier.dart` | Modify | versiones junto a `termsAcceptedAt` (:333) |
| `lib/features/profile/application/trainer_location_consent_providers.dart` | **New** | gate + dismissal de sesión |
| `lib/features/profile/presentation/trainer_location_consent_sheet.dart` | **New** | el sheet |
| `lib/features/profile/presentation/profile_edit_trainer_screen.dart` | Modify | fila de estado + pedido antes del primer publish (D-F) |
| aviso de atleta (no bloqueante) | **New** | gate: `role == athlete && termsAcceptedAt != null && termsAcceptedAt.isBefore(kPrivacyV1PublishedAt)` |
| `lib/l10n/*` | Modify | strings placeholder |

**Delta de forecast**: el 4º campo suma ~25 líneas generadas (85 → ~110). Total
~660 → **~690**. No cambia la estrategia: ya requería `size:exception`.

---

## Testing bajo Strict TDD

`fake_cloud_firestore` ya es el estándar en `test/features/profile/data/`.

| Capa | Qué se fija | Cómo |
|---|---|---|
| Unit — constantes | bumpear `kPrivacyVersion` no toca `kTermsVersion` | assert directo |
| Unit — modelo | round-trip de los 4 campos; ausente ⇒ `null` | `fromJson`/`toJson` |
| **Repo — R1** | `revokeTrainerLocationConsent` **no** lanza `ArgumentError` | fake + `expect(..., returnsNormally)` |
| **Repo — R2** | tras revocar, `users/{uid}.trainerLocations` sigue **intacto** y el partial no llevó claves de ubicación | leer el doc del fake |
| **Repo — R3** | tras revocar, `tPP.trainerLocations == []` **y `trainerOffersOnline` sin cambios** | leer los dos docs |
| **Repo — anti-republish** | con `consentAt == null`, un `update()` con las tres claves **no** escribe ubicación en `tPP`, pero sí bio/rate/offersOnline | el caso que mata a (b) |
| Repo — grant | `grant` re-espeja las ubicaciones guardadas | leer `tPP` |
| Repo — signup | los tres caminos estampan ambas versiones | fake |
| Provider — gate | los 4 estados de la tabla; atleta ⇒ `false`; caso (C) (promovido hoy, versión al día) ⇒ `true` | `ProviderContainer` + perfil fake |
| Widget — sheet | **sólo estado y semántica**: qué método se llamó por salida, y que no reaparece | ver abajo |

> 🚨 **`google_fonts` nunca carga en `flutter_test`** (no hay `fonts:` en pubspec
> ni `.ttf` en el repo): mide con la fuente de fallback y los textos salen ~2,5×
> más anchos. **Ningún test puede afirmar sobre ancho, wrapping ni overflow del
> sheet.** El layout se verifica en device, por slice.

---

## Qué NO se toca

| Cosa | Por qué |
|---|---|
| `firestore.rules` | El `allow update` de `users/{uid}` usa `affectedKeys().hasAny([...])`, **no** `hasOnly()`: no hay allowlist. Un trainer puede auto-estamparse el consentimiento con un write artesanal. **Estos campos son evidencia, no una frontera de confianza** — mismo régimen que `termsAcceptedAt`. No introducimos una debilidad nueva **y no prometemos una garantía que el modelo no da** (§11.1) |
| `_assertTrainerLocationStateIsValid` | Su hueco (early-return con una sola clave) es real, pero ningún camino nuevo lo pisa. Arreglarlo obliga a un `get` en todo `update()` y es un refactor con su propio blast radius |
| `promote_user_to_trainer.js` | D-G |
| `treino-dev` | **Es PRODUCCIÓN.** Cero escrituras en todo el ciclo. Sin backfill |
| Visibilidad del discovery / rules de `trainerPublicProfiles` | La ubicación del PF **sigue siendo pública a propósito**; lo que se arregla es que se haya consentido |
| Sección 10 de la política, i18n, re-consentimiento de T&C | Fuera de alcance (§3) |

---

## Abierto

- [ ] **Para legal, no para ingeniería**: cerrar el sheet sin decidir deja la
      ubicación publicada (status quo + evidencia de que se informó). Una lectura
      estricta del art. 5 (consentimiento **afirmativo**) pediría despublicar.
      **Default de ingeniería: no despublicar** — castigar un no-respuesta
      rompiéndole el negocio en silencio es la falla de R2 con otro disfraz, y la
      población es chica y contactable (§8).
- [ ] Copy exacto del sheet y del aviso de atleta (§8.1).
- [ ] Si "apagar" debe además desvincular alumnos. *Lean*: no (§8.2).
