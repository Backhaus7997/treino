# Design — Coach Hub Web: Pagos Section (W4.2)

Change: `coach-hub-pagos-web` · Project: treino · Repo: `C:\Users\Martin\Desktop\treino\treino`
Phase: design (the HOW at architectural level). Presentation-only, reuse-first, zero backend change.

All decisions below are grounded in the real code (file + line references inline).

---

## 0. Ground truth verified in code

| Fact | Source | Confirmed value |
|---|---|---|
| `Payment` shape | `payments/domain/payment.dart:22-32` | `id, trainerId, athleteId, amountArs:int, concept, status, periodKey?:String, createdAt:DateTime, paidAt?:DateTime`. NO `dueDate`. |
| Trainer-wide stream | `payments/application/payment_providers.dart:16-22` | `trainerPaymentsProvider` = `StreamProvider.autoDispose<List<Payment>>`, filters `trainerId==uid`. Primary source. |
| Current-period pending | `payments/application/pagos_por_cobrar_provider.dart:98` | `pagosPorCobrarProvider` = `Provider.autoDispose<AsyncValue<List<CobroPendiente>>>`. |
| **Period key = source of truth** | `pagos_por_cobrar_provider.dart:136-142` | `now = DateTime.now().toUtc()`; `monthKey = '$year-${month.padLeft(2,'0')}'`; `weekKey = isoWeekPeriodKey(now)`. **Calendar month, UTC.** |
| One-off pending handling | `pagos_por_cobrar_provider.dart:157-170` | ALL `status==pending` docs per athlete are surfaced as a single `CobroPendiente(cadence: suelto)`, regardless of billing config. This is the ONLY source of `pending` docs (recurring charges are derived, not stored as pending). |
| Athlete name resolution | `alumnos_screen.dart:97-110` | `userPublicProfilesBatchProvider(ids.join(','))` — chunked batch, no N+1. Proven roster pattern. |
| Trainer's own profile | `profile/application/user_providers.dart:19` | `userProfileProvider` = `StreamProvider<UserProfile?>`. |
| `paymentAlias` | `profile/domain/user_profile.dart:52` | `String? paymentAlias` on `UserProfile`. Nullable. |
| `url_launcher` idiom | `workout/.../exercise_video_player.dart:67-80` | `launchUrl(uri, mode: LaunchMode.externalApplication)` + try/catch + `ScaffoldMessenger` snackbar on failure. |
| Section contract | `agenda_web_screen.dart:1-8,32-37` | `ConsumerStatefulWidget`, NO Scaffold/SafeArea (shell provides), `AppPalette.of(context)`, es-AR hardcoded + `// i18n`, `showDialog`. |
| Palette tokens | `app/theme/app_palette.dart:21-102` | `accent, bgCard, border, borderHover, textPrimary, textMuted, danger, warning`. No HEX literals allowed (AGENTS.md:44). |
| Icons | AGENTS.md:45 | `TreinoIcon.X` only, never `PhosphorIcons`. |

---

## 1. Widget extraction map (PR1) — RESOLVED shared location

### Resolved shared location
**`lib/features/coach_hub/presentation/sections/pagos/widgets/`**

Rationale: the reuse is confined to two Coach Hub sections (`alumnos` detail + new `pagos`). A broader `lib/features/payments/presentation/` shared dir is rejected — these widgets carry Coach-Hub-specific contract (hardcoded es-AR, no `AppL10n`, `AppPalette`), which is a web-shell convention, not a domain concern. Keeping them under `sections/pagos/widgets/` keeps the ADR-CHW section-ownership model intact and avoids cross-feature coupling. `alumnos` importing from a sibling section's `widgets/` is acceptable (both are Coach Hub presentation; no layering violation).

### Members to extract (all currently private in `sections/alumnos/alumno_detail_screen.dart`)

| Current member | Lines | New public name | New file | Notes |
|---|---|---|---|---|
| `String _fmtArs(int)` | 934-943 | `String fmtArs(int)` | `widgets/payment_format.dart` | drop `_`. Pure fn. |
| `String fmtDayMonth(DateTime)` | 969 | `fmtDayMonth` (already public) | `widgets/payment_format.dart` | already imported by test — move as-is. |
| `DateTime? nextDueDate(AthleteBilling, DateTime)` | 974-986 | `nextDueDate` (already public) | `widgets/payment_format.dart` | already imported by test — move as-is. |
| `const _kMesesLargos` | 952-966 | `kMesesLargos` (lib-private to file) | `widgets/payment_format.dart` | needed by `fmtDayMonth`. Keep top-level in same file. |
| `_RegistrarPagoDialog` | 1313-1401 | `RegistrarPagoDialog` | `widgets/registrar_pago_dialog.dart` | `StatefulWidget`, returns `({int amount, String concept})?` via `Navigator.pop`. Public const ctor `const RegistrarPagoDialog({super.key})`. |
| `_PagosTable` | 1403-1485 | `PagosTable` | `widgets/pagos_table.dart` | `StatelessWidget`, props `payments`, `palette`. Uses `fmtArs` + `_fmtDate`. |
| `_EstadoCuentaCard` + `_EstadoCuentaCardState` | 1073-1194 | `EstadoCuentaCard` | `widgets/estado_cuenta_card.dart` | `StatefulWidget`, props `palette`, `pending`, `onMarcarPagado`. Uses `fmtArs`. |
| `_marcarPagado(ctx, ref, CobroPendiente)` | 1221-1276 | `marcarPagado` | `widgets/marcar_pagado_actions.dart` | plus its helpers `_paidPaymentFor` (1203-1219) → `paidPaymentFor`, `_pagoSnack` (1196-1198) → `pagoSnack`. Depends on `currentUidProvider`, `paymentRepositoryProvider`, `isoWeekPeriodKey`. |
| `_registrarPago(ctx, ref, athleteId)` | 1278-1309 | `registrarPago` | `widgets/marcar_pagado_actions.dart` | opens `RegistrarPagoDialog` → `repo.add`. |

**Dependency notes discovered by reading the code:**
- `_fmtDate` (used by `_PagosTable` at 1450) is a separate private helper elsewhere in the file — must be checked and either extracted alongside `PagosTable` or inlined. (Grep for `_fmtDate` in alumno_detail before the move; it formats `createdAt` as `dd/MM/yyyy` per test line 945 `'10/01/2026'`.)
- `_marcarPagado` uses `isoWeekPeriodKey` (imported from `pagos_por_cobrar_provider.dart`) — the new `marcar_pagado_actions.dart` re-imports it from the same place. Do NOT duplicate the ISO-week logic.
- `EstadoCuentaCard` owns the in-flight double-tap guard (`_inFlight` set, key = `athleteId|cadence|concept|amount`) — MOVE VERBATIM; it prevents double-charging (alumno_detail:1089-1106).

### How `alumno_detail_screen.dart` re-imports
Add at top of `alumno_detail_screen.dart`:
```dart
import 'sections/pagos/widgets/payment_format.dart';           // fmtArs, fmtDayMonth, nextDueDate
import 'sections/pagos/widgets/registrar_pago_dialog.dart';    // RegistrarPagoDialog
import 'sections/pagos/widgets/pagos_table.dart';              // PagosTable
import 'sections/pagos/widgets/estado_cuenta_card.dart';       // EstadoCuentaCard
import 'sections/pagos/widgets/marcar_pagado_actions.dart';    // marcarPagado, registrarPago
```
(Path is relative to `sections/alumnos/`; adjust to `../pagos/widgets/...`.) Then delete the moved definitions and rename call sites: `_fmtArs`→`fmtArs`, `_RegistrarPagoDialog`→`RegistrarPagoDialog`, `_PagosTable`→`PagosTable`, `_EstadoCuentaCard`→`EstadoCuentaCard`, `_marcarPagado`→`marcarPagado`, `_registrarPago`→`registrarPago`. `_PagosTab` (999-1071) STAYS in alumno_detail — it is athlete-scoped, not reused.

### PR1 = pure move, ZERO behavior change — safety net
Existing tests that pin current behavior (must stay green with NO edits to assertions):
- **`test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart`** — 37+ widget tests. Directly relevant:
  - `tab Pagos: al día + sin historial` (588), `pendiente + historial con datos` (601), `suma varios cobros` (654), `monto 7 dígitos` (676), `registrar pago crea Payment` (691), `monto/concepto inválido NO escribe` (718/742), `marcar pagado suelto→markManyPaid` (765), `mensual→periodKey` (796), `semanal→isoWeekPeriodKey` (826), `porSesión→sin periodKey` (857), `cancelar NO escribe` (889).
  - **Public group tests** `nextDueDate` (1189-1234) and `fmtDayMonth` (1236-1244) already `import` these top-level functions from `alumno_detail_screen.dart`. AFTER the move, the test's import path must be updated to `payment_format.dart` (this is a test-file edit, allowed in PR1 as part of the mechanical move — it does not change assertions).
- **`test/features/payments/pagos_por_cobrar_payments_error_test.dart`** — pins provider error behavior (untouched by extraction; provider is not modified).

**PR1 gate**: `flutter analyze` 0 issues + `dart format .` + full test suite green. Because the extraction includes a test-import update, run the alumno_detail test explicitly.

---

## 2. Vencido / Por vencer period boundary — CRITICAL correctness

### Where the boundary comes from
`periodKey` is the source of truth (`pagos_por_cobrar_provider.dart:141-142`), but **the pending docs that become `Vencido` are one-off (`suelto`) charges that have NO `periodKey`** (they are ad-hoc `+ Cobro` entries; recurring charges are derived, never persisted as `pending`). Therefore the only usable boundary for a stored pending doc is its `createdAt` compared against the **calendar-month start** — the SAME `now`/month definition `pagosPorCobrarProvider` uses.

Current period start (UTC, matches the provider's `now`):
```dart
final now = DateTime.now().toUtc();
final periodStart = DateTime.utc(now.year, now.month, 1); // 1st of current calendar month, UTC
```

### The exact Vencido predicate
```dart
bool isVencido(Payment p) =>
    p.status == PaymentStatus.pending &&
    p.createdAt.toUtc().isBefore(periodStart);
```

### Why this is exactly ONE-OF {Por vencer, Vencido} with no overlap, no gap
- **Por vencer** = `pagosPorCobrarProvider`. For one-off pending docs it surfaces EVERY `status==pending` doc for the athlete (provider lines 157-170) — it does NOT filter by period. So on its own, "Por vencer" would include old pending docs too.
- To make the two buckets **partition** the pending set, the web layer splits the SAME pending docs by `createdAt` against `periodStart`:
  - `createdAt >= periodStart` → **Por vencer** (current period).
  - `createdAt < periodStart` → **Vencido** (a prior period, still unpaid).
- A pending doc has exactly one `createdAt`, so it lands in exactly one bucket. No overlap. No gap.

**IMPORTANT nuance (documented, not a bug):** `pagosPorCobrarProvider` aggregates all pending one-offs of an athlete into a single `CobroPendiente`. For the Por-vencer TAB we therefore have two consistent options — pick **Option A** for correctness:
- **Option A (chosen):** derive BOTH buckets directly from `trainerPaymentsProvider` pending docs, splitting by `createdAt` vs `periodStart`. This guarantees the partition at the raw-doc level and gives per-payment rows (needed for per-row `Marcar pagado` / `Recordar`).
- Option B (rejected for the tab): use `pagosPorCobrarProvider` for Por vencer. Rejected because its aggregation collapses multiple pending docs into one row (loses per-row actions) and it also injects DERIVED recurring charges (mensual/semanal/porSesión) that have no Firestore doc — those cannot be "reminded" or shown in a stable per-payment table. `pagosPorCobrarProvider` remains the source for the **Pendiente cobrar KPI** (section 4), where its cadence-aware total is exactly what we want.

### Bucketing logic (per-payment, tab-level)
```dart
final all = trainerPaymentsProvider.value; // List<Payment>, trainerId==uid
final now = DateTime.now().toUtc();
final periodStart = DateTime.utc(now.year, now.month, 1);

final paid      = all.where((p) => p.status == PaymentStatus.paid);
final pending   = all.where((p) => p.status == PaymentStatus.pending);
final vencidos  = pending.where((p) => p.createdAt.toUtc().isBefore(periodStart));
final porVencer = pending.where((p) => !p.createdAt.toUtc().isBefore(periodStart));
final todos     = all;
```
Sort each bucket by `createdAt` DESC (same as alumno_detail history, line 1020).

---

## 3. Provider / state wiring

### New web-only derived provider (nothing added to shared payments layer)
File: `sections/pagos/widgets/pagos_buckets_provider.dart` (or co-located in the screen file; a named provider is cleaner for testing).

```dart
/// 4-tab bucketing of the trainer's payments. Web-only (Coach Hub Pagos).
/// Composes trainerPaymentsProvider only — does NOT touch the shared
/// payments layer. autoDispose bounds the listener to the section lifetime.
class PagosBuckets {
  const PagosBuckets({
    required this.vencidos,
    required this.porVencer,
    required this.pagados,
    required this.todos,
  });
  final List<Payment> vencidos;
  final List<Payment> porVencer;
  final List<Payment> pagados;
  final List<Payment> todos;
}

final pagosBucketsProvider =
    Provider.autoDispose<AsyncValue<PagosBuckets>>((ref) {
  final async = ref.watch(trainerPaymentsProvider);
  return async.whenData((all) {
    final now = DateTime.now().toUtc();
    final periodStart = DateTime.utc(now.year, now.month, 1);
    final sorted = [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pending = sorted.where((p) => p.status == PaymentStatus.pending);
    return PagosBuckets(
      vencidos: pending
          .where((p) => p.createdAt.toUtc().isBefore(periodStart))
          .toList(),
      porVencer: pending
          .where((p) => !p.createdAt.toUtc().isBefore(periodStart))
          .toList(),
      pagados:
          sorted.where((p) => p.status == PaymentStatus.paid).toList(),
      todos: sorted,
    );
  });
});
```
- Placement: keep it in `sections/pagos/` (presentation feature). It is NOT in `lib/features/payments/*` — constraint honored.
- Loading/error propagate straight from `trainerPaymentsProvider` via `whenData`.

### Athlete display names (reuse the roster pattern verbatim)
```dart
final ids = (buckets.todos.map((p) => p.athleteId).toSet().toList()..sort());
final profilesAsync = ref.watch(userPublicProfilesBatchProvider(ids.join(',')));
// name = profiles[p.athleteId]?.displayName ?? 'Alumno'  // i18n fallback
```
Single chunked read, no N+1 (matches `alumnos_screen.dart:97-99`).

### Tab state — `TabController`
Use a `TabController` (`SingleTickerProviderStateMixin` on the section state) — NOT a `StateProvider<int>`. Rationale: `alumno_detail_screen` already drives its tab bar with a `TabController`; the tab index is pure ephemeral UI state local to this screen, has no cross-widget consumers, and does not need to survive rebuilds/navigation. A provider would be over-engineering. The Row-action callbacks (`Marcar pagado`, `Recordar`) read `ref` from the `ConsumerState`.

---

## 4. KPI computation (client-side, from the streams)

Row of 3 cards. `now = DateTime.now().toUtc()`, `monthKey = '$year-${month.padLeft(2,'0')}'`, `periodStart = DateTime.utc(now.year, now.month, 1)`.

| KPI | Formula | Source |
|---|---|---|
| **Ingreso del mes** | `sum(amountArs)` over `paid` payments where `paidAt` (fallback `createdAt`) is in the current calendar month: `d.year==now.year && d.month==now.month`. | `trainerPaymentsProvider` (`pagosBucketsProvider.pagados`, then filter by paid date). |
| **Pendiente cobrar** | `pagosPorCobrarProvider.valueOrNull.fold(0, (s,c) => s + c.amountArs)`. | `pagosPorCobrarProvider` — cadence-aware total (mensual/semanal/porSesión + one-offs). This is the semantically correct "what's owed this period" number and matches the per-athlete card in alumno_detail (line 1128). |
| **Vencido** | `buckets.vencidos.fold(0, (s,p) => s + p.amountArs)`. | `pagosBucketsProvider.vencidos`. |

**Ingreso del mes date choice:** use `paidAt ?? createdAt`. For rows created via `registrarPago`/`marcarPagado`, `paidAt == createdAt == now` (alumno_detail:1217-1218, 1297-1298), so both agree; `paidAt` is the semantically correct field and the `??` guards legacy docs without `paidAt`.

**Proyectado mes — DROPPED.** Rationale: a meaningful projection needs "expected recurring revenue for the month across all athletes" = sum of each active athlete's `billing.amountArs` normalized to a month by cadence (weekly ×~4.33, per-session = unknowable). That requires reading every athlete's `athleteBillingProvider` and a cadence-normalization model — NOT trivially client-side, and per-session has no deterministic monthly value. It is not in the W4.2 success criteria. Ship 3 KPIs; leave the 4th slot out (or a muted "—" placeholder if the layout needs 4 cells). Documented as V2.

---

## 5. WhatsApp reminder

### Message template
```dart
String reminderText(Payment p, String? paymentAlias) {
  final monto = fmtArs(p.amountArs);            // "$28.000"
  final base = 'Hola! Te recuerdo el pago de ${p.concept} por $monto.'; // i18n
  final alias = (paymentAlias == null || paymentAlias.trim().isEmpty)
      ? ''
      : ' Podés transferir a: ${paymentAlias.trim()}';                   // i18n
  return '$base$alias';
}
```
- `paymentAlias` comes from `ref.watch(userProfileProvider).valueOrNull?.paymentAlias` (the TRAINER's own profile, `user_profile.dart:52`).
- **Null / empty alias handled:** the alias sentence is simply omitted; the reminder still sends monto + concepto. No crash, no "null" string.

### Exact `url_launcher` call (matches `exercise_video_player.dart:67-80`)
```dart
Future<void> recordar(BuildContext context, Payment p, String? alias) async {
  final text = Uri.encodeComponent(reminderText(p, alias)); // percent-encode
  final uri = Uri.parse('https://wa.me/?text=$text');
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos abrir WhatsApp.')), // i18n
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No pudimos abrir WhatsApp.')), // i18n
    );
  }
}
```
- `wa.me/?text=` (NO phone) — trainer picks the contact in WhatsApp. Athlete phone is not stored (explore gap confirmed: not in `UserPublicProfile`).
- Encoding: `Uri.encodeComponent` on the message body only (not the whole URL) so spaces/accents/`$` are safe.
- On web builds `LaunchMode.externalApplication` opens `wa.me` in a new tab → WhatsApp Web/app; identical idiom to the existing YouTube launcher.

---

## 6. Screen structure + PR2 file list

### `PagosScreen` widget tree (`ConsumerStatefulWidget`, no Scaffold)
```
PagosScreen (ConsumerStatefulWidget, SingleTickerProviderStateMixin)
  build:
    palette = AppPalette.of(context)
    bucketsAsync = ref.watch(pagosBucketsProvider)
    trainerProfile = ref.watch(userProfileProvider)   // for paymentAlias
    pendienteAsync = ref.watch(pagosPorCobrarProvider) // for Pendiente KPI
    bucketsAsync.when(
      loading -> CircularProgressIndicator
      error   -> muted 'No se pudieron cargar los pagos.'  // i18n
      data(buckets) ->
        SingleChildScrollView( padding 24 )
          Column(stretch)
            _SectionHeader('PAGOS', subtitle '<n> pagos registrados')   // i18n
            SizedBox(18)
            PagosKpiRow(ingresoMes, pendienteCobrar, vencido)            // widget
            SizedBox(18)
            TabBar(controller: _tab, tabs: [
              'Vencidos·${buckets.vencidos.length}',
              'Por vencer·${buckets.porVencer.length}',
              'Pagados·${buckets.pagados.length}',
              'Todos',                                                   // i18n
            ])
            SizedBox(12)
            IndexedStack(index: _tab.index) OR per-tab PagosWebTable(
              rows: bucket, profiles: profilesMap, palette,
              onMarcarPagado: (p) => marcarPagadoDoc(...),   // pending only
              onRecordar:     (p) => recordar(context, p, alias),
              showActions: tab != Pagados,
            )
```
- NO `Scaffold`/`SafeArea` (ADR-CHW-005). The shell provides chrome.
- Actions column: `Recordar` + `Marcar pagado` shown for pending rows (Vencidos/Por vencer/Todos-pending); Pagados rows show only status.
- `Marcar pagado` for a raw pending doc = `repo.markManyPaid([p.id], now)` (these are one-off `suelto` docs) — reuse `paymentRepositoryProvider`. This is a THIN new action distinct from the cadence-aware `marcarPagado(CobroPendiente)` extracted in PR1 (which stays for the estado-de-cuenta card). Do not conflate the two.

### PR2 new files
| File | Content | ~lines |
|---|---|---|
| `sections/pagos/pagos_web_screen.dart` | `PagosScreen` + `_SectionHeader` + tab wiring + row-action callbacks (`recordar`, `marcarPagadoDoc`) | ~230 |
| `sections/pagos/widgets/pagos_buckets_provider.dart` | `PagosBuckets` + `pagosBucketsProvider` | ~45 |
| `sections/pagos/widgets/pagos_kpi_row.dart` | `PagosKpiRow` (3 KPI cards, `AppPalette`) | ~90 |
| `sections/pagos/widgets/pagos_web_table.dart` | trainer-wide table: ALUMNO·MONTO·FECHA·ESTADO·ACCIONES (distinct from PR1's athlete-scoped `PagosTable`) | ~140 |
| `test/.../sections/pagos/pagos_web_screen_test.dart` | bucketing, KPI totals, Vencido boundary, WhatsApp URL, Marcar pagado write | ~ (test, not counted in prod budget) |

### Edit to `sections/pagos/routes.dart`
Replace the placeholder (`routes.dart:13-20`):
```dart
final List<RouteBase> pagosRoutes = [
  GoRoute(
    path: '/pagos',
    builder: (_, __) => const PagosScreen(),   // was ProximamenteScreen
  ),
];
```
Add `import '../pagos/pagos_web_screen.dart';` (adjust relative path) and drop the now-unused `proximamente_screen.dart` import. `pagosSidebarItems` (routes.dart:22-30) **unchanged** — it already registers the `/pagos` item.

### Sidebar test trap — DO NOT add a badge
`test/.../shell/sidebar_registry_test.dart:121-125` asserts EVERY item has `badgeProvider == null`. The mockup shows tab counts (`Vencidos·3`) but those live INSIDE the screen's `TabBar`, not on the sidebar item. **Do not set `badgeProvider` on `pagosSidebarItems`** or that test breaks. Tab counts are computed from `pagosBucketsProvider` in the screen.

### Rough line budget (confirm each PR ≤ 400)
- **PR1** (extraction): ~250-320 changed lines — mostly cut/paste moves + 5 renamed call sites in alumno_detail + 1 test-import update. Net new logic ≈ 0.
- **PR2** (screen): ~230 + 45 + 90 + 140 ≈ **~505 prod lines across 4 new files**. RISK: exceeds 400. Mitigation options for apply:
  - The KPI row + table are new widgets, not edits — a reviewer can review them independently. Prefer to keep PR2 as one logical unit but flag `size:exception` OR split PR2 into **PR2a** (screen + buckets provider + KPI row + routes wiring, ~365) and **PR2b** (rich table with per-row WhatsApp/Marcar actions, ~140). Recommend the 2a/2b split to stay under budget cleanly. Final call belongs to the tasks/apply phase per delivery strategy.

---

## 7. ADRs

### ADR-PGW-001 — Shared widget location = `sections/pagos/widgets/`
**Decision:** Extract the reusable payment widgets/formatters into `lib/features/coach_hub/presentation/sections/pagos/widgets/`, made public (drop `_`), and have `alumno_detail_screen.dart` import them.
**Rationale:** Reuse is confined to two Coach Hub sections; the widgets carry Coach-Hub presentation conventions (hardcoded es-AR, no `AppL10n`, `AppPalette`). A domain-level `payments/presentation/` dir would leak web-shell conventions into the shared feature.
**Rejected:** (a) `lib/features/payments/presentation/` — wrong layer, couples domain to Coach Hub UI conventions. (b) A top-level `lib/features/coach_hub/presentation/shared_widgets/` — premature generalization; only `pagos` + `alumnos` consume these.
**Consequence:** `alumnos` imports a sibling section's `widgets/`. Acceptable (both Coach Hub presentation). PR1 is a pure move; behavior pinned by `alumno_detail_screen_test.dart`.

### ADR-PGW-002 — Vencido derivation (Approach B) + calendar-month boundary
**Decision:** `Vencido = status==pending && createdAt.toUtc() < firstDayOfCurrentMonth(UTC)`. `Por vencer = pending && createdAt >= periodStart`. Both derived from raw `trainerPaymentsProvider` docs so they partition the pending set.
**Rationale:** `Payment` has no `dueDate`. `periodKey` is the source of truth for period identity, but stored pending docs are one-off charges without a `periodKey`; their `createdAt` vs the SAME calendar-month start that `pagosPorCobrarProvider` uses (`now.toUtc()`, `DateTime.utc(y,m,1)`) is the only consistent boundary. Splitting the identical pending set by one `createdAt` yields exactly-one-of with no overlap/gap.
**Rejected:** (a) Cloud Function to synthesize missed recurring periods — out of scope (needs backend). (b) Using `pagosPorCobrarProvider` for the Por-vencer tab — its aggregation collapses per-doc rows (kills per-row actions) and injects derived recurring charges with no Firestore doc (un-remindable). It IS used for the Pendiente-cobrar KPI, where a cadence-aware total is correct.
**Consequence:** Vencidos surfaces only EXISTING unpaid one-off docs from prior months; recurring months never explicitly charged are invisible in V1 (documented gap, needs CF for V2).

### ADR-PGW-003 — No-backend WhatsApp via `wa.me/?text=`
**Decision:** `launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication)`, no phone number; message = monto + concepto + trainer `paymentAlias` (alias sentence omitted when null/empty).
**Rationale:** Athlete phone is not stored (`UserPublicProfile` has no phone). `wa.me` without a number lets the trainer pick the contact. Reuses the proven `exercise_video_player.dart` launcher idiom (try/catch + snackbar fallback). Zero backend, zero new data.
**Rejected:** (a) Store athlete phone — schema/privacy change, out of scope. (b) Copy-to-clipboard — worse UX than opening WhatsApp directly.
**Consequence:** One extra tap (contact selection) in WhatsApp. Acceptable for V1.

### ADR-PGW-004 — 2-PR chained delivery
**Decision:** PR1 = pure widget extraction (green tests, no behavior change). PR2 = `/pagos` screen + KPI row + tabs + WhatsApp + routes wiring. If PR2 exceeds 400 lines, split into PR2a (screen+KPI+routes) / PR2b (rich table+actions).
**Rationale:** Extraction is a safe, independently-reviewable refactor that de-risks PR2 and keeps each slice near the 400-line budget. Delivery strategy = `ask-on-risk` (from proposal); the >400 forecast for PR2 is flagged here for the review-workload guard.
**Rejected:** Single mega-PR — >600 lines total, mixes refactor with feature, hard to review/revert.
**Consequence:** Per-PR revert. PR1 revert restores inline privates; PR2 revert restores `ProximamenteScreen`. No data migration.

---

## Constraints honored
- Reuse-only: NO changes to `lib/features/payments/*` or shared providers. `pagosBucketsProvider` lives in `sections/pagos/` (presentation).
- Coach Hub section contract: `ConsumerStatefulWidget`, no Scaffold/SafeArea, `showDialog`/`AlertDialog`, `AppPalette.of(context)` (no HEX), `TreinoIcon` (no PhosphorIcons), es-AR hardcoded + `// i18n`, no `AppL10n`.
- Sidebar registry test invariant preserved (no `badgeProvider`).

## Risks / unresolved
- **PR2 > 400 lines** (Med): mitigated by PR2a/2b split; decision deferred to tasks/apply per `ask-on-risk`.
- **`_fmtDate` location** (Low): must be located in alumno_detail during PR1 and extracted/inlined with `PagosTable`. Verify before moving.
- **Vencido semantic gap** (Med, documented): recurring periods never charged are invisible; V1 surfaces only existing pending docs. Needs CF for V2.
- **Test import update in PR1** (Low): moving `nextDueDate`/`fmtDayMonth` requires updating `alumno_detail_screen_test.dart`'s import to `payment_format.dart`. Mechanical, no assertion change.
