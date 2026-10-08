// Regresión: "No pudimos cargar tu feed" justo después de seguir a alguien.
//
// Firestore emite el snapshot OPTIMISTA (con la arista nueva y
// `hasPendingWrites: true`) antes de que el servidor confirme el commit. Si el
// feed arma su `whereIn` con ese uid, las rules (`postFollowerAccepted` lee la
// arista) deniegan la query entera y el error queda cacheado en la family.
//
// El filtro vive en `FollowRepository.watchConfirmedFollowingOf`, así que acá
// se ejerce el repositorio REAL con un Firestore doble que emite snapshots con
// metadata (`fake_cloud_firestore` no modela `hasPendingWrites`, por eso no
// sirve para reproducir esto).
// ignore_for_file: subtype_of_sealed_class
// (mocktail sobre tipos sellados de cloud_firestore: mismo trato que otros
// tests del repo)
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/moderation/application/moderation_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockQuery extends Mock implements Query<Map<String, Object?>> {}

class _MockSnapshot extends Mock
    implements QuerySnapshot<Map<String, Object?>> {}

class _MockDoc extends Mock
    implements QueryDocumentSnapshot<Map<String, Object?>> {}

class _MockMetadata extends Mock implements SnapshotMetadata {}

class _MockUser extends Mock implements User {
  @override
  String get uid => 'u1';
}

QuerySnapshot<Map<String, Object?>> _snap(
  List<String> followees, {
  required bool pending,
}) {
  final meta = _MockMetadata();
  when(() => meta.hasPendingWrites).thenReturn(pending);
  final docs = followees.map((f) {
    final d = _MockDoc();
    when(d.data).thenReturn({'followeeUid': f});
    return d;
  }).toList();
  final s = _MockSnapshot();
  when(() => s.metadata).thenReturn(meta);
  when(() => s.docs).thenReturn(docs);
  return s;
}

/// Como el snapshot de Firestore: quien se suscribe recibe de entrada el último
/// estado (el provider se suscribe recién después de resolver auth).
class _ReplaySubject {
  final _controller =
      StreamController<QuerySnapshot<Map<String, Object?>>>.broadcast();
  QuerySnapshot<Map<String, Object?>>? _last;

  void add(QuerySnapshot<Map<String, Object?>> s) {
    _last = s;
    _controller.add(s);
  }

  Stream<QuerySnapshot<Map<String, Object?>>> get stream => Stream.multi((c) {
        if (_last != null) c.add(_last!);
        final sub = _controller.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });

  void close() => _controller.close();
}

void main() {
  late _ReplaySubject server;
  late bool includedMetadataChanges;
  late ProviderContainer container;
  late List<String> queriedKeys;
  late Set<String> confirmedOnServer;

  setUp(() {
    server = _ReplaySubject();
    includedMetadataChanges = false;
    queriedKeys = [];
    // Lo que el servidor ya ve como seguido: las rules niegan cualquier otro.
    confirmedOnServer = {'u1', 'u2'};

    final firestore = _MockFirestore();
    final collection = _MockCollection();
    final query = _MockQuery();
    when(() => firestore.collection('follows')).thenReturn(collection);
    when(() => collection.where(any(), isEqualTo: any(named: 'isEqualTo')))
        .thenReturn(query);
    when(() => query.where(any(), isEqualTo: any(named: 'isEqualTo')))
        .thenReturn(query);
    when(
      () => query.snapshots(
        includeMetadataChanges: any(named: 'includeMetadataChanges'),
      ),
    ).thenAnswer((inv) {
      includedMetadataChanges =
          inv.namedArguments[#includeMetadataChanges] as bool? ?? false;
      return server.stream;
    });

    container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((ref) => Stream.value(_MockUser())),
        blockedUidsProvider('u1')
            .overrideWith((ref) => Stream.value(const <String>[])),
        feedForFriendsProvider.overrideWith((ref, key) async {
          queriedKeys.add(key);
          final denied =
              key.split(' ').where((u) => !confirmedOnServer.contains(u));
          if (denied.isNotEmpty) {
            // Espeja el rechazo de la query entera por las rules.
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            );
          }
          return const <Post>[];
        }),
      ],
    );
    addTearDown(() {
      container.dispose();
      server.close();
    });
  });

  test(
      'seguir a alguien: el snapshot optimista no llega al feed y nunca hay '
      'error; al confirmar, el feed incluye al nuevo seguido', () async {
    // Mantiene vivo el feed (autoDispose del stream) y registra todo estado.
    final states = <AsyncValue<List<Post>>>[];
    container.listen<AsyncValue<List<Post>>>(
      myFollowingFeedProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );

    // Estado previo confirmado: sigo a u2.
    server.add(_snap(['u2'], pending: false));
    await pumpEventQueue();
    expect(container.read(myFollowingFeedProvider).hasValue, isTrue);
    expect(queriedKeys.last.split(' '), unorderedEquals(['u1', 'u2']));

    // Toco SEGUIR a u3: snapshot optimista (con u3) ANTES del commit.
    server.add(_snap(['u2', 'u3'], pending: true));
    await pumpEventQueue();

    expect(states.any((s) => s.hasError), isFalse,
        reason: 'el optimista no debe armar una query con u3');
    expect(queriedKeys.any((k) => k.contains('u3')), isFalse);

    // El servidor commitea la arista y confirma.
    confirmedOnServer.add('u3');
    server.add(_snap(['u2', 'u3'], pending: false));
    await pumpEventQueue();

    expect(
        states
            .where((s) => s.hasError)
            .map((s) => '${s.error} $queriedKeys')
            .toList(),
        isEmpty);
    final last = container.read(myFollowingFeedProvider);
    expect(last.hasValue, isTrue);
    expect(
      queriedKeys.last.split(' '),
      unorderedEquals(['u1', 'u2', 'u3']),
    );
    expect(includedMetadataChanges, isTrue,
        reason: 'sin includeMetadataChanges la confirmación no emite');
  });

  test('un cambio de metadata con los mismos datos no rearma la key', () async {
    container.listen(followingProvider('u1'), (_, __) {});

    server.add(_snap(['u2'], pending: true));
    server.add(_snap(['u2'], pending: false));
    server.add(_snap(['u2'], pending: false));
    await pumpEventQueue();

    final emitted = <List<String>>[];
    container.listen<AsyncValue<List<String>>>(
      followingProvider('u1'),
      (_, next) => next.whenData(emitted.add),
    );
    server.add(_snap(['u2'], pending: false));
    await pumpEventQueue();

    expect(emitted, isEmpty,
        reason: 'la lista igual a la anterior se deduplica');
    expect(container.read(followingProvider('u1')).value, ['u2']);
  });
}
