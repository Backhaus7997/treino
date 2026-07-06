import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';
import 'package:treino/features/feed/presentation/public_profile_screen.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/l10n/app_l10n.dart';

// Stub notifier that resolves/errors based on the injected AsyncValue.
// Must extend PublicProfileViewNotifier so the type is compatible with
// publicProfileViewProvider.overrideWith(() => ...).
class _StubPublicProfileViewNotifier extends PublicProfileViewNotifier {
  _StubPublicProfileViewNotifier(this._value);
  final AsyncValue<PublicProfileView> _value;

  @override
  Future<PublicProfileView> build(String arg) async {
    switch (_value) {
      case AsyncData<PublicProfileView>(:final value):
        return value;
      case AsyncError<PublicProfileView>(:final error):
        throw error;
      default:
        // Loading: never resolve.
        await Completer<void>().future;
        return _value.requireValue;
    }
  }
}

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

PublicProfileView _view({
  String authorDisplayName = 'Tincho',
  String? authorAvatarUrl,
  String? authorGymId,
  bool isSelf = false,
  bool isPublic = true,
  dynamic friendship,
}) =>
    PublicProfileView(
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorGymId: authorGymId,
      friendship: friendship,
      isSelf: isSelf,
      isPublic: isPublic,
    );

Widget _wrap({
  required Widget child,
  required AsyncValue<PublicProfileView> view,
  String viewerUid = 'viewer',
}) {
  final firestore = FakeFirebaseFirestore();
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      authStateChangesProvider
          .overrideWith((_) => Stream.value(_userWithUid(viewerUid))),
      publicProfileViewProvider.overrideWith(
        () => _StubPublicProfileViewNotifier(view),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('PublicProfileScreen', () {
    testWidgets(
        'SCENARIO-207: provides own back affordance, no AppBackground/SafeArea',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      // Screen now wraps its body in a transparent Scaffold + AppBar so it has
      // an on-screen back affordance (mirrors TrainerPublicProfileScreen).
      // That is the screen's Scaffold plus the outer test wrapper's = 2.
      expect(find.byType(Scaffold), findsNWidgets(2));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsNothing); // custom leading, not default
      expect(find.widgetWithIcon(IconButton, TreinoIcon.back), findsOneWidget);
      // Still does NOT introduce its own AppBackground — it composites over the
      // shell's AppBackground via the transparent Scaffold/AppBar. (The AppBar
      // contributes its own internal SafeArea, which is expected and harmless,
      // so we no longer assert SafeArea is absent.)
      expect(find.byType(AppBackground), findsNothing);
    });

    testWidgets(
        'SCENARIO-208: self-visit (isSelf=true) hides SEGUIR and MENSAJE',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isSelf: true)),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PublicProfileFollowButton), findsNothing);
      expect(find.text('MENSAJE'), findsNothing);
      // Hero + stats still render
      expect(find.text('TINCHO'), findsOneWidget);
    });

    testWidgets('SCENARIO-209: non-self renders SEGUIR and MENSAJE buttons',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isSelf: false)),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PublicProfileFollowButton), findsOneWidget);
      expect(find.text('MENSAJE'), findsOneWidget);
    });

    testWidgets('SCENARIO-227: loading state renders CircularProgressIndicator',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: const AsyncLoading(),
      ));
      // Don't settle — stay in loading
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('TINCHO'), findsNothing);
    });

    testWidgets('SCENARIO-228: error state renders graceful fallback text',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncError(Exception('boom'), StackTrace.empty),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar este perfil.'), findsOneWidget);
    });

    testWidgets('SCENARIO-230: RUTINAS PÚBLICAS tab is active by default',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('RUTINAS PÚBLICAS'), findsOneWidget);
      expect(find.text('ACTIVIDAD'), findsOneWidget);
      // Default body copy
      expect(find.text('Aún no hay rutinas públicas.'), findsOneWidget);
    });

    testWidgets('SCENARIO-231/232/233: tapping ACTIVIDAD switches body copy',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      // Initially rutinas
      expect(find.text('Aún no hay rutinas públicas.'), findsOneWidget);
      expect(find.text('Aún no hay actividad reciente.'), findsNothing);

      // Tap ACTIVIDAD pill
      await tester.tap(find.text('ACTIVIDAD'));
      await tester.pumpAndSettle();

      expect(find.text('Aún no hay actividad reciente.'), findsOneWidget);
      expect(find.text('Aún no hay rutinas públicas.'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Privacy gate — Instagram-style. Header + follow button stay visible; the
  // detailed content (stats numbers, tabs) is gated to accepted followers.
  // ---------------------------------------------------------------------------
  group('PublicProfileScreen — privacy gate', () {
    Friendship acceptedFriendship() => Friendship(
          id: 'target_viewer',
          uidA: 'target',
          uidB: 'viewer',
          status: FriendshipStatus.accepted,
          requesterId: 'viewer',
          members: const ['target', 'viewer'],
          createdAt: DateTime.utc(2026, 1, 1),
        );

    testWidgets(
        'private + non-follower → hides tabs and shows "Perfil privado" notice',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isPublic: false, friendship: null)),
      ));
      await tester.pumpAndSettle();

      // Notice is visible.
      expect(find.text('Perfil privado'), findsOneWidget);
      // Tabs are NOT rendered.
      expect(find.text('RUTINAS PÚBLICAS'), findsNothing);
      expect(find.text('ACTIVIDAD'), findsNothing);
      // Follow button IS still rendered (the whole point: allow request).
      expect(find.byType(PublicProfileFollowButton), findsOneWidget);
    });

    testWidgets(
        'private + accepted follower → shows tabs (gate lifted)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(
          _view(isPublic: false, friendship: acceptedFriendship()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Perfil privado'), findsNothing);
      expect(find.text('RUTINAS PÚBLICAS'), findsOneWidget);
      expect(find.text('ACTIVIDAD'), findsOneWidget);
    });

    testWidgets(
        'private + isSelf → shows tabs (owner always sees own profile)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isPublic: false, isSelf: true)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Perfil privado'), findsNothing);
      expect(find.text('RUTINAS PÚBLICAS'), findsOneWidget);
    });

    testWidgets(
        'public + non-follower → shows tabs (no gate)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view(isPublic: true, friendship: null)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Perfil privado'), findsNothing);
      expect(find.text('RUTINAS PÚBLICAS'), findsOneWidget);
    });
  });
}
