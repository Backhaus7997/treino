import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/application/user_public_profile_providers.dart';
import '../domain/follow.dart';
import '../domain/post.dart';
import '../domain/public_profile_view.dart';
import 'follow_providers.dart';

/// Returns the most-recent `Post` authored by [targetUid], or null if the
/// target has never posted. Used to extract denormalized author fields
/// (displayName, avatarUrl, gymId) for the public profile screen.
///
/// Auth-gated: returns null when unauthenticated (route is auth-gated anyway,
/// but defensive null avoids leaking data on race conditions).
final firstPostByAuthorProvider =
    FutureProvider.family<Post?, String>((ref, targetUid) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) return null;

  final firestore = ref.watch(firestoreProvider);
  final snap = await firestore
      .collection('posts')
      .where('authorUid', isEqualTo: targetUid)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get();

  if (snap.docs.isEmpty) return null;
  // Inject the doc id so seed-written posts (which strip `id` from the body
  // and store it only as the doc ID) deserialize correctly — matches
  // PostRepository._fromDoc. Post.id is required with no default.
  final doc = snap.docs.first;
  return Post.fromJson({...doc.data(), 'id': doc.id});
});

/// AsyncNotifier that composes [userPublicProfileProvider] with las DOS
/// aristas del par en un solo view-model que `PublicProfileScreen` observa.
/// Re-corre `build` en cada emisión upstream — propagación en vivo sin rxdart.
///
/// **Dos listeners, no uno.** Antes acá había un solo `friendshipByPairProvider`
/// porque `friendships` tenía UN documento por par: "yo lo sigo" y "él me
/// sigue" eran el mismo hecho y no se podían distinguir. Con el grafo dirigido
/// son dos documentos con doc id distinto, y cada botón de la pantalla mira el
/// que le corresponde (design §6): el pill de SEGUIR mira la saliente, el botón
/// MENSAJE mira la entrante.
///
/// Sources author identity from `userPublicProfileProvider(targetUid)`.
/// La rama `isSelf` saltea las dos aristas.
/// REQ-FPS-007, ADR-FPS-002, ADR-FPS-003.
class PublicProfileViewNotifier
    extends AutoDisposeFamilyAsyncNotifier<PublicProfileView, String> {
  @override
  Future<PublicProfileView> build(String targetUid) async {
    final auth = await ref.watch(authStateChangesProvider.future);
    if (auth == null) {
      return const PublicProfileView(
        authorDisplayName: 'Anónimo',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: null,
        incomingFollow: null,
        isSelf: false,
      );
    }

    final viewerUid = auth.uid;
    final isSelf = viewerUid == targetUid;

    // ref.watch on a StreamProvider's .future re-runs build on each upstream
    // emission — no ref.listen plumbing needed (ADR-FPS-003).
    final profile =
        await ref.watch(userPublicProfileProvider(targetUid).future);
    // Las dos direcciones se consultan por SEPARADO, por doc id directo. No
    // hay un provider "de la relación" que devuelva un solo objeto: eso
    // volvería a colapsar los dos sentidos, que es justo el bug del modelo
    // viejo.
    final outgoingFollow = isSelf
        ? null
        : await ref.watch(
            followEdgeProvider(Follow.edgeId(viewerUid, targetUid)).future,
          );
    final incomingFollow = isSelf
        ? null
        : await ref.watch(
            followEdgeProvider(Follow.edgeId(targetUid, viewerUid)).future,
          );

    return PublicProfileView(
      authorDisplayName: profile?.displayName ?? 'Anónimo',
      authorAvatarUrl: profile?.avatarUrl,
      authorGymId: profile?.gymId,
      outgoingFollow: outgoingFollow,
      incomingFollow: incomingFollow,
      isSelf: isSelf,
      workoutsCount: profile?.workoutsCount,
      racha: profile?.racha,
      followersCount: profile?.followersCount,
      followingCount: profile?.followingCount,
      // Missing profile → default true (matches UserPublicProfile default);
      // legacy docs without the field decode as public and stay discoverable.
      isPublic: profile?.isProfilePublic ?? true,
    );
  }
}

final publicProfileViewProvider = AsyncNotifierProvider.family
    .autoDispose<PublicProfileViewNotifier, PublicProfileView, String>(
  PublicProfileViewNotifier.new,
);
