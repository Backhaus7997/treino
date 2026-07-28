import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentSnapshot,
        FieldValue,
        FirebaseException,
        FirebaseFirestore;

import '../../profile/domain/experience_level.dart';
import '../domain/routine.dart';
import '../domain/routine_source.dart';
import '../domain/routine_status.dart';
import '../domain/routine_visibility.dart';
import '../domain/template_rating.dart';

class RoutineRepository {
  RoutineRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('routines');

  /// Returns only system-seeded template routines (source == 'system').
  ///
  /// Renamed from [listAll] per REQ-USR-015 / ADR-USR-05. The added
  /// `source == 'system'` filter closes the latent contamination risk: any
  /// future user-created routine accidentally flipped to `visibility=public`
  /// would no longer surface in the Plantillas screen.
  ///
  /// Used by [routinesProvider] (Plantillas section).
  Future<List<Routine>> listSystemTemplates() async {
    final snap = await _collection
        .where('source', isEqualTo: 'system')
        .where('visibility', isEqualTo: 'public')
        .get();
    return snap.docs.map(_fromDoc).whereType<Routine>().toList();
  }

  /// Returns every community-published trainer template — `trainer-template`
  /// docs whose owning trainer flipped `visibility` to `public` via
  /// [publishTemplate].
  ///
  /// Equality-only query, so it rides Firestore's automatic single-field
  /// indexes (no composite index needed); callers decide presentation order.
  /// Used by the athlete Plantillas tab to surface community templates
  /// alongside the system catalogue.
  Future<List<Routine>> listPublishedTemplates() async {
    final snap = await _collection
        .where('source', isEqualTo: 'trainer-template')
        .where('visibility', isEqualTo: 'public')
        .get();
    return snap.docs.map(_fromDoc).whereType<Routine>().toList();
  }

  /// Creates a new routine owned by [uid] (athlete self-authored).
  ///
  /// Enforces defensive invariants client-side before write (Firestore rules
  /// enforce the same constraints server-side):
  /// - [uid] must be non-empty.
  /// - [draft] must not carry `assignedBy` or `assignedTo`.
  ///
  /// Forces `source=user-created`, `createdBy=uid`, `visibility=private`,
  /// `status=active`, and `createdAt=FieldValue.serverTimestamp()`.
  ///
  /// REQ-USR-004, SCENARIO-USR-005..007, ADR-USR-03.
  Future<Routine> createUserOwned({
    required String uid,
    required Routine draft,
  }) async {
    if (uid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'must be non-empty');
    }
    if (draft.assignedBy != null) {
      throw ArgumentError(
        'user-created routines must not carry assignedBy',
      );
    }
    if (draft.assignedTo != null) {
      throw ArgumentError(
        'user-created routines must not carry assignedTo',
      );
    }

    // Strip trainer-only keys before write — the Firestore create rule for
    // user-created routines requires that `assignedBy` and `assignedTo` be
    // ABSENT (not just null). Routine.toJson() emits both as `null` because
    // they're nullable freezed fields, which would cause permission-denied
    // even though the values are null. REQ-USR-004 + the rule check
    // `!('assignedBy' in request.resource.data)`.
    //
    // `visibility` is clamped to {'private','public'} — the athlete can
    // opt-in at create time to share the routine on their public profile.
    // `shared` remains trainer-assigned only, and any other unexpected
    // value is coerced back to `private` (defensive).
    final visibilityStr =
        draft.visibility == RoutineVisibility.public ? 'public' : 'private';
    final json = draft.toJson()
      ..remove('id')
      ..remove('assignedBy')
      ..remove('assignedTo')
      ..['source'] = 'user-created'
      ..['createdBy'] = uid
      ..['visibility'] = visibilityStr
      ..['status'] = 'active'
      ..['createdAt'] = FieldValue.serverTimestamp();

    final ref = await _collection.add(json);
    return draft.copyWith(
      id: ref.id,
      source: RoutineSource.userCreated,
      createdBy: uid,
      visibility: visibilityStr == 'public'
          ? RoutineVisibility.public
          : RoutineVisibility.private,
      status: RoutineStatus.active,
    );
  }

  /// Returns a live stream of the athlete's own active routines, ordered
  /// newest first.
  ///
  /// Returns [Stream.value] of an empty list when [uid] is empty (safe guard
  /// for unauthenticated widget state).
  ///
  /// Requires the composite index on `(createdBy, source, status, createdAt)`
  /// declared in `firestore.indexes.json` (REQ-USR-017 / ADR-USR-03).
  ///
  /// REQ-USR-007, SCENARIO-USR-015, ADR-FRI-013.
  Stream<List<Routine>> listUserCreated(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return _collection
        .where('createdBy', isEqualTo: uid)
        .where('source', isEqualTo: 'user-created')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).whereType<Routine>().toList());
  }

  /// Updates the content of an existing athlete-owned routine.
  ///
  /// Only mutates content fields (name, days, level). The immutable identity
  /// fields (createdBy, createdAt, source, visibility, status) are stripped
  /// from the payload so the Firestore owner-update rule does not see them
  /// change, matching the `affectedKeys()` guard in firestore.rules.
  ///
  /// Enforces defensive invariants client-side before write:
  /// - [uid] must be non-empty.
  /// - [draft.id] must be non-empty.
  /// - [draft.assignedBy] and [draft.assignedTo] must be null.
  ///
  /// REQ-USR-018, ADR-USR-03.
  Future<Routine> updateUserOwned({
    required String uid,
    required Routine draft,
  }) async {
    if (uid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'must be non-empty');
    }
    if (draft.id.isEmpty) {
      throw ArgumentError.value(draft.id, 'draft.id', 'must be non-empty');
    }
    if (draft.assignedBy != null) {
      throw ArgumentError(
        'user-created routines must not carry assignedBy',
      );
    }
    if (draft.assignedTo != null) {
      throw ArgumentError(
        'user-created routines must not carry assignedTo',
      );
    }

    // Build update payload with ONLY the content fields the athlete controls.
    // Omitting createdBy, createdAt, source, status, id, assignedBy, and
    // assignedTo keeps the update within the narrow owner-update Firestore
    // rule.
    //
    // `visibility` IS included in this payload since REQ-USR-012 was
    // reopened to let the athlete flip a routine between `private` and
    // `public` retroactively (Instagram-style). The rule caps the accepted
    // values at `{'private', 'public'}` — `shared` remains trainer-only.
    //
    // ⚠️  COUPLING WARNING — field list below:
    // If you add a field to the Routine model that athletes should be able to
    // edit, add it here AND add it to the hasOnly list in firestore.rules
    // (UPDATE path 2). Omitting it from either side will either silently drop
    // data or cause permission-denied on ALL athlete routine updates.
    final json = <String, Object?>{
      'name': draft.name,
      'level': draft.level.toJson(),
      'days': draft.days.map((d) => d.toJson()).toList(),
      // Periodization: authored week count (mirror in firestore.rules hasOnly).
      'numWeeks': draft.numWeeks,
      // Owner can toggle between private and public — rule enforces the set.
      'visibility': draft.visibility.toJson(),
    };

    await _collection.doc(draft.id).update(json);
    return draft;
  }

  /// Updates the content of an existing trainer-assigned plan.
  ///
  /// Only mutates content fields (name, split, level, days). The immutable
  /// identity fields (assignedBy, assignedTo, source, createdBy, createdAt)
  /// are stripped from the payload so the Firestore trainer-update rule does
  /// not see them change, matching the `affectedKeys()` guard in
  /// firestore.rules.
  ///
  /// Enforces defensive invariants client-side before write:
  /// - [uid] must be non-empty.
  /// - [draft.id] must be non-empty.
  ///
  /// ⚠️  COUPLING WARNING — field list below:
  /// If you add a field to the Routine model that trainers should be able to
  /// edit on assigned plans, add it here AND add it to the hasOnly list in
  /// firestore.rules (trainer-assigned UPDATE path). Omitting it from either
  /// side will either silently drop data or cause permission-denied on ALL
  /// trainer plan updates.
  Future<Routine> updateAssigned({
    required String uid,
    required Routine draft,
  }) async {
    if (uid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'must be non-empty');
    }
    if (draft.id.isEmpty) {
      throw ArgumentError.value(draft.id, 'draft.id', 'must be non-empty');
    }

    // Build update payload with ONLY the content fields the trainer controls.
    // Omitting assignedBy, assignedTo, source, createdBy, createdAt, id,
    // visibility, and status keeps the update within the narrow
    // trainer-update Firestore rule.
    final json = <String, Object?>{
      'name': draft.name,
      'split': draft.split,
      'level': draft.level.toJson(),
      'days': draft.days.map((d) => d.toJson()).toList(),
      // Periodization: authored week count (mirror in firestore.rules hasOnly).
      'numWeeks': draft.numWeeks,
    };

    await _collection.doc(draft.id).update(json);
    return draft;
  }

  /// Updates the content of an existing trainer template.
  ///
  /// Only mutates content fields (name, split, level, days). The immutable
  /// identity fields (assignedBy, source, createdBy, createdAt, assignedTo)
  /// are stripped from the payload so the Firestore trainer-template-update
  /// rule does not see them change, matching the `affectedKeys()` guard in
  /// firestore.rules.
  ///
  /// Enforces defensive invariants client-side before write:
  /// - [uid] must be non-empty.
  /// - [draft.id] must be non-empty.
  ///
  /// ⚠️  COUPLING WARNING — field list below:
  /// If you add a field to the Routine model that trainers should be able to
  /// edit on templates, add it here AND add it to the hasOnly list in
  /// firestore.rules (trainer-template UPDATE path). Omitting it from either
  /// side will either silently drop data or cause permission-denied on ALL
  /// trainer template updates.
  Future<Routine> updateTemplate({
    required String uid,
    required Routine draft,
  }) async {
    if (uid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'must be non-empty');
    }
    if (draft.id.isEmpty) {
      throw ArgumentError.value(draft.id, 'draft.id', 'must be non-empty');
    }

    // Build update payload with ONLY the content fields the trainer controls.
    // Omitting assignedBy, source, createdBy, createdAt, assignedTo, id,
    // visibility, and status keeps the update within the narrow
    // trainer-template-update Firestore rule.
    final json = <String, Object?>{
      'name': draft.name,
      'split': draft.split,
      'level': draft.level.toJson(),
      'days': draft.days.map((d) => d.toJson()).toList(),
      // Periodization: authored week count (mirror in firestore.rules hasOnly).
      'numWeeks': draft.numWeeks,
    };

    await _collection.doc(draft.id).update(json);
    return draft;
  }

  /// Soft-deletes a routine by flipping its `status` to `archived`.
  ///
  /// The document is preserved so that historical workout session references
  /// remain intact (ADR-USR-04). Only the `status` field is mutated,
  /// matching the narrow Firestore update rule (REQ-USR-013).
  ///
  /// REQ-USR-006, SCENARIO-USR-010..011.
  Future<void> archive(String routineId) async {
    await _collection.doc(routineId).update({'status': 'archived'});
  }

  Future<Routine?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    return _fromDoc(snap);
  }

  /// Live stream of a single routine doc by id. Emits a new [Routine] on every
  /// Firestore write, so screens watching it (routine detail) auto-refresh
  /// after an edit — mirroring [listUserCreated]/[watchTemplatesBy]. Resolves
  /// to `null` when the doc does not exist. Works for both public catalogue
  /// plantillas and private trainer-assigned plans, same as [getById].
  Stream<Routine?> watchById(String id) {
    return _collection.doc(id).snapshots().map(_fromDoc);
  }

  /// Same as [getById], but resolves to `null` when the routine is not VISIBLE
  /// to the caller instead of throwing.
  ///
  /// Two Firestore codes both mean "you cannot have this routine", and a caller
  /// that treats the routine as OPTIONAL enrichment should see `null` for both:
  /// - `not-found`: the doc was deleted.
  /// - `permission-denied`: e.g. a `trainer-template` an athlete trained from
  ///   while the trainer had `sharedTemplatesWithAthletes` on, after the trainer
  ///   flipped it off. The old sessions keep referencing that routineId forever.
  ///
  /// Every OTHER [FirebaseException] (`unavailable`, `deadline-exceeded`, …)
  /// RETHROWS, deliberately. A transient network failure must never be mistaken
  /// for "no routine": the insights radars use this for the muscle-group slot
  /// fallback, and silently resolving to `null` there would drop custom-exercise
  /// sets from the radar axes while the header total still counts them — a
  /// silently WRONG chart instead of an honest, retryable error.
  ///
  /// Callers that REQUIRE the routine (plan progress, routine detail) must keep
  /// using [getById], so a genuine backend failure still surfaces to them.
  Future<Routine?> getByIdIfVisible(String id) async {
    try {
      return await getById(id);
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' || e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  /// Returns all plans assigned to [athleteId] by a trainer,
  /// ordered newest first (by `createdAt` DESC).
  ///
  /// Requires a composite index on `assignedTo + source + createdAt`
  /// (declared in `firestore.indexes.json`).
  ///
  /// REQ-COACH-PLANS-001, SCENARIO-432, SCENARIO-433.
  Future<List<Routine>> listAssignedTo(String athleteId) async {
    final snap = await _collection
        .where('assignedTo', isEqualTo: athleteId)
        .where('source', isEqualTo: 'trainer-assigned')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    return snap.docs.map(_fromDoc).whereType<Routine>().toList();
  }

  /// Persists a trainer-assigned plan.
  ///
  /// Validations (client-side):
  /// - `routine.assignedBy` must be non-null and non-empty.
  /// - `routine.assignedTo` must be non-null and non-empty.
  ///
  /// The `id` field is removed from the JSON before calling `.add()` so
  /// Firestore generates the document id. `createdAt` is set to
  /// [FieldValue.serverTimestamp] at write time.
  ///
  /// Returns the saved [Routine] with its Firestore-generated [Routine.id].
  ///
  /// REQ-COACH-PLANS-002, SCENARIO-434, SCENARIO-435.
  Future<Routine> createAssigned(Routine routine) async {
    if (routine.assignedBy == null || routine.assignedBy!.isEmpty) {
      throw ArgumentError.value(
        routine.assignedBy,
        'assignedBy',
        'assignedBy must be a non-empty trainer uid',
      );
    }
    if (routine.assignedTo == null || routine.assignedTo!.isEmpty) {
      throw ArgumentError.value(
        routine.assignedTo,
        'assignedTo',
        'assignedTo must be a non-empty athlete uid',
      );
    }

    final json = routine.toJson()..remove('id');
    json['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _collection.add(json);
    return routine.copyWith(id: ref.id);
  }

  /// Persists a trainer template — a routine the PF owns but hasn't
  /// assigned to any athlete yet. Lives in the same `routines` collection
  /// with `source = 'trainer-template'` and `assignedTo = null`, so
  /// `assignTemplateToAthlete` can later copy it into a regular
  /// `trainer-assigned` doc when the PF picks an alumno for it.
  Future<Routine> createTemplate(Routine routine) async {
    if (routine.assignedBy == null || routine.assignedBy!.isEmpty) {
      throw ArgumentError.value(
        routine.assignedBy,
        'assignedBy',
        'assignedBy must be a non-empty trainer uid',
      );
    }
    if (routine.assignedTo != null && routine.assignedTo!.isNotEmpty) {
      throw ArgumentError.value(
        routine.assignedTo,
        'assignedTo',
        'templates must not have an assignedTo athlete',
      );
    }
    final templateRoutine = routine.copyWith(
      source: RoutineSource.trainerTemplate,
      assignedTo: null,
      visibility: RoutineVisibility.private,
    );
    final json = templateRoutine.toJson()..remove('id');
    json['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _collection.add(json);
    return templateRoutine.copyWith(id: ref.id);
  }

  /// Publishes a trainer template to the community catalogue by flipping its
  /// `visibility` to `public`.
  ///
  /// Single-field update on purpose — it matches the narrow owner-only
  /// Firestore rule (`affectedKeys() == {'visibility'}`), same idiom as
  /// [archive]. Rules enforce that only the owning trainer may flip it and
  /// only on `trainer-template` docs.
  Future<void> publishTemplate(String templateId) =>
      _setTemplateVisibility(templateId, RoutineVisibility.public);

  /// Takes a published template back to `private`.
  ///
  /// Ratings already left by the community are kept in the subcollection, so
  /// re-publishing restores them (and the routine's aggregates) intact.
  Future<void> unpublishTemplate(String templateId) =>
      _setTemplateVisibility(templateId, RoutineVisibility.private);

  Future<void> _setTemplateVisibility(
    String templateId,
    RoutineVisibility visibility,
  ) async {
    if (templateId.isEmpty) {
      throw ArgumentError.value(templateId, 'templateId', 'must be non-empty');
    }
    await _collection.doc(templateId).update({
      'visibility': visibility.toJson(),
    });
  }

  /// Deletes a routine document by [id]. Used by the trainer to remove a
  /// template from their library. The UI only exposes this on the trainer's
  /// own templates; Firestore rules enforce that only the owner
  /// (`assignedBy == request.auth.uid`) may delete.
  Future<void> deleteRoutine(String id) async {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'routine id must be non-empty');
    }
    await _collection.doc(id).delete();
  }

  /// Live stream of the trainer's personal templates ordered newest-first.
  ///
  /// Rules: only the owner (`assignedBy == request.auth.uid`) can read
  /// templates. Composite index on `assignedBy + source + createdAt` is
  /// declared alongside the existing `assignedTo` index.
  Stream<List<Routine>> watchTemplatesBy(String trainerId) {
    return _collection
        .where('assignedBy', isEqualTo: trainerId)
        .where('source', isEqualTo: 'trainer-template')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(_fromDoc).whereType<Routine>().toList());
  }

  /// Copies an existing template into a brand-new trainer-assigned routine
  /// for [athleteId]. The template itself is left untouched so it can be
  /// reused for other athletes. Returns the freshly created assigned routine.
  Future<Routine> assignTemplateToAthlete({
    required Routine template,
    required String athleteId,
  }) async {
    if (template.source != RoutineSource.trainerTemplate) {
      throw ArgumentError.value(
        template.source,
        'template.source',
        'only trainer templates can be assigned via this method',
      );
    }
    if (template.assignedBy == null || template.assignedBy!.isEmpty) {
      throw ArgumentError.value(
        template.assignedBy,
        'template.assignedBy',
        'template must carry the trainer uid',
      );
    }
    final assigned = template.copyWith(
      id: '',
      source: RoutineSource.trainerAssigned,
      assignedTo: athleteId,
      visibility: RoutineVisibility.private,
    );
    return createAssigned(assigned);
  }

  // ── Community ratings on published templates (Fase W3) ────────────────────

  CollectionReference<Map<String, Object?>> _ratingsOf(String routineId) =>
      _collection.doc(routineId).collection('ratings');

  /// Writes (or overwrites) [rating] at its deterministic doc id — the
  /// rater's uid — so each user holds exactly ONE rating per template. Set
  /// without merge so stale fields from a previous version never survive,
  /// mirroring `ReviewRepository.upsert` semantics.
  ///
  /// Client-side guards mirror the Firestore rules (rating 1..5, comment
  /// ≤500). The rules additionally require the parent to be a published
  /// `trainer-template` NOT owned by the rater — the author cannot rate
  /// their own work.
  Future<void> upsertTemplateRating({
    required String routineId,
    required TemplateRating rating,
  }) async {
    if (routineId.isEmpty) {
      throw ArgumentError.value(routineId, 'routineId', 'must be non-empty');
    }
    if (rating.userId.isEmpty) {
      throw ArgumentError.value(
        rating.userId,
        'rating.userId',
        'must be non-empty',
      );
    }
    if (rating.rating < 1 || rating.rating > 5) {
      throw ArgumentError.value(
        rating.rating,
        'rating.rating',
        'must be within 1..5',
      );
    }
    final comment = rating.comment;
    if (comment != null && comment.length > 500) {
      throw ArgumentError.value(
        comment,
        'rating.comment',
        'must be at most 500 characters',
      );
    }
    await _ratingsOf(routineId).doc(rating.userId).set(rating.toJson());
  }

  /// Live stream of every rating left on a template, newest first.
  ///
  /// Single orderBy on a subcollection field — covered by Firestore's
  /// automatic single-field index, no composite needed. The doc id is
  /// injected as `userId` so the id stays authoritative even for docs whose
  /// body drifted (mirrors [_fromDoc]).
  Stream<List<TemplateRating>> watchTemplateRatings(String routineId) {
    return _ratingsOf(routineId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => [
            for (final d in s.docs)
              TemplateRating.fromJson({...d.data(), 'userId': d.id}),
          ],
        );
  }

  /// Live stream of the caller's own rating on a template — `null` while the
  /// user hasn't rated it yet. Drives the editable "my rating" input in the
  /// published-template detail.
  Stream<TemplateRating?> watchMyTemplateRating({
    required String routineId,
    required String userId,
  }) {
    return _ratingsOf(routineId).doc(userId).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return TemplateRating.fromJson({...data, 'userId': snap.id});
    });
  }

  /// Deserializes a Firestore doc into a [Routine], injecting the doc id.
  ///
  /// Trainer-assigned routines are written via `.add()` and do NOT carry an
  /// `id` field inside their data. Seeded plantillas DO have an `id` field
  /// (set explicitly by the seed script). Injecting `snap.id` unconditionally
  /// handles both cases: it overrides the existing value for seeds (same id)
  /// and supplies the missing field for trainer-assigned docs.
  Routine? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Routine.fromJson({...data, 'id': snap.id});
  }
}
