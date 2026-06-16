import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
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
}) =>
    PublicProfileView(
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorGymId: authorGymId,
      friendship: null,
      isSelf: isSelf,
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
        'SCENARIO-207: does not introduce Scaffold/AppBackground/SafeArea',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const PublicProfileScreen(targetUid: 'target'),
        view: AsyncData(_view()),
      ));
      await tester.pumpAndSettle();

      // Only 1 Scaffold from the outer test wrapper
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBackground), findsNothing);
      expect(find.byType(SafeArea), findsNothing);
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
}
