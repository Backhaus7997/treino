import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provides the [FirebaseFunctions] instance scoped to the southamerica-east1
/// region used by all coach-hub callable functions.
///
/// Overridable in widget tests via ProviderScope.overrides.
/// ADR-CXP-008.
final cloudFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'),
);
