# Producto — TREINO

Reglas de producto: naming, tab bar, roles, scope. Cosas que no son técnicas pero que el agente y el dev necesitan saber **siempre**.

## Naming (crítico — no confundir)

- **TREINO** = nombre de la marca/app. Aparece en logo, splash, App Store, Play Store.
- **Coach** = nombre del módulo y de la pestaña que gestiona Personal Trainers. **No** decirle "TREINO" al tab.
- **Entreno IA** = feature de IA generadora de rutinas. **NO usar** el nombre antiguo "Coach IA". La pantalla en Flutter es `WorkoutAIView`, ruta `/workout/ai`.
- Las clases de dominio del PF mantienen el prefijo `Trainer*` (`TrainerProfile`, `TrainerStudentLink`, etc.) porque describen al actor-persona, no al feature.

## Tab bar (5 tabs, Inicio al medio)

| # | Tab | Ícono | Ruta | Contiene |
|---|---|---|---|---|
| 1 | Entrenar | `TreinoIcon.tabWorkout` | `/workout` | Rutinas, Workout Player, Explore programas, Historial, Entreno IA |
| 2 | Feed | `TreinoIcon.tabFeed` | `/feed` | Amigos · Comunidad · Público (3 segmentos), perfiles, friend requests. Sin PFs. |
| 3 | **Inicio** | `TreinoIcon.tabHome` | `/home` | Mockup Mobile Home (streak, stats, card HOY con CTA, amigos entrenando) |
| 4 | Coach | `TreinoIcon.tabCoach` | `/coach` | Discovery cercana, mis coaches, chat, agenda, planes asignados. Vista distinta según rol. |
| 5 | Perfil | `TreinoIcon.tabProfile` | `/profile` | Datos, gym, apariencia (toggle paleta), ajustes, logout |

**Lógica del orden**:
- Izquierda (acción): Entrenar + Feed.
- Centro: Inicio (home base).
- Derecha (gestión): Coach + Perfil — caen cómodas bajo el pulgar derecho.

**Discovery de PFs vive sólo en la tab Coach**. El Feed es 100% social.

## Roles del producto (inmutables)

- `UserProfile.role`: `"athlete" | "trainer"`. **Inmutable** después de la creación.
- Signup público (email / Google / Apple) **siempre** crea `role = "athlete"`. Una regla Firestore lo fuerza:
  ```
  match /users/{uid} {
    allow create: if request.auth.uid == uid
                  && request.resource.data.role == "athlete";
    allow update: if request.auth.uid == uid
                  && request.resource.data.role == resource.data.role;
  }
  ```
- Cuentas de **trainers** sólo se crean **manualmente** por el equipo TREINO vía Firebase Admin SDK. No hay UI self-service para volverse PF.
- En la app, link discreto en login: `¿Sos entrenador? Pedí tu alta` que abre form externo (Tally/Typeform).

### Vistas según rol en la tab Coach

- **`role == "athlete"`**: header con filtros + carrusel "En tu gym" + sección "Cerca tuyo" + sección "Mis coaches".
- **`role == "trainer"`**: pestañas DASHBOARD · ALUMNOS · AGENDA · COMUNIDADES.

No hay toggle interno entre vistas — el rol es uno solo y se elige al crear la cuenta.

## Out of scope — NO implementar

Aunque el repo viejo (`gymrankiOS` / `gymrank` Android) los tenía, en TREINO Flutter quedan **fuera**:

- Ranking (global, semanal, mensual, gym)
- Retos / Challenges
- Missions
- Bets
- Levels / XP / Puntos comparativos
- Gamificación en general

Si el usuario pide implementar alguno, **frená y confirmá** antes de hacerlo — viola scope acordado.

## Tono y voz (microcopy)

- **Vos-form rioplatense**: "entrená hoy", "empezá", "no rompas la racha".
- **CTAs imperativos en mayúsculas**: `EMPEZAR ENTRENAMIENTO`, `VER TODO`, `CARGAR PLAN`.
- **Sin signos de apertura** (`¡ ¿`).
- **Sin copy corporativo** ("¡Bienvenido a tu viaje fitness!" ❌).
- Frases cortas, directas, accionables.
- Números siempre con unidad al lado y más chica: `12 días`, `55 min`, `4.8k XP`.

## Stat de "volumen" en el Home

`volumen = Σ (peso × reps × sets)` de la semana, en kg. Para bodyweight usa el peso del usuario. Cardio e isométricos no aportan volumen.

Formato:
- < 1.000 kg → mostrar `876` directo, sin `k`.
- 1.000 – 99.999 kg → `12.4k`.
- ≥ 100.000 kg → `124k`.
- ≥ 1.000.000 kg → `1.2M`.
