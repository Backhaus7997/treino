import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

// ─── Factories ──────────────────────────────────────────────────────────────

TrainerLink _link({
  required String id,
  required TrainerLinkStatus status,
  String athleteId = 'a1',
  DateTime? pausedAt,
  String? terminationReason,
}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 10),
      acceptedAt: status == TrainerLinkStatus.active ||
              status == TrainerLinkStatus.paused ||
              status == TrainerLinkStatus.terminated
          ? DateTime.utc(2026, 1, 11)
          : null,
      pausedAt: pausedAt,
      terminationReason: terminationReason,
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

// ─── Test helpers ────────────────────────────────────────────────────────────

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
        // Locale explícito → sino el default en test env es en_US y AppL10n
        // resuelve las keys en el ARB inglés (que es scaffold), rompiendo
        // los expect() en español.
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      ),
    );

/// Returns ProviderScope overrides that stub [trainerLinksStreamProvider]
/// with [links] and [userPublicProfileProvider] for each link's athleteId.
List<Override> _stubLinks(
  List<TrainerLink> links,
) {
  return <Override>[
    trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
    userProfileProvider.overrideWith(
      (ref) => Stream.value(_trainerProfile()),
    ),
    for (final l in links)
      userPublicProfileProvider(l.athleteId).overrideWith(
        (ref) => Stream.value(_pub(l.athleteId, 'Atleta ${l.id}')),
      ),
    // Providers que lee la redesign (PR1). Stub vacío: estos tests validan las
    // solicitudes pendientes, no los KPIs.
    currentUidProvider.overrideWithValue('trainer-1'),
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
  ];
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ── Pending solicitudes (accept / decline) ─────────────────────────────────
  // SCEN-CHLM-013..017 (Pausar / Terminar / Reanudar on active/paused cards,
  // filter chips, stream re-renders) REMOVED in PR1 — management moved to
  // /alumnos. Accept/decline solicitudes tests will be added in PR3 (phase 9).

  group('SCEN-HOY-pending — pending solicitudes render', () {
    testWidgets('pending link shows accept and decline buttons',
        (tester) async {
      final links = [
        _link(id: 'r1', status: TrainerLinkStatus.pending),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('accept_r1')), findsOneWidget);
      expect(find.byKey(const Key('decline_r1')), findsOneWidget);
    });

    testWidgets('no pending links → solicitudes section hidden',
        (tester) async {
      final links = [
        _link(id: 'a1', status: TrainerLinkStatus.active),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('accept_a1')), findsNothing);
      expect(find.byKey(const Key('decline_a1')), findsNothing);
    });
  });
}
