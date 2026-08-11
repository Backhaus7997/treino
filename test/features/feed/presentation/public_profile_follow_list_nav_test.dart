import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';
import 'package:treino/features/feed/presentation/public_profile_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/l10n/app_l10n.dart';

const _locale = Locale('es', 'AR');

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

class _StubViewNotifier extends PublicProfileViewNotifier {
  @override
  Future<PublicProfileView> build(String arg) async => const PublicProfileView(
        authorDisplayName: 'Tincho',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: null,
        incomingFollow: null,
        isSelf: false,
        isPublic: true,
      );
}

/// Monta el perfil público bajo [branch] y registra la sub-ruta `follows`
/// igual que el router real, para poder afirmar DÓNDE cae el push.
Widget _wrap({required String branch}) {
  final router = GoRouter(
    initialLocation: '$branch/profile/target',
    routes: [
      GoRoute(
        path: '$branch/profile/:uid',
        builder: (_, state) => Scaffold(
          body: PublicProfileScreen(
            targetUid: state.pathParameters['uid']!,
          ),
        ),
        routes: [
          GoRoute(
            path: 'follows',
            builder: (_, state) => Scaffold(
              body: Text(
                'LISTA ${state.uri.path} tab=${state.uri.queryParameters['tab']}',
              ),
            ),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      authStateChangesProvider
          .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      publicProfileViewProvider.overrideWith(_StubViewNotifier.new),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: _locale,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('tocar SEGUIDORES abre la lista en la pestaña de seguidores',
      (tester) async {
    await tester.pumpWidget(_wrap(branch: '/feed'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SEGUIDORES'));
    await tester.pumpAndSettle();

    expect(
      find.text('LISTA /feed/profile/target/follows tab=followers'),
      findsOneWidget,
    );
  });

  testWidgets('tocar SIGUIENDO abre la lista en la pestaña de seguidos',
      (tester) async {
    await tester.pumpWidget(_wrap(branch: '/feed'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SIGUIENDO'));
    await tester.pumpAndSettle();

    expect(
      find.text('LISTA /feed/profile/target/follows tab=following'),
      findsOneWidget,
    );
  });

  // El perfil público está registrado bajo DOS ramas (/feed y /home) porque
  // _ShellScaffold saca la tab resaltada del prefijo de la ruta. Si el push
  // hardcodeara /feed, abrir la lista desde INICIO saltaría a la tab FEED y el
  // back caería en el lugar equivocado (issue #387).
  testWidgets('desde la rama /home el push se queda en /home', (tester) async {
    await tester.pumpWidget(_wrap(branch: '/home'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SEGUIDORES'));
    await tester.pumpAndSettle();

    expect(
      find.text('LISTA /home/profile/target/follows tab=followers'),
      findsOneWidget,
    );
    expect(find.textContaining('/feed/'), findsNothing);
  });

  testWidgets('volver desde la lista cae en el perfil del que se salió',
      (tester) async {
    await tester.pumpWidget(_wrap(branch: '/feed'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SEGUIDORES'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).pop();
    await tester.pumpAndSettle();

    expect(find.byType(PublicProfileScreen), findsOneWidget);
  });
}
