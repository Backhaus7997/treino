import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
import 'package:treino/features/profile/profile_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Minimal [AuthNotifier] stub that does not call Firebase.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier({User? user}) : _user = user;
  final User? _user;

  @override
  Future<User?> build() async => _user;

  @override
  Future<void> signOut() async {}
}

UserProfile _testProfile() => UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

Widget _buildScreen({required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: ProfileScreen()),
        routes: [
          GoRoute(
            path: 'friend-requests',
            builder: (_, __) => const Scaffold(body: Text('FRIEND_REQUESTS')),
          ),
          GoRoute(
            path: 'edit-personal',
            builder: (_, __) => const Scaffold(body: Text('EDIT_PERSONAL')),
          ),
          GoRoute(
            path: 'gym',
            builder: (_, __) => const Scaffold(body: Text('GYM')),
          ),
          GoRoute(
            path: 'routines',
            builder: (_, __) => const Scaffold(body: Text('ROUTINES')),
          ),
          GoRoute(
            path: 'settings',
            builder: (_, __) => const Scaffold(body: Text('SETTINGS')),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

List<Override> _baseOverrides() => [
      authNotifierProvider.overrideWith(_StubAuthNotifier.new),
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      userProfileProvider.overrideWith((_) => Stream.value(_testProfile())),
      pendingRequestCountProvider('').overrideWith((_) => 0),
      pendingRequestsStreamProvider('').overrideWith((_) => Stream.value([])),
    ];

void main() {
  group('ProfileScreen — stats row (SCENARIO-316..319)', () {
    // SCENARIO-317: Stats row shows dashes while loading
    testWidgets('SCENARIO-317: loading state shows "--" for all stats',
        (tester) async {
      // Use a Completer that never completes to keep the provider in loading.
      final completer = Completer<UserSessionStats>();

      await tester.pumpWidget(
        _buildScreen(overrides: [
          ..._baseOverrides(),
          userSessionStatsProvider.overrideWith((_) => completer.future),
        ]),
      );

      // Pump once — still in loading state.
      await tester.pump();

      // All three stat labels should be visible.
      expect(find.text('SESIONES'), findsOneWidget);
      expect(find.text('VOLUMEN KG'), findsOneWidget);
      expect(find.text('RACHA'), findsOneWidget);

      // All three values should be '--'.
      expect(find.text('--'), findsNWidgets(3));

      // Complete the future before disposal to avoid pending timer assertion.
      completer.completeError(Exception('cleanup'));
    });

    // SCENARIO-316: Stats row renders with data
    testWidgets('SCENARIO-316: data state renders real stat values',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          ..._baseOverrides(),
          userSessionStatsProvider.overrideWith((_) async =>
              const UserSessionStats(
                  totalSessions: 42, totalVolumeKg: 15000.0, streak: 7)),
        ]),
      );

      await tester.pump(); // provider resolves synchronously in tests

      expect(find.text('SESIONES'), findsOneWidget);
      expect(find.text('42'), findsOneWidget); // totalSessions
      expect(find.text('VOLUMEN KG'), findsOneWidget);
      expect(find.text('15.0k'),
          findsOneWidget); // kFormatMagnitude(15000), never overstates volume
      expect(find.text('RACHA'), findsOneWidget);
      expect(find.text('7'), findsOneWidget); // streak
    });

    // SCENARIO-318: Stats row shows dashes on error
    testWidgets('SCENARIO-318: error state shows "--" for all stats',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          ..._baseOverrides(),
          userSessionStatsProvider.overrideWith((_) async {
            throw Exception('Firestore unavailable');
          }),
        ]),
      );

      await tester.pump(); // let error propagate

      expect(find.text('SESIONES'), findsOneWidget);
      expect(find.text('VOLUMEN KG'), findsOneWidget);
      expect(find.text('RACHA'), findsOneWidget);
      expect(find.text('--'), findsNWidgets(3));
    });

    // SCENARIO-319: PERFIL text (now in ProfileHeader) and sign-out button are always visible
    testWidgets(
        'SCENARIO-319: PERFIL text and sign-out button are always visible',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          ..._baseOverrides(),
          userSessionStatsProvider.overrideWith((_) async =>
              const UserSessionStats(
                  totalSessions: 0, totalVolumeKg: 0, streak: 0)),
        ]),
      );

      await tester.pump();

      // PERFIL heading (from ProfileHeader) and sign-out button must survive
      // regardless of stats.
      expect(find.text('PERFIL'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    // Additional: color semantics — RACHA uses highlight (magenta), SESIONES uses accent
    testWidgets('color semantics: stats row uses AppPalette correctly',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          ..._baseOverrides(),
          userSessionStatsProvider.overrideWith((_) async =>
              const UserSessionStats(
                  totalSessions: 10, totalVolumeKg: 2000, streak: 5)),
        ]),
      );

      await tester.pump();

      // Verify that data state renders — color assertions are via palette
      // constants since building context to call AppPalette.of() is complex.
      // SESIONES + VOLUMEN KG value → mint accent (#2CE5A2)
      // RACHA value → magenta highlight (#C123E0)
      final sesionesValue = tester.widgetList<Text>(find.text('10')).first;
      expect(sesionesValue.style?.color, AppPalette.mintMagenta.accent);

      final rachaValue = tester.widgetList<Text>(find.text('5')).first;
      expect(rachaValue.style?.color, AppPalette.mintMagenta.highlight);
    });

    // SCENARIO-319 extension: sign-out button present even in loading state
    testWidgets('sign-out preserved in loading state', (tester) async {
      final completer = Completer<UserSessionStats>();

      await tester.pumpWidget(
        _buildScreen(overrides: [
          ..._baseOverrides(),
          userSessionStatsProvider.overrideWith((_) => completer.future),
        ]),
      );

      await tester.pump();

      expect(find.text('PERFIL'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);

      completer.completeError(Exception('cleanup'));
    });
  });
}
