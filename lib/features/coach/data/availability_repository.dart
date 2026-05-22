import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/availability_override.dart';
import '../domain/availability_rule.dart';

/// Firestore-backed repository for trainer availability rules and overrides.
///
/// Collections:
///   `coach_availability_rules/{id}`    — recurring weekly rules (REQ-004)
///   `coach_availability_overrides/{id}` — date-specific overrides (REQ-005)
class AvailabilityRepository {
  AvailabilityRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _rules =>
      _firestore.collection('coach_availability_rules');

  CollectionReference<Map<String, Object?>> get _overrides =>
      _firestore.collection('coach_availability_overrides');

  // ─── Rules ────────────────────────────────────────────────────────────────

  /// Persists a new [AvailabilityRule] at `coach_availability_rules/{rule.id}`.
  /// SCENARIO-485.
  Future<void> addRule(AvailabilityRule rule) async {
    await _rules.doc(rule.id).set(rule.toJson());
  }

  /// Updates an existing [AvailabilityRule] at `coach_availability_rules/{rule.id}`.
  Future<void> updateRule(AvailabilityRule rule) async {
    await _rules.doc(rule.id).update(rule.toJson());
  }

  /// Deletes the rule doc at `coach_availability_rules/{ruleId}`. SCENARIO-486.
  Future<void> deleteRule(String trainerId, String ruleId) async {
    await _rules.doc(ruleId).delete();
  }

  /// Real-time stream of all rules for [trainerId]. SCENARIO-487.
  Stream<List<AvailabilityRule>> watchRules(String trainerId) {
    return _rules
        .where('trainerId', isEqualTo: trainerId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AvailabilityRule.fromJson({...d.data(), 'id': d.id}))
            .toList());
  }

  // ─── Overrides ────────────────────────────────────────────────────────────

  /// Persists a new [AvailabilityOverride] at
  /// `coach_availability_overrides/{override.id}`.
  Future<void> addOverride(AvailabilityOverride override) async {
    await _overrides.doc(override.id).set(override.toJson());
  }

  /// Deletes the override doc at `coach_availability_overrides/{overrideId}`.
  Future<void> deleteOverride(String trainerId, String overrideId) async {
    await _overrides.doc(overrideId).delete();
  }

  /// Real-time stream of overrides for [trainerId] whose `date` falls within
  /// [[fromDate], [toDate]] inclusive. SCENARIO-488.
  Stream<List<AvailabilityOverride>> watchOverrides(
    String trainerId,
    DateTime fromDate,
    DateTime toDate,
  ) {
    return _overrides
        .where('trainerId', isEqualTo: trainerId)
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate.toUtc()))
        .where('date',
            isLessThanOrEqualTo: Timestamp.fromDate(toDate.toUtc()))
        .snapshots()
        .map((snap) => snap.docs
            .map((d) =>
                AvailabilityOverride.fromJson({...d.data(), 'id': d.id}))
            .toList());
  }
}
