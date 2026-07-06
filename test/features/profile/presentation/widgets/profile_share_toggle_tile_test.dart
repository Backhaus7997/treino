// Widget tests for ProfileShareToggleTile.
//
// Covered:
//   - No active trainer link → tile is disabled + hint about vinculation
//   - Share OFF (no profile_shares doc) + active link → toggle is OFF; tapping calls grant
//   - Share ON (profile_shares doc exists) + active link → toggle is ON; tapping calls revoke

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/locale_resolver.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/profile_share_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/profile_share_repository.dart';
import 'package:treino/features/coach/domain/profile_share.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/widgets/profile_share_toggle_tile.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Spy repository ────────────────────────────────────────────────────────────

class _SpyRepo extends ProfileShareRepository {
  _SpyRepo() : super(firestore: FakeFirebaseFirestore());

  int grantCalls = 0;
  int revokeCalls = 0;

  @override
  Future<void> grant({
    required String athleteId,
    required String trainerId,
    String? phone,
    DateTime? bornAt,
    int? heightCm,
    double? bodyWeightKg,
    dynamic gender,
    dynamic experienceLevel,
    required DateTime updatedAt,
  }) async {
    grantCalls++;
  }

  @override
  Future<void> revoke(String athleteId) async {
    revokeCalls++;
  }

  @override
  Stream<ProfileShare?> watchForAthlete(String athleteId) => Stream.value(null);
}

// ── Test helpers ──────────────────────────────────────────────────────────────

const _myUid = 'athlete-001';
const _trainerId = 'trainer-001';

UserProfile _profile() => UserProfile(
      uid: _myUid,
      email: 'a@test.com',
      displayName: 'Atleta Test',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

TrainerLink _link() => TrainerLink(
      id: 'link-1',
      trainerId: _trainerId,
      athleteId: _myUid,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2024),
    );

Widget _wrap({
  required _SpyRepo spyRepo,
  TrainerLink? activeLink,
  ProfileShare? existingShare,
}) {
  return ProviderScope(
    overrides: [
      // Auth — null user, tile handles empty uid gracefully
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      // Own profile (tile reads uid + profile fields from here)
      userProfileProvider.overrideWith((ref) => Stream.value(_profile())),
      // Active trainer link (null = no link)
      currentAthleteLinkProvider.overrideWith((ref) async => activeLink),
      // Current share state
      profileShareProvider.overrideWith(
        (ref, athleteId) => Stream.value(existingShare),
      ),
      // Repository spy
      profileShareRepositoryProvider.overrideWith((ref) => spyRepo),
    ],
    child: MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      localeResolutionCallback: (l, s) =>
          resolveLocale(l ?? const Locale('es', 'AR'), s),
      theme: AppTheme.dark(),
      home: const Scaffold(body: ProfileShareToggleTile()),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
      'disabled when no active trainer link — shows hint about vinculation',
      (tester) async {
    final spy = _SpyRepo();
    await tester.pumpWidget(_wrap(
      spyRepo: spy,
      activeLink: null,
      existingShare: null,
    ));
    await tester.pumpAndSettle();

    // Title present
    expect(find.text('Compartir mis datos con mi entrenador'), findsOneWidget);

    // Hint about needing a link
    expect(
      find.textContaining('Vinculáte con un entrenador'),
      findsOneWidget,
    );

    // Switch is disabled — value is false
    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.onChanged, isNull);
    expect(switchWidget.value, isFalse);
    expect(spy.grantCalls, 0);
  });

  testWidgets('toggle OFF → tapping calls grant (not revoke)', (tester) async {
    final spy = _SpyRepo();
    await tester.pumpWidget(_wrap(
      spyRepo: spy,
      activeLink: _link(),
      existingShare: null, // no current share → toggle is OFF
    ));
    await tester.pumpAndSettle();

    // Toggle should be OFF
    final switchBefore = tester.widget<Switch>(find.byType(Switch));
    expect(switchBefore.value, isFalse);

    // Tap the switch → should call grant
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(spy.grantCalls, 1);
    expect(spy.revokeCalls, 0);
  });

  testWidgets('toggle ON → tapping calls revoke (not grant)', (tester) async {
    final spy = _SpyRepo();
    final existingShare = ProfileShare(
      trainerId: _trainerId,
      updatedAt: DateTime.utc(2026, 7, 6),
    );

    await tester.pumpWidget(_wrap(
      spyRepo: spy,
      activeLink: _link(),
      existingShare: existingShare, // share exists → toggle is ON
    ));
    await tester.pumpAndSettle();

    // Toggle should be ON
    final switchBefore = tester.widget<Switch>(find.byType(Switch));
    expect(switchBefore.value, isTrue);

    // Tap the switch → should call revoke
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(spy.revokeCalls, 1);
    expect(spy.grantCalls, 0);
  });
}
