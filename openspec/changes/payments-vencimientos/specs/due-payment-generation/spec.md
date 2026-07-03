# Due Payment Generation Specification

## Purpose

Scheduled Cloud Function that persists deterministic pending `Payment` documents for recurring trainer↔athlete billing cadences (mensual, semanal). Replaces the purely in-memory derivation with authoritative Firestore-backed records that carry a real `dueAt` date.

## Requirements

### REQ-VENC-01: Scheduled Trigger

The CF `generateDuePayments` MUST run on a cron schedule of approximately 03:00 ART (America/Sao_Paulo timezone), deployed to region `southamerica-east1`.

#### SCENARIO-VENC-01: Trigger fires at scheduled time

- GIVEN the CF is deployed and the cron schedule is active
- WHEN the clock reaches 03:00 ART on any calendar day
- THEN the CF handler executes without manual invocation
- AND execution is recorded in Cloud Logging

### REQ-VENC-02: Cadence Scope

The CF MUST generate Payment documents only for `AthleteBilling` records whose `cadence` is `mensual` or `semanal`. It MUST NOT generate documents for `porSesion` or `suelto` cadences.

#### SCENARIO-VENC-03: CF skips porSesion and suelto cadences

- GIVEN a trainer↔athlete link exists with `cadence == porSesion` or `cadence == suelto`
- WHEN the CF runs
- THEN no Payment document is created for that link

### REQ-VENC-03: Active Link Filter

The CF MUST process only trainer↔athlete links that are ACTIVE at execution time. Inactive or deleted links MUST be excluded.

### REQ-VENC-04: Deterministic Document ID

The CF MUST create Payment documents using the ID format `${trainerId}_${athleteId}_${periodKey}` where `periodKey` is:
- `mensual`: current month in `YYYY-MM` format
- `semanal`: current ISO week in `YYYY-Www` format

#### SCENARIO-VENC-02: CF creates correct mensual Payment doc

- GIVEN an active trainer↔athlete link with `cadence == mensual`
- WHEN the CF runs during period `2026-07`
- THEN a Payment document is created with `id == "${trainerId}_${athleteId}_2026-07"`
- AND `status == pending`
- AND `dueAt` is set to the configured default due day within the period (day 1 of the following month or a pinned day — per design)
- AND `periodKey == "2026-07"`

#### SCENARIO-VENC-04: CF creates correct semanal Payment doc

- GIVEN an active trainer↔athlete link with `cadence == semanal`
- WHEN the CF runs during ISO week 2026-W27
- THEN a Payment document is created with `id == "${trainerId}_${athleteId}_2026-W27"`
- AND `status == pending`
- AND `dueAt` is set to the last day (Sunday) of ISO week 2026-W27
- AND `periodKey == "2026-W27"`

### REQ-VENC-05: Idempotency — No Duplicate Creation

The CF MUST be idempotent. Before creating a document, it MUST check for an existing Payment by FIELDS `(trainerId, athleteId, periodKey)` — not by document ID alone. If a matching document already exists (regardless of whether it was auto-id or deterministic-id), the CF MUST skip creation.

#### SCENARIO-VENC-05: Idempotent re-run creates no duplicate

- GIVEN the CF already ran for the current period and created a Payment for `(trainerId, athleteId, periodKey)`
- WHEN the CF runs again for the same period
- THEN no second Payment document is created
- AND the existing document is not modified

#### SCENARIO-VENC-06: CF skips when a legacy manual doc already covers the period

- GIVEN a manually created Payment with an auto-generated ID exists, with `trainerId`, `athleteId`, and `periodKey` matching the current period
- WHEN the CF runs
- THEN the CF detects the existing doc via field query `(trainerId, athleteId, periodKey)`
- AND skips creation — no duplicate document appears

### REQ-VENC-06: No Overwrite of Paid Documents

The CF MUST NOT overwrite or modify any Payment document whose `status` is `paid`.

#### SCENARIO-VENC-07: CF does not overwrite an already-paid doc

- GIVEN a Payment document exists for `(trainerId, athleteId, periodKey)` with `status == paid`
- WHEN the CF runs for that same period
- THEN the existing document is left unchanged
- AND no new document is created for that period

### REQ-VENC-07: Pure Handler Testability

The CF logic MUST be extracted as a pure handler function (`generateDuePaymentsHandler`) separate from the `onSchedule` wrapper, enabling unit testing against the Firestore emulator without a live trigger.

### REQ-VENC-08: dueAt Assignment

Each Payment document created by the CF MUST have `dueAt` set:
- `mensual`: a pinned default due day within the period (design determines exact day; `AthleteBilling` has no `dueDayOfMonth`)
- `semanal`: the last day (Sunday) of the ISO week
