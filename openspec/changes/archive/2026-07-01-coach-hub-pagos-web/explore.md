# Exploration: coach-hub-pagos-web

Fase W4.2 — Sección Pagos del Coach Hub web (`/pagos`, NEGOCIO group).
Scope locked: manual tracking + WhatsApp reminder. NO gateway.

---

## Current State

### 1. Domain — Payment & AthleteBilling

**`lib/features/payments/domain/payment.dart`** (lines 10-36)

```dart
enum PaymentStatus { pending, paid }

class Payment {
  String id, trainerId, athleteId, concept;
  int amountArs;
  PaymentStatus status;
  String? periodKey;   // "2026-06" for mensual, "2026-W24" for semanal, null otherwise
  DateTime createdAt;
  DateTime? paidAt;
}
```

**Critical for 3-tab grouping**: `Payment` has NO `dueDate` field. The mockup shows "Vencido 4d", "En 4 días" — these durations are NOT stored in Firestore. They must be derived client-side from `createdAt` + cadence info (via `AthleteBilling`), or defined purely by the pending/paid state plus recurrence period.

**State derivation**:
- **Activos** (current period unpaid) → `pagosPorCobrarProvider` already derives these as `CobroPendiente` per athlete.
- **Vencidos** (past periods unpaid) → NOT currently computed. `pagosPorCobrarProvider` only checks the CURRENT period. A payment from a prior period that was never settled has no explicit record; the only trace is the absence of a paid record with a matching past `periodKey`. Deriving "past overdue" is non-trivial client-side.
- **Cobrados** (paid) → `Payment` with `status == PaymentStatus.paid`.

**`lib/features/payments/domain/athlete_billing.dart`** (lines 11-38)

```dart
enum BillingCadence { mensual, semanal, porSesion, suelto }

class AthleteBilling {
  String trainerId, athleteId;
  int amountArs;
  BillingCadence cadence;
  DateTime updatedAt;
}
```

No `dueDate` here either. "Vencido" in the mockup likely means pending Payment docs whose `createdAt` is older than the current period (suelto charges created weeks ago), not a computed "missed monthly". The mockup's "Vencido Nd" counter is probably N days since `createdAt` of the pending payment.

### 2. Payments Repository

**`lib/features/payments/data/payment_repository.dart`**

| Method | Query shape | Notes |
|--------|-------------|-------|
| `add(Payment)` | write | auto-id doc |
| `markPaid(id, paidAt)` | update status+paidAt | single doc |
| `markManyPaid(ids, paidAt)` | batch update | for suelto bundles |
| `watchForTrainer(trainerId)` | `where('trainerId', isEqualTo: trainerId)` | returns ALL trainer payments, all athletes |
| `watchForAthlete(athleteId)` | `where('athleteId', isEqualTo: athleteId)` | athlete vantage |

Single-field queries — no composite index required. `watchForTrainer` is exactly what the `/pagos` section needs.

### 3. Application — Providers

**`lib/features/payments/application/payment_providers.dart`**

- `trainerPaymentsProvider` — `StreamProvider.autoDispose<List<Payment>>` — live stream of ALL payments for the current trainer across ALL athletes. **This is the primary provider for the /pagos section.**
- `athletePaymentsProvider` — athlete-vantage (not relevant here).

**`lib/features/payments/application/billing_providers.dart`**

- `athleteBillingProvider` — `StreamProvider.autoDispose.family<AthleteBilling?, String>` — per-athlete billing config for current trainer.
- `athleteBillingPairProvider` — athlete vantage (not relevant here).

**`lib/features/payments/application/pagos_por_cobrar_provider.dart`**

- `pagosPorCobrarProvider` — `Provider.autoDispose<AsyncValue<List<CobroPendiente>>>` — derives pending charges per active athlete from `trainerPaymentsProvider` + `athleteBillingProvider` + sessions. Already watches `trainerPaymentsProvider` for the trainer-wide payment stream. **Perfectly reusable for the "Activos" tab.**

**`lib/features/payments/application/mi_cuota_provider.dart`**

- `miCuotaProvider` — athlete vantage. Not relevant.

**CRITICAL QUESTION — trainer-wide aggregation**: `trainerPaymentsProvider` already exists at `payment_providers.dart:16`. It streams all payments across all athletes for the trainer. The gap is NOT the provider — it exists. The gap is a **derived provider** that categorizes payments into the 3 mockup tabs (Activos / Vencidos / Cobrados) with athlete names and a "days overdue/remaining" computation.

### 4. Existing Per-Athlete Pagos Actions (commits #188 / #190)

All in **`lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart`**:

| Widget/Function | Lines | API |
|---|---|---|
| `_PagosTab` | 999-1071 | `ConsumerWidget`, takes `athleteId`. State-of-account card + payment history table. |
| `_EstadoCuentaCard` | 1073-1194 | `StatefulWidget`. Props: `palette, pending: List<CobroPendiente>, onMarcarPagado`. Renders pending charges with in-flight dedup guard. |
| `_RegistrarPagoDialog` | 1311-1401 | `StatefulWidget`. Returns `({int amount, String concept})` via `Navigator.pop`. |
| `_PagosTable` | 1403-1485 | `StatelessWidget`. Props: `payments: List<Payment>, palette`. Columns: FECHA / CONCEPTO / MONTO / ESTADO. |
| `_marcarPagado(context, ref, CobroPendiente)` | 1221-1276 | Top-level function. `AlertDialog` confirm → `markManyPaid` (suelto) or `repo.add` (recurring). Full cadence switch. |
| `_registrarPago(context, ref, athleteId)` | 1278-1309 | Top-level function. Opens `_RegistrarPagoDialog` → `repo.add(Payment(..., status: paid))`. |
| `_paidPaymentFor(...)` | 1203-1219 | Helper that builds a paid `Payment` with correct `periodKey`. |
| `_fmtArs(int)` | 934-943 | Formats `28000 → "$28.000"`. |
| `nextDueDate(AthleteBilling, DateTime)` | 974-986 | Returns next due `DateTime` for mensual/semanal, null for porSesion/suelto. |
| `fmtDayMonth(DateTime)` | 969-970 | `"22 mayo"` format. |

**Reuse strategy**: `_RegistrarPagoDialog`, `_EstadoCuentaCard`, `_PagosTable`, `_marcarPagado`, `_registrarPago` and all formatting helpers are currently private (underscore prefix) inside `alumno_detail_screen.dart`. They must be extracted to a shared location (e.g. `lib/features/coach_hub/presentation/sections/pagos/widgets/`) to be reused in the new `/pagos` section without duplication.

### 5. WhatsApp Deep Link

No existing `wa.me` deep link in the codebase. `url_launcher: ^6.3.0` is already in `pubspec.yaml` (line 57) and used in `lib/features/workout/presentation/widgets/exercise_video_player.dart` (lines 70-72) with `launchUrl(uri, mode: LaunchMode.inAppBrowserView)`. The pattern for WhatsApp would be:

```dart
final uri = Uri.parse('https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}');
await launchUrl(uri, mode: LaunchMode.externalApplication);
```

`paymentAlias` field exists on `UserProfile` (`lib/features/profile/domain/user_profile.dart:52`) and is editable in `profile_edit_trainer_screen.dart:59`. The WhatsApp message template would embed this alias: "Hola [nombre], te recuerdo el pago de [concepto] — [monto]. Podés transferir a: [paymentAlias]".

The trainer's phone number is NOT stored in `UserProfile`. The `wa.me` link requires a phone number as the target, not the trainer's own number — it's a reminder SENT TO THE ATHLETE. The athlete's phone is also not in `UserPublicProfile`. This is a gap: the reminder button needs the athlete's WhatsApp number, which doesn't exist in the data model.

**Alternative**: use `wa.me` without a number as a deep link to open WhatsApp for the trainer to manually select the conversation (`https://wa.me/`), or use the trainer's share link approach. This needs a decision before implementation.

### 6. Mockup Layout

**`docs/web-trainer/screens/pagos/pagos.png`**

The mockup shows:
- **Header**: "PAGOS" title + subtitle "Gestión, comunicación e ingresos"
- **Action buttons**: "Exportar" + "+ Registrar pago" (top right)
- **KPI row** (4 cards): "INGRESO DEL MES $642k (36 cobrados)", "PENDIENTE COBRAR $96k (6 alumnos)", "VENCIDO $82k (3 alumnos · -15%)", "PROYECTADO MES $738k (53 cobros pagos)"
- **Tab bar**: "Vencidos · 3 | Por vencer · 5 | Pagados · 16 | Todos"
- **Table columns**: ALUMNO · PLAN · MONTO · VENCIMIENTO · ESTADO · ACCIONES
- **Row actions**: "Recordar" (WhatsApp reminder) + "Marcar pagado"
- **Status badges**: "Vencido 4d", "Vencido 12d", "En 4 días", "En 9 días"
- **Month selector**: "Abril 2026" (suggests filtering by month)

**Tab semantics from mockup**:
- "Vencidos" = payments overdue (past their expected payment date)
- "Por vencer" = payments due soon (within current period, not yet overdue)
- "Pagados" = paid payments for the period
- "Todos" = all payments

The mockup uses "PLAN" column (Premium / Basico) — this maps to `BillingCadence` labels, not to a subscription plan. The "VENCIMIENTO" date column is NOT in the `Payment` model — it would need to be derived from `createdAt` + cadence period logic.

### 7. Section Contract (Coach Hub Web)

Confirmed from `agenda_web_screen.dart` (lines 1-36) and `alumno_detail_screen.dart` (lines 43-46):
- `ConsumerStatefulWidget` (if state needed) or `ConsumerWidget`
- NO `Scaffold` / NO `SafeArea` — shell provides chrome (ADR-CHW-005)
- `showDialog` / `AlertDialog` — NO bottom sheets
- `AppPalette.of(context)` for colors
- Spanish hardcoded + `// i18n` comment markers
- NO `AppL10n`
- Sidebar item registered in `sections/pagos/routes.dart` via `pagosSidebarItems` (already exists, currently points to `ProximamenteScreen`)

### 8. Firestore Rules

**`firestore.rules` lines 683-697**:

```
match /payments/{paymentId} {
  allow read: if request.auth != null
              && (request.auth.uid == resource.data.trainerId
                  || request.auth.uid == resource.data.athleteId);
  ...
}
```

The read rule allows individual-document reads for trainer or athlete. The `watchForTrainer(trainerId)` query uses `where('trainerId', isEqualTo: trainerId)` — this is a **collection-level query** that the rules engine evaluates differently. In Firestore, a collection query is only allowed if the rules allow reading EVERY document that could match. Since the rule checks `resource.data.trainerId == request.auth.uid`, a query on `trainerId == auth.uid` is consistent and **already works** (confirmed by `trainerPaymentsProvider` being in active use). No rule gap.

---

## Affected Areas

- `lib/features/coach_hub/presentation/sections/pagos/routes.dart` — replace `ProximamenteScreen` with real screen
- `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` — extract shared widgets to pagos/widgets/
- `lib/features/payments/application/payment_providers.dart` — `trainerPaymentsProvider` already exists, no changes needed
- `lib/features/payments/application/pagos_por_cobrar_provider.dart` — `pagosPorCobrarProvider` reused as-is for "Activos" tab
- New files to create (presentation layer only):
  - `lib/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart`
  - `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_kpi_row.dart`
  - `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_table.dart`
  - `lib/features/coach_hub/presentation/sections/pagos/widgets/registrar_pago_dialog.dart` (extracted from alumno_detail_screen)
  - `lib/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_helpers.dart` (extracted from alumno_detail_screen)

---

## Gap Analysis

| Gap | Severity | Notes |
|-----|----------|-------|
| "Vencido" state derivation | Medium | `Payment` has no `dueDate`. "Vencidos" tab requires deriving past-period debts from `createdAt` + cadence. For `suelto` charges: `pending` payment with `createdAt` older than N days = overdue. For recurring: absence of a paid record for a past `periodKey`. Needs a local provider that computes this from `trainerPaymentsProvider` + `athleteBillingProvider`. |
| WhatsApp athlete phone number | High | `wa.me/{phone}` requires the athlete's phone. Athlete phone is NOT in `UserPublicProfile`. Options: (a) open WhatsApp share with pre-filled message (trainer picks contact), (b) add phone field to `UserPublicProfile` (new backend), (c) skip pre-filling and just copy message to clipboard. Which is acceptable for V1? |
| KPI row metrics | Medium | "INGRESO DEL MES", "PROYECTADO MES" require month-scoped aggregation from `trainerPaymentsProvider`. Pure client-side computation from the existing stream — no new backend query needed. |
| "VENCIMIENTO" column date | Low | Not stored. Must derive next-period due date from `AthleteBilling.cadence` + `createdAt`. `nextDueDate()` helper already exists in `alumno_detail_screen.dart:974`. |
| Widget extraction | Medium | `_RegistrarPagoDialog`, `_EstadoCuentaCard`, `_marcarPagado`, `_paidPaymentFor`, `_fmtArs`, `nextDueDate`, `fmtDayMonth` are all private. Must promote to shared location — a refactor PR that shouldn't change behavior. |
| Month filter | Low | Mockup shows "Abril 2026" selector. Simple client-side filter on `createdAt` month from the existing stream. |

---

## Approaches

### Approach A — Flat list with client-side grouping (recommended)

Use `trainerPaymentsProvider` (existing) + `pagosPorCobrarProvider` (existing) as data sources. Derive the 4 tabs entirely client-side in a new `pagosWebSectionProvider`:

- **Activos (Por vencer)**: athletes that appear in `pagosPorCobrarProvider` — current period pending. Already computed.
- **Vencidos**: pending `Payment` docs where `createdAt` is older than the current period boundary. For `suelto`: any `pending` payment older than 30 days (configurable). For recurring: no explicit Firestore record — would need to flag athletes that have no paid record for N past periods (complex).
- **Cobrados (Pagados)**: `Payment` docs with `status == paid` filtered by selected month.
- **Todos**: full `trainerPaymentsProvider` list filtered by month.

Pros:
- Zero new Firestore reads (reuses existing streams)
- No new domain/repository code
- Consistent with "REUSE mobile 100%" constraint

Cons:
- "Vencidos" for recurring cadences is approximated (can't perfectly reconstruct past missed periods without a separate audit trail)
- Provider gets moderately complex

Effort: **Low-Medium** (new derived provider ~80 lines + new screen ~300 lines)

### Approach B — Derived provider with explicit overdue flag

Same as A, but define "Vencido" strictly as: a `pending` Payment document (any cadence) where `createdAt` is before the current period start. This maps directly to Firestore data without cadence inference:

- "Vencido" = `status == pending AND createdAt < periodStart`
- "Por vencer" = `status == pending AND createdAt >= periodStart` (current period)
- "Cobrado" = `status == paid`

This is simpler and fully data-driven. The tradeoff: it only catches recurring charges that the trainer explicitly created as Payment docs (via "Registrar pago"). For athletes on `mensual` / `semanal` cadence who were NEVER explicitly charged (no payment doc exists), they won't appear as "Vencidos" — only in "Por vencer" via `pagosPorCobrarProvider`.

Pros:
- Simple derivation logic
- Fully consistent with Firestore data
- No guessing about past periods

Cons:
- Doesn't surface athletes who were never explicitly charged for past periods
- May undercount "Vencidos" compared to what a trainer expects

Effort: **Low** (simple filter on the existing stream)

### Approach C — New Firestore index + backend query for "overdue"

Add a composite index on `(trainerId, status, createdAt)` and query past-period pending payments directly. Compute period start in the app, pass as a Firestore `where` clause.

Pros:
- Accurate at scale (no client-side list iteration)
- True server-side filtering

Cons:
- Requires a new composite index (infra change)
- Still can't reconstruct "missed months" without explicit payment records
- Adds complexity for marginal gain at trainer scale (< 100 athletes)

Effort: **Medium** (index + new repository method + new provider)

---

## Recommendation

**Approach B** for the initial implementation, with a path to A for the "missed recurring periods" feature later.

Rationale:
1. The scope is locked to manual tracking — trainers manually register and mark payments. "Vencido" in that model = a manually-created pending payment that's old. This is exactly what Approach B computes.
2. Zero new backend code, no composite index.
3. Consistent with the mobile app's philosophy: `pagosPorCobrarProvider` already handles "current period pending"; the `/pagos` section adds the historical view.
4. The WhatsApp gap (no athlete phone) should be resolved as "open WhatsApp with pre-filled message, trainer picks contact" — `wa.me` without phone, or a system share sheet. This is a product decision that should be confirmed before implementing the reminder button. For V1, render the "Recordar" button as disabled with a tooltip or implement via `launchUrl('https://wa.me/?text=...')`.

---

## Open Questions

1. **WhatsApp reminder mechanics**: target is the athlete, but their phone is not stored. Options: (a) open WhatsApp share with pre-filled message (trainer picks contact), (b) add phone field to `UserPublicProfile` (new backend), (c) skip pre-filling and just copy message to clipboard. Which is acceptable for V1?

2. **"Vencidos" definition**: should it be strictly data-driven (pending Payment docs with old `createdAt`) OR should it also surface athletes on recurring cadences with no paid record for a past period (even if no Payment doc was ever created for that period)?

3. **KPI cards**: the mockup shows 4 aggregate KPIs including "PROYECTADO MES". Is projected revenue in scope for W4.2 or deferred?

4. **Month selector**: is the "Abril 2026" filter a hard requirement for W4.2 or can it ship as "current month only"?

5. **Widget extraction refactor**: should the extraction of `_RegistrarPagoDialog` etc. from `alumno_detail_screen.dart` be a separate PR (prerequisite) or bundled into the same W4.2 PR?

---

## Risks

- **"Vencido" derivation gap**: the data model has no explicit `dueDate`. If the product expectation is "automatically detect athletes who missed a monthly payment even if no payment doc was created", this cannot be derived from existing Firestore data without additional writes (e.g., a scheduled Cloud Function that creates "missed" payment records). This would be a significant scope expansion.
- **WhatsApp athlete phone**: not in the data model. Any "send reminder directly to athlete's WhatsApp" requires either storing the phone number (new backend field) or a different UX (trainer picks contact manually).
- **Widget coupling**: `_marcarPagado` reads `currentUidProvider` and `paymentRepositoryProvider` via `ref` — it's tightly coupled to the provider graph but is otherwise stateless w.r.t. athleteId. Extraction is safe.
- **`url_launcher` on web**: `launchUrl` is already used in the project and works on web for `externalApplication` mode. No new dependency needed.

---

## Ready for Proposal

Yes. The billing surface is well-understood, `trainerPaymentsProvider` already covers the trainer-wide data need, `pagosPorCobrarProvider` covers the "Activos" grouping, and the dialog/table widgets exist and need extraction. The only blockers before proposing are the two product decisions (WhatsApp UX + "Vencidos" definition).
