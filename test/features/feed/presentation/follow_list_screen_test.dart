import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/features/feed/application/follow_list_providers.dart';
import 'package:treino/features/feed/presentation/follow_list_screen.dart';
import 'package:treino/features/feed/presentation/widgets/user_search_result_tile.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

/// El árbol y las aserciones tienen que resolver el MISMO locale: sin el
/// `locale:` explícito, MaterialApp cae en inglés y los `find.text` contra
/// strings en castellano no encuentran nada.
const _locale = Locale('es', 'AR');

UserPublicProfile _profile(String uid) => UserPublicProfile(
      uid: uid,
      displayName: uid.toUpperCase(),
      displayNameLowercase: uid,
    );

/// Override de una de las dos listas. La otra queda vacía salvo que se pase.
List<Override> _lists({
  required String targetUid,
  List<UserPublicProfile> followers = const [],
  List<UserPublicProfile> following = const [],
}) =>
    [
      followListProvider(followListKey(FollowListKind.followers, targetUid))
          .overrideWith((ref) async => followers),
      followListProvider(followListKey(FollowListKind.following, targetUid))
          .overrideWith((ref) async => following),
    ];

Widget _wrap({
  String targetUid = 'target',
  String? viewerUid = 'viewer',
  FollowListKind initialKind = FollowListKind.followers,
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: '/list',
    routes: [
      GoRoute(
        path: '/list',
        builder: (_, __) => Scaffold(
          body: FollowListScreen(
            targetUid: targetUid,
            initialKind: initialKind,
          ),
        ),
      ),
      GoRoute(
        path: '/feed/profile/:uid',
        builder: (_, state) =>
            Scaffold(body: Text('Perfil ${state.pathParameters['uid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(viewerUid),
      userPublicProfileProvider(targetUid)
          .overrideWith((ref) => Stream.value(_profile(targetUid))),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: _locale,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('pinta una fila por seguidor', (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: _lists(
        targetUid: 'target',
        followers: [_profile('ana'), _profile('beto')],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(UserSearchResultTile), findsNWidgets(2));
    expect(find.text('ANA'), findsOneWidget);
    expect(find.text('BETO'), findsOneWidget);
  });

  testWidgets('arranca en la pestaña que le pasan', (tester) async {
    await tester.pumpWidget(_wrap(
      initialKind: FollowListKind.following,
      overrides: _lists(
        targetUid: 'target',
        followers: [_profile('me-sigue')],
        following: [_profile('lo-sigo')],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('LO-SIGO'), findsOneWidget);
    expect(find.text('ME-SIGUE'), findsNothing);
  });

  // Las dos listas son conjuntos distintos: cambiar de pill tiene que cambiar
  // el contenido, no reordenarlo.
  testWidgets('tocar la otra pill cambia de lista', (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: _lists(
        targetUid: 'target',
        followers: [_profile('me-sigue')],
        following: [_profile('lo-sigo')],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ME-SIGUE'), findsOneWidget);

    final l10n = await AppL10n.delegate.load(_locale);
    await tester.tap(find.text(l10n.followListTabFollowing));
    await tester.pumpAndSettle();

    expect(find.text('LO-SIGO'), findsOneWidget);
    expect(find.text('ME-SIGUE'), findsNothing);
  });

  testWidgets('tocar una fila navega al perfil de esa persona', (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: _lists(targetUid: 'target', followers: [_profile('ana')]),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(UserSearchResultTile));
    await tester.pumpAndSettle();

    expect(find.text('Perfil ana'), findsOneWidget);
  });

  group('estado vacío', () {
    testWidgets('lista ajena: habla en tercera persona', (tester) async {
      await tester.pumpWidget(_wrap(overrides: _lists(targetUid: 'target')));
      await tester.pumpAndSettle();

      final l10n = await AppL10n.delegate.load(_locale);
      expect(find.text(l10n.followListEmptyFollowers), findsOneWidget);
    });

    testWidgets('lista propia: habla en segunda persona', (tester) async {
      await tester.pumpWidget(_wrap(
        targetUid: 'viewer',
        viewerUid: 'viewer',
        overrides: _lists(targetUid: 'viewer'),
      ));
      await tester.pumpAndSettle();

      final l10n = await AppL10n.delegate.load(_locale);
      expect(find.text(l10n.followListEmptyFollowersSelf), findsOneWidget);
    });

    testWidgets('el vacío de SEGUIDOS es un texto distinto al de SEGUIDORES',
        (tester) async {
      await tester.pumpWidget(_wrap(
        initialKind: FollowListKind.following,
        overrides: _lists(targetUid: 'target'),
      ));
      await tester.pumpAndSettle();

      final l10n = await AppL10n.delegate.load(_locale);
      expect(find.text(l10n.followListEmptyFollowing), findsOneWidget);
      expect(find.text(l10n.followListEmptyFollowers), findsNothing);
    });
  });

  testWidgets('el error muestra un mensaje, no una pantalla en blanco',
      (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: [
        followListProvider(followListKey(FollowListKind.followers, 'target'))
            .overrideWith((ref) async => throw Exception('boom')),
        followListProvider(followListKey(FollowListKind.following, 'target'))
            .overrideWith((ref) async => const []),
      ],
    ));
    await tester.pumpAndSettle();

    final l10n = await AppL10n.delegate.load(_locale);
    expect(find.text(l10n.followListLoadError), findsOneWidget);
  });

  // Regla del proyecto: TreinoTappable REEMPLAZA a GestureDetector/InkWell.
  //
  // Se afirma sobre los GestureDetector que NO cuelgan de un TreinoTappable,
  // porque TreinoTappable usa uno internamente y exigir cero sería imposible.
  //
  // Se excluye el subárbol de UserSearchResultTile: ese widget ya usaba
  // GestureDetector crudo antes de esta pantalla y arreglarlo cambiaría
  // también el feedback táctil de la búsqueda de usuarios, que no es este
  // cambio. Queda anotado como deuda.
  testWidgets('el cromo propio de la pantalla no usa GestureDetector crudo',
      (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: _lists(targetUid: 'target', followers: [_profile('ana')]),
    ));
    await tester.pumpAndSettle();

    final enElTile = find
        .descendant(
          of: find.byType(UserSearchResultTile),
          matching: find.byType(GestureDetector),
        )
        .evaluate()
        .toSet();

    final sueltos = find
        .descendant(
          of: find.byType(FollowListScreen),
          matching: find.byType(GestureDetector),
        )
        .evaluate()
        .where((e) => !enElTile.contains(e))
        .where(
          (e) => find
              .ancestor(
                of: find.byWidget(e.widget),
                matching: find.byType(TreinoTappable),
              )
              .evaluate()
              .isEmpty,
        )
        .toList();

    expect(
      sueltos,
      isEmpty,
      reason: 'GestureDetector sueltos: '
          '${sueltos.map((e) => e.widget.runtimeType).toList()}',
    );
  });
}
