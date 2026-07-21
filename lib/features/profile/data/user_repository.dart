import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore, SetOptions, Timestamp;

import '../../gyms/data/gym_repository.dart';
import '../../gyms/domain/gym.dart' show kNoGymId;
import '../domain/user_profile.dart';
import '../domain/user_role.dart';

class UserRepository {
  UserRepository({
    required FirebaseFirestore firestore,
    GymRepository? gyms,
  })  : _firestore = firestore,
        _gyms = gyms ?? GymRepository(firestore: firestore);

  final FirebaseFirestore _firestore;

  // gyms-foundation Phase 3: resolves the composed brand-branch display name
  // when `update()` receives a new `gymId`, so `gymName` can be dual-written
  // into userPublicProfiles (mirrors `CheckIn.gymName`). Defaults to a
  // firestore-backed instance so existing call sites that only pass
  // `firestore:` keep working unchanged.
  final GymRepository _gyms;

  // Fields that must never be mutated by client code (mirrors firestore.rules).
  static const _immutableFields = {'uid', 'role', 'email', 'createdAt'};

  // Fields that, when present in an update partial, must be propagated to the
  // userPublicProfiles document.
  static const _publicFields = {'displayName', 'avatarUrl', 'gymId'};

  // Fields that, when present in an update partial, trigger a dual-write to
  // the trainerPublicProfiles document. TRAINER-SPECIFIC ONLY.
  //
  // Originally (PR #58, coach-discovery-infra) this set included `displayName`
  // and `avatarUrl` so trainer profile changes would propagate to the
  // discovery card. The unintended consequence: ANY athlete completing
  // ProfileSetup (which sends `displayName`) triggered a batch write to
  // trainerPublicProfiles — denied by firestore.rules → atomic rollback →
  // users/{uid} never received the form values → auth_redirect looped back to
  // /profile-setup forever. Discovered 2026-05-21 during wire-real-stats PR#3
  // smoke when creating a second test account.
  //
  // Approach E (ADR-TPO-001): uid is now threaded into the trainer subset so
  // the Firestore create rule (request.resource.data.uid == uid) passes on the
  // first-ever trainer dual-write. SetOptions(merge:true) makes re-writing uid
  // on existing docs a no-op.
  static const _trainerPublicFields = {
    'trainerBio',
    'trainerSpecialty',
    'trainerGeohash', // DEPRECATED — backward compat
    'trainerLatitude', // DEPRECATED
    'trainerLongitude', // DEPRECATED
    'trainerMonthlyRate',
    'paymentAlias',
    // Multi-location (Fase 6 Etapa 0)
    'trainerLocations',
    'trainerGeohashes',
    'trainerOffersOnline',
    // ADR-RV-005: CF-write-only — do not add averageRating or reviewCount here.
    // Those fields are written exclusively by the reviewAggregate Cloud Function
    // and must never be propagated by client dual-write.
  };

  CollectionReference<Map<String, Object?>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, Object?>> get _userPublicProfiles =>
      _firestore.collection('userPublicProfiles');

  CollectionReference<Map<String, Object?>> get _trainerPublicProfiles =>
      _firestore.collection('trainerPublicProfiles');

  // ---------------------------------------------------------------------------
  // Private helpers — REQ-UPP-002 / ADR-UPP-11
  // Callers MUST NOT pass displayNameLowercase — it is always derived here.
  // ---------------------------------------------------------------------------

  /// Builds the full public subset from a [UserProfile], deriving
  /// `displayNameLowercase` automatically.
  Map<String, Object?> _publicSubsetFromProfile(UserProfile profile) {
    return {
      'uid': profile.uid,
      'displayName': profile.displayName,
      'displayNameLowercase': profile.displayName?.trim().toLowerCase(),
      'avatarUrl': profile.avatarUrl,
      'gymId': profile.gymId,
    };
  }

  /// Builds a partial public update map from a raw update [partial], deriving
  /// `displayNameLowercase` when `displayName` is present. Returns `null` when
  /// no public-relevant fields (`displayName`, `avatarUrl`, `gymId`) are in
  /// [partial] — callers must skip the public write in that case.
  ///
  /// `uid` is always folded in so the write satisfies the userPublicProfiles
  /// CREATE rule (`request.resource.data.uid == uid`) on a FIRST-EVER write.
  /// `createIfAbsent` only backfills the public doc when `users/{uid}` is also
  /// absent, so accounts whose `users` doc predates the dual-write never got a
  /// public doc — their ProfileSetup submit hit a merge-as-create on
  /// userPublicProfiles and was denied → permission-denied → batch rollback →
  /// the athlete was stranded on the onboarding screen. SetOptions(merge:true)
  /// makes re-writing uid on an existing doc a no-op. Mirrors the same fix
  /// already applied to [_trainerPublicSubsetFromPartial] (ADR-TPO-001).
  ///
  /// gyms-foundation Phase 3: when [partial] carries a new `gymId`, also
  /// resolves and writes the composed brand-branch `gymName` (mirrors
  /// `CheckIn.gymName`). This is the ONLY async step in the public subset
  /// build — `null`/[kNoGymId]/unknown ids all resolve to `gymName: null`
  /// without throwing, so a stale or bad id never blocks the batch write.
  Future<Map<String, Object?>?> _publicSubsetFromPartial(
    Map<String, Object?> partial, {
    required String uid,
  }) async {
    final hasPublicField = partial.keys.any((k) => _publicFields.contains(k));
    if (!hasPublicField) return null;

    final result = <String, Object?>{};
    if (partial.containsKey('displayName')) {
      final name = partial['displayName'] as String?;
      result['displayName'] = name;
      result['displayNameLowercase'] = name?.trim().toLowerCase();
    }
    if (partial.containsKey('avatarUrl')) {
      result['avatarUrl'] = partial['avatarUrl'];
    }
    if (partial.containsKey('gymId')) {
      final gymId = partial['gymId'] as String?;
      result['gymId'] = gymId;
      result['gymName'] = await _resolveGymName(gymId);
    }
    // Always include uid — required by the create rule on the first write.
    result['uid'] = uid;
    return result;
  }

  /// Resolves the composed brand-branch display name for [gymId].
  ///
  /// - `null` or [kNoGymId] → `null`, no lookup attempted.
  /// - Unknown/unresolvable id → `null`, logged, never throws — a stale or
  ///   deleted gym doc must not abort the whole `update()` batch.
  Future<String?> _resolveGymName(String? gymId) async {
    if (gymId == null || gymId == kNoGymId) return null;
    try {
      final gym = await _gyms.getById(gymId);
      return gym?.name;
    } catch (e, st) {
      developer.log(
        'UserRepository: failed to resolve gymName for gymId=$gymId',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Builds a partial trainer-public update map from a raw update [partial].
  ///
  /// Returns `null` when no trainer-specific field is in [partial] — callers
  /// must skip the trainerPublicProfiles write in that case. See the comment
  /// on [_trainerPublicFields] for the rationale (athlete signup regression
  /// from PR #58).
  ///
  /// When a trainer-specific field IS present, `displayName` and `avatarUrl`
  /// are still folded into the subset body if also present in [partial], so a
  /// trainer save that bundles identity + trainer fields keeps the discovery
  /// card in sync. `displayNameLowercase` is always derived when `displayName`
  /// is present.
  ///
  /// REQ-COACH-DISC-DUAL-001.
  Map<String, Object?>? _trainerPublicSubsetFromPartial(
    Map<String, Object?> partial, {
    required String uid,
  }) {
    final hasTrainerField =
        partial.keys.any((k) => _trainerPublicFields.contains(k));
    if (!hasTrainerField) return null;

    final result = <String, Object?>{};
    if (partial.containsKey('displayName')) {
      final name = partial['displayName'] as String?;
      result['displayName'] = name;
      result['displayNameLowercase'] = name?.trim().toLowerCase();
    }
    if (partial.containsKey('avatarUrl')) {
      result['avatarUrl'] = partial['avatarUrl'];
    }
    if (partial.containsKey('trainerBio')) {
      result['trainerBio'] = partial['trainerBio'];
    }
    if (partial.containsKey('trainerSpecialty')) {
      result['trainerSpecialty'] = partial['trainerSpecialty'];
    }
    if (partial.containsKey('trainerGeohash')) {
      result['trainerGeohash'] = partial['trainerGeohash'];
    }
    if (partial.containsKey('trainerLatitude')) {
      result['trainerLatitude'] = partial['trainerLatitude'];
    }
    if (partial.containsKey('trainerLongitude')) {
      result['trainerLongitude'] = partial['trainerLongitude'];
    }
    if (partial.containsKey('trainerMonthlyRate')) {
      result['trainerMonthlyRate'] = partial['trainerMonthlyRate'];
    }
    if (partial.containsKey('paymentAlias')) {
      result['paymentAlias'] = partial['paymentAlias'];
    }
    // ── Multi-location (Fase 6 Etapa 0) ──────────────────────────────────
    if (partial.containsKey('trainerLocations')) {
      result['trainerLocations'] = partial['trainerLocations'];
    }
    if (partial.containsKey('trainerGeohashes')) {
      result['trainerGeohashes'] = partial['trainerGeohashes'];
    }
    if (partial.containsKey('trainerOffersOnline')) {
      result['trainerOffersOnline'] = partial['trainerOffersOnline'];
    }
    // ADR-TPO-001: include uid so the Firestore create rule passes on
    // the first-ever write. SetOptions(merge:true) makes this idempotent.
    result['uid'] = uid;
    return result;
  }

  /// Valida que el partial NO deje al PF en estado inválido. Combinación
  /// `trainerLocations vacío + trainerOffersOnline:false` significa "no
  /// trabaja en ningún lado" — no tiene sentido + rompe discovery.
  ///
  /// Solo aplica cuando AMBOS campos están en el partial (un update parcial
  /// que solo toca uno no puede saber el estado final sin un get previo;
  /// asumimos que el caller maneja el estado consistente).
  static void _assertTrainerLocationStateIsValid(
    Map<String, Object?> partial,
  ) {
    final hasLocations = partial.containsKey('trainerLocations');
    final hasOnline = partial.containsKey('trainerOffersOnline');
    if (!hasLocations || !hasOnline) return;
    final locations = partial['trainerLocations'] as List?;
    final online = partial['trainerOffersOnline'] as bool?;
    final isEmpty = locations == null || locations.isEmpty;
    if (isEmpty && (online == false || online == null)) {
      throw ArgumentError(
        'Un PF no puede tener cero ubicaciones físicas Y offersOnline:false. '
        'Activá clases virtuales o agregá al menos una ubicación.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Creates the `users/{uid}` doc if missing, with `displayName: null`.
  /// Atomically also creates `userPublicProfiles/{uid}` in the same batch.
  /// REQ-UPP-009.
  ///
  /// [termsAcceptedAt] (QA-AUTH-001, issue #434): only the email signup flow
  /// passes this — the checkbox gate lives in `register_screen.dart`, and by
  /// the time `AuthService.signUpWithEmail` reaches this call the user has
  /// already accepted. `null` leaves the field unset, matching a legacy
  /// pre-feature account.
  Future<UserProfile> getOrCreate({
    required String uid,
    required String email,
    DateTime? termsAcceptedAt,
  }) async {
    final existing = await get(uid);
    if (existing != null) return existing;
    final now = DateTime.now().toUtc();
    final profile = UserProfile(
      uid: uid,
      email: email,
      displayName: null,
      role: UserRole.athlete,
      createdAt: now,
      updatedAt: now,
      termsAcceptedAt: termsAcceptedAt,
    );

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), profile.toJson());
    batch.set(
      _userPublicProfiles.doc(uid),
      _publicSubsetFromProfile(profile),
      SetOptions(merge: true),
    );
    await batch.commit();

    return profile;
  }

  /// Best-effort backfill on sign-in. Creates the doc with `displayName: null`
  /// and atomically also creates/updates `userPublicProfiles/{uid}`.
  /// REQ-UPP-010.
  Future<void> createIfAbsent({
    required String uid,
    required String email,
  }) async {
    final snap = await _users.doc(uid).get();
    if (snap.exists) return;
    final now = DateTime.now().toUtc();
    final profile = UserProfile(
      uid: uid,
      email: email,
      displayName: null,
      role: UserRole.athlete,
      createdAt: now,
      updatedAt: now,
    );

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), profile.toJson(), SetOptions(merge: true));
    batch.set(
      _userPublicProfiles.doc(uid),
      _publicSubsetFromProfile(profile),
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<UserProfile?> get(String uid) async {
    final snap = await _users.doc(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return UserProfile.fromJson(data);
  }

  /// Partial update. Immutable fields are filtered out defensively.
  /// `updatedAt` is always overwritten — callers do not set it.
  ///
  /// Dual-write strategy (atomic WriteBatch):
  ///   - `users/{uid}` — always written.
  ///   - `userPublicProfiles/{uid}` — written when partial contains any of
  ///     `displayName`, `avatarUrl`, `gymId`. REQ-UPP-011, REQ-UPP-012.
  ///   - `trainerPublicProfiles/{uid}` — written when partial contains any
  ///     trainer-specific field (see [_trainerPublicFields]).
  ///     REQ-COACH-DISC-DUAL-001.
  ///
  /// All three writes are in a single batch.commit() — no partial state.
  Future<void> update(String uid, Map<String, Object?> partial) async {
    _assertTrainerLocationStateIsValid(partial);
    final sanitized = Map<String, Object?>.fromEntries(
      partial.entries.where((e) => !_immutableFields.contains(e.key)),
    )..['updatedAt'] = Timestamp.fromDate(DateTime.now().toUtc());

    final publicSubset = await _publicSubsetFromPartial(partial, uid: uid);
    final trainerPublicSubset =
        _trainerPublicSubsetFromPartial(partial, uid: uid);

    if (publicSubset == null && trainerPublicSubset == null) {
      // No public-relevant fields — single write to users only.
      await _users.doc(uid).set(sanitized, SetOptions(merge: true));
      return;
    }

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), sanitized, SetOptions(merge: true));

    if (publicSubset != null) {
      batch.set(
        _userPublicProfiles.doc(uid),
        publicSubset,
        SetOptions(merge: true),
      );
    }

    if (trainerPublicSubset != null) {
      batch.set(
        _trainerPublicProfiles.doc(uid),
        trainerPublicSubset,
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Stream<UserProfile?> watch(String uid) {
    return _users
        .doc(uid)
        .snapshots()
        // A cold local cache yields a first snapshot with exists=false BEFORE
        // the network confirms — emitting null here sends an existing user to
        // /profile-setup. Only a server-confirmed snapshot may report absence.
        .where((snap) => snap.exists || !snap.metadata.isFromCache)
        .map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return UserProfile.fromJson(data);
    });
  }

  Future<void> delete(String uid) async {
    throw UnsupportedError(
      'UserRepository.delete is not allowed from client code. '
      'Account deletion goes through a privileged Cloud Function.',
    );
  }
}
