# Delta for Trainer Profile Onboarding (equivalente web, #1331)

**Change**: coach-hub-onboarding-pf-promovido
**Capability**: `trainer-profile-onboarding` (`openspec/specs/trainer-profile-onboarding/spec.md`)
**Detalle normativo**: `../coach-hub/spec.md` (`REQ-CHW-ONB-001..015`). Este delta solo
declara la relación; no duplica escenarios.

## ADDED Requirements

### Requirement: REQ-TPO-WEB-001 — El Hub aplica un gate equivalente a REQ-TPO-GATE-001..004

El Coach Hub MUST aplicar a todo trainer con `!trainerProfileComplete` un gate propio
equivalente a REQ-TPO-GATE-001 (entrada), con salida simétrica y sin ciclos
(REQ-TPO-GATE-002), sin afectar a atletas (REQ-TPO-GATE-003) y sin lógica duplicada del
router de mobile: el Hub usa su propio predicado `hubOnboardingStage`
(`age → identity → pf → done`, ruta única `/completar-perfil`; REQ-CHW-ONB-001..003). El predicado de completitud MUST seguir siendo
`trainerProfileComplete` (única fuente de verdad compartida con mobile). Los routers de
mobile y del Hub son independientes: un PF que completa el perfil en el Hub MUST NOT ver
el gate de mobile (salvo que mobile exija algo que el Hub no pide; hoy no hay diferencia, ya que
la etapa `pf` exige modalidad online o al menos una ubicación).

#### Scenario: SCENARIO-TPO-WEB-001 — Salida del Hub coincide con `trainerProfileComplete` (P)

- GIVEN cualquier combinación de campos de perfil de trainer
- THEN `hubOnboardingStage == done` implica `trainerProfileComplete == true`, y con `bornAt` válido y `displayName` presente, `hubOnboardingStage == pf` si y solo si `!trainerProfileComplete`

#### Scenario: SCENARIO-TPO-WEB-002 — Mobile no gatea tras completar en el Hub (M)

- Ver SCENARIO-CHW-ONB-057.
