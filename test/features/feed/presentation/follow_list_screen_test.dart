import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/follow_list_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/data/follow_repository.dart';
import 'package:treino/features/feed/presentation/follow_list_screen.dart';
import 'package:treino/features/feed/presentation/widgets/user_search_result_tile.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

/// El árbol y las aserciones tienen que resolver el MISMO locale: sin el
/// `locale:` explícito, MaterialApp cae en inglés y los `find.text` contra
/// strings en castellano no encuentran nada.
const _locale = Locale('es', 'AR');

class _MockUser extends Mock implements User {
  _MockUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
}

/// Repositorio con un stream que el test controla, para simular la
/// re-emisión que hace Firestore (snapshot de cache y después de servidor, o
/// cualquier cambio en vivo del grafo).
class _StreamFollowRepository extends Fake implements FollowRepository {
  _StreamFollowRepository(this.followers);
  final StreamController<List<String>> followers;
  @override
  Stream<List<String>> watchFollowersOf(String uid) => followers.stream;
  @override
  Stream<List<String>> watchFollowingOf(String uid) =>
      const Stream<List<String>>.empty();
}

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
  String branch = '/feed',
  List<Override> overrides = const [],
}) {
  // Se monta con la MISMA forma de ruta que el router real
  // (`{rama}/profile/{uid}/follows`) para que `matchedLocation` sea el de
  // producción. El perfil se registra bajo las dos ramas, como en router.dart.
  final router = GoRouter(
    initialLocation: '$branch/profile/$targetUid/follows',
    routes: [
      for (final rama in const ['/feed', '/home'])
        GoRoute(
          path: '$rama/profile/:uid',
          builder: (_, state) => Scaffold(
              body: Text('Perfil $rama ${state.pathParameters['uid']}')),
          routes: [
            GoRoute(
              path: 'follows',
              builder: (_, state) => Scaffold(
                body: FollowListScreen(
                  targetUid: state.pathParameters['uid']!,
                  initialKind: initialKind,
                ),
              ),
            ),
          ],
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

    expect(find.text('Perfil /feed ana'), findsOneWidget);
  });

  // La navegación de SALIDA tiene que respetar la rama igual que la de
  // ENTRADA. Hardcodear /feed acá reintroduce el mismo issue #387 que el hop
  // anterior evita a propósito: _ShellScaffold saca la tab resaltada del
  // prefijo de la ruta.
  testWidgets('tocar una fila NO saca al usuario de la rama /home',
      (tester) async {
    await tester.pumpWidget(_wrap(
      branch: '/home',
      overrides: _lists(targetUid: 'target', followers: [_profile('ana')]),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(UserSearchResultTile));
    await tester.pumpAndSettle();

    expect(find.text('Perfil /home ana'), findsOneWidget);
    expect(find.text('Perfil /feed ana'), findsNothing);
  });

  // Un stream de Firestore re-emite seguido: snapshot de cache y después de
  // servidor al abrir, y cada vez que alguien sigue o deja de seguir. Si cada
  // re-emisión tira la lista abajo y muestra el spinner, la pantalla parpadea
  // y el scroll se va a cero.
  testWidgets('una re-emisión del stream no reemplaza la lista por el spinner',
      (tester) async {
    final controller = StreamController<List<String>>.broadcast();
    addTearDown(controller.close);
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('userPublicProfiles')
        .doc('ana')
        .set(_profile('ana').toJson());

    await tester.pumpWidget(_wrap(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((ref) => Stream.value(_MockUser('viewer'))),
        followRepositoryProvider
            .overrideWithValue(_StreamFollowRepository(controller)),
      ],
    ));
    controller.add(['ana']);
    await tester.pumpAndSettle();
    expect(find.byType(UserSearchResultTile), findsOneWidget);

    // Segunda emisión con el MISMO contenido. La lista no puede desaparecer
    // en NINGÚN frame del camino.
    controller.add(['ana']);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'apareció el spinner en el frame $i de la re-emisión',
      );
    }
    await tester.pumpAndSettle();
    expect(find.byType(UserSearchResultTile), findsOneWidget);
  });

  // Coherencia con UserSearchResultTile, que es la fila de esta misma
  // pantalla: un perfil sin nombre se muestra como "Anónimo", no como un
  // hueco. Un título vacío se lee como pantalla rota.
  testWidgets('sin displayName el header dice Anónimo, no queda vacío',
      (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: [
        userPublicProfileProvider('target').overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(uid: 'target', displayName: null),
          ),
        ),
        ..._lists(targetUid: 'target', followers: [_profile('ana')]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('ANÓNIMO'), findsOneWidget);
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
