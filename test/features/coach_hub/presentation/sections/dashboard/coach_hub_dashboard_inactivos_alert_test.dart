// RED tests for _InactivosSection (real provider) and _AlertBanner (real provider).
//
// SCENARIO-HOY-09A+: inactivos list shows real athlete names, empty state,
//                     and "N de M" disclaimer.
// SCENARIO-HOY-03A+: alert banner composes vencidos + solicitudes + inactivos.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Factories ─────────────────────────────────────────────────────────────────

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Test Trainer',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

TrainerLink _pendingLink(String id) => TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'req-$id',
      status: TrainerLinkStatus.pending,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

// ─── Test helpers ──────────────────────────────────────────────────────────────

/// Wraps [child] in wide (>= 900px) viewport — needs right column rendered.
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

/// Base overrides with stubbed inactivosProvider — safe for all tests.
List<Override> _baseOverrides({
  InactivosResult? inactivosResult,
  List<TrainerLink> links = const [],
  List<Payment> payments = const [],
  Map<String, String> athleteNames = const {},
}) {
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
    totalUnreadCountProvider.overrideWithValue(0),
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream.value(const <Appointment>[]),
    ),
    // Stub inactivosProvider — avoid real Firestore in widget tests.
    inactivosProvider.overrideWith(
      (ref) async => inactivosResult ??
          const InactivosResult(
            inactiveAthleteIds: [],
            totalSharingCount: 0,
          ),
    ),
    // Resolve public profiles for athlete names.
    for (final entry in athleteNames.entries)
      userPublicProfileProvider(entry.key).overrideWith(
        (ref) => Stream.value(_pub(entry.key, entry.value)),
      ),
  ];
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── SCENARIO-HOY-09A+ — Inactivos: shows athlete names ────────────────────

  group('SCENARIO-HOY-09A+ — inactivos section shows inactive athlete names',
      () {
    testWidgets('renders list with inactive athlete names', (tester) async {
      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(
          inactivosResult: const InactivosResult(
            inactiveAthleteIds: ['a1', 'a2'],
            totalSharingCount: 3,
          ),
          athleteNames: {
            'a1': 'Ana López',
            'a2': 'Bruno García',
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('ALUMNOS INACTIVOS'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Ana López'), findsOneWidget);
      expect(find.textContaining('Bruno García'), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-09B — Inactivos: empty state ─────────────────────────────

  group('SCENARIO-HOY-09B — inactivos section shows empty state when none',
      () {
    testWidgets('shows "Sin alumnos inactivos" when all are active',
        (tester) async {
      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(
          inactivosResult: const InactivosResult(
            inactiveAthleteIds: [],
            totalSharingCount: 2,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin alumnos inactivos'), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-09C — Inactivos: "N de M" sharing disclaimer ────────────

  group('SCENARIO-HOY-09C — inactivos section shows "N de M" disclaimer', () {
    testWidgets('shows sharing note when not all athletes share', (tester) async {
      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(
          inactivosResult: const InactivosResult(
            inactiveAthleteIds: ['a1'],
            totalSharingCount: 2,
          ),
          athleteNames: {'a1': 'Ana López'},
        ),
      ));
      await tester.pumpAndSettle();

      // "N de M con datos compartidos" — verify the disclaimer is present.
      expect(find.textContaining('de'), findsAtLeastNWidgets(1));
      expect(find.textContaining('compartidos'), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-03A+ — Alert banner: all clear ───────────────────────────

  group('SCENARIO-HOY-03A+ — alert banner shows "Todo al día" when no alerts',
      () {
    testWidgets('renders "Todo al día" when 0 vencidos + 0 solicitudes + 0 inactivos',
        (tester) async {
      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(
          inactivosResult: const InactivosResult(
            inactiveAthleteIds: [],
            totalSharingCount: 0,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Todo al día'), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-03B — Alert banner: composed summary ────────────────────

  group('SCENARIO-HOY-03B — alert banner shows composed summary', () {
    testWidgets('renders composed summary with non-zero counts', (tester) async {
      final payments = [
        Payment(
          id: 'p1',
          trainerId: 'trainer-1',
          athleteId: 'a1',
          amountArs: 10000,
          concept: 'Mensualidad',
          status: PaymentStatus.pending,
          createdAt: DateTime.utc(2025, 1, 1), // definitely vencido
        ),
      ];
      final links = [
        TrainerLink(
          id: 'req1',
          trainerId: 'trainer-1',
          athleteId: 'b1',
          status: TrainerLinkStatus.pending,
          requestedAt: DateTime.utc(2026, 1, 1),
        ),
      ];

      await tester.pumpWidget(_wrapWide(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(
          payments: payments,
          links: links,
          inactivosResult: const InactivosResult(
            inactiveAthleteIds: ['c1'],
            totalSharingCount: 1,
          ),
          athleteNames: {'a1': 'Alumno A1', 'c1': 'Inactive C1'},
        ),
      ));
      await tester.pumpAndSettle();

      // The composed summary should be present with counts.
      // "1 vencido(s)" or similar substring.
      expect(find.textContaining('vencido'), findsAtLeastNWidgets(1));
    });
  });
}
