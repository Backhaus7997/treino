# Auditoría exploratoria TREINO — 2026-06-16

**69 bugs confirmados** (verificados adversarialmente por un panel de agentes) en 19 targets sobre los 17 módulos de `lib/features`.

Severidad: **high=23, medium=30, low=16** (critical=0).

Baseline objetivo en el momento de la auditoría: `flutter analyze` 0 errores/0 warnings en codigo real, `flutter test` 2305 passed.

## Resumen

| # | Sev | Módulo | Bug | Ubicación |
|---|-----|--------|-----|-----------|
| 1 | high | workout · UI | Weight input silently keeps stale value when cleared or out of range, logging the wrong weight | `lib/features/workout/presentation/session_player_screen.dart:1312` |
| 2 | high | workout · UI | Routine editor KG field rejects decimal weights (integer-only keyboard + int parse) | `lib/features/workout/presentation/routine_editor_screen.dart:2744` |
| 3 | high | workout · logic+data | Abandoned sessions inflate public workout count and streak | `lib/features/workout/data/session_repository.dart:97` |
| 4 | high | coach · UI | Availability rule editor lets trainer save end-time ≤ start-time, silently producing zero bookable slots | `lib/features/coach/presentation/availability_editor_screen.dart:530` |
| 5 | high | coach · logic+data | Trainer discovery only queries the athlete's own geohash cell, dropping nearby trainers across cell boundaries | `lib/features/coach/application/trainer_discovery_providers.dart:262` |
| 6 | high | coach_hub | Plan duration (durationWeeks) is silently dropped when building the Routine | `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:225` |
| 7 | high | profile | AccountDeletionNotifier.retry() never sets accountDeletionInFlightProvider — fast-retry deletion strands the user on /profile-setup | `lib/features/profile/application/account_deletion_notifier.dart:83` |
| 8 | high | feed | Feed queries have no orderBy — posts render in arbitrary order despite "newest first" docs | `lib/features/feed/data/post_repository.dart:42` |
| 9 | high | feed | feedForFriendsProvider keyed on List<String> — no value equality causes cache thrash and redundant reads | `lib/features/feed/application/post_providers.dart:20` |
| 10 | high | chat | Relative-time date label shows wrong day for negative-offset timezones (UTC not converted to local) | `lib/features/chat/presentation/chat_list_screen.dart:264` |
| 11 | high | check_in | Check-in write failures are silently swallowed — user sees success on failure | `lib/features/check_in/presentation/check_in_dialog.dart:132` |
| 12 | high | performance | Log screen shows local-time date but record is stored/displayed in UTC → off-by-one day near midnight | `/Users/martinbackhaus/treino/lib/features/performance/presentation/log_performance_test_screen.dart:34` |
| 13 | high | insights | N+1 sequential Firestore reads: setLogs fetched one session at a time | `lib/features/insights/application/insights_providers.dart:53` |
| 14 | high | insights | Sets from custom/trainer exercises silently dropped from setsByGroup | `lib/features/insights/application/insights_providers.dart:56` |
| 15 | high | insights | Target sets from custom exercises dropped; denormalized slot.muscleGroup ignored | `lib/features/insights/application/insights_providers.dart:74` |
| 16 | high | home | ISO week number returns 0 (and is off-by-one) at year boundaries -> Home shows "SEM 0" | `lib/features/home/widgets/esta_semana_card.dart:310` |
| 17 | high | gyms | Parse exception in one gym doc fails the entire catalog read (whereType filters nulls, not throws) | `lib/features/gyms/data/gym_repository.dart:29` |
| 18 | high | notifications | FcmService.init leaks onTokenRefresh subscription and double-saves tokens when called twice | `lib/features/notifications/data/fcm_service.dart:58` |
| 19 | high | notifications | Background notification taps never navigate: onMessageOpenedApp is never subscribed in production | `lib/app/app.dart:47` |
| 20 | high | payments | Weekly charge double-billed across ISO year boundary (calendar year used in periodKey) | `lib/features/payments/application/pagos_por_cobrar_provider.dart:117` |
| 21 | high | payments | Same ISO-year-boundary periodKey bug in athlete 'Mi Cuota' view | `lib/features/payments/application/mi_cuota_provider.dart:99` |
| 22 | high | payments | porSesion over-counts sessions finished before the trainer link existed | `lib/features/payments/application/pagos_por_cobrar_provider.dart:216` |
| 23 | high | payments | porSesion over-counts pre-link sessions in athlete 'Mi Cuota' | `lib/features/payments/application/mi_cuota_provider.dart:171` |
| 24 | medium | workout · UI | Routine editor screen uses hardcoded Spanish for many user-facing strings | `lib/features/workout/presentation/routine_editor_screen.dart:616` |
| 25 | medium | workout · logic+data | updateSet uses pre-await snapshot, silently dropping a concurrent logSet | `lib/features/workout/application/session_notifier.dart:240` |
| 26 | medium | workout · logic+data | finish() does a full sessions-collection read on every workout completion | `lib/features/workout/data/session_repository.dart:92` |
| 27 | medium | workout · logic+data | Hardcoded Spanish post text bypasses AppL10n | `lib/features/workout/application/post_workout_notifier.dart:28` |
| 28 | medium | coach · UI | Pervasive hardcoded Spanish user-facing strings despite AppL10n/ARB migration | `lib/features/coach/presentation/trainer_dashboard_tab.dart:1492` |
| 29 | medium | coach · UI | 'Resumen del día' counts in-progress sessions as completed (done) and never as pending | `lib/features/coach/presentation/trainer_dashboard_tab.dart:364` |
| 30 | medium | coach · UI | cancelFutureSeries reads every confirmed appointment for the trainer to cancel one series | `lib/features/coach/data/appointment_repository.dart:246` |
| 31 | medium | coach · logic+data | 28-day booking-horizon rule (REQ-COACH-AGENDA-009) is documented but never enforced | `lib/features/coach/data/appointment_repository.dart:30` |
| 32 | medium | coach · logic+data | trainedTodayProvider fans out a full session-history read per shared athlete (N+1) on every rebuild | `lib/features/coach/application/trained_today_provider.dart:63` |
| 33 | medium | coach_hub | Manual exercise pick assigns the match to all same-named unmatched rows in the day | `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:156` |
| 34 | medium | coach_hub | Athlete picker uses a deprecated one-shot FutureProvider, missing real-time updates | `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:829` |
| 35 | medium | coach_hub | Partial multi-athlete assignment failure clears the plan with no retry path | `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:109` |
| 36 | medium | profile | Personal-edit _save() lacks a re-entrancy guard; header back-tap is not disabled during save | `lib/features/profile/presentation/profile_edit_personal_screen.dart:159` |
| 37 | medium | profile_setup | Raw Material icon Icons.alternate_email used instead of TreinoIcon (project rule violation) | `/Users/martinbackhaus/treino/lib/features/profile_setup/presentation/steps/step_1_username_avatar.dart:87` |
| 38 | medium | feed | Non-atomic followingCount read-modify-write in accept()/delete() — lost updates under concurrency | `lib/features/feed/data/friendship_repository.dart:76` |
| 39 | medium | feed | Char counter counts UTF-16 code units while submit gate counts grapheme clusters | `lib/features/feed/presentation/create_post_screen.dart:89` |
| 40 | medium | feed | Follow/Accept tap handlers have no error handling — network failure throws uncaught async error | `lib/features/feed/presentation/widgets/public_profile_follow_button.dart:50` |
| 41 | medium | chat | Entire chat feature uses hardcoded Spanish strings instead of AppL10n | `lib/features/chat/presentation/chat_list_screen.dart:38` |
| 42 | medium | check_in | Check-in recorded as gym check-in when user has the 'no-gym' sentinel | `lib/features/check_in/application/check_in_providers.dart:46` |
| 43 | medium | measurements | Trainer only sees measurements they personally recorded; co-trainer / reassignment loses history | `lib/features/measurements/application/measurement_providers.dart:24` |
| 44 | medium | measurements | Empty measurement can be saved (no 'at least one field' validation) | `lib/features/measurements/presentation/log_measurement_screen.dart:161` |
| 45 | medium | performance | Entire performance feature hardcodes Spanish strings instead of AppL10n (project migrated to ARB/AppL10n) | `/Users/martinbackhaus/treino/lib/features/performance/presentation/log_performance_test_screen.dart:159` |
| 46 | medium | performance | Misleading PROGRESO header (▲ 0.0, '0 días', no chart) when selected metric has only one data point | `/Users/martinbackhaus/treino/lib/features/performance/presentation/widgets/performance_progress_chart.dart:203` |
| 47 | medium | home | Resume-session dedup uses identical() on Dart records, so it never dedupes -> modal can stack | `lib/features/home/home_screen.dart:64` |
| 48 | medium | home | ref used after await in onDiscard without a mounted/ref-alive guard | `lib/features/home/home_screen.dart:118` |
| 49 | medium | home | EmpezarEntrenamientoCard ships hardcoded fake plan data including a static "HOY · JUEVES" | `lib/features/home/widgets/empezar_entrenamiento_card.dart:15` |
| 50 | medium | notifications | ForegroundSnackBarHandler is dead code duplicating app.dart's inline foreground handler | `lib/features/notifications/presentation/foreground_snackbar_handler.dart:16` |
| 51 | medium | payments | 'Mi Cuota' silently swallows stream errors, showing wrong/empty amounts | `lib/features/payments/application/mi_cuota_provider.dart:90` |
| 52 | medium | payments | Payments-stream error makes every athlete appear unpaid (wrong charges shown) | `lib/features/payments/application/pagos_por_cobrar_provider.dart:108` |
| 53 | medium | payments | Marking multiple one-off (suelto) payments paid is non-atomic — no batch in repository | `lib/features/payments/data/payment_repository.dart:24` |
| 54 | low | workout · UI | Routine detail, exercise detail and other workout screens use hardcoded Spanish | `lib/features/workout/presentation/routine_detail_screen.dart:57` |
| 55 | low | workout · logic+data | _finalize() kills the timer before the finish write completes; failed write leaves session unfinished and frozen | `lib/features/workout/application/session_notifier.dart:278` |
| 56 | low | coach · UI | Accept/Reject pending-request buttons have no in-flight guard (double-submit) | `lib/features/coach/presentation/trainer_dashboard_tab.dart:307` |
| 57 | low | coach_hub | Weight values render with a trailing .0 (e.g. '60.0 kg') in the day-item subtitle | `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:635` |
| 58 | low | auth | signUpWithEmail leaves an orphan Auth user if sendEmailVerification throws | `lib/features/auth/data/auth_service.dart:50` |
| 59 | low | profile | Volume stat uses kFormat which rounds to nearest k (1500 kg → '2k'), overstating displayed volume | `lib/features/profile/profile_screen.dart:169` |
| 60 | low | profile_setup | Height field silently nulls out (and disables Next) when user enters a decimal | `/Users/martinbackhaus/treino/lib/features/profile_setup/presentation/steps/step_4_weight_height.dart:42` |
| 61 | low | feed | Material Icons used directly instead of TreinoIcon (project rule violation) | `lib/features/feed/presentation/search_users_screen.dart:116` |
| 62 | low | feed | firstPostByAuthorProvider deserializes Post without injecting doc id — latent crash on id-stripped docs | `lib/features/feed/application/public_profile_providers.dart:59` |
| 63 | low | check_in | Non-atomic read-then-write in createTodayCheckIn can produce concurrent duplicate writes | `lib/features/check_in/data/check_in_repository.dart:44` |
| 64 | low | measurements | Raw double interpolation produces ugly values (e.g. '70.0 kg', floating-point tails) in latest-measurement card | `lib/features/coach/presentation/athlete_detail_screen.dart:555` |
| 65 | low | performance | Athlete provider over-reads: fetches ALL trainer tests then filters client-side, ignoring the existing per-athlete query | `/Users/martinbackhaus/treino/lib/features/performance/application/performance_test_providers.dart:23` |
| 66 | low | insights | Week boundaries use Duration(days:N) on local DateTimes (DST drift) | `lib/features/insights/application/insights_providers.dart:23` |
| 67 | low | home | N+1 Firestore reads behind EstaSemanaCard (serial listSetLogs per session) | `lib/features/insights/application/insights_providers.dart:53` |
| 68 | low | reviews | N+1 Firestore real-time listeners: one userPublicProfiles listener per review tile | `lib/features/reviews/presentation/widgets/review_tile.dart:50` |
| 69 | low | reviews | avatarUrl is gated on displayName != null, conflating 'no name' with 'deleted account' | `lib/features/reviews/presentation/widgets/review_tile.dart:59` |

## Detalle por severidad

### [HIGH] Weight input silently keeps stale value when cleared or out of range, logging the wrong weight

- **Módulo:** workout · UI
- **Ubicación:** `lib/features/workout/presentation/session_player_screen.dart:1312`
- **Categoría:** correctness
- **Descripción:** _RepsSetRow._onWeightChanged only updates _weightKg when the parsed value is non-null and within [0,500]. Clearing the field (empty -> parsed==null), typing a value >500, or a transient unparseable state leaves _weightKg at its previous value. The summary row text and the value logged on check then reflect the stale weight, not what the user sees/intends.
- **Repro:** On a current set, clear the weight field (or type 600). The big number/summary still shows the old kg. Tap the check circle -> the set is logged with the old weight, not 0/the intended value.
- **Fix sugerido:** On empty/invalid input set _weightKg = 0 (or clamp to the [0,500] bound) and call setState so the displayed summary stays in sync with what will be logged; only reject characters via inputFormatters, not whole values.

### [HIGH] Routine editor KG field rejects decimal weights (integer-only keyboard + int parse)

- **Módulo:** workout · UI
- **Ubicación:** `lib/features/workout/presentation/routine_editor_screen.dart:2744`
- **Categoría:** correctness
- **Descripción:** The set-row KG field uses TextInputType.number with onChanged parsing via int.tryParse and writes s.weightKg = v?.toDouble(); the controller is also seeded with weightKg.toStringAsFixed(0). Decimal weights (e.g. 17.5 kg) cannot be entered: typing '17.5' yields int.tryParse==null which clears the weight, and reopening an existing 17.5 kg slot displays it as '17'. SetSpec.weightKg is a double, so the editor cannot author common fractional loads.
- **Repro:** Open the routine editor, add an exercise, type 17.5 into the KG cell -> the weight is cleared/not saved. Edit a slot that already has 17.5 kg -> it shows 17.
- **Fix sugerido:** Use keyboardType: numberWithOptions(decimal: true), parse with double.tryParse(v.replaceAll(',', '.')) into a double?, and seed the controller with a decimal-preserving formatter (e.g. strip trailing .0 only).

### [HIGH] Abandoned sessions inflate public workout count and streak

- **Módulo:** workout · logic+data
- **Ubicación:** `lib/features/workout/data/session_repository.dart:97`
- **Categoría:** Correctness / Data
- **Descripción:** finish() recomputes workoutsCount as finishedList.length and racha via computeStreak(finishedList), where finishedList = all sessions with status == finished. Abandoned sessions are also written with status=finished (only wasFullyCompleted=false differs), so abandoning a barely-started workout still bumps the public workout count and training streak.
- **Repro:** Start a session, log nothing, abandon it. SessionNotifier.abandonSession() calls repo.finish(wasFullyCompleted:false), which sets status=finished and then computeStreak counts that day. The history UI (historial_section.dart filters on wasFullyCompleted) won't show it, but the public profile counters and streak increase.
- **Fix sugerido:** Filter by wasFullyCompleted before computing counters: `final completedList = allSessions.where((s) => s.status == SessionStatus.finished && s.wasFullyCompleted).toList();` and pass completedList to both workoutsCount and computeStreak (or add a wasFullyCompleted guard inside computeStreak). This matches the display filter in historial_section.dart:52 and planProgressProvider (session_providers.dart:155).

### [HIGH] Availability rule editor lets trainer save end-time ≤ start-time, silently producing zero bookable slots

- **Módulo:** coach · UI
- **Ubicación:** `lib/features/coach/presentation/availability_editor_screen.dart:530`
- **Categoría:** correctness
- **Descripción:** The rule form (`_RuleFormSheetState._save`) writes the rule with no validation that end (hour:minute) is after start, nor that the window is at least one slot wide. `AvailabilityRule` (domain/availability_rule.dart) and `AvailabilityRepository.addRule/updateRule` also have no guard. When endTotalMinutes <= startTotalMinutes, `_addSlotsFromWindow` in compute_free_slots.dart generates NO slots, so the trainer believes availability is published but athletes/the trainer-day sheet see an empty day.
- **Repro:** As a trainer open the availability editor, add a rule with start 11:00 and end 09:00 (or start 09:00 / end 09:00), save. The rule appears in 'MIS HORARIOS DE TRABAJO' but no free slots are ever generated for that weekday in compute_free_slots / TrainerDayDetailSheet.
- **Fix sugerido:** Before saving, validate that endHour*60+endMinute >= startHour*60+startMinute + slotDurationMin; otherwise show a SnackBar/error and abort. Mirror the guard in AvailabilityRepository.addRule/updateRule (or a domain assert on AvailabilityRule) so invalid windows can never be persisted.

### [HIGH] Trainer discovery only queries the athlete's own geohash cell, dropping nearby trainers across cell boundaries

- **Módulo:** coach · logic+data
- **Ubicación:** `lib/features/coach/application/trainer_discovery_providers.dart:262`
- **Categoría:** Correctness / data query
- **Descripción:** trainerDiscoveryProvider calls repo.listByGeohashes([athleteGeohash]) with ONLY the athlete's own geohash5 (~4.9km cell). The repository method's own docstring states it is meant to receive 'el geohash5 del atleta + los 8 vecinos cardinales', but no neighbor expansion is done. A trainer physically a few hundred meters away but in an adjacent geohash cell is never fetched, so the haversine reorder and the distance filter cannot include them.
- **Repro:** Athlete near a geohash cell edge with a real trainer 500m away across the boundary. Open discovery (location granted) and/or apply the '< 2 km' distance filter: the nearby trainer does not appear because they were never in the candidate set.
- **Fix sugerido:** Compute the 8 neighboring geohash5 cells for the athlete's position and pass [self, ...neighbors] (<=9 values, within the 30-value array-contains-any limit) to listByGeohashes. Add a geohashNeighbors helper in core/utils/geohash.dart.

### [HIGH] Plan duration (durationWeeks) is silently dropped when building the Routine

- **Módulo:** coach_hub
- **Ubicación:** `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:225`
- **Categoría:** Correctness
- **Descripción:** _buildRoutine never maps plan.durationWeeks (validated 1-52 in the Excel parser and shown in the preview as 'Duración X sem') to Routine.numWeeks. The Routine constructor keeps its @Default(1), so every imported multi-week plan is persisted as a single-week routine, discarding the periodization the trainer entered.
- **Repro:** Import an Excel plan with 'Duración semanas' = 8, assign it to an athlete. The created routine doc has numWeeks = 1; the athlete only ever sees week 1 of an 8-week plan.
- **Fix sugerido:** Pass numWeeks: plan.durationWeeks into the Routine(...) call in _buildRoutine (the Routine model already declares `@Default(1) int numWeeks`).

### [HIGH] AccountDeletionNotifier.retry() never sets accountDeletionInFlightProvider — fast-retry deletion strands the user on /profile-setup

- **Módulo:** profile
- **Ubicación:** `lib/features/profile/application/account_deletion_notifier.dart:83`
- **Categoría:** state-management
- **Descripción:** deleteAccount() sets accountDeletionInFlightProvider=true (line 57) and resets it in finally (line 70) so the router (router.dart:121) defers the loggedIn=true+profile=null redirect during the CF cascade window. The retry() path (within the 5-min re-auth window) calls _callCfAndFinish() directly but NEVER sets that flag and has no finally to reset it.
- **Repro:** Trigger account deletion, let it fail once (e.g. transient CF error), then tap 'Reintentar' in the error snackbar within 5 minutes. retry() runs the CF which deletes the Firestore profile before the Auth user; with the in-flight flag unset, the router sees loggedIn=true + profile=null and redirects to /profile-setup instead of /welcome, stranding the user mid-deletion.
- **Fix sugerido:** Mirror deleteAccount's guard in retry(): set ref.read(accountDeletionInFlightProvider.notifier).state = true before _callCfAndFinish() and reset it in a finally block. Better, extract the in-flight-flag management into _callCfAndFinish itself so both entry paths are protected.

### [HIGH] Feed queries have no orderBy — posts render in arbitrary order despite "newest first" docs

- **Módulo:** feed
- **Ubicación:** `lib/features/feed/data/post_repository.dart:42`
- **Categoría:** correctness
- **Descripción:** feedPublic() (line 42), feedForFriends() (line 51) and feedForGym() (line 74) all run Firestore queries with no .orderBy('createdAt', descending: true). The docstrings and the myGymFeedProvider comment explicitly promise "newest first", but Firestore returns documents in document-ID order, so the feed is effectively random/insertion order, not chronological.
- **Repro:** Create several posts at different times in any segment (Amigos/Mi Gym/Público) and open the feed. New posts do not appear at the top; ordering is whatever Firestore returns by doc id.
- **Fix sugerido:** Add .orderBy('createdAt', descending: true) to each query (and an optional .limit for paging). feedForFriends uses whereIn on authorUid, so add a composite index (privacy ==, authorUid in, createdAt desc) or sort client-side after merging the chunks; feedForGym needs index (privacy ==, authorGymId ==, createdAt desc).

### [HIGH] feedForFriendsProvider keyed on List<String> — no value equality causes cache thrash and redundant reads

- **Módulo:** feed
- **Ubicación:** `lib/features/feed/application/post_providers.dart:20`
- **Categoría:** state-management
- **Descripción:** feedForFriendsProvider is a FutureProvider.family<List<Post>, List<String>>. Dart List does not implement value equality (uses identity), so Riverpod treats every distinct list instance as a new family key. myFriendsFeedProvider feeds it the friendUids list produced by acceptedFriendsProvider, which is a StreamProvider that emits a brand-new List instance on every Firestore snapshot. Each emission therefore creates a NEW provider entry and re-issues the Firestore feed query, leaking old uncached entries and multiplying reads.
- **Repro:** Open the Amigos feed and have any friendship doc change (or the snapshot re-emit). myFriendsFeedProvider re-watches feedForFriendsProvider with a new list identity, spawning a fresh Firestore query each time instead of reusing the cached result.
- **Fix sugerido:** Key the family on a value-equal type: either sort+join the uids into a single String key (as the docstring already hints) and split inside the provider, or wrap in an equatable/IList. Alternatively fold the friends query into myFriendsFeedProvider so it does not pass a List as a family arg.

### [HIGH] Relative-time date label shows wrong day for negative-offset timezones (UTC not converted to local)

- **Módulo:** chat
- **Ubicación:** `lib/features/chat/presentation/chat_list_screen.dart:264`
- **Categoría:** Edge cases
- **Descripción:** TimestampConverter.fromJson always returns UTC DateTime (json.toDate().toUtc()), so chat.lastMessageAt is in UTC. _relativeTime formats the fallback date with createdAt.day/createdAt.month directly without .toLocal(). For users in negative-offset zones (Argentina is UTC-3, the app's target market) a message sent late evening local time has a UTC date one day ahead, so the chat list shows tomorrow's date.
- **Repro:** In Argentina (UTC-3), send/receive a message after 21:00 local. Let it age past 7 days so the dd/mm branch is hit (or change device clock). The list shows the date one day ahead of when the message was actually sent locally.
- **Fix sugerido:** Convert to local before formatting: final local = createdAt.toLocal(); use local.day / local.month. The delta computation via DateTime.now().difference(createdAt) is instant-correct and needs no change, but the absolute date fields must use .toLocal().

### [HIGH] Check-in write failures are silently swallowed — user sees success on failure

- **Módulo:** check_in
- **Ubicación:** `lib/features/check_in/presentation/check_in_dialog.dart:132`
- **Categoría:** State management
- **Descripción:** The 'Si' button awaits CheckInNotifier.confirm() then unconditionally pops the dialog. confirm() wraps the Firestore write in AsyncValue.guard, so it never throws; any write error is captured into the notifier state, which is read by no widget anywhere. The user gets visual confirmation (dialog closes) even when the check-in never persisted.
- **Repro:** Trigger the check-in dialog with no network / Firestore rules denying the write, tap 'Si'. The dialog closes as if it succeeded, but no check-in doc is created and no error is shown. The dialog also won't reappear (session flag already set), so the user silently has no check-in for the day.
- **Fix sugerido:** Have the button (or the dialog) read/listen to checkInNotifierProvider. After confirm(), inspect state.hasError and surface a SnackBar / retry instead of popping; only pop on success. Alternatively make confirm() rethrow and try/catch in onPressed.

### [HIGH] Log screen shows local-time date but record is stored/displayed in UTC → off-by-one day near midnight

- **Módulo:** performance
- **Ubicación:** `/Users/martinbackhaus/treino/lib/features/performance/presentation/log_performance_test_screen.dart:34`
- **Categoría:** Edge cases / timezone
- **Descripción:** _formatDateTimeEs calls dt.toLocal() (line 34) and the header shows DateTime.now() (local), but _save stores recordedAt = DateTime.now().toUtc() (line 172) and every consumer (athlete_detail_screen _formatMeasurementDate explicitly states 'display as-is, no .toLocal()' and the chart's _shortDate) renders the date in UTC. The log form's displayed date and the persisted/displayed date disagree.
- **Repro:** As a trainer in Argentina (UTC-3), open the log form between 21:00 and 23:59 local time. The header shows today's date (e.g. '16 jun'). Save. The summary card and PROGRESO chart immediately show the record dated tomorrow (e.g. '17 jun', UTC) — a one-day discrepancy versus what the trainer just saw.
- **Fix sugerido:** Make the convention consistent. Either store local-naive or apply the same UTC display convention in the log header (drop .toLocal() in _formatDateTimeEs to match _formatMeasurementDate / _shortDate), or convert everywhere to .toLocal() for display. Pick one and apply it across log screen, summary card, and chart.

### [HIGH] N+1 sequential Firestore reads: setLogs fetched one session at a time

- **Módulo:** insights
- **Ubicación:** `lib/features/insights/application/insights_providers.dart:53`
- **Categoría:** Data/Firestore
- **Descripción:** The setsByGroup loop awaits repo.listSetLogs(...) sequentially once per weekly finished session. Each call is a separate Firestore subcollection round-trip, executed serially (await inside a for loop), so total latency scales linearly with the number of sessions in the week.
- **Repro:** Open Insights for a user who trained 5-6 times this week. The screen issues 5-6 sequential setLogs reads (plus the all-sessions read), each blocking the next, making the spinner visibly slow on a cold cache or slow network.
- **Fix sugerido:** Parallelize the per-session reads with Future.wait, e.g. `final logsPerSession = await Future.wait(weekSessions.map((s) => repo.listSetLogs(uid: uid, sessionId: s.id)));` then iterate the flattened results. This collapses N serial round-trips into one parallel batch.

### [HIGH] Sets from custom/trainer exercises silently dropped from setsByGroup

- **Módulo:** insights
- **Ubicación:** `lib/features/insights/application/insights_providers.dart:56`
- **Categoría:** Correctness
- **Descripción:** setsByGroup resolves a set's muscle group via `byId[log.exerciseId]?.muscleGroup`, where byId is built only from the public catalogue (exercisesProvider -> ExerciseRepository.listAll). SetLog stores only exerciseId, and trainer-defined custom exercises (category 'custom', stored under a trainer's customExercises subcollection) are NOT in the public catalogue. The lookup returns null and those sets are silently excluded from every group total.
- **Repro:** Athlete on a trainer-assigned routine logs sets for a trainer custom exercise (e.g. a machine the trainer added). Those sets never appear in the 'MÚSCULOS DE LA SEMANA' counts, so the weekly set totals undercount real training volume.
- **Fix sugerido:** Either denormalize muscleGroup onto SetLog at write time (preferred, avoids extra reads), or fall back to resolving unknown exerciseIds via slotExerciseProvider / the routine's custom exercises before discarding. At minimum, the group resolution must not assume every logged exerciseId exists in the public catalogue.

### [HIGH] Target sets from custom exercises dropped; denormalized slot.muscleGroup ignored

- **Módulo:** insights
- **Ubicación:** `lib/features/insights/application/insights_providers.dart:74`
- **Categoría:** Correctness
- **Descripción:** targetByGroup uses `byId[slot.exerciseId]?.muscleGroup` to bucket each slot's targetSets. RoutineSlot already carries a denormalized `muscleGroup` field (routine_slot.dart:39), but the provider ignores it and does a catalogue lookup instead. For slots referencing custom exercises (not in the public catalogue) byId returns null, so their targetSets contribute zero to the target totals — and the whole 'VOLUMEN POR GRUPO' card can be wrong or empty for trainer-built plans.
- **Repro:** A trainer builds a routine using custom exercises. When the athlete opens Insights, the volume bars omit those slots' target sets (done/target ratios are skewed, or the card may show no bars at all), even though the slot's own muscleGroup field has the correct group.
- **Fix sugerido:** Use the slot's already-denormalized field: `final group = slot.muscleGroup.toDisplayGroup();` instead of the catalogue lookup. This is both correct for custom exercises and removes a dependency on the catalogue being complete.

### [HIGH] ISO week number returns 0 (and is off-by-one) at year boundaries -> Home shows "SEM 0"

- **Módulo:** home
- **Ubicación:** `lib/features/home/widgets/esta_semana_card.dart:310`
- **Categoría:** correctness
- **Descripción:** _isoWeekNumber uses the simplified formula ((dayOfYear - weekday + 10) / 7).floor() but never handles the two ISO-8601 edge cases: a result of 0 means the date belongs to the LAST week (52 or 53) of the previous ISO year, and a result of 53 on a short final week means week 1 of the next year. As written it returns 0 for early-January dates that fall in the previous year's last week.
- **Repro:** Verified by running the exact function: 2027-01-01 (Fri) and 2021-01-01 (Fri) both return week 0 (correct ISO = 53); 2023-01-01 (Sun) returns 0 (correct = 52). A user opening the app on Jan 1-3 in those years sees the card header render "SEM 0 · ENE".
- **Fix sugerido:** Replace the ad-hoc math with a correct ISO-8601 implementation: compute woy = ((ordinalDay - isoWeekday + 10) / 7).floor(); if woy < 1 return weeks of previous year (52 or 53); if woy == 53 and the year does not actually have 53 ISO weeks, return 1. Also note int.parse(difference.inDays.toString()) is a pointless round-trip and should just be difference.inDays.

### [HIGH] Parse exception in one gym doc fails the entire catalog read (whereType filters nulls, not throws)

- **Módulo:** gyms
- **Ubicación:** `lib/features/gyms/data/gym_repository.dart:29`
- **Categoría:** Data/Firestore
- **Descripción:** `listAll()` (and `getByIds` at line 50) map docs through `_fromDoc(...).whereType<Gym>()`. `_fromDoc` only returns null for missing/absent docs; if `Gym.fromJson` throws (wrong-type lat/lng/geohash, missing required field, bad createdAt), the exception propagates out of `.map().whereType()` and aborts the whole list. One malformed gym doc therefore breaks the entire gyms catalog rather than being skipped.
- **Repro:** Insert one gyms doc with a malformed field (e.g. lat stored as a String, or missing geohash). gymsProvider then resolves to an error and the trainer profile gyms picker (profile_edit_trainer_screen.dart:95,501) shows no gyms / errors, even though 20 valid gyms exist.
- **Fix sugerido:** Wrap the parse per-doc in try/catch inside `_fromDoc` (return null + log on failure) so a single bad document is skipped instead of failing the batch, matching the resilient intent of `whereType<Gym>()`.

### [HIGH] FcmService.init leaks onTokenRefresh subscription and double-saves tokens when called twice

- **Módulo:** notifications
- **Ubicación:** `lib/features/notifications/data/fcm_service.dart:58`
- **Categoría:** State management / Leak
- **Descripción:** init() unconditionally assigns _messaging.onTokenRefresh.listen(...) to _refreshSub without first cancelling any existing subscription. init() is invoked from two places: the auth lifecycle provider on sign-in (notification_providers.dart:47) and again from PermissionGate._requestPermission after a permission grant (permission_gate.dart:79). The second call overwrites _refreshSub, orphaning the first subscription (leak) and leaving two active listeners, so every subsequent token refresh fires saveToken twice (duplicate Firestore writes / arrayUnion calls).
- **Repro:** Sign in (init #1 registers listener A). Complete profile so PermissionGate fires and grants permission -> init #2 registers listener B, overwriting _refreshSub. Listener A is now leaked. When FCM rotates the token, both A and B call saveToken, producing duplicate writes; on sign-out only B (the last) is cancelled, A keeps running.
- **Fix sugerido:** Cancel and null the existing subscription before resubscribing, and make init idempotent: at the top of init() do `await _refreshSub?.cancel(); _refreshSub = null;` before assigning the new listener (or guard with `if (_refreshSub != null) return;` after token save). Mirror the cleanup already done in dispose().

### [HIGH] Background notification taps never navigate: onMessageOpenedApp is never subscribed in production

- **Módulo:** notifications
- **Ubicación:** `lib/app/app.dart:47`
- **Categoría:** Correctness / Feature wiring
- **Descripción:** FcmService exposes onMessageOpenedApp (fcm_service.dart:96) for handling taps that bring the app from background to foreground, and the test suite simulates a `_BackgroundTapListener` whose comment says 'Simulates background tap subscription from app.dart'. But app.dart only wires the foreground stream (onForegroundMessage, line 47) and the cold-start getInitialMessage (line 53). No production code ever subscribes to onMessageOpenedApp, so tapping a push notification while the app is backgrounded does not navigate to the deepLink.
- **Repro:** Background the app (do not terminate). Send a push with data.deepLink. Tap the system notification. The app resumes but stays on the current screen instead of navigating to the deep link, because onMessageOpenedApp has no listener.
- **Fix sugerido:** In _TreinoAppState.initState, subscribe to fcm.onMessageOpenedApp and route via goDeepLink, mirroring the test's _BackgroundTapListener: store the subscription in a field and cancel it in dispose(). Use _router.routerDelegate.navigatorKey.currentContext and check ctx.mounted before calling goDeepLink(ctx, message.data['deepLink'] as String?).

### [HIGH] Weekly charge double-billed across ISO year boundary (calendar year used in periodKey)

- **Módulo:** payments
- **Ubicación:** `lib/features/payments/application/pagos_por_cobrar_provider.dart:117`
- **Categoría:** Correctness
- **Descripción:** weekKey is built as '${currentYear}-W${currentWeek}' using now.year (calendar year), but _isoWeekNumber returns ISO-week numbers whose owning year can differ from the calendar year near Jan 1 / Dec 31. The same physical ISO week therefore gets two different keys on either side of New Year, so the 'already paid this week' check (p.periodKey == weekKey) fails and the athlete is charged a second time.
- **Repro:** Trainer has a 'semanal' athlete. On 2026-12-31 (Thu) confirm the weekly charge -> stored periodKey '2026-W53'. On 2027-01-01 (Fri, same ISO week Mon 2026-12-28..Sun 2027-01-03) the provider computes weekKey '2027-W53', which does not match '2026-W53', so the same week shows as unpaid and is charged again.
- **Fix sugerido:** Derive the ISO year from the Thursday of the week (the same thursday.year used inside _isoWeekNumber) and use it in the key, e.g. compute (isoYear, isoWeek) together and build '${isoYear}-W${isoWeek}'. Apply the identical fix to the writer in trainer_dashboard_tab.dart so reader and writer agree.

### [HIGH] Same ISO-year-boundary periodKey bug in athlete 'Mi Cuota' view

- **Módulo:** payments
- **Ubicación:** `lib/features/payments/application/mi_cuota_provider.dart:99`
- **Categoría:** Correctness
- **Descripción:** weekKey uses now.year (calendar year) combined with the ISO week number from _isoWeekNumber, identical to the trainer-side defect. Around the New Year boundary the athlete's 'semanal' charge is shown as unpaid again because the generated weekKey no longer matches the periodKey written when it was paid.
- **Repro:** Athlete with a 'semanal' billing config. A weekly payment marked paid on 2026-12-31 stored periodKey '2026-W53'. Open Mi Cuota on 2027-01-01: provider builds '2027-W53', the paid check fails, and the already-paid week reappears as owed.
- **Fix sugerido:** Use the ISO year (thursday.year) when building weekKey, sharing one helper that returns both ISO year and ISO week. Keep it identical to the trainer-side and the payment writer.

### [HIGH] porSesion over-counts sessions finished before the trainer link existed

- **Módulo:** payments
- **Ubicación:** `lib/features/payments/application/pagos_por_cobrar_provider.dart:216`
- **Categoría:** Edge cases
- **Descripción:** When no payment exists yet, lastPaidAt defaults to epoch (1970), so every finished session in the athlete's entire history that finished after epoch is counted as billable. Sessions completed before the athlete ever linked to/started paying this trainer (TrainerLink.acceptedAt) are wrongly charged. The athlete-side miCuota has the same logic.
- **Repro:** An athlete with a long pre-existing workout history links to a trainer and is set to 'por_sesion'. Before any payment is recorded, the dashboard immediately shows the athlete owing for ALL historically finished sessions (count includes pre-link sessions), not just sessions since the relationship started.
- **Fix sugerido:** Initialize the billing window from max(epoch_or_lastPaidAt, link.acceptedAt) and only count sessions whose finishedAt isAfter that floor, so pre-link history is excluded.

### [HIGH] porSesion over-counts pre-link sessions in athlete 'Mi Cuota'

- **Módulo:** payments
- **Ubicación:** `lib/features/payments/application/mi_cuota_provider.dart:171`
- **Categoría:** Edge cases
- **Descripción:** Mirror of the trainer-side defect: with lastPaidAt defaulting to epoch and no acceptedAt floor, the athlete sees a per-session charge counting every finished session ever recorded, including sessions done before linking to this trainer.
- **Repro:** Athlete with prior workout history is configured 'por_sesion' by a trainer. Open Mi Cuota before any payment: the amount equals (all finished sessions in history) * amountArs instead of only sessions since the link/last payment.
- **Fix sugerido:** Clamp the counting window to the trainer link's acceptedAt (available on the link object) as well as lastPaidAt; only count sessions finished after that floor.

### [MEDIUM] Routine editor screen uses hardcoded Spanish for many user-facing strings

- **Módulo:** workout · UI
- **Ubicación:** `lib/features/workout/presentation/routine_editor_screen.dart:616`
- **Categoría:** i18n
- **Descripción:** While the editor uses AppL10n for titles/labels, large amounts of user-facing copy are hardcoded Spanish: the Duplicar/Eliminar/Add-scope dialogs (616-825), default day name 'Dia N' (350/463/679/694), section labels 'SEMANAS'/'DIAS DEL PLAN'/'NIVEL' (1353/1375/1412), week controls 'Semana'/'Quitar ultima'/'Duplicar semana' (1607/1624/1641), 'Sem N' (1687), invalid-week hint 'Sets incompletos en Sem...' (1399), slot menu 'Cambiar ejercicio'/'Subir'/'Bajar'/'Eliminar' (2274-2297), 'Descanso'/'Agregar ejercicio'/'+ Agregar set' (2312/2084/2351), set-type menu (2688-2692) and measure-mode menu 'Reps'/'Tiempo' (2457/2465).
- **Repro:** Inspect the editor in a non-Spanish locale; these strings do not localize.
- **Fix sugerido:** Extract to ARB keys and consume via AppL10n; for the default day name use a localized template rather than the literal 'Dia $n' (which is also compared by string in _removeDay re-numbering).

### [MEDIUM] updateSet uses pre-await snapshot, silently dropping a concurrent logSet

- **Módulo:** workout · logic+data
- **Ubicación:** `lib/features/workout/application/session_notifier.dart:240`
- **Categoría:** State management (Riverpod)
- **Descripción:** updateSet captures `current = state.value` before the Firestore await, then rebuilds setLogs from `current.setLogs` after the await and overwrites state with AsyncData. logSet (line 204) correctly re-reads `state.value` after its await for exactly this reason; updateSet does not. A logSet that completes during the updateSet await is lost from state.
- **Repro:** Edit an existing set (updateSet, ~300ms write) while the user taps to log a new set (logSet) so both awaits overlap. logSet appends its persisted log and sets state; updateSet then overwrites state with the older current.setLogs (missing the new log). The new set vanishes from the UI until the screen reloads.
- **Fix sugerido:** Re-read latest state after the await, mirroring logSet: `final latest = state.value ?? current; final newLogs = latest.setLogs.map((l) => l.id == updated.id ? updated : l).toList(growable: false); state = AsyncData(latest.copyWith(setLogs: newLogs));`

### [MEDIUM] finish() does a full sessions-collection read on every workout completion

- **Módulo:** workout · logic+data
- **Ubicación:** `lib/features/workout/data/session_repository.dart:92`
- **Categoría:** Data / Firestore
- **Descripción:** After every finish/abandon, finish() runs `colRef.get()` over the entire users/{uid}/sessions collection (no limit) and filters in Dart. Read cost and latency grow linearly with the user's lifetime session count, charged on every single workout.
- **Repro:** A long-term user with hundreds of finished sessions finishes one more workout; finish() reads every historical session doc just to recompute a count and streak.
- **Fix sugerido:** Maintain counters incrementally: use FieldValue.increment(1) for workoutsCount on the public profile, and compute streak from a bounded recent window (e.g. orderBy startedAt desc limit ~60) rather than reading the full collection. If the full read must stay for the streak, at least cap it with a date/limit window.

### [MEDIUM] Hardcoded Spanish post text bypasses AppL10n

- **Módulo:** workout · logic+data
- **Ubicación:** `lib/features/workout/application/post_workout_notifier.dart:28`
- **Categoría:** i18n
- **Descripción:** shareWorkout builds the shared Post with a hardcoded literal '¡Terminé mi entreno! 💪'. The project migrated user-facing strings to AppL10n (presentation widgets in this feature use it), but this user-visible feed text is not localizable. Notifiers have no BuildContext, so AppL10n.of(context) is unavailable here.
- **Repro:** An English-locale user shares a workout from the post-workout summary; the generated feed post text is always Spanish regardless of locale.
- **Fix sugerido:** Pass the localized text into shareWorkout from the UI: `shareWorkout(session, text: AppL10n.of(context).workoutSharedDefault)` and add the ARB key, so the notifier stays context-free while the string is localized.

### [MEDIUM] Pervasive hardcoded Spanish user-facing strings despite AppL10n/ARB migration

- **Módulo:** coach · UI
- **Ubicación:** `lib/features/coach/presentation/trainer_dashboard_tab.dart:1492`
- **Categoría:** i18n
- **Descripción:** Many user-facing strings are hardcoded in Spanish in files that already import and use AppL10n for other strings, violating the project's ARB/AppL10n migration. Examples: dashboard month/day name arrays and section titles ('PAGOS POR COBRAR', 'SOLICITUDES PENDIENTES', 'RECHAZAR', 'ACEPTAR', '+ INVITAR ALUMNO', 'COBRO SUELTO', '¿Marcar como cobrado?', 'Cobro registrado.'); new_session_sheet ('Una vez', 'Se repite', 'DÍAS', 'REPETIR POR', 'Elegí un alumno.', 'No podés registrar una sesión en el pasado.', '$count sesiones registradas'); session_detail_sheet ('GUARDAR NOTAS', 'CANCELAR RESERVA', 'Cancelar toda la serie', 'Notas guardadas.'); appointment_detail_sheet ('Detalle del turno', 'VER PERFIL DEL ALUMNO', 'CANCELAR TURNO (menos de 24h)'); availability_editor_screen ('MIS HORARIOS DE TRABAJO', 'EXCEPCIONES', '¿Eliminar esta excepción?', 'Editar horario'); athlete_detail_screen ('ANTROPOMETRÍA', 'RENDIMIENTO', 'COBRO', 'NOTA DEL ALUMNO', 'CONFIGURAR COBRO'); trainers_list_screen ('ENCONTRÁ TU', 'COACH', 'PRESENCIAL', 'ONLINE'); trainers_map_bottom_sheet ('ENTRENADORES CERCA', 'Sin entrenadores con ubicación en esta zona.').
- **Repro:** Switch app locale (or grep the scope for GoogleFonts/Text with literal Spanish). These strings will not localize because they bypass AppL10n.
- **Fix sugerido:** Move each user-facing literal into the ARB files and read via AppL10n.of(context), consistent with the strings already migrated in the same widgets. Pluralized strings (e.g. 'sesión/sesiones registradas', 'medición/mediciones', 'día/días') should use ARB plural selectors.

### [MEDIUM] 'Resumen del día' counts in-progress sessions as completed (done) and never as pending

- **Módulo:** coach · UI
- **Ubicación:** `lib/features/coach/presentation/trainer_dashboard_tab.dart:364`
- **Categoría:** correctness
- **Descripción:** The dashboard derives `done` as confirmed sessions where `!a.startsAt.isAfter(now)` — i.e. the moment start time passes, a session flips from 'pendientes' to 'completadas', even though it is still ongoing (duration not elapsed). A 60-min session that started 5 minutes ago is reported as completed.
- **Repro:** As a trainer with a session starting at the current minute, open the dashboard: the count moves from Pendientes to Completadas immediately at start time rather than at end time.
- **Fix sugerido:** Compare against session end instead of start for the done/pending split, e.g. treat as done only when `a.startsAt.add(Duration(minutes: a.durationMin)).isBefore(now)`, and pending while it has not ended.

### [MEDIUM] cancelFutureSeries reads every confirmed appointment for the trainer to cancel one series

- **Módulo:** coach · UI
- **Ubicación:** `lib/features/coach/data/appointment_repository.dart:246`
- **Categoría:** data
- **Descripción:** Cancelling a recurring series queries ALL future confirmed appointments for the trainer (no recurringId filter, since Firestore can't combine it efficiently here) and filters client-side by `recurringId`. For an active trainer this reads the entire forward booking set on every 'cancelar toda la serie', and all matching writes go in a single non-chunked WriteBatch (500-op limit) — a long-lived, dense series could exceed the batch limit and throw.
- **Repro:** Trainer with many confirmed future appointments taps 'CANCELAR TODA LA SERIE' from SessionDetailSheet: the repository downloads all future confirmed docs to find the series members; with a very large series the single batch.commit() can hit the 500-write cap.
- **Fix sugerido:** Persist a queryable field (e.g. store recurringId and filter `where('recurringId', isEqualTo: ...)` with a composite index on trainerId+recurringId+startsAt), and chunk the writes into batches of ≤500 (or use multiple commits) to stay under Firestore's batch limit.

### [MEDIUM] 28-day booking-horizon rule (REQ-COACH-AGENDA-009) is documented but never enforced

- **Módulo:** coach · logic+data
- **Ubicación:** `lib/features/coach/data/appointment_repository.dart:30`
- **Categoría:** Correctness / dead code
- **Descripción:** BookingTooFarAheadException (agenda_exceptions.dart:29-36) documents that book() throws when startsAt is more than 28 days from now (SCENARIO-496 / REQ-COACH-AGENDA-009). book() contains no such check, and grep shows the exception is never thrown anywhere. The horizon limit is silently unenforced and the exception class is dead.
- **Repro:** Call book() (or surface a slot) with startsAt 60 days in the future. The booking succeeds with no BookingTooFarAheadException, violating the stated requirement.
- **Fix sugerido:** At the top of book(), guard: if (startsAt.toUtc().difference(DateTime.now().toUtc()) > const Duration(days: 28)) throw const BookingTooFarAheadException(); Add a test covering the 28-day boundary.

### [MEDIUM] trainedTodayProvider fans out a full session-history read per shared athlete (N+1) on every rebuild

- **Módulo:** coach · logic+data
- **Ubicación:** `lib/features/coach/application/trained_today_provider.dart:63`
- **Categoría:** Data/Firestore performance
- **Descripción:** The provider loops over every active+sharing athlete and ref.watch(sessionsByUidProvider(athleteId)) for each, which triggers a full listByUid Firestore read of that athlete's entire session history. Cost scales linearly with the trainer's athlete count, and because sessionsByUidProvider is autoDispose it re-reads on navigation churn. For a trainer with dozens of athletes this is a heavy, repeated fan-out just to compute 'who trained today'.
- **Repro:** Trainer with N shared athletes opens the dashboard. N separate full-history reads fire; revisiting the screen re-triggers them.
- **Fix sugerido:** Use a bounded server-side query (e.g. a collectionGroup or per-athlete query limited to finishedAt >= startOfTodayUtc with a small limit) instead of pulling each athlete's complete session list, or cache/aggregate 'trained today' so the dashboard reads O(1).

### [MEDIUM] Manual exercise pick assigns the match to all same-named unmatched rows in the day

- **Módulo:** coach_hub
- **Ubicación:** `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:156`
- **Categoría:** Correctness
- **Descripción:** _pickExerciseFor matches items to update by `it.rowName == rowName && it.exerciseId == null`, keyed only on the row text. If the same unmatched exercise name appears more than once within a single day (e.g. two supersets typed identically), picking a match for one row resolves ALL of them at once, and only one corresponding entry is removed from `unmatched` while the others are wrongly mapped or left dangling.
- **Repro:** Create a day with two rows both named 'Sentadilla X' that don't match the catalog. In the preview, tap 'Asignar manualmente' on the first and pick an exercise. Both rows get mapped to that exercise, even though the trainer only resolved one.
- **Fix sugerido:** Match on a stable per-item identity (e.g. include the item index within the day, or add a unique row id to RawParsedItem/ParsedPlanItem) instead of rowName, and update/remove exactly the targeted item.

### [MEDIUM] Athlete picker uses a deprecated one-shot FutureProvider, missing real-time updates

- **Módulo:** coach_hub
- **Ubicación:** `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:829`
- **Categoría:** State management (Riverpod)
- **Descripción:** _AthletePicker watches linksForTrainerProvider, which is explicitly @Deprecated in trainer_link_providers.dart in favor of the real-time trainerLinksStreamProvider (the dashboard already uses the stream). As a FutureProvider it loads once; if a link is accepted/paused/terminated (from mobile or another tab) while the preview is open, the selectable athlete list goes stale, and a freshly accepted athlete won't appear without leaving and re-entering the screen.
- **Repro:** Open the plan preview; in parallel accept a new athlete link from the mobile app or dashboard. The new active athlete does not show up in the preview's picker.
- **Fix sugerido:** Switch _AthletePicker to ref.watch(trainerLinksStreamProvider) (filtering status == active) to match the dashboard and get real-time updates, removing the dependency on the deprecated provider.

### [MEDIUM] Partial multi-athlete assignment failure clears the plan with no retry path

- **Módulo:** coach_hub
- **Ubicación:** `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:109`
- **Categoría:** Data/Firestore
- **Descripción:** _assign loops over selected athletes calling repo.createAssigned one-by-one (non-atomic). If only SOME succeed, it still clears parsedPlanProvider (sets state = null) and navigates to /dashboard, showing 'Plan asignado a N atleta(s). M fallaron.' The in-memory parsed plan is gone, so the trainer has no way to retry the failed athletes without re-uploading and re-parsing the Excel.
- **Repro:** Select 3 athletes and assign; force one createAssigned to fail (e.g. transient Firestore/network error). You're sent to the dashboard, the plan state is wiped, and the failed athlete(s) have no assignment and no retry affordance.
- **Fix sugerido:** On partial failure, keep parsedPlanProvider populated and stay on the preview (or keep only the failed athleteIds selected) so the trainer can retry; only clear state and navigate when all assignments succeed.

### [MEDIUM] Personal-edit _save() lacks a re-entrancy guard; header back-tap is not disabled during save

- **Módulo:** profile
- **Ubicación:** `lib/features/profile/presentation/profile_edit_personal_screen.dart:159`
- **Categoría:** state-management
- **Descripción:** _save() has no `if (busy) return` at the top — it relies entirely on the GUARDAR pill being disabled via ValueListenableBuilder. The header back GestureDetector (onTap: _onBackTap, line 356) and the discard pill are not all consistently gated, and an in-flight avatar upload + Firestore update can be interrupted: tapping back during save pops the route (context.pop after confirm) while the async update()/upload() is still running, and on a successful upload followed by a failed update the uploaded avatar URL is never persisted, so a retry re-uploads (orphaned storage object).
- **Repro:** Pick a new avatar, tap GUARDAR, then immediately tap the back arrow in the header (it stays tappable). The discard dialog appears and confirming pops the screen while the upload/update future is still in flight.
- **Fix sugerido:** Add `if (_saveState.value == _SaveState.uploading || _saveState.value == _SaveState.saving) return;` at the top of _save(); disable _onBackTap (and the avatar picker) while busy; and only clear the staged avatar / update _existingAvatarUrl after update() succeeds.

### [MEDIUM] Raw Material icon Icons.alternate_email used instead of TreinoIcon (project rule violation)

- **Módulo:** profile_setup
- **Ubicación:** `/Users/martinbackhaus/treino/lib/features/profile_setup/presentation/steps/step_1_username_avatar.dart:87`
- **Categoría:** project-rule
- **Descripción:** The username AuthInput passes `leadingIcon: Icons.alternate_email`, a raw Material icon. The project mandates icons come from the centralized `TreinoIcon` registry (which is Phosphor-based) so iconography stays consistent; every other input/widget in this scope uses TreinoIcon (e.g. step 4 uses TreinoIcon.scales / TreinoIcon.ruler).
- **Repro:** Open the profile setup flow step 1: the username field shows a Material at-sign icon that visually differs from the Phosphor icon set used everywhere else (different stroke/weight).
- **Fix sugerido:** Add an at/email icon to lib/core/widgets/treino_icon.dart (TreinoIcon already exposes `mail = PhosphorIconsRegular.envelope`; or add an `atSign`/`user` entry) and reference `TreinoIcon.atSign` (or TreinoIcon.user) here. Remove the raw `Icons.alternate_email`.

### [MEDIUM] Non-atomic followingCount read-modify-write in accept()/delete() — lost updates under concurrency

- **Módulo:** feed
- **Ubicación:** `lib/features/feed/data/friendship_repository.dart:76`
- **Categoría:** data
- **Descripción:** accept() (lines 76-81) and delete() (lines 151-157) read the public profile, compute currentFollowing +/- 1, then write it back with a separate set(merge). This read-modify-write is not transactional, so two concurrent accepts/deletes (or an accept racing a workout-finish counter write) can clobber each other and drop a count.
- **Repro:** Accept two friend requests in quick succession (or accept while another counter write to the same userPublicProfiles doc is in flight). followingCount ends up off by one because both reads saw the same stale value.
- **Fix sugerido:** Use FieldValue.increment(1) / FieldValue.increment(-1) via updateCounters (atomic server-side increment) instead of read-then-write, with a floor enforced separately if negative values are a concern.

### [MEDIUM] Char counter counts UTF-16 code units while submit gate counts grapheme clusters

- **Módulo:** feed
- **Ubicación:** `lib/features/feed/presentation/create_post_screen.dart:89`
- **Categoría:** correctness
- **Descripción:** _CharCounter is fed state.text.length (UTF-16 code units, line 89) and compares against kMaxPostChars, but CreatePostState.canSubmit uses text.characters.length (grapheme clusters). With emoji or composed characters the displayed counter and the over-limit color can disagree with whether the post is actually submittable — e.g. the counter shows red "over limit" while canSubmit is still true, or vice versa.
- **Repro:** Type emoji (each is 2+ UTF-16 units) until near 280. The "X / 280" counter turns red/over before the grapheme count actually reaches 280, yet PUBLICAR stays enabled (or the inverse), confusing the user.
- **Fix sugerido:** Use state.text.characters.length for the counter to match canSubmit's grapheme-based limit (pass it from the notifier or compute it in _CharCounter).

### [MEDIUM] Follow/Accept tap handlers have no error handling — network failure throws uncaught async error

- **Módulo:** feed
- **Ubicación:** `lib/features/feed/presentation/widgets/public_profile_follow_button.dart:50`
- **Categoría:** state-management
- **Descripción:** The SEGUIR onTap (lines 50-56) awaits repo.request() and the ACEPTAR onTap (lines 79-87) awaits repo.accept() with no try/catch. If the Firestore write fails (offline, permission denied), the exception propagates out of the async GestureDetector callback as an unhandled error with no user feedback. The unfriend sheet and inbox tiles correctly wrap their calls in try/catch; these two paths do not.
- **Repro:** Open a public profile while offline (or with a rule that denies the write) and tap SEGUIR or ACEPTAR. The write throws, nothing is shown to the user, and an uncaught async error is logged.
- **Fix sugerido:** Wrap both awaits in try/catch and surface a snackbar/inline error (and guard ref usage after await), matching the fire-and-forget+swallow pattern already used in _showUnfriendSheet and FriendRequestInboxTile.

### [MEDIUM] Entire chat feature uses hardcoded Spanish strings instead of AppL10n

- **Módulo:** chat
- **Ubicación:** `lib/features/chat/presentation/chat_list_screen.dart:38`
- **Categoría:** i18n
- **Descripción:** The project migrated to ARB/AppL10n (46 feature files consume it, including the sibling coach feature), but every user-facing string in chat is a hardcoded Spanish literal: 'MENSAJES', 'Iniciá la conversación', 'Sin mensajes todavía', the empty/error copy, plus 'Usuario', 'Usuario eliminado', 'No pudimos cargar los mensajes.', composer hint 'Escribí un mensaje…', 'Enviar', and the snackbar 'No pudimos enviar el mensaje. Probá de nuevo.' in chat_screen.dart. The _relativeTime tokens ('recién', 'hace Xm/h/d') are also hardcoded.
- **Repro:** Switch app locale to English (intl_en.arb is present). All chat UI stays in Spanish.
- **Fix sugerido:** Add chat ARB keys to intl_en.arb / intl_es_AR.arb and replace literals with AppL10n.of(context). The code even has 'i18n: Fase 6 Etapa 3' TODO comments acknowledging this is pending.

### [MEDIUM] Check-in recorded as gym check-in when user has the 'no-gym' sentinel

- **Módulo:** check_in
- **Ubicación:** `lib/features/check_in/application/check_in_providers.dart:46`
- **Categoría:** Correctness
- **Descripción:** confirm() derives inGym from `gymId != null`, but a user whose profile gymId is the kNoGymId sentinel ('no-gym') passes a non-null gymId. The resulting CheckIn is stored with inGym=true, gymId='no-gym', gymName=null — an inconsistent record that claims to be a gym check-in pointing at the 'no gym' sentinel.
- **Repro:** Set a user's profile gymId to 'no-gym' (the kNoGymId sentinel from gym.dart). Open the feed, tap 'Si' on the check-in dialog. Inspect /users/{uid}/checkIns/{date}: it has gymId:'no-gym' with no gymName, treated as an in-gym check-in.
- **Fix sugerido:** Treat kNoGymId as not-in-gym. In FeedScreen pass null when gymId == kNoGymId, or in confirm()/createTodayCheckIn compute inGym as `gymId != null && gymId != kNoGymId && gymId.isNotEmpty` and null out gymId/gymName accordingly.

### [MEDIUM] Trainer only sees measurements they personally recorded; co-trainer / reassignment loses history

- **Módulo:** measurements
- **Ubicación:** `lib/features/measurements/application/measurement_providers.dart:24`
- **Categoría:** Data/Firestore
- **Descripción:** measurementsForAthleteProvider queries watchRecordedBy(trainerUid) and then filters by athleteId, so the trainer only ever sees measurements whose recordedBy equals their own uid. Any measurement logged for the same athlete by a previous trainer or a co-trainer is silently invisible, even though the repository already exposes watchForAthlete(athleteId) which is the correct query for an athlete-scoped view.
- **Repro:** Athlete A has measurements logged by trainer T1. Reassign A to trainer T2 (or have a second trainer log a measurement). Open the athlete detail / ANTROPOMETRÍA section as T2: the history recorded by T1 is missing, the count is wrong, and the progress chart restarts.
- **Fix sugerido:** Drive the athlete view from watchForAthlete(athleteId) (filter by athleteId, sort by recordedAt) so all measurements for the athlete are returned regardless of who recorded them. The existing watchForAthlete method is already implemented but unused (dead code) — wire it up here, or document explicitly that single-trainer scoping is intended.

### [MEDIUM] Empty measurement can be saved (no 'at least one field' validation)

- **Módulo:** measurements
- **Ubicación:** `lib/features/measurements/presentation/log_measurement_screen.dart:161`
- **Categoría:** Edge cases
- **Descripción:** _save() builds and persists a Measurement even when every numeric field is empty and notes is blank. _parseDouble returns null for empty input and there is no guard requiring at least one non-null metric, so the GUARDAR MEDICIÓN button is enabled and a fully-null document is written to Firestore.
- **Repro:** Open LogMeasurementScreen, type nothing, tap GUARDAR MEDICIÓN. A measurement doc with all metrics null and no notes is created. It inflates the '$count mediciones registradas' counter and can flip the chart gate to '>=2' with no actual data, showing an empty/degenerate PROGRESO chart.
- **Fix sugerido:** Compute a hasAnyValue flag (any _parseDouble(...) != null || notes non-empty) and either disable canSave or show a snackbar and return early in _save() when nothing was entered.

### [MEDIUM] Entire performance feature hardcodes Spanish strings instead of AppL10n (project migrated to ARB/AppL10n)

- **Módulo:** performance
- **Ubicación:** `/Users/martinbackhaus/treino/lib/features/performance/presentation/log_performance_test_screen.dart:159`
- **Categoría:** i18n
- **Descripción:** User-facing strings are hardcoded Spanish across the whole scope: 'No hay sesión activa...' (159), 'Evaluación guardada' (198), the save-error snackbar (205-208), 'Cancelar' (236), 'Cargar evaluación' (249), 'GUARDAR EVALUACIÓN' (462), all section labels and field labels; plus 'PROGRESO' (183), span labels 'día/días/semana/semanas' (93-95) and unit/metric labels in performance_progress_chart.dart. The hosting coach feature (athlete_detail_screen.dart) uses AppL10n.of(context).* for all its strings, so this scope is an un-migrated island.
- **Repro:** Grep the scope: no AppL10n / context.l10n references exist, while sibling coach screens use AppL10n.of(context). Switching app locale leaves these screens in Spanish.
- **Fix sugerido:** Move user-facing literals to intl_*.arb keys and read them via AppL10n.of(context) (as athlete_detail_screen does), or add CoachStrings-style shims. Month name arrays (_kMonths / _kMonthsShort) and date/plural formatting should use intl DateFormat / plural rules rather than hand-rolled arrays.

### [MEDIUM] Misleading PROGRESO header (▲ 0.0, '0 días', no chart) when selected metric has only one data point

- **Módulo:** performance
- **Ubicación:** `/Users/martinbackhaus/treino/lib/features/performance/presentation/widgets/performance_progress_chart.dart:203`
- **Categoría:** Correctness / UI
- **Descripción:** The caller gates the chart on total test count (athlete_detail_screen.dart:843 `if (tests.length >= 2)`), but a metric needs ≥2 NON-NULL values of the SAME field to be plottable. _buildAvailable falls back to [_kAllMetrics.first] (CMJ) when no metric qualifies (line 152). _ChartHeader then renders for any non-empty points (line 203), so with a single data point it shows delta=0 → '▲ 0.0 cm (0 días)' and no line chart (line 208 requires length≥2). The 'progress' card looks broken/misleading.
- **Repro:** Log two performance tests for an athlete but fill DIFFERENT metrics each time (e.g. test 1: only CMJ; test 2: only Sprint 20m). tests.length==2 so the card renders, but no metric has 2 points. The card shows the CMJ fallback chip with a '▲ 0.0 cm (0 días)' header and an empty chart area.
- **Fix sugerido:** Have _buildAvailable return an empty list when no metric has ≥2 points and render the 'Cargá otra evaluación...' hint instead of the chart; or guard _ChartHeader to only show when points.length >= 2 so a single point never produces a fake delta. Also avoid the [_kAllMetrics.first] fallback that fabricates an unplottable selection.

### [MEDIUM] Resume-session dedup uses identical() on Dart records, so it never dedupes -> modal can stack

- **Módulo:** home
- **Ubicación:** `lib/features/home/home_screen.dart:64`
- **Categoría:** state-management
- **Descripción:** The ref.listen guard does `identical((prev as AsyncData).value, next.value)` to avoid re-showing the resume dialog. activeSessionForUidProvider returns a fresh Dart record `(session:..., setLogs:...)` on every run, and two records with equal fields are == but never identical. So when the provider re-emits the same active session (it watches currentUidProvider -> authStateChangesProvider, a stream that can re-emit while _AthleteHome stays mounted), the guard fails and _maybeShowResumePrompt fires again.
- **Repro:** Verified Dart record semantics by execution: identical(r1, r2) is false for two records with the same field values even when r1 == r2 is true. With the barrierDismissible:false modal already open, a second identical 'Entrenamiento en curso' dialog gets pushed on top.
- **Fix sugerido:** Compare by value or by stable id instead of identity: e.g. guard on `prev?.valueOrNull?.session.id == next.valueOrNull?.session.id` (or use == on the record). Optionally also track a 'dialog already shown' flag so a re-emit can't stack a second dialog.

### [MEDIUM] ref used after await in onDiscard without a mounted/ref-alive guard

- **Módulo:** home
- **Ubicación:** `lib/features/home/home_screen.dart:118`
- **Categoría:** state-management
- **Descripción:** In the resume modal's onDiscard callback, after `await repo.finish(...)` the code calls `ref.invalidate(activeSessionForUidProvider)` using the WidgetRef captured from _AthleteHome.build. If _AthleteHome is disposed during the await (user navigates away while the finish write is in flight), invalidating through a disposed ref can throw. The code guards dialogCtx.mounted before popping but not the ref usage.
- **Repro:** Open the resume dialog, tap 'Descartar', and navigate/pop the home tab before the Firestore finish() write completes; the post-await ref.invalidate runs against a torn-down scope.
- **Fix sugerido:** Capture the provider container or read sessionRepositoryProvider before the await, and guard the post-await ref work (e.g. only invalidate if context.mounted, or perform the invalidate via a captured container). Prefer reading needed objects before awaiting and checking mounted after.

### [MEDIUM] EmpezarEntrenamientoCard ships hardcoded fake plan data including a static "HOY · JUEVES"

- **Módulo:** home
- **Ubicación:** `lib/features/home/widgets/empezar_entrenamiento_card.dart:15`
- **Categoría:** correctness
- **Descripción:** The primary home CTA card renders fully hardcoded values (_dayLabel 'HOY · JUEVES', _heroLabel 'PUSH', '6 ejercicios', '~55 min', muscle subtitle) that never reflect the user's actual routine or the real weekday. The 'HOY · JUEVES' label always reads JUEVES regardless of the current day, so a user opening on any other day sees a wrong 'today'.
- **Repro:** Open the Home tab on any day that is not Thursday; the card still shows 'HOY · JUEVES'. The exercise count, duration and workout name are identical for every user.
- **Fix sugerido:** Wire the card to the real plan/session provider (today's planned routine day) like EstaSemanaCard wires weeklyInsightsProvider. At minimum derive the day label from DateTime.now().weekday. Until wired, treat the displayed numbers as not safe to ship to users.

### [MEDIUM] ForegroundSnackBarHandler is dead code duplicating app.dart's inline foreground handler

- **Módulo:** notifications
- **Ubicación:** `lib/features/notifications/presentation/foreground_snackbar_handler.dart:16`
- **Categoría:** Maintainability / Dead code
- **Descripción:** ForegroundSnackBarHandler is never mounted in the app (the only reference outside its own file is its test). app.dart reimplements the identical foreground-SnackBar logic inline (_onForeground, app.dart:69). Having two divergent copies of the same behavior is a maintenance hazard — the widget version still hardcodes 'Ver' and relies on a per-build _routerContext, while the live app.dart version uses AppL10n and the router navigator key. Fixes applied to one will silently miss the other.
- **Repro:** Grep the lib tree for ForegroundSnackBarHandler: it appears only in its own file and its test, never in home_screen.dart or app.dart where the SnackBar is actually wired.
- **Fix sugerido:** Either delete foreground_snackbar_handler.dart (and its test) and keep the single inline handler in app.dart, or refactor app.dart to mount ForegroundSnackBarHandler and remove the duplicated inline logic so there is exactly one source of truth.

### [MEDIUM] 'Mi Cuota' silently swallows stream errors, showing wrong/empty amounts

- **Módulo:** payments
- **Ubicación:** `lib/features/payments/application/mi_cuota_provider.dart:90`
- **Categoría:** State management (Riverpod)
- **Descripción:** Unlike pagosPorCobrarProvider, miCuotaProvider never checks hasError on any dependency (currentAthleteLink, athletePayments, athleteBillingPair, sessions). When a watched stream errors with no prior value, the loading guard (isLoading && !hasValue) is false, so the provider proceeds using valueOrNull ?? const [] and emits AsyncValue.data with incomplete data, hiding the failure from the user.
- **Repro:** Force a Firestore permission/transient error on athletePaymentsProvider while viewing Mi Cuota with no cached value. Instead of an error UI, the athlete sees an empty or partial cuota (e.g. recurring charge shown but pending one-offs missing), with no indication anything failed.
- **Fix sugerido:** After each ref.watch, add a hasError && !hasValue branch that returns AsyncValue.error(asyncVal.error!, asyncVal.stackTrace!), matching the pattern already used for linksAsync in pagosPorCobrarProvider.

### [MEDIUM] Payments-stream error makes every athlete appear unpaid (wrong charges shown)

- **Módulo:** payments
- **Ubicación:** `lib/features/payments/application/pagos_por_cobrar_provider.dart:108`
- **Categoría:** State management (Riverpod)
- **Descripción:** Only linksAsync is checked for hasError. If trainerPaymentsProvider errors with no prior value, the loading guard is skipped and allPayments falls back to const [], so the 'already paid' / lastPaidAt logic treats everyone as never paid and re-surfaces charges. sessionsAsync/billingAsync errors are likewise swallowed via valueOrNull.
- **Repro:** Trigger a transient error on trainerPaymentsProvider (e.g. offline/permission blip) before any payment data has loaded. The dashboard lists every active athlete as owing their full recurring charge again, because the empty fallback hides all prior 'paid' records.
- **Fix sugerido:** Add hasError && !hasValue guards (return AsyncValue.error) for paymentsAsync, and treat per-athlete billingAsync/sessionsAsync errors explicitly instead of silently falling back to empty data.

### [MEDIUM] Marking multiple one-off (suelto) payments paid is non-atomic — no batch in repository

- **Módulo:** payments
- **Ubicación:** `lib/features/payments/data/payment_repository.dart:24`
- **Categoría:** Data/Firestore
- **Descripción:** PaymentRepository exposes only single-doc markPaid; the suelto confirmation loops markPaid per id sequentially (trainer_dashboard_tab.dart:1007-1009). If one update fails midway (network error, or a concurrently deleted doc making update throw not-found), earlier docs are already marked paid while later ones are not, leaving the athlete's pending charges in an inconsistent half-paid state.
- **Repro:** Athlete has 3 pending one-off charges. Trainer taps 'Cobrado' while connectivity drops after the first write, or one of the payment docs was deleted: the first payment flips to paid, the loop throws on a later doc, and the UI shows an error while 1 of 3 is already paid.
- **Fix sugerido:** Add a markManyPaid(List<String> ids, DateTime paidAt) to PaymentRepository that uses a WriteBatch (firestore.batch() + batch.update per id + batch.commit) so all docs flip atomically, and call it from the suelto branch instead of the per-id loop.

### [LOW] Routine detail, exercise detail and other workout screens use hardcoded Spanish

- **Módulo:** workout · UI
- **Ubicación:** `lib/features/workout/presentation/routine_detail_screen.dart:57`
- **Categoría:** i18n
- **Descripción:** Multiple screens/widgets bypass AppL10n with hardcoded Spanish: routine_detail_screen ('Rutina no encontrada' 57, 'Esta rutina no tiene dias configurados.' 63, 'No pudimos cargar la rutina.' 94, 'EJERCICIOS/SETS/MINUTOS' 289-297, 'EMPEZAR' 969/1064, 'PLAN COMPLETADO'/'COMPLETADO'/'SEMANA BLOQUEADA'/'DIA BLOQUEADO' 834/897/929, 'Sin ejercicios esta semana' 256, 'Reintentar' 1126); exercise_detail_screen ('Ejercicio no encontrado' 76, 'No pudimos cargar el ejercicio.' 80, 'VIDEO/TECNICA/HISTORIAL' 170/177/186, 'Aun no entrenaste este ejercicio' 474); my_exercises_screen ('MIS EJERCICIOS' 38, '+ NUEVO EJERCICIO' 89, empty-state copy 120/130); custom_exercise_editor_screen (header/labels/toasts throughout); resume_session_modal ('Entrenamiento en curso' / continue/discard 30-75); exercise_video_player ('No pudimos abrir el video.' 69, placeholder copy 297-299).
- **Repro:** Inspect these screens with the AppL10n migration in mind; sibling screens localize but these do not.
- **Fix sugerido:** Migrate these literals to ARB keys via AppL10n, consistent with the already-localized workout screens.

### [LOW] _finalize() kills the timer before the finish write completes; failed write leaves session unfinished and frozen

- **Módulo:** workout · logic+data
- **Ubicación:** `lib/features/workout/application/session_notifier.dart:278`
- **Categoría:** State management (Riverpod)
- **Descripción:** finishSession/abandonSession set _finalized=true and cancel the timer (via _finalize) BEFORE awaiting repo.finish(). If the Firestore write throws, the exception propagates uncaught, the session doc is never marked finished, but the in-memory notifier is already finalized (timer dead, _finalized=true) so no further mutation or retry is possible without rebuilding the provider.
- **Repro:** Trigger finishSession while offline / with a Firestore error. _finalize() runs, then repo.finish() throws; the active session remains status=active in Firestore while the local notifier is dead, and the elapsed timer no longer updates.
- **Fix sugerido:** Await the write first inside a try, and only call _finalize() after it succeeds; on failure, surface AsyncError and keep the notifier usable so the user can retry. Alternatively wrap finish in try/catch and reset _finalized/restart the timer on failure.

### [LOW] Accept/Reject pending-request buttons have no in-flight guard (double-submit)

- **Módulo:** coach · UI
- **Ubicación:** `lib/features/coach/presentation/trainer_dashboard_tab.dart:307`
- **Categoría:** state-management
- **Descripción:** `_PendingRequestCard` is a stateless ConsumerWidget; its ACEPTAR/RECHAZAR onPressed call `trainerLinkRepository.accept/decline` with no disabled/loading state. A fast double-tap before the stream rebuilds removes the card fires the mutation twice (and logs analytics twice for accept).
- **Repro:** Double-tap ACEPTAR quickly on a pending request before the list rebuilds: accept(link.id) and logLinkAccepted run twice.
- **Fix sugerido:** Convert to a stateful widget (or track a per-link saving flag) and disable both buttons once a request is in flight, re-enabling only on error.

### [LOW] Weight values render with a trailing .0 (e.g. '60.0 kg') in the day-item subtitle

- **Módulo:** coach_hub
- **Ubicación:** `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart:635`
- **Categoría:** UI/layout
- **Descripción:** _itemSubtitle interpolates weightKg (a double) directly: ' · ${i.weightKg} kg'. The Excel template ships integer weights (60, 50, 40) which _asNumber parses to doubles, so whole-number weights display as '60.0 kg' instead of '60 kg'. Minor but user-visible polish issue on every imported plan.
- **Repro:** Import the bundled template and open the preview; each exercise shows e.g. '4 × 8-10 · 90s · 60.0 kg'.
- **Fix sugerido:** Format the weight to strip a trailing zero, e.g. weight == weight.roundToDouble() ? weight.toStringAsFixed(0) : weight.toString(), before interpolation.

### [LOW] signUpWithEmail leaves an orphan Auth user if sendEmailVerification throws

- **Módulo:** auth
- **Ubicación:** `lib/features/auth/data/auth_service.dart:50`
- **Categoría:** data-firestore
- **Descripción:** In signUpWithEmail, `user.sendEmailVerification()` (line 50) runs inside the outer try. If it throws a FirebaseAuthException (e.g. too-many-requests on the verification quota), it is caught at line 70 and rethrown as AuthFailure.fromFirebase, but unlike the Firestore-failure path (lines 57-65) the orphan Auth user is NOT deleted. The account is created in Firebase Auth with no Firestore profile and no rollback, and the user sees an error as if signup failed.
- **Repro:** Force sendEmailVerification to fail (e.g. exceed Firebase's email-verification rate limit during signup). The Auth user persists while the UI reports failure; retrying hits email-already-in-use.
- **Fix sugerido:** Wrap sendEmailVerification in its own try and treat its failure as non-fatal (verification can be re-sent later), or apply the same best-effort `user.delete()` rollback used for the Firestore-failure branch before rethrowing.

### [LOW] Volume stat uses kFormat which rounds to nearest k (1500 kg → '2k'), overstating displayed volume

- **Módulo:** profile
- **Ubicación:** `lib/features/profile/profile_screen.dart:169`
- **Categoría:** correctness
- **Descripción:** The VOLUMEN KG stat renders kFormat(s.totalVolumeKg). kFormat uses (value/1000).toStringAsFixed(0) which ROUNDS, so 1500 kg shows '2k' and 1499 kg shows '1k'. For a fitness app, rounding total lifted volume UP by up to ~500 kg is misleading; the documented examples (kFormat(1500) → '2k') confirm the rounding is by design but it inflates the user's headline number.
- **Repro:** Finish sessions totalling 1500 kg of volume; the profile stats card shows '2k' instead of ~'1.5k'.
- **Fix sugerido:** Use truncation or one-decimal formatting for volume (e.g. (value/1000).toStringAsFixed(1) → '1.5k', or floor), or display the raw integer with thousands separators for sub-10k values.

### [LOW] Height field silently nulls out (and disables Next) when user enters a decimal

- **Módulo:** profile_setup
- **Ubicación:** `/Users/martinbackhaus/treino/lib/features/profile_setup/presentation/steps/step_4_weight_height.dart:42`
- **Categoría:** edge-case
- **Descripción:** _syncHeight parses the height controller with `int.tryParse(_heightCtrl.text.trim())`. The field uses `TextInputType.number` which on several platforms/locales still permits a decimal separator or paste. Any non-integer input (e.g. '168.0', '168,5', or a stray space mid-string) makes int.tryParse return null, so updateHeightCm(null) is called: the draft height clears, isStep4Valid becomes false and the 'EMPEZAR' button silently greys out, while the validator error (only shown on form submit/validation, not on this live listener) never surfaces. The user sees text in the field but cannot proceed and gets no inline explanation.
- **Repro:** On step 4 type a height like '168.5' (or paste '168.0'): the primary button becomes disabled with no visible error explaining why; deleting the decimal re-enables it.
- **Fix sugerido:** Restrict input with an inputFormatter (FilteringTextInputFormatter.digitsOnly) on the height field, and/or surface the validator message live (e.g. validate on change) so a non-integer height shows 'Número entero inválido' instead of silently disabling Next. Weight already tolerates comma via replaceAll(',', '.'); height should at least guard against the same separator.

### [LOW] Material Icons used directly instead of TreinoIcon (project rule violation)

- **Módulo:** feed
- **Ubicación:** `lib/features/feed/presentation/search_users_screen.dart:116`
- **Categoría:** project-rule
- **Descripción:** search_users_screen.dart uses Icons.arrow_back (line 116) and Icons.close (line 190) directly from Material. Project rule requires TreinoIcon.X (e.g. TreinoIcon.back is already used in friend_requests_inbox_screen.dart). This bypasses the icon system and produces visual inconsistency.
- **Repro:** Code review / visual diff: the search screen's back and clear icons are stock Material glyphs, not the Phosphor-based TreinoIcon set used everywhere else in the feature.
- **Fix sugerido:** Replace Icons.arrow_back with TreinoIcon.back and Icons.close with the appropriate TreinoIcon (e.g. TreinoIcon.x / close equivalent).

### [LOW] firstPostByAuthorProvider deserializes Post without injecting doc id — latent crash on id-stripped docs

- **Módulo:** feed
- **Ubicación:** `lib/features/feed/application/public_profile_providers.dart:59`
- **Categoría:** data
- **Descripción:** firstPostByAuthorProvider calls Post.fromJson(snap.docs.first.data()) directly (line 59) without the {...data, 'id': snap.id} merge that PostRepository._fromDoc deliberately uses. Post.id is a required field with no default; per the repository's own comments, seed-written posts strip 'id' from the body and store it only as the doc id, so this path would throw during deserialization for such docs. The provider currently has no consumers (dead code), so it is not user-hittable today, but the inconsistency is a real latent bug if it gets wired up.
- **Repro:** Wire firstPostByAuthorProvider to a screen and point it at a target whose most-recent post was seed-written (no 'id' in the body). Post.fromJson throws on the missing required 'id'.
- **Fix sugerido:** Either remove the unused provider, or change line 59 to Post.fromJson({...snap.docs.first.data(), 'id': snap.docs.first.id}) to match the repository's _fromDoc behavior.

### [LOW] Non-atomic read-then-write in createTodayCheckIn can produce concurrent duplicate writes

- **Módulo:** check_in
- **Ubicación:** `lib/features/check_in/data/check_in_repository.dart:44`
- **Categoría:** Data/Firestore
- **Descripción:** createTodayCheckIn does a get() then a separate set() (read-then-write). The Si button is not disabled during the await and the doc id is deterministic per day, so a rapid double-tap (or concurrent device) can have both calls observe 'no existing doc' and both call set(). Idempotency by doc id keeps the data correct, but the guard is not actually atomic and the second set() can overwrite checkedInAt.
- **Repro:** Double-tap the 'Si' button quickly (no disabled/loading state on the button). Both invocations may pass the existing.exists check before either set() lands, issuing two writes for the same day.
- **Fix sugerido:** Use set(..., SetOptions(merge:false)) inside a Firestore transaction, or use a create-only write (e.g. handle the already-exists case) so the existence check and write are atomic. Also disable the Si button while checkInNotifierProvider state is loading.

### [LOW] Raw double interpolation produces ugly values (e.g. '70.0 kg', floating-point tails) in latest-measurement card

- **Módulo:** measurements
- **Ubicación:** `lib/features/coach/presentation/athlete_detail_screen.dart:555`
- **Categoría:** Correctness
- **Descripción:** The latest-measurement summary card interpolates the stored doubles directly ('${latest.weightKg} kg', '${latest.fatPercentage}%', etc.) with no formatting, unlike the in-scope chart which uses a value%1==0 ? toStringAsFixed(0) : toStringAsFixed(1) pattern. Whole numbers render as '70.0 kg' and float round-trips can render long decimal tails.
- **Repro:** Log a measurement with Peso=70 (or any value whose parse leaves a binary-float tail). The summary card shows '70.0 kg' instead of '70 kg' and is inconsistent with the chart header formatting.
- **Fix sugerido:** Reuse the same formatting helper the chart uses (value % 1 == 0 ? toStringAsFixed(0) : toStringAsFixed(1)) for the summary metric values so the card and chart are consistent.

### [LOW] Athlete provider over-reads: fetches ALL trainer tests then filters client-side, ignoring the existing per-athlete query

- **Módulo:** performance
- **Ubicación:** `/Users/martinbackhaus/treino/lib/features/performance/application/performance_test_providers.dart:23`
- **Categoría:** Data/Firestore
- **Descripción:** performanceTestsForAthleteProvider streams watchRecordedBy(trainerUid) — every performance_test the trainer ever recorded for ANY athlete — then filters to athleteId and sorts client-side (lines 27-28). The repository already exposes watchForAthlete(athleteId) (data/performance_test_repository.dart:53) which is a single-field query and is never used. For a trainer with many athletes this re-reads and re-streams the entire trainer-wide collection per athlete-detail view.
- **Repro:** Open athlete detail for one athlete; the stream loads/streams every test the trainer ever logged across all athletes, not just this athlete's. Read cost and payload grow with the trainer's total history rather than the athlete's.
- **Fix sugerido:** Use the existing repository.watchForAthlete(athleteId) (single-field query on athleteId, no composite index) and keep the client-side ascending sort. This scopes reads to the athlete and removes the dead watchForAthlete/unused code path.

### [LOW] Week boundaries use Duration(days:N) on local DateTimes (DST drift)

- **Módulo:** insights
- **Ubicación:** `lib/features/insights/application/insights_providers.dart:23`
- **Categoría:** Edge cases
- **Descripción:** weekEndExclusive = weekStart.add(Duration(days:7)) and _mondayOfWeek uses .subtract(Duration(days: N)) on a local DateTime. Across a DST transition these land at 23:00 or 01:00 instead of local midnight, shifting the inclusive week window by an hour and the day-chip dayOfMonth labels (insights_screen.dart:222: weekStart.add(Duration(days:i)).day) potentially onto the wrong calendar day. Impact is low for the primary locale (Argentina does not observe DST), but the code is locale-agnostic.
- **Repro:** Run the app in a DST-observing timezone during the spring-forward / fall-back week: the week range header and/or a day chip's number can be off by one near the boundary, and a session started just after local midnight on the boundary day could fall outside the week filter.
- **Fix sugerido:** Compute boundaries with calendar arithmetic instead of Duration: derive weekEndExclusive as DateTime(weekStart.year, weekStart.month, weekStart.day + 7) and day labels as DateTime(weekStart.year, weekStart.month, weekStart.day + i), which normalize correctly across DST.

### [LOW] N+1 Firestore reads behind EstaSemanaCard (serial listSetLogs per session)

- **Módulo:** home
- **Ubicación:** `lib/features/insights/application/insights_providers.dart:53`
- **Categoría:** data-firestore
- **Descripción:** weeklyInsightsProvider, which EstaSemanaCard watches, iterates weekSessions and awaits repo.listSetLogs(uid, sessionId) one session at a time inside a for loop (serial N+1). The same file already uses Future.wait for parallelism elsewhere (lastWeightByExerciseProvider), so this loop needlessly serializes the set-log reads that drive the home card.
- **Repro:** Open the Home tab for a user with several finished sessions this week; the card's data state waits on sequential per-session subcollection reads before rendering.
- **Fix sugerido:** Collect the futures and await Future.wait(weekSessions.map((s) => repo.listSetLogs(uid: uid, sessionId: s.id))) to parallelize, then aggregate setsByGroup from the combined results.

### [LOW] N+1 Firestore real-time listeners: one userPublicProfiles listener per review tile

- **Módulo:** reviews
- **Ubicación:** `lib/features/reviews/presentation/widgets/review_tile.dart:50`
- **Categoría:** Data/Firestore
- **Descripción:** TrainerReviewsSection builds a Column of ReviewTile widgets (up to 10), and each ReviewTile calls ref.watch(userPublicProfileProvider(review.athleteId)), which opens an independent userPublicProfiles/{athleteId} snapshots() listener (user_public_profile_repository.dart line 36). Rendering the section therefore opens up to 10 concurrent per-document real-time listeners, an N+1 read/listen pattern. It is bounded at 10 so the impact is limited, but it adds avoidable Firestore reads and listeners on every profile view.
- **Repro:** Open a trainer profile with 10 reviews and observe 10 separate userPublicProfiles document listeners being established.
- **Fix sugerido:** Resolve author profiles once for the batch (e.g. a whereIn / batched get over the distinct athleteIds in the loaded reviews, or a short-lived cache provider) and pass the resolved profile into each ReviewTile instead of each tile opening its own live listener.

### [LOW] avatarUrl is gated on displayName != null, conflating 'no name' with 'deleted account'

- **Módulo:** reviews
- **Ubicación:** `lib/features/reviews/presentation/widgets/review_tile.dart:59`
- **Categoría:** Correctness
- **Descripción:** `final avatarUrl = profile?.displayName != null ? profile?.avatarUrl : null;` ties showing the avatar to the presence of a displayName. A valid, non-deleted profile that has an avatar but a null/blank displayName will be rendered as 'Usuario eliminado' with no avatar, mislabeling a live account as deleted. The deleted-account signal should be the profile being null, not the displayName being null.
- **Repro:** A review author whose userPublicProfiles doc exists with avatarUrl set but displayName null renders as 'Usuario eliminado' without their avatar.
- **Fix sugerido:** Base the deleted fallback on `profile == null` only: `final name = profile?.displayName ?? 'Usuario eliminado'; final avatarUrl = profile?.avatarUrl;` (and handle a blank displayName explicitly if that is a real state).

