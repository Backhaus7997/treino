# Plan Fase 11 — Perfil Público (rediseño Coach Hub Web)

> Estado: PLANIFICADO. Este archivo queda SIN COMMITEAR; el WU final (WU-06) lo commitea.
> Backend de artefactos: hybrid (engram topic `sdd/redesign-coach-hub-web/plan-fase11` + este md).

## 1. Anatomía objetivo (mockup `docs/web-trainer/screens/perfil-publico/perfil-publico.png`)

Layout de dos columnas dentro del shell del Coach Hub (desktop-only):

- **Header**: breadcrumb "Trainer · Perfil público", título `PERFIL PÚBLICO` (Barlow Condensed 700 UPPERCASE) + subtítulo "Tu carta de presentación en TREINO Coach Discovery". Acciones top-right en el mockup: "Vista pública", "Compartir", "Publicar".
- **Columna izquierda (editor)**: cards `IDENTIDAD` (avatar + Subir foto + toggle Visible + Nombre, Título, Experiencia, Ubicación, Bio), `ESPECIALIDADES` (chips multi-select + sugeridas) + `MODALIDAD` (Online/Presencial/Híbrido + gimnasio), `CERTIFICACIONES` (lista + Agregar), `REDES Y LINKS` (Instagram/WhatsApp/Web/YouTube).
- **Columna derecha (preview sticky)**: card "PREVIEW EN TREINO COACH DISCOVERY" — banner degradé, avatar, nombre + check verificado, "Personal Trainer · Hipertrofia", ubicación · Online+Presencial, stats (ALUMNOS · RATING★+RESEÑAS · AÑOS), chips de especialidad, "PLANES DESDE $28k/mes", CTA "Solicitar contacto".

## 2. Realidad del código (censo)

- **NO existe** ninguna sección `perfil_publico`/`perfil`/`profile` en `lib/features/coach_hub/presentation/sections/`. Hay que crearla, registrar ruta en `lib/app/coach_hub_router.dart` (spread `...perfilPublicoRoutes`) e ítem de sidebar en `lib/features/coach_hub/presentation/shell/sidebar_registry.dart` (spread `...perfilPublicoSidebarItems`). Patrón: `sections/chat/routes.dart`.
- **Modelo de datos** `TrainerPublicProfile` (`lib/features/coach/domain/trainer_public_profile.dart`), doc `trainerPublicProfiles/{uid}`, espejo de escritura vía `UserRepository.update` (dual-write atómico a `users/{uid}` + `trainerPublicProfiles/{uid}`, subset `_trainerPublicFields`).
- **Fuente de verdad para editar** = `userProfileProvider` (`UserProfile` del PF logueado, tiene `trainerBio`, `trainerSpecialty` String, `trainerMonthlyRate` int?, `trainerLocations`, `trainerOffersOnline`, `avatarUrl`, `displayName`). Escrituras: `userRepositoryProvider.update(uid, partial)`.
- **Lectura del doc público** (para rating/reseñas): `trainerByIdProvider(uid)` → `TrainerPublicProfile` (tiene `averageRating`, `reviewCount`).
- `TrainerSpecialty` = enum FIJO de 10 valores (powerlifting, crossfit, bodybuilding, hipertrofia, wellness, kinesiologia, funcional, running, yoga, calistenia). **SINGLE-select** — el multi-select del mockup NO tiene modelo.
- Completitud: `UserProfileTrainerCompleteness.trainerProfileComplete` (bio + specialty + rate + (locations|online)).
- Conteo de alumnos activos: `trainerLinksStreamProvider` (usado en `cuenta_tab.dart`).
- `currentUidProvider` en `features/workout/application/session_providers.dart`.

### Campos del mockup SIN backend (FANTASÍA — fuera de scope, NO se renderizan como inputs muertos)
Título libre, Experiencia/Años, MULTI-especialidad, Certificaciones, Redes y Links (Instagram/WhatsApp/Web/YouTube), toggle Visible / botón Publicar. Ninguno existe en `UserProfile` ni `TrainerPublicProfile` y agregarlos exige migración → fuera del alcance de un rediseño.

### Archivos PROHIBIDOS / caja negra
- `lib/features/profile/trainer_profile_view.dart` — USER FILE INTOCABLE con cambios sin commitear. NO importar en código nuevo.
- `lib/features/feed/presentation/public_profile_screen.dart` — perfil público mobile del feed. NO tocar; solo reusar providers de lectura si aplica.
- `lib/features/coach/presentation/trainer_public_profile_screen.dart` (discovery mobile) — NO tocar; se puede mirar como referencia de composición del hero/stats.
- l10n (`lib/l10n/*`) — INTOCABLE. Strings nuevos: hardcode es-AR Rioplatense con comentario `// i18n: Fase 11`.
- `sections/routine_editor/*` — fuera de esta sección, no aplica.

## 3. Decisión de arquitectura (ADR-F11-01): sección "Perfil Público" preview-first

**Contexto**: la sección no existe; el mockup es un editor completo + preview; ~70% de sus campos no tienen modelo; los campos que SÍ están cableados usan `UserRepository.update`; el rating/reseñas es read-only (CF).

**Decisión**: crear una sección nueva de DOS COLUMNAS responsive dentro del shell:
- **DERECHA** = card "Coach Discovery preview" READ-ONLY, pulida al pixel (norte de la fase), 100% data real vía `userProfileProvider` (identidad/bio/specialty/rate/online) + `trainerByIdProvider(uid)` (rating/reseñas) + `trainerLinksStreamProvider` (alumnos). Sin "años" (no cableado).
- **IZQUIERDA** = editor tokenizado que cablea SOLO mutaciones reales de doc único ya probadas: `trainerBio`, `trainerSpecialty` (single-select), `trainerMonthlyRate`. Guardado vía `userRepositoryProvider.update` (patrón `cuenta_tab.dart`: dirty tracking + spinner + snackbar).
- **Nombre + Foto** → read-only en IDENTIDAD con deep-link a `/ajustes` (Cuenta) — evita duplicar la lógica de split de nombre y el uploader.
- **Modalidad + Ubicaciones** → resumen READ-ONLY (online + count de locations) con nota honesta "Editá modalidad y ubicaciones desde la app móvil" — NO se edita inline para NO tocar el invariante del repo (0 locations + offersOnline:false lanza `ArgumentError`).
- **Fantasía** → NO se renderiza. Nota opcional "más campos próximamente".

**Alternativas rechazadas**:
- (A) Editor completo del mockup con todos los campos → exige migración Firestore (título, experiencia, certificaciones, redes, multi-specialty, publish flag) + crea inputs muertos. Viola la regla de honestidad y el scope de rediseño.
- (B) Preview 100% read-only sin edición → sub-entrega: hay mutaciones limpias cableadas que vale la pena exponer.
- (C) Duplicar `ProfileEditTrainerScreen` (multi-location + gym picker + GPS) en web → duplicación pesada de lógica compleja; viola "segundo copy-paste = extraer componente". Deep-link en su lugar.

**Consecuencias**: superficie honesta, sin backend nuevo, segura frente al invariante de locations. Identidad (foto/nombre) respeta su home actual (Cuenta). El "live preview mientras tipeás" es opcional (nice-to-have); el preview refleja estado guardado + edición local si es barato.

## 4. Componentes y flujo de datos

```
PerfilPublicoScreen (sin Scaffold; renderiza dentro de CoachHubScaffold)
├── userProfileProvider.when  → TreinoStateSwitcher (loading shimmer / error+retry / data)
│   └── data(profile)
│       ├── Header (TreinoSectionHeader "PERFIL PÚBLICO" + subtítulo)
│       ├── [!trainerProfileComplete] banner honesto "perfil incompleto"
│       ├── Row responsive (LayoutBuilder / responsive.dart)
│       │   ├── Col izquierda (editor)
│       │   │   ├── IdentidadCard (avatar+nombre read-only, bio inline → update{trainerBio})
│       │   │   └── EspecialidadPrecioCard (specialty single-select + precio → update{...}; modalidad read-only)
│       │   └── Col derecha
│       │       └── CoachDiscoveryPreviewCard(profile, trainerByIdProvider(uid), linksCount)
```

Providers leídos: `userProfileProvider`, `userRepositoryProvider`, `trainerByIdProvider(uid)`, `trainerLinksStreamProvider`. Escrituras: `userRepositoryProvider.update`.

## 5. Work Units (atómicos, secuenciales, TDD estricto)

- **WU-01** Scaffold: ruta + sidebar + `PerfilPublicoScreen` mínima funcional (pre-rediseño) + harness de evidencia fase-11 + captura BEFORE + commit.
- **WU-02** Card "Coach Discovery preview" (columna derecha), data real, estados/motion, dark+light + commit.
- **WU-03** Card IDENTIDAD + editor de bio inline (save real) + deep-link a Cuenta + commit.
- **WU-04** Card ESPECIALIDAD (single-select) + PRECIO (save real) + modalidad read-only + commit.
- **WU-05** Estados + motion + responsive + banner de perfil incompleto + commit.
- **WU-06** Evidencia AFTER + gates full (flutter test + analyze 42) + commit del plan + commit final.

## 6. Riesgos

- Agregar un ítem al `sidebarRegistry` puede romper tests que asertan el conteo/orden de ítems del sidebar (no prohibidos → actualizables). Verificar `test/` de sidebar.
- El comparador del harness de evidencia hardcodea `fase-8`; WU-01 debe adaptarlo a `fase-11`.
- Coach Hub es desktop-only (`ADR-CHW-004`): a <768px el shell muestra `MobileBanner`. El guard de evidencia debe ramificar por viewport (igual que chat).
- `averageRating`/`reviewCount` NO están en `UserProfile` (solo en `TrainerPublicProfile`) → el preview los lee de `trainerByIdProvider`, no del provider de edición.
- Grupo de sidebar: se propone `gestion` (adyacente a Chat, sin header nuevo). Ajuste menor a criterio del ejecutor.
- Icono: reusar `TreinoIcon.*` existente o extender `treino_icon.dart` con nombre semántico (ej. `globe`); no prohibido.
