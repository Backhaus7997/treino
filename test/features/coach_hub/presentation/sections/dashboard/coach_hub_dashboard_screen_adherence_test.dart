// RED → GREEN tests for PR2 adherencia ring + KPI tile.
//
// Covers:
//   SCENARIO-ADH-RING-01: ring renders "82%" given stubbed provider = 82.0.
//   SCENARIO-ADH-RING-02: ring renders "--" when provider returns null.
//   SCENARIO-ADH-KPI-01:  KPI tile value shows "82%" given stubbed 82.0.
//   SCENARIO-ADH-KPI-02:  KPI tile value shows "--" when provider returns null.
//   REGRESSION-EXISTING:  PR1 + PR2 tests still pass with aggregateAdherenceProvider stubbed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
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
      displayName: 'Coach Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

// ─── Test helper ───────────────────────────────────────────────────────────────

/// Wraps [child] in a standard test harness. Uses a narrow viewport (no wide
/// two-column layout needed; ring is in WelcomeCard which renders in both).
Widget _wrap(
  Widget child, {
  required List<Override> overrides,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      ),
    );

/// Base set of overrides to render the dashboard without Firestore calls.
/// [adherenceValue] is stubbed into [aggregateAdherenceProvider].
List<Override> _overrides({double? adherenceValue}) => [
      currentUidProvider.overrideWithValue('trainer-1'),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(_trainerProfile()),
      ),
      trainerLinksStreamProvider.overrideWith(
        (ref) => Stream.value(const <TrainerLink>[]),
      ),
      pagosBucketsProvider.overrideWith(
        (ref) => const AsyncData(PagosBuckets(
          vencidos: [],
          porVencer: [],
          pagados: [],
          todos: [],
        )),
      ),
      totalUnreadCountProvider.overrideWithValue(0),
      trainerAppointmentsStreamProvider.overrideWith(
        (ref, key) => Stream.value(const <Appointment>[]),
      ),
      inactivosProvider.overrideWith(
        (ref) async => const InactivosResult(
          inactiveAthleteIds: [],
          totalSharingCount: 0,
        ),
      ),
      aggregateAdherenceProvider.overrideWith(
        (ref) async => adherenceValue,
      ),
    ];

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // SCENARIO-ADH-RING-01: ring renders formatted % value when data is available.
  group('SCENARIO-ADH-RING-01 — adherencia ring renders real value', () {
    testWidgets('ring shows "82%" when aggregateAdherenceProvider = 82.0',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _overrides(adherenceValue: 82.0),
      ));
      await tester.pumpAndSettle();

      // The ring text should show 82%.
      expect(find.text('82%'), findsWidgets);
    });
  });

  // SCENARIO-ADH-RING-02: ring renders "--" when provider returns null.
  group('SCENARIO-ADH-RING-02 — adherencia ring shows "--" when null', () {
    testWidgets('ring shows "--" when aggregateAdherenceProvider = null',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _overrides(adherenceValue: null),
      ));
      await tester.pumpAndSettle();

      // "--" is displayed in both ring and KPI tile.
      expect(find.text('--'), findsWidgets);
    });
  });

  // SCENARIO-ADH-KPI-01: KPI tile value shows formatted % when data available.
  group('SCENARIO-ADH-KPI-01 — KPI adherencia tile shows real value', () {
    testWidgets('KPI tile for adherencia shows "82%" when provider = 82.0',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _overrides(adherenceValue: 82.0),
      ));
      await tester.pumpAndSettle();

      // The KPI label should exist.
      expect(find.textContaining('Adherencia promedio'), findsOneWidget);
      // The value tile should show 82%.
      expect(find.text('82%'), findsWidgets);
    });
  });

  // SCENARIO-ADH-KPI-02: KPI tile value shows "--" when null.
  group('SCENARIO-ADH-KPI-02 — KPI adherencia tile shows "--" when null', () {
    testWidgets('KPI tile shows "--" when provider = null', (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _overrides(adherenceValue: null),
      ));
      await tester.pumpAndSettle();

      // Label present.
      expect(find.textContaining('Adherencia promedio'), findsOneWidget);
      // Value is "--" (same placeholder key as before for null).
      expect(find.text('--'), findsWidgets);
    });
  });

  // REGRESSION: dashboard renders without exceptions when no fan-out providers.
  group('REGRESSION — dashboard renders without crashing with empty links', () {
    testWidgets(
        'empty links produce null adherencia without hanging pumpAndSettle',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _overrides(adherenceValue: null),
      ));
      // Must resolve synchronously — pumpAndSettle must not timeout.
      await tester.pumpAndSettle();

      expect(find.byType(CoachHubDashboardScreen), findsOneWidget);
    });
  });
}
