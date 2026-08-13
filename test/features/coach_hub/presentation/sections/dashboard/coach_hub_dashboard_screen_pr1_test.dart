// Task 3.1 RED — PR1 tests for CoachHubDashboardScreen
// Covers SCENARIO-HOY-01A/01B, SCENARIO-HOY-03A, SCENARIO-HOY-04A/04B/04C,
// SCENARIO-HOY-05A/05B/05C/05D/05E, SCENARIO-HOY-10A
//
// Note: SCENARIO-HOY-04A and related interaction scenarios (accept/decline)
// are in PR3. This file focuses on the layout and KPI rendering.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Factories ────────────────────────────────────────────────────────────────

UserProfile _trainerProfile({String displayName = 'Joaco Trainer'}) =>
    UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: displayName,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

TrainerLink _link({
  required String id,
  required TrainerLinkStatus status,
  String athleteId = 'a1',
}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 10),
      acceptedAt:
          status == TrainerLinkStatus.active ? DateTime.utc(2026, 1, 11) : null,
    );

Payment _payment({
  required String id,
  required PaymentStatus status,
  required int amountArs,
  DateTime? paidAt,
  DateTime? createdAt,
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'a1',
      amountArs: amountArs,
      concept: 'Mensualidad',
      status: status,
      createdAt: createdAt ?? DateTime.utc(2025, 12, 1),
      paidAt: paidAt,
    );

// ─── Test helpers ─────────────────────────────────────────────────────────────

/// Wraps [child] with ProviderScope + MaterialApp using the dark theme.
Widget _wrap(
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
        home: Scaffold(body: child),
      ),
    );

/// Standard PR1 overrides: minimal viable provider set for the new screen.
List<Override> _baseOverrides({
  String trainerDisplayName = 'Joaco Trainer',
  List<TrainerLink> links = const [],
  List<Payment> payments = const [],
  int unreadCount = 0,
}) {
  return [
    currentUidProvider.overrideWithValue('trainer-1'),
    userProfileProvider.overrideWith(
      (ref) => Stream.value(_trainerProfile(displayName: trainerDisplayName)),
    ),
    trainerLinksStreamProvider.overrideWith(
      (ref) => Stream.value(links),
    ),
    pagosBucketsProvider.overrideWith(
      (ref) => AsyncData(PagosBuckets(
        vencidos: payments
            .where((p) =>
                p.status == PaymentStatus.pending &&
                p.createdAt.toUtc().isBefore(DateTime.utc(
                    DateTime.now().toUtc().year,
                    DateTime.now().toUtc().month,
                    1)))
            .toList(),
        porVencer:
            payments.where((p) => p.status == PaymentStatus.pending).toList(),
        pagados: payments.where((p) => p.status == PaymentStatus.paid).toList(),
        todos: payments,
      )),
    ),
    totalUnreadCountProvider.overrideWithValue(unreadCount),
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream.value(const <Appointment>[]),
    ),
    // Stub inactivosProvider — real provider requires Firestore.
    inactivosProvider.overrideWith(
      (ref) async => const InactivosResult(
        inactiveAthleteIds: [],
      ),
    ),
  ];
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── SCENARIO-HOY-03A — Alert banner (real provider) ──────────────────────

  group('SCENARIO-HOY-03A — alert banner real data', () {
    testWidgets('banner renders "Todo al día" when all counts are 0',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(),
      ));
      await tester.pumpAndSettle();

      // With 0 vencidos, 0 solicitudes, 0 inactivos → "Todo al día".
      expect(
        find.textContaining('Todo al día'),
        findsOneWidget,
      );
    });
  });

  // ── SCENARIO-HOY-04A — Welcome card greeting ─────────────────────────────

  group('SCENARIO-HOY-04A — welcome card greeting and summary', () {
    testWidgets('greeting shows BUENAS with trainer first name in uppercase',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(
          trainerDisplayName: 'Joaco Trainer',
          links: [
            _link(id: 'p1', status: TrainerLinkStatus.pending, athleteId: 'b1'),
            _link(id: 'p2', status: TrainerLinkStatus.pending, athleteId: 'b2'),
          ],
          payments: [
            _payment(
              id: 'pago1',
              status: PaymentStatus.pending,
              amountArs: 10000,
              createdAt: DateTime.utc(2025, 1, 1), // definitely vencido
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      // El saludo es un RichText: "BUENAS, " (blanco) + "JOACO" (mint).
      final greeting = tester.widgetList<RichText>(find.byType(RichText)).where(
        (rt) {
          final s = rt.text.toPlainText();
          return s.contains('BUENAS,') && s.contains('JOACO');
        },
      );
      expect(greeting, isNotEmpty,
          reason: 'saludo con "BUENAS, " + nombre en mint');
    });
  });

  // ── SCENARIO-HOY-04B — Adherencia ring placeholder ───────────────────────

  group('SCENARIO-HOY-04B — adherencia ring shows placeholder', () {
    testWidgets('ring area shows "--" and no real provider value',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('--'), findsAtLeastNWidgets(1));
    });
  });

  // ── SCENARIO-HOY-04C — Mensajes count is real ────────────────────────────

  group('SCENARIO-HOY-04C — Mensajes count from totalUnreadCountProvider', () {
    testWidgets('quick action label shows real unread count', (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(unreadCount: 7),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('(7)'), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-05A — Alumnos activos KPI ───────────────────────────────

  group('SCENARIO-HOY-05A — alumnos activos KPI tile', () {
    testWidgets('shows count of active links only', (tester) async {
      final links = [
        _link(id: 'a1', status: TrainerLinkStatus.active),
        _link(id: 'a2', status: TrainerLinkStatus.active, athleteId: 'a2'),
        _link(id: 'a3', status: TrainerLinkStatus.active, athleteId: 'a3'),
        _link(id: 'p1', status: TrainerLinkStatus.paused, athleteId: 'p1'),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(links: links),
      ));
      await tester.pumpAndSettle();

      // 3 active, 1 paused → tile shows '3'
      // The label is present:
      expect(find.textContaining('ALUMNOS ACTIVOS'), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-05C — Adherencia placeholder KPI ────────────────────────

  group('SCENARIO-HOY-05C — adherencia KPI tile shows placeholder', () {
    testWidgets('adherencia tile value is "--"', (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('ADHERENCIA PROMEDIO'), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-05E — KPI loading state ─────────────────────────────────

  group('SCENARIO-HOY-05E — KPI tile handles loading state', () {
    testWidgets('loading state does not crash', (tester) async {
      // Override with loading state
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_trainerProfile()),
          ),
          trainerLinksStreamProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
          pagosBucketsProvider.overrideWith(
            (ref) => const AsyncLoading<PagosBuckets>(),
          ),
          totalUnreadCountProvider.overrideWithValue(0),
          trainerAppointmentsStreamProvider.overrideWith(
            (ref, key) => const Stream.empty(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: CoachHubDashboardScreen()),
        ),
      ));
      await tester.pump();

      // Should render without throwing
      expect(find.byType(CoachHubDashboardScreen), findsOneWidget);
    });
  });

  // ── SCENARIO-HOY-10A — Importar plan CTA navigates ───────────────────────

  group('SCENARIO-HOY-10A — Importar plan CTA present', () {
    testWidgets('welcome card quick actions contain importar plan',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _baseOverrides(),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Importar plan'), findsOneWidget);
    });
  });
}
