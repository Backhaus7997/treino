import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/home/home_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/l10n/app_l10n.dart';

UserProfile _profile() => UserProfile(
      uid: 'u1',
      email: 'u1@test.com',
      displayName: 'Martín',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
    );

Session _session() => Session(
      id: 'stub-session-001',
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 5, 18, 18, 42),
      status: SessionStatus.active,
      dayNumber: 1,
    );

/// Bumping this re-runs [activeSessionForUidProvider], which returns a brand
/// new Dart record each time. Before the fix the listener compared records with
/// `identical`, which is never true across runs, so each re-emit pushed another
/// 'Entrenamiento en curso' dialog on top of the barrier-dismissible one.
void main() {
  testWidgets(
      'resume dialog does not stack when the provider re-emits the same active session',
      (tester) async {
    final bump = StateProvider<int>((ref) => 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => Stream.value(_profile())),
          activeSessionForUidProvider.overrideWith((ref) async {
            ref.watch(bump); // re-run on bump
            return (session: _session(), setLogs: <SetLog>[]);
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entrenamiento en curso'), findsOneWidget);

    // Re-emit the SAME active session (same id, fresh record).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    container.read(bump.notifier).state++;
    await tester.pumpAndSettle();

    // Still exactly one dialog — the id-based guard suppressed the duplicate.
    expect(find.text('Entrenamiento en curso'), findsOneWidget);
  });
}
