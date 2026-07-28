// Regresión (reporte directo de Martín, 2026-07-28): al compartir un entreno
// terminado, el post NO aparecía en el feed AMIGOS hasta reiniciar la app.
//
// Causa raíz: `shareWorkout` invalidaba sólo el WRAPPER (`myFriendsFeedProvider`),
// pero el resultado del query vive en la family `feedForFriendsProvider` (no
// autoDispose). `ref.invalidate` NO cascada a las dependencias (QA-498, #497):
// el wrapper re-corría su body, volvía a watchear la MISMA instancia de la
// family (misma key: mismos amigos) y recibía la lista cacheada — el query a
// Firestore jamás se re-emitía hasta reiniciar la app.
//
// Estos tests usan el PostWorkoutNotifier REAL con un PostRepository fake
// in-memory: la cadena wrapper → family → repo es la de producción.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/post_workout_notifier.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

/// Repo fake con store in-memory: `create` persiste y los feeds leen del
/// store, igual que Firestore. Cuenta las emisiones de `feedForFriends` para
/// poder afirmar que el query se RE-emite (y no que la family sirve caché).
class _InMemoryPostRepository extends Fake implements PostRepository {
  final List<Post> store = [];
  int feedForFriendsCalls = 0;

  @override
  Future<Post> create(Post input) async {
    final post = input.copyWith(id: 'post-${store.length + 1}');
    store.add(post);
    return post;
  }

  @override
  Future<List<Post>> feedForFriends(List<String> friendUids) async {
    feedForFriendsCalls++;
    return store
        .where((p) =>
            p.privacy == PostPrivacy.friends &&
            friendUids.contains(p.authorUid))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

UserProfile _makeProfile() => UserProfile(
      uid: 'u1',
      email: 'martin@test.com',
      displayName: 'Martín',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Session _makeSession() => Session(
      id: 's1',
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 7, 28, 10, 0),
      finishedAt: DateTime.utc(2026, 7, 28, 10, 30),
      totalVolumeKg: 1200.0,
      durationMin: 30,
      status: SessionStatus.finished,
      dayNumber: 1,
      wasFullyCompleted: true,
    );

void main() {
  late _InMemoryPostRepository repo;

  setUp(() {
    repo = _InMemoryPostRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith(
          (ref) => Stream.value(_MockUser(uid: 'u1')),
        ),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_makeProfile()),
        ),
        acceptedFriendsProvider('u1').overrideWith(
          (ref) => Stream.value(const ['u2']),
        ),
        postRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    // Mantiene vivos el feed y el notifier como lo hace la app montada
    // (el feed queda watcheado por la pantalla; el notifier, por el summary).
    container.listen(myFriendsFeedProvider, (_, __) {});
    container.listen(postWorkoutNotifierProvider, (_, __) {});
    return container;
  }

  group('share workout → feed refresh (sin reiniciar la app)', () {
    test(
        'el post del entreno compartido aparece en el feed AMIGOS '
        'inmediatamente después de shareWorkout', () async {
      final container = makeContainer();

      // 1. El feed ya cargó ANTES de compartir (el caso real: el usuario
      //    visitó el feed, entrenó, y comparte al terminar).
      final before = await container.read(myFriendsFeedProvider.future);
      expect(before, isEmpty);

      // 2. Comparte el entreno terminado.
      await container.read(postWorkoutNotifierProvider.notifier).shareWorkout(
            _makeSession(),
            text: '¡Terminé mi entreno! 💪',
            exerciseCount: 3,
          );

      // 3. Sin reiniciar: el feed AMIGOS debe exponer el post nuevo.
      final after = await container.read(myFriendsFeedProvider.future);
      expect(
        after.map((p) => p.text),
        contains('¡Terminé mi entreno! 💪'),
        reason: 'el post compartido debe aparecer sin reiniciar la app',
      );
      expect(after.single.authorUid, 'u1');
      expect(after.single.routineTag?.routineName, 'Push');
    });

    test(
        'compartir re-emite el query del feed AMIGOS aunque la key de la '
        'family no cambie (misma lista de amigos)', () async {
      final container = makeContainer();

      await container.read(myFriendsFeedProvider.future);
      expect(repo.feedForFriendsCalls, 1);

      await container.read(postWorkoutNotifierProvider.notifier).shareWorkout(
            _makeSession(),
            text: 'Entreno compartido',
            exerciseCount: 3,
          );

      await container.read(myFriendsFeedProvider.future);
      expect(
        repo.feedForFriendsCalls,
        greaterThanOrEqualTo(2),
        reason: 'feedForFriendsProvider (family subyacente) debe invalidarse '
            'tras el create — invalidar sólo el wrapper deja el query '
            'cacheado hasta reiniciar la app',
      );
    });
  });
}
