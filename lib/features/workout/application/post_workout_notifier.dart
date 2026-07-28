import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../feed/application/feed_screen_providers.dart';
import '../../feed/application/post_providers.dart';
import '../../feed/data/post_photo_upload_service.dart';
import '../../feed/domain/post.dart';
import '../../feed/domain/post_privacy.dart';
import '../../feed/domain/routine_tag.dart';
import '../../feed/domain/workout_snapshot.dart';
import '../../feed/domain/workout_stats.dart';
import '../../profile/application/user_providers.dart';
import '../domain/session.dart';
import 'session_muscle_distribution.dart';
import 'session_providers.dart';

class PostWorkoutNotifier extends AutoDisposeAsyncNotifier<void> {
  /// True mientras hay un [shareWorkout] en vuelo. NO se deriva de
  /// `state.isLoading`: el estado de un AsyncNotifier ya arranca en
  /// `AsyncLoading` mientras `build()` está pendiente, así que ese chequeo
  /// bloquearía el primer share legítimo.
  bool _publishing = false;

  @override
  Future<void> build() async {}

  Future<void> shareWorkout(
    Session session, {
    required String text,
    required int exerciseCount,
    String? localPhotoPath,
  }) async {
    // Guard de reentrancia: el gate del botón depende de que la UI vea el
    // AsyncLoading de abajo, y eso recién ocurre en el próximo frame — dos
    // taps dentro de esa ventana entraban acá dos veces y publicaban DOS
    // posts, cada uno con su propia foto subida.
    if (_publishing) return;
    _publishing = true;
    state = const AsyncLoading();
    try {
      final authUser = await ref.read(authStateChangesProvider.future);
      final profile = await ref.read(userProfileProvider.future);

      final snapshot = await _buildSnapshot(
        uid: authUser!.uid,
        sessionId: session.id,
      );

      final repo = ref.read(postRepositoryProvider);
      // Con foto, el doc id se aloca client-side ANTES de subir para que el
      // path de Storage (postPhotos/{uid}/{postId}.{ext}) referencie al post
      // real. Sin foto, id vacío → lo asigna create(), idéntico a siempre.
      final postId = localPhotoPath == null ? '' : repo.newPostId();
      String? photoUrl;
      if (localPhotoPath != null) {
        photoUrl = await ref
            .read(postPhotoUploadServiceProvider)
            .upload(localPhotoPath, postId: postId);
      }

      final post = Post(
        id: postId,
        authorUid: authUser.uid,
        authorDisplayName: profile?.displayName ?? '',
        authorAvatarUrl: profile?.avatarUrl,
        authorGymId: profile?.gymId,
        text: text,
        routineTag: RoutineTag(
          routineId: session.routineId,
          routineName: session.routineName,
        ),
        privacy: PostPrivacy.friends,
        createdAt: DateTime.now().toUtc(),
        workoutStats: WorkoutStats(
          volumeKg: session.totalVolumeKg,
          durationMin: session.durationMin,
          exerciseCount: exerciseCount,
        ),
        photoUrl: photoUrl,
        workoutSnapshot: snapshot,
      );

      try {
        await repo.create(post);
      } catch (_) {
        // La foto ya subió pero el post no existe — cleanup best-effort del
        // huérfano antes de propagar (mismo patrón que el send de chat media).
        if (photoUrl != null) {
          try {
            await ref
                .read(postPhotoUploadServiceProvider)
                .deleteByDownloadUrl(photoUrl);
          } catch (_) {
            // Nunca enmascarar el error original del create.
          }
        }
        rethrow;
      }

      invalidateAllFeedProviders(ref);

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    } finally {
      // Se libera SIEMPRE, también al fallar: si no, un error dejaba el
      // composer sin poder reintentar hasta recrear el notifier.
      _publishing = false;
    }
  }

  /// Arma el [WorkoutSnapshot] de la sesión leyendo los mismos providers que
  /// ya alimentan el resumen post-entreno (Riverpod dedupea los fetches).
  ///
  /// Best-effort: el snapshot es un ENHANCEMENT del post — si setLogs o la
  /// distribución muscular fallan, el share sigue sin snapshot (mismo
  /// contrato que la sección del resumen, que tampoco bloquea la pantalla).
  Future<WorkoutSnapshot?> _buildSnapshot({
    required String uid,
    required String sessionId,
  }) async {
    final key = (uid: uid, sessionId: sessionId);
    try {
      final summary = await ref.read(sessionSummaryProvider(key).future);
      if (summary.setLogs.isEmpty) return null;

      SessionMuscleDistribution distribution;
      try {
        distribution =
            await ref.read(sessionMuscleDistributionProvider(key).future);
      } catch (_) {
        distribution = emptySessionMuscleDistribution;
      }

      return buildWorkoutSnapshot(
        setLogs: summary.setLogs,
        setsByAxis: distribution.setsByAxis,
        volumeKgByAxis: distribution.volumeKgByAxis,
      );
    } catch (_) {
      return null;
    }
  }
}

final postWorkoutNotifierProvider =
    AsyncNotifierProvider.autoDispose<PostWorkoutNotifier, void>(
  PostWorkoutNotifier.new,
);
