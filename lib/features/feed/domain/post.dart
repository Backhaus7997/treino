// ignore_for_file: invalid_annotation_target — @JsonKey sobre un parámetro
// de factory freezed. json_serializable SÍ lo lee (se ve en post.g.dart);
// el analizador no sabe que freezed lo reenvía. Mismo caso que session.dart.
// ignore: unused_import — Timestamp is used by the generated post.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'post_privacy.dart';
import 'reaction_counts_converter.dart';
import 'reaction_type.dart';
import 'routine_tag.dart';
import 'workout_snapshot.dart';
import 'workout_stats.dart';

part 'post.freezed.dart';
part 'post.g.dart';

@freezed
class Post with _$Post {
  const factory Post({
    required String id,
    required String authorUid,
    // Author display fields denormalized at write time (same ADR as authorGymId).
    // Stale-on-update is accepted — standard social-media pattern.
    // `@Default('Anónimo')` handles legacy Firestore docs that predate this field —
    // json_serializable applies the default when the JSON key is missing.
    @Default('Anónimo') String authorDisplayName,
    required String? authorAvatarUrl,
    required String? authorGymId,
    required String text,
    required RoutineTag? routineTag,
    required PostPrivacy privacy,
    @TimestampConverter() required DateTime createdAt,
    // Contrato de una sola dirección: el cliente lo LEE, nunca lo escribe.
    // `reactionCounts` lo mantiene en exclusiva la Cloud Function con el Admin
    // SDK, y el `allow create` de `posts` no lo lista en su `hasOnly` — con la
    // key presente, TODO create de post era PERMISSION_DENIED.
    //
    // `includeToJson: false` no toca `fromJson`: la lectura sigue poblando el
    // campo desde lo que escribió la función. Abrir la key en el `hasOnly`
    // habría sido el fix tentador y equivocado: dejaría que cualquiera se
    // plante 999 reacciones en su propio post
    // (`functions/src/__tests__/reaction-rules.test.ts`).
    //
    // Lo custodia `test/conformance/post_wire_shape_parity_test.dart`.
    @JsonKey(includeToJson: false)
    @ReactionCountsConverter()
    @Default(<ReactionType, int>{})
    Map<ReactionType, int> reactionCounts,
    // QA-FEED-364/389: workout metrics for the feed card's stats row. Optional
    // (NOT `required`) on purpose — a manual post or a legacy doc simply omits
    // it and the card hides the row. Keeping it non-required also means the
    // other Post(...) call sites (e.g. manual create-post) need no change.
    WorkoutStats? workoutStats,
    // Foto opcional adjuntada desde el composer de share-a-workout. Optional
    // (NOT `required`) igual que workoutStats — posts manuales y legacy la
    // omiten y la card no renderiza imagen; ningún call site existente cambia.
    String? photoUrl,
    // Detalle del entreno para el feed (ejercicios + sets + distribución
    // muscular). Mismo contrato opcional que workoutStats: null en posts
    // manuales/legacy → la card esconde la sección expandible.
    WorkoutSnapshot? workoutSnapshot,
  }) = _Post;

  factory Post.fromJson(Map<String, Object?> json) => _$PostFromJson(json);
}
