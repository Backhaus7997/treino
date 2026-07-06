// Task 6.1 RED — PR2 tests for CoachHubDashboardScreen right column
// Covers SCENARIO-HOY-07A, SCENARIO-HOY-07B, SCENARIO-HOY-08A, SCENARIO-HOY-08B,
// SCENARIO-HOY-09A
//
// These tests verify the real implementation of:
//   - _ProximasSesiones: confirmed && future appointments, sorted, take 4
//   - _Vencimientos7d: vencidos from pagosBucketsProvider + "Ver todos" link
//   - _InactivosSection: placeholder card
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart'
    show TrainerLink;
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Factories ─────────────────────────────────────────────────────────────────

UserProfile _trainerProfile({String displayName = 'Test Trainer'}) =>
    UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: displayName,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Creates a future confirmed appointment starting at [startsAt].
Appointment _confirmedAppointment({
  required String id,
  required String athleteDisplayName,
  required DateTime startsAt,
}) =>
    Appointment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'a1',
      athleteDisplayName: athleteDisplayName,
      startsAt: startsAt,
      durationMin: 60,
      status: AppointmentStatus.confirmed,
    );

UserPublicProfile _pub(String uid) => UserPublicProfile(
      uid: uid,
      displayName: 'Alumno $uid',
      displayNameLowercase: 'alumno $uid',
    );

Payment _pendingPayment({
  required String id,
  required int amountArs,
  required String athleteId,
  DateTime? createdAt,
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      amountArs: amountArs,
      concept: 'Mensualidad',
      status: PaymentStatus.pending,
      // Vencido = createdAt before start of current month
      createdAt: createdAt ?? DateTime.utc(2025, 1, 1),
    );

// ─── Test helpers ──────────────────────────────────────────────────────────────

/// Wraps [child] in a wide (>= 900px) viewport so the two-column layout renders.
Widget _wrapWide(
  Widget child, {
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            height: 900,
            child: child,
          ),
        ),
      ),
    );

/// Base overrides that mirror the PR1 _baseOverrides set exactly so the
/// dashboard renders without provider exceptions.
List<Override> _baseOverrides({
  List<Appointment> appointments = const [],
  List<Payment> payments = const [],
  List<TrainerLink> links = const [],
  int unreadCount = 0,
}) {
  final athleteIds = <String>{
    ...payments.map((p) => p.athleteId),
    ...links.map((l) => l.athleteId),
  };
  return [
    currentUidProvider.overrideWithValue('trainer-1'),
    userProfileProvider.overrideWith(
      (ref) => Stream.value(_trainerProfile()),
    ),
    trainerLinksStreamProvider.overrideWith(
      (ref) => Stream.value(links),
    ),
    pagosBucketsProvider.overrideWith(
      (ref) => AsyncData(PagosBuckets(
        vencidos: payments
            .where(
              (p) =>
                  p.status == PaymentStatus.pending &&
                  p.createdAt.toUtc().isBefore(DateTime.utc(
                      DateTime.now().toUtc().year,
                      DateTime.now().toUtc().month,
                      1)),
            )
            .toList(),
        porVencer:
            payments.where((p) => p.status == PaymentStatus.pending).toList(),
        pagados: payments.where((p) => p.status == PaymentStatus.paid).toList(),
        todos: payments,
      )),
    ),
    totalUnreadCountProvider.overrideWithValue(unreadCount),
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream.value(appointments),
    ),
    // Nombres de alumno para las filas — sino userPublicProfileProvider pega a
    // Firestore (no inicializado en CI) y el build del dashboard explota.
    for (final id in athleteIds)
      userPublicProfileProvider(id).overrideWith(
        (ref) => Stream.value(_pub(id)),
      ),
  ];
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── SCENARIO-HOY-07A — Próximas sesiones shows upcoming confirmed sessions ──

  group(
      'SCENARIO-HOY-07A — próximas sesiones shows upcoming confirmed sessions',
      () {
    testWidgets('shows up to 4 upcoming confirmed sessions sorted by time',
        (tester) async {
      final now = DateTime.now().toUtc();
      final appointments = [
        _confirmedAppointment(
          id: 'a1',
          athleteDisplayName: 'Ana López',
          startsAt: now.add(const Duration(hours: 1)),
        ),
        _confirmedAppointment(
          id: 'a2',
          athleteDisplayName: 'Bruno García',
          startsAt: now.add(const Duration(hours: 2)),
        ),
        _confirmedAppointment(
          id: 'a3',
          athleteDisplayName: 'Carla Rodríguez',
          startsAt: now.add(const Duration(hours: 3)),
        ),
        _confirmedAppointment(
          id: 'a4',
          athleteDisplayName: 'Diego Martínez',
          startsAt: now.add(const Duration(hours: 4)),
        ),
        _confirmedAppointment(
          id: 'a5',
          athleteDisplayName: 'Eva Sánchez',
          startsAt: now.add(const Duration(hours: 5)),
        ),
        _confirmedAppointment(
          id: 'a6',
          athleteDisplayName: 'Fabio Torres',
          startsAt: now.add(const Duration(hours: 6)),
        ),
      ];

      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(appointments: appointments),
      ));
      await tester.pumpAndSettle();

      // Section label visible
      expect(find.textContaining('PRÓXIMAS SESIONES'), findsAtLeastNWidgets(1));

      // First 4 athlete names visible (5th and 6th clipped by take(4))
      expect(find.textContaining('Ana López'), findsOneWidget);
      expect(find.textContaining('Bruno García'), findsOneWidget);
      expect(find.textContaining('Carla Rodríguez'), findsOneWidget);
      expect(find.textContaining('Diego Martínez'), findsOneWidget);
      // The 5th should NOT be rendered
      expect(find.textContaining('Eva Sánchez'), findsNothing);
    });
  });

  // ── SCENARIO-HOY-07C — Próximas sesiones: prefijo de día (no-hoy) ──────────

  group('SCENARIO-HOY-07C — próximas sesiones day prefix', () {
    testWidgets('non-today session shows "mañana" day prefix', (tester) async {
      // +1 día en hora LOCAL → siempre "mañana" sin importar la TZ del CI.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final appointments = [
        _confirmedAppointment(
          id: 't1',
          athleteDisplayName: 'Manana Alumno',
          startsAt: tomorrow,
        ),
      ];

      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(appointments: appointments),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('mañana'), findsOneWidget);
      expect(find.textContaining('Manana Alumno'), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-07B — Próximas sesiones empty state ──────────────────────

  group('SCENARIO-HOY-07B — próximas sesiones empty state', () {
    testWidgets('shows empty state message when no upcoming sessions',
        (tester) async {
      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(appointments: const []),
      ));
      await tester.pumpAndSettle();

      // Empty state message visible
      expect(
        find.textContaining('No hay sesiones próximas'),
        findsOneWidget,
      );
    });
  });

  // ── SCENARIO-HOY-08A — Vencimientos section shows overdue entries ──────────

  group('SCENARIO-HOY-08A — vencimientos section shows overdue entries', () {
    testWidgets('shows vencidos entries and "Ver todos" link', (tester) async {
      final payments = [
        _pendingPayment(
          id: 'p1',
          amountArs: 20000,
          athleteId: 'a1',
          createdAt: DateTime.utc(2025, 1, 1),
        ),
        _pendingPayment(
          id: 'p2',
          amountArs: 15000,
          athleteId: 'a2',
          createdAt: DateTime.utc(2025, 2, 1),
        ),
        _pendingPayment(
          id: 'p3',
          amountArs: 30000,
          athleteId: 'a3',
          createdAt: DateTime.utc(2025, 3, 1),
        ),
        _pendingPayment(
          id: 'p4',
          amountArs: 12000,
          athleteId: 'a4',
          createdAt: DateTime.utc(2025, 4, 1),
        ),
      ];

      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(payments: payments),
      ));
      await tester.pumpAndSettle();

      // Section title visible
      expect(find.textContaining('VENCIMIENTOS'), findsAtLeastNWidgets(1));

      // "Ver todos" link visible
      expect(find.textContaining('Ver todos'), findsAtLeastNWidgets(1));
    });
  });

  // ── SCENARIO-HOY-08B — Vencimientos empty state ───────────────────────────

  group('SCENARIO-HOY-08B — vencimientos empty state', () {
    testWidgets('shows empty state when no overdue payments', (tester) async {
      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(payments: const []),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin pagos vencidos'), findsOneWidget);
    });
  });

  // SCENARIO-HOY-09A (inactivos placeholder) eliminado: _InactivosSection ahora
  // es real (dashboard-hoy-aggregates PR1). El comportamiento real está cubierto
  // en coach_hub_dashboard_inactivos_alert_test.dart (09A+/09B/09C).
}
