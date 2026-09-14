# Proposal: consentimiento-legal-versionado

**Change**: Versionar la aceptación de los documentos legales + consentimiento
específico para la publicación de la ubicación del PF
**Branch**: `feat/consentimiento-legal-versionado` (PR único contra `main`)
**Date**: 2026-09-03
**Base**: `main` @ `60d7f451`
**Delivery**: **single-PR** (decisión explícita del usuario). El forecast supera
el presupuesto de 400 líneas → requiere label **`size:exception`** aprobado por
el maintainer. **No** se parte en PRs encadenados.

---

## 1. Intent — qué pasó y por qué ahora

El PR **#941** (mergeado, `60d7f451`) reescribió la sección **"4. Ubicación"** de
la Política de Privacidad. El texto **anterior** decía:

> "Solo accedemos a tu ubicación si la activás expresamente, y únicamente para
> mostrarte entrenadores cerca tuyo. **Tu ubicación no es visible para otros
> usuarios.**"

Para un **entrenador** eso era **falso**, y no por un matiz:

| Evidencia | Comando |
|---|---|
| `trainerLocations` y `trainerGeohashes` viajan en el dual-write a `trainerPublicProfiles` (`user_repository.dart:61-62`) | `rg -n 'trainerLocations\|trainerGeohashes' lib/features/profile/data/user_repository.dart` |
| Ese doc lo lee **cualquier autenticado** (`firestore.rules:1319`) | `rg -n 'match /trainerPublicProfiles' -A 3 firestore.rules` |

O sea: pin en el mapa y distancia calculada hasta cada atleta. No es una fuga —
**es la feature de discovery**. El texto nuevo (`legal_content.dart:150-165`) ya
lo dice bien. Lo que falta es todo lo demás.

### Agujero A — no sabemos qué texto aceptó cada quien

`UserProfile.termsAcceptedAt` (`user_profile.dart:55`) es un `DateTime?` **sin
versión**. No hay ningún gate de versión en el repo:

```bash
rg -i -n 'policyVersion|acceptedVersion|legalVersion|consentVersion|reconsent' .
# → 0 hits (repo completo)
```

> Nota: la forma `rg -rni "…"` que circuló en el brief **no hace lo que parece** —
> en ripgrep `-r` es `--replace` y se come el `ni` como valor. Ripgrep ya es
> recursivo. Un comando que no hace lo que dice no prueba nada (AGENTS.md §11.1).

### Agujero B — la sección 10 promete algo que no existe

`legal_content.dart:200-203`: *"Podemos actualizar esta Política de Privacidad.
Si los cambios son relevantes, te lo avisaremos dentro de la app."* No hay
camino de notificación. La política se actualizó el 3 de septiembre y nadie se
enteró.

### Agujero C — el texto no se volvió falso con el tiempo: se volvió falso en la PROMOCIÓN

Por AGENTS.md §3 los trainers **no se auto-registran**: los crea el equipo a mano
por Admin SDK, y `scripts/promote_user_to_trainer.js:72` sólo hace
`batch.update(users/{uid}, { role: 'trainer' })` (`rg -n 'batch.update'
scripts/promote_user_to_trainer.js`). El rol está pineado inmutable en las rules
(`firestore.rules:172`), así que **no hay otro camino**.

Consecuencia: la persona aceptó la política **siendo atleta**, cuando *"tu
ubicación no es visible para otros usuarios"* era literalmente **cierta para
ella**. El texto se volvió falso por **un acto del equipo**, no del usuario.

**Corolario que invalida la solución obvia:** un atleta que se registre hoy ya
guarda el número de versión vigente. Si lo promovemos mañana, un gate de
`acceptedVersion < versiónVigente` **nunca dispara** — y le publicamos la
ubicación sin que jamás haya consentido esa finalidad. **El versionado solo no
cierra el problema.**

---

## 2. Decisiones lockeadas

| # | Decisión | Fundamento |
|---|---|---|
| **D1** | **Dos** constantes de versión: `kTermsVersion` y `kPrivacyPolicyVersion`, enteros monótonos, al lado de `kTermsLastUpdated`/`kPrivacyLastUpdated` | Una sola constante reintroduce exactamente el acoplamiento que el dartdoc de `kPrivacyLastUpdated` (`legal_content.dart:21-28`) documenta como error: con una sola, reescribir la política *"o dejaba la política fechada en junio, o le inventaba a los Términos una revisión que nunca tuvieron"*. Un `acceptedPolicyVersion` único comete el mismo pecado un nivel más abajo. (Simetría con `kPrivacyLastUpdated` sugeriría `kPrivacyVersion`; nombre final lo cierra design.) |
| **D2** | Enteros, no fechas ni semver | Una fecha en string invita a comparar mal; semver invita a discutir si un typo es patch. Un entero sólo admite `<`. |
| **D3** | Dos campos en `UserProfile`: `acceptedTermsVersion` / `acceptedPrivacyVersion` (`int?`), junto a `termsAcceptedAt` | `null` ⇒ cuenta legacy sin evidencia — el patrón que el modelo **ya** documenta para `termsAcceptedAt` (`user_profile.dart:50-55`). Ambos arrancan en `1` = "el texto vigente hoy". **Sin backfill**: para la población actual el puente es la fecha (`termsAcceptedAt < 2026-09-03` ⇒ aceptó el texto viejo de "4. Ubicación"). Es un puente de una sola vez, no un mecanismo — la fecha es justo lo que la versión existe para reemplazar. |
| **D4** | Un tercer campo, **específico**: `trainerLocationConsentAt` (`DateTime?`) | Consentimiento **para una finalidad determinada** (Ley 25.326 art. 5), disparado en la **promoción a trainer**, no en el signup. Es lo único que cierra (C): no depende de que el número de versión cambie. |
| **D5** | **Flujo separado por rol** | El daño fue distinto y la respuesta también. |
| **D6** | Alcance asimétrico: el **schema** para todos, el **aviso de re-consentimiento** sólo para trainers | Ver D5. |

### D5 en detalle

- **Atleta → aviso informativo NO bloqueante.** Para el atleta el texto viejo era
  sustancialmente cierto. El texto nuevo *agrega precisión* (la zona de ~5 km que
  se le manda al proveedor de mapas); no revela un tratamiento oculto. Bloquear a
  quien no fue engañado es teatro de compliance.
- **Entrenador → sheet al entrar**, con el cambio en criollo (*"tu ubicación
  aparece en tu perfil público, con pin y distancia hasta cada atleta"*) y **una
  salida real**: aceptar, **o apagar la publicación**. La 25.326 exige
  consentimiento informado y **revocable**, no un muro. Un sheet sin salida no es
  consentimiento: es un `OK` forzado.

---

## 3. Scope

### In scope
- `kTermsVersion` + `kPrivacyPolicyVersion` en `legal_content.dart`, con dartdoc que explique por qué son dos.
- `acceptedTermsVersion`, `acceptedPrivacyVersion`, `trainerLocationConsentAt` en `UserProfile` (+ regen freezed).
- Estampado de las dos versiones en los **tres** caminos de aceptación que hoy escriben `termsAcceptedAt`: signup email (`auth_service.dart`), submit de ProfileSetup OAuth (`profile_setup_notifier.dart`), `UserRepository.getOrCreate`.
- Aviso informativo no bloqueante para atletas con evidencia previa al 3-sep.
- Sheet de re-consentimiento para trainers, con rama **aceptar** y rama **apagar la publicación**.
- Camino de revocación que **no** deja el perfil en estado inválido (§6, riesgo R1).
- Tests: modelo, repositorio (incluida la trampa), gate por rol, y que el sheet no reaparezca tras decidir.

### Out of scope (explícito)
- **Backfill** de versiones sobre cuentas existentes. Cualquier escritura masiva sobre `treino-dev` es **producción** y no entra acá.
- Registro de auditoría inmutable (colección `consents/` append-only con IP/user-agent). Si legal lo pide, es su propio change.
- Notificación **push** del cambio de política. Este change usa superficies in-app.
- Re-consentimiento de **Términos** (sólo cambió la Política).
- Traducción / i18n de los textos legales.
- Endurecer las rules de `trainerPublicProfiles` o cambiar la visibilidad del discovery. La ubicación del PF **sigue siendo pública a propósito** — lo que arreglamos es que se haya consentido.
- Reescribir la sección 10 para prometer menos.

---

## 4. Capabilities

### New
- `legal-consent-versioning`: aceptación versionada de T&C y Política, más el consentimiento de finalidad específica para la publicación de la ubicación del PF y su revocación.

### Modified
- `trainer-profile-onboarding` (`openspec/specs/trainer-profile-onboarding/spec.md` — es la única spec consolidada que nombra `trainerLocations`/`trainerOffersOnline`): la publicación de ubicación pasa a requerir consentimiento registrado, y gana un camino de revocación que debe respetar el invariante de estado válido.

---

## 5. Affected Areas

| Área | Impacto | Qué cambia |
|---|---|---|
| `lib/features/auth/presentation/legal/legal_content.dart` | Modified | +2 constantes con dartdoc |
| `lib/features/profile/domain/user_profile.dart` | Modified | +3 campos |
| `user_profile.freezed.dart` / `.g.dart` | Generated | Regen — `dart run build_runner build --delete-conflicting-outputs` (AGENTS.md §7.4) |
| `lib/features/auth/data/auth_service.dart` | Modified | Estampa versiones en signup email |
| `lib/features/profile_setup/application/profile_setup_notifier.dart` | Modified | Estampa versiones en submit OAuth |
| `lib/features/profile/data/user_repository.dart` | Modified | `getOrCreate` acepta las versiones; camino de revocación |
| Sheet de re-consentimiento (nuevo) + gate/provider | New | Sólo `role == 'trainer'` |
| Aviso informativo de atleta (nuevo) | New | No bloqueante |
| `firestore.rules` | **Sin cambios** | El update de `users/{uid}` **no** tiene `keys().hasOnly()` (líneas 167-202): el dueño escribe cualquier campo no pineado. Verificable: `rg -n 'hasOnly' firestore.rules \| rg '^(1[6-9][0-9]\|20[0-2]):'` → sin salida. |

**Y esto hay que decirlo, no dejarlo implícito**: como no hay allowlist, un
trainer puede auto-estamparse `trainerLocationConsentAt` con una escritura
artesanal. Estos campos son **evidencia, no una frontera de confianza** — igual
que `termsAcceptedAt`, que ya vive bajo el mismo régimen. No introducimos una
debilidad nueva; tampoco pretendamos que cerramos una.

---

## 6. Risks

| # | Riesgo | Prob. | Mitigación |
|---|---|---|---|
| **R1** | **La trampa del estado inválido.** `trainerLocations.isEmpty && !trainerOffersOnline` es INVÁLIDO y `UserRepository.update()` lo rechaza con `ArgumentError` (`user_repository.dart:241-256`, llamado en :350). "Apagar la publicación" cae justo ahí: si la revocación manda `{trainerLocations: [], trainerOffersOnline: false}`, el usuario recibe **una excepción en la cara** en el momento de ejercer un derecho. | **Alta** | La revocación debe forzar `trainerOffersOnline: true` en el mismo partial, o no pasar por `update()`. Pinneado por test. |
| **R2** | **La otra cara de R1, peor.** El guard sale temprano si el partial no trae **las dos** claves (`if (!hasLocations \|\| !hasOnline) return;`, :246). Mandar sólo `{trainerLocations: []}` **pasa el guard**, escribe, y deja al PF en el estado inválido exacto que el guard existe para prevenir: **invisible, sin error y sin explicación**. Un guard que no cubre el caso es peor que ninguno (AGENTS.md §11.1). | **Alta** | Test que fije el hueco; la revocación nunca manda una sola clave. |
| **R3** | **Cómo se "apaga" sin romper el dual-write.** Tres formas, las tres chocan: (a) vaciar `trainerLocations` en `users/` **borra los datos** del PF; (b) tocar sólo `trainerPublicProfiles` **rompe la simetría** del dual-write y el próximo guardado del perfil **re-publica en silencio**, re-rompiendo el consentimiento; (c) que el consentimiento **gatee el subset** de `_trainerPublicSubsetFromPartial` no destruye nada, pero deja el doc público ya publicado sin limpiar. | **Alta** | **Es la decisión de ingeniería más difícil del change → handoff explícito a `sdd-design`.** *Lean*: (c) + una escritura puntual de "despublicar" para quien revoque con ubicación ya publicada. |
| **R4** | **Loop de nag.** Si el sheet se gatea sólo por `trainerLocationConsentAt == null`, quien elija "apagar" lo ve **en cada arranque**: la negativa no queda registrada en ningún lado. | Media | *Lean*: gatear por `role == 'trainer' && trainerLocationConsentAt == null && trainerLocations.isNotEmpty` — sin ubicación publicada no hay nada que consentir. Alternativa: campo de negativa explícita. Design decide. |
| **R5** | Ruido de regen freezed en el diff. `rg -c trainerOffersOnline user_profile.freezed.dart` → **25** apariciones por campo; 3 campos ≈ **+75** líneas generadas que el reviewer saltea. | Media | Commit separado sólo para el regen, para que el diff revisable quede limpio. |
| **R6** | El texto del sheet lo escribe ingeniería y termina en jerga legal | Media | El copy es **decisión de producto/legal** (§8), no de este change. |
| **R7** | No sabemos cuántos trainers hay en producción | — | Ver §8. **No se corre nada contra `treino-dev`.** |

---

## 7. Rollback

> 🚨 **`treino-dev` es PRODUCCIÓN** — es el único proyecto Firebase de TREINO.
> Ver [openspec/AGENTS.md](../../AGENTS.md) · [#826](https://github.com/Backhaus7997/treino/issues/826).

Barato, y a propósito: el change es **puramente aditivo**. Revert del PR → los
tres campos dejan de escribirse y el resto los ignora (`null` = legacy, que es
el estado de hoy). **No hay migración de schema, no hay índices nuevos, no hay
rules que redeployar, no hay Cloud Functions.** Lo único no revertible por `git`
son los `trainerLocationConsentAt` ya estampados por usuarios reales — y eso es
justamente lo que queremos conservar.

---

## 8. Dependencias y qué NO decide ingeniería

**Producto / legal** (bloquea el copy, no el schema):
1. El texto exacto del sheet del PF y del aviso del atleta.
2. Si "apagar la publicación" debe además desvincular al PF de sus alumnos actuales. *Lean de ingeniería*: **no** — el vínculo no depende de la ubicación.
3. Si hace falta registro de auditoría inmutable (hoy fuera de alcance, §3).

**Población afectada**: la lista de trainers **no se obtiene corriendo nada
contra producción desde este change**. Se pide al equipo o se saca con un script
**read-only**: `scripts/audit_trainer_profiles.mjs` — verificado sin una sola
escritura, `rg -n '\.set\(|\.update\(|\.delete\(|\.add\(|batch\(|bulkWriter'
scripts/audit_trainer_profiles.mjs` → 0 hits. (Ojo: AGENTS.md § Entornos lo
nombra sin extensión y el archivo es **`.mjs`**, no `.js` — un `node
scripts/audit_trainer_profiles.js` falla por archivo inexistente.)
La población es **conocida, chica y contactable** por construcción: la creó el
equipo a mano, uno por uno, con `promote_user_to_trainer.js`. Eso hace que un
aviso in-app + un contacto directo sea una respuesta proporcionada, y es la
razón por la que no hace falta un backfill.

---

## 9. Review Workload Forecast

| Área | ~líneas |
|---|---|
| `legal_content.dart` (2 constantes + dartdoc) | 25 |
| `user_profile.dart` (3 campos + comentarios) | 30 |
| **Regen freezed / `.g.dart`** (generado, 25 líneas × 3 campos + JSON) | **85** |
| Estampado en los 3 caminos de aceptación | 40 |
| Sheet de re-consentimiento del PF + gate/provider | 180 |
| Aviso no bloqueante del atleta | 60 |
| Camino de revocación (R1/R2/R3) | 40 |
| Tests | 200 |
| **Total estimado** | **~660** |

- **400-line budget risk: High**
- **Chained PRs recommended: No** — `delivery_strategy: single-pr`, decisión explícita del usuario.
- **Decision needed before apply: Yes** → **el PR requiere label `size:exception` aprobado por el maintainer antes de mergear.**
- Atenuante real, no excusa: **~85 líneas (13%) son código generado por `build_runner`** y otras **200 son tests**. El diff que exige criterio humano es de ~375 líneas. Si el regen va en su propio commit (R5), el reviewer puede saltearlo con seguridad.

---

## 10. Success Criteria

- [ ] Una cuenta nueva (email **y** OAuth) guarda `acceptedTermsVersion` y `acceptedPrivacyVersion` con el valor de las constantes vigentes.
- [ ] Las dos constantes son independientes: bumpear la de Política **no** toca la de Términos. Pinneado por test.
- [ ] Un PF con ubicación publicada y `trainerLocationConsentAt == null` ve el sheet al entrar. Un atleta en el mismo estado **no** queda bloqueado.
- [ ] **Aceptar** estampa `trainerLocationConsentAt` y el sheet no vuelve.
- [ ] **Apagar la publicación** deja el perfil en estado **válido** y **visible** (no dispara `ArgumentError` ni cae en el estado inválido silencioso de R2), y el sheet no vuelve.
- [ ] Test que fija el hueco de R2: un partial con **una sola** de las dos claves no puede dejar el doc en `[] + false`.
- [ ] Un PF promovido **hoy**, con `acceptedPrivacyVersion` ya igual al vigente, **igual** recibe el pedido de consentimiento — el caso (C), que un gate de versión solo nunca dispararía.
- [ ] `flutter analyze` → 0 issues · `flutter test` verde (AGENTS.md §7). El formateo, **acotado a los archivos tocados** (`dart format <archivos>`): un `dart format .` sobre el repo entero arrastra reformateos ajenos por drift del SDK.
- [ ] Ninguna escritura contra `treino-dev` en todo el ciclo del change.
