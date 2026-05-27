import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/commercial_plan.dart';

/// Firestore-backed repository for trainer commercial plans (pricing tiers).
///
/// Documents live at `commercialPlans/{planId}` with auto-generated IDs.
/// All reads/writes are scoped to the trainer's uid via Firestore rules —
/// this repository does NOT enforce ownership client-side; rules are the
/// source of truth.
class CommercialPlanRepository {
  CommercialPlanRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _col =>
      _firestore.collection('commercialPlans');

  // ─── create ────────────────────────────────────────────────────────────────

  /// Creates a new plan with auto-generated ID, returns the persisted plan
  /// with `id`, `createdAt`, `updatedAt` populated by Firestore server.
  Future<CommercialPlan> create({
    required String trainerId,
    required String name,
    required int priceArs,
    String shortDescription = '',
    int durationMonths = 1,
    BillingFrequency billingFrequency = BillingFrequency.monthly,
    List<PlanInclude> includes = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final doc = _col.doc();
    final plan = CommercialPlan(
      id: doc.id,
      trainerId: trainerId,
      name: name,
      shortDescription: shortDescription,
      priceArs: priceArs,
      durationMonths: durationMonths,
      billingFrequency: billingFrequency,
      includes: includes,
      status: CommercialPlanStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    await doc.set(plan.toJson()..remove('id'));
    return plan;
  }

  // ─── update ────────────────────────────────────────────────────────────────

  /// Updates fields on an existing plan. Bumps `updatedAt` to now.
  /// Whoever owns the doc (trainerId == auth.uid) is enforced by rules.
  Future<void> update(CommercialPlan plan) async {
    final next = plan.copyWith(updatedAt: DateTime.now().toUtc());
    await _col.doc(plan.id).update(next.toJson()..remove('id'));
  }

  // ─── archive ───────────────────────────────────────────────────────────────

  /// Soft-delete: flips status → archived. The doc remains for historical
  /// reference (e.g. subscriptions that were created against it).
  Future<void> archive(String planId) async {
    await _col.doc(planId).update({
      'status': 'archived',
      'updatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
    });
  }

  // ─── watchForTrainer ───────────────────────────────────────────────────────

  /// Live stream of plans owned by [trainerId], ordered by createdAt desc.
  /// Returns ALL statuses (active + archived); UI filters as needed.
  Stream<List<CommercialPlan>> watchForTrainer(String trainerId) {
    return _col
        .where('trainerId', isEqualTo: trainerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => CommercialPlan.fromJson({...d.data(), 'id': d.id}))
            .toList());
  }
}
