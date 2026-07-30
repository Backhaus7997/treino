import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/coach_hub_app.dart';
import 'core/persistence/shared_prefs_provider.dart';
import 'features/auth/application/auth_notifier.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/chat/application/chat_providers.dart';
import 'features/coach/application/agenda_providers.dart';
import 'features/coach/application/trainer_link_providers.dart';
import 'features/coach/domain/appointment.dart';
import 'features/coach/domain/trainer_link.dart';
import 'features/coach/domain/trainer_link_status.dart';
import 'features/coach_hub/application/aggregate_adherence_provider.dart';
import 'features/coach_hub/application/inactivos_provider.dart';
import 'features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'features/payments/domain/payment.dart';
import 'features/profile/application/user_providers.dart';
import 'features/profile/application/user_public_profile_providers.dart';
import 'features/profile/domain/user_profile.dart';
import 'features/profile/domain/user_public_profile.dart';
import 'features/profile/domain/user_role.dart';
import 'features/workout/application/session_providers.dart';

/// THROWAWAY VISUAL PREVIEW — TREINO Coach Hub dashboard with fake data.
///
/// Boots the SAME [CoachHubApp] used by `lib/main_coach_hub.dart`, but every
/// data-reading provider is overridden with realistic in-memory fake data via
/// Riverpod `overrides`. There is NO Firebase initialization, NO Firestore
/// read, NO Auth call — nothing in this file touches the backend.
///
/// Purpose: let a human SEE the dashboard fully rendered ("gimnasio activo,
/// realista") without needing seeded emulator data or a live project.
///
/// This file is:
///   - NOT used in production (no build/deploy target references it).
///   - NOT a test (no assertions, not run by `flutter test`).
///   - Safe to delete at any time.
///
/// Run local:
///   flutter run -t lib/main_coach_hub_preview.dart -d chrome
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Datos de formato de fecha en español (etiquetas del calendario, meses) —
  // mismo requisito que el entry point real, sin esto widgets de fecha
  // crashean.
  await initializeDateFormatting('es');

  // Eager-resolve SharedPreferences before runApp — ThemeModeNotifier /
  // SidebarCollapsedNotifier read sharedPreferencesProvider.requireValue at
  // init time (ADR-LM-009). Mirrors lib/main_coach_hub.dart.
  final prefs = await SharedPreferences.getInstance();

  final fake = _FakeCoachHubData();

  runApp(
    ProviderScope(
      overrides: [
        // Synchronous by contract — see sharedPreferencesOverride (#543).
        sharedPreferencesOverride(prefs),

        // ── Auth bypass ──────────────────────────────────────────────────
        // The router redirect (coachHubRedirect) requires a non-null user
        // AND a trainer-role profile, or it bounces to /login / /not-allowed.
        authNotifierProvider.overrideWith(() => _StubAuthNotifier(_FakeUser())),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(fake.trainerProfile),
        ),

        // ── Identity / roster ────────────────────────────────────────────
        currentUidProvider.overrideWithValue(fake.trainerUid),
        trainerLinksStreamProvider.overrideWith(
          (ref) => Stream.value(fake.trainerLinks),
        ),

        // ── Pagos ─────────────────────────────────────────────────────────
        pagosBucketsProvider
            .overrideWith((ref) => AsyncData(fake.pagosBuckets)),

        // ── Chat badge ────────────────────────────────────────────────────
        totalUnreadCountProvider.overrideWithValue(2),

        // ── Agenda ────────────────────────────────────────────────────────
        trainerAppointmentsStreamProvider.overrideWith(
          (ref, key) => Stream.value(fake.appointments),
        ),

        // ── KPIs derivados ────────────────────────────────────────────────
        aggregateAdherenceProvider.overrideWith((ref) async => 85.0),
        inactivosProvider.overrideWith(
          (ref) async => InactivosResult(
            inactiveAthleteIds: [fake.inactiveAthleteId],
          ),
        ),

        // ── Resolución de nombres (uno por c/u de los athleteIds fake) ────
        for (final profile in fake.publicProfiles)
          userPublicProfileProvider(profile.uid).overrideWith(
            (ref) => Stream.value(profile),
          ),
      ],
      child: const CoachHubApp(),
    ),
  );
}

// ─── Auth bypass stubs ──────────────────────────────────────────────────────

/// Stub [AuthNotifier] that seeds `state` with a fixed fake user instead of
/// listening to `authStateChangesProvider` (which would hit Firebase Auth).
/// Shape mirrors `_StubAuthNotifier` in
/// `test/app/coach_hub_router_shell_test.dart`.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._user);
  final User _user;

  @override
  Future<User?> build() async {
    state = AsyncData(_user);
    return _user;
  }
}

/// Minimal non-null [User] stand-in. The router redirect only checks
/// non-nullity (`auth.valueOrNull != null`) — it never reads `.uid` or any
/// other member off this object, so a `noSuchMethod` stub is sufficient and
/// avoids pulling `mocktail` into `lib/`.
class _FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// ─── Fake dataset ───────────────────────────────────────────────────────────

/// Realistic "gimnasio activo" dataset for the preview: 6 active athletes +
/// 1 pending request + 1 inactive, a mix of today/future sessions, and a
/// coherent set of payments (~$480.000 ingreso del mes + pendientes).
///
/// All dates are anchored to `DateTime.now()` so the preview always looks
/// current, regardless of when it's run.
class _FakeCoachHubData {
  _FakeCoachHubData() : now = DateTime.now();

  final DateTime now;

  final String trainerUid = 'trainer-preview-1';

  // ── Athletes ────────────────────────────────────────────────────────────
  // 6 active + 1 pending + 1 inactive = 8 distinct athlete identities.
  static const _activeAthletes = [
    (id: 'a-mateo', name: 'Mateo Fernández'),
    (id: 'a-lucia', name: 'Lucía Gómez'),
    (id: 'a-joaquin', name: 'Joaquín Rodríguez'),
    (id: 'a-sofia', name: 'Sofía Martínez'),
    (id: 'a-tomas', name: 'Tomás Álvarez'),
    (id: 'a-valentina', name: 'Valentina Torres'),
  ];
  static const _pendingAthlete = (id: 'a-pending-1', name: 'Bautista Romero');
  static const _inactiveAthlete = (id: 'a-inactive-1', name: 'Camila Ibáñez');

  String get inactiveAthleteId => _inactiveAthlete.id;

  UserProfile get trainerProfile => UserProfile(
        uid: trainerUid,
        email: 'coach.preview@treino.app',
        displayName: 'Coach Preview',
        role: UserRole.trainer,
        createdAt: now.subtract(const Duration(days: 400)),
        updatedAt: now,
      );

  List<TrainerLink> get trainerLinks => [
        for (final a in _activeAthletes)
          TrainerLink(
            id: 'link-${a.id}',
            trainerId: trainerUid,
            athleteId: a.id,
            status: TrainerLinkStatus.active,
            requestedAt: now.subtract(const Duration(days: 90)),
            acceptedAt: now.subtract(const Duration(days: 89)),
          ),
        TrainerLink(
          id: 'link-${_pendingAthlete.id}',
          trainerId: trainerUid,
          athleteId: _pendingAthlete.id,
          status: TrainerLinkStatus.pending,
          requestedAt: now.subtract(const Duration(days: 1)),
        ),
        TrainerLink(
          id: 'link-${_inactiveAthlete.id}',
          trainerId: trainerUid,
          athleteId: _inactiveAthlete.id,
          status: TrainerLinkStatus.active,
          requestedAt: now.subtract(const Duration(days: 60)),
          acceptedAt: now.subtract(const Duration(days: 59)),
        ),
      ];

  /// Public profile per distinct athleteId referenced anywhere in the fake
  /// dataset (links, appointments, payments, inactivos) — otherwise names
  /// render as "…" (unresolved).
  List<UserPublicProfile> get publicProfiles => [
        for (final a in _activeAthletes)
          UserPublicProfile(
            uid: a.id,
            displayName: a.name,
            displayNameLowercase: a.name.toLowerCase(),
          ),
        UserPublicProfile(
          uid: _pendingAthlete.id,
          displayName: _pendingAthlete.name,
          displayNameLowercase: _pendingAthlete.name.toLowerCase(),
        ),
        UserPublicProfile(
          uid: _inactiveAthlete.id,
          displayName: _inactiveAthlete.name,
          displayNameLowercase: _inactiveAthlete.name.toLowerCase(),
        ),
      ];

  // ── Agenda ──────────────────────────────────────────────────────────────
  // 3-4 sessions today at various hours + 2 future sessions (next few days).
  List<Appointment> get appointments {
    final today = DateTime(now.year, now.month, now.day);
    return [
      _appointment(
        id: 'appt-today-1',
        athlete: _activeAthletes[0],
        startsAt: today.add(const Duration(hours: 8)),
      ),
      _appointment(
        id: 'appt-today-2',
        athlete: _activeAthletes[1],
        startsAt: today.add(const Duration(hours: 10, minutes: 30)),
      ),
      _appointment(
        id: 'appt-today-3',
        athlete: _activeAthletes[2],
        startsAt: today.add(const Duration(hours: 17)),
      ),
      _appointment(
        id: 'appt-today-4',
        athlete: _activeAthletes[3],
        startsAt: today.add(const Duration(hours: 19)),
      ),
      _appointment(
        id: 'appt-future-1',
        athlete: _activeAthletes[4],
        startsAt: today.add(const Duration(days: 2, hours: 9)),
      ),
      _appointment(
        id: 'appt-future-2',
        athlete: _activeAthletes[5],
        startsAt: today.add(const Duration(days: 4, hours: 18)),
      ),
    ];
  }

  Appointment _appointment({
    required String id,
    required ({String id, String name}) athlete,
    required DateTime startsAt,
  }) =>
      Appointment(
        id: id,
        trainerId: trainerUid,
        athleteId: athlete.id,
        athleteDisplayName: athlete.name,
        startsAt: startsAt,
        durationMin: 60,
        status: AppointmentStatus.confirmed,
      );

  // ── Pagos ───────────────────────────────────────────────────────────────
  // Ingreso del mes ~$480.000 (paid, paidAt earlier this month) + por cobrar:
  // 2 pending (porVencer) + 1 vencido.
  PagosBuckets get pagosBuckets {
    final monthStart = DateTime.utc(now.year, now.month, 1);

    final pagados = [
      _payment(
        id: 'pay-paid-1',
        athlete: _activeAthletes[0],
        amountArs: 160000,
        status: PaymentStatus.paid,
        createdAt: monthStart.add(const Duration(days: 2)),
        paidAt: monthStart.add(const Duration(days: 2)),
      ),
      _payment(
        id: 'pay-paid-2',
        athlete: _activeAthletes[1],
        amountArs: 160000,
        status: PaymentStatus.paid,
        createdAt: monthStart.add(const Duration(days: 3)),
        paidAt: monthStart.add(const Duration(days: 3)),
      ),
      _payment(
        id: 'pay-paid-3',
        athlete: _activeAthletes[2],
        amountArs: 160000,
        status: PaymentStatus.paid,
        createdAt: monthStart.add(const Duration(days: 5)),
        paidAt: monthStart.add(const Duration(days: 5)),
      ),
    ]; // 3 × 160.000 = 480.000

    final porVencer = [
      _payment(
        id: 'pay-pending-1',
        athlete: _activeAthletes[3],
        amountArs: 150000,
        status: PaymentStatus.pending,
        createdAt: now,
        dueAt: now.add(const Duration(days: 5)),
      ),
      _payment(
        id: 'pay-pending-2',
        athlete: _activeAthletes[4],
        amountArs: 150000,
        status: PaymentStatus.pending,
        createdAt: now,
        dueAt: now.add(const Duration(days: 8)),
      ),
    ];

    final vencidos = [
      _payment(
        id: 'pay-overdue-1',
        athlete: _activeAthletes[5],
        amountArs: 150000,
        status: PaymentStatus.pending,
        createdAt: now.subtract(const Duration(days: 10)),
        dueAt: now.subtract(const Duration(days: 3)),
      ),
    ];

    return PagosBuckets(
      vencidos: vencidos,
      porVencer: porVencer,
      pagados: pagados,
      todos: [...vencidos, ...porVencer, ...pagados],
    );
  }

  Payment _payment({
    required String id,
    required ({String id, String name}) athlete,
    required int amountArs,
    required PaymentStatus status,
    required DateTime createdAt,
    DateTime? paidAt,
    DateTime? dueAt,
  }) =>
      Payment(
        id: id,
        trainerId: trainerUid,
        athleteId: athlete.id,
        amountArs: amountArs,
        concept: 'Mensualidad',
        status: status,
        createdAt: createdAt,
        paidAt: paidAt,
        dueAt: dueAt,
      );
}
