import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_entitlement.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/weighted_load.dart';

/// TS/Dart parity regression pin (paywall Fase 7, PR4, H1).
///
/// Reads the SAME golden fixture the TS side reads
/// (`functions/src/__tests__/weighted-load.test.ts` reads
/// `functions/src/subscriptions/weighted-load-cases.json`), via `dart:io` —
/// `flutter test`'s working directory is the package root, which contains
/// `functions/`. This is the safety net design D-3 calls for:
/// `computeWeightedLoad` has set semantics (dedupe/filter order matters) that
/// cross-language comments alone don't catch — H1 (weighted-load.ts filtered
/// `blocked` AFTER dedupe instead of before, sub-counting the load) shipped
/// to production and survived review despite matching comments on both
/// sides. `weighted_load.dart` has always filtered/deduped in the correct
/// order, so every case here is expected to pass immediately — this file
/// exists to make a FUTURE divergence fail loudly instead of silently.
void main() {
  final fixtureFile = File(
    'functions/src/subscriptions/weighted-load-cases.json',
  );
  final cases = (jsonDecode(fixtureFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  group(
      'computeWeightedLoad — golden fixture parity (weighted-load-cases.json)',
      () {
    for (final testCase in cases) {
      test(testCase['name'] as String, () {
        final links = (testCase['links'] as List)
            .cast<Map<String, dynamic>>()
            .map(
              (l) => TrainerLink(
                id: '${l['athleteId']}-link',
                trainerId: 'trainer-1',
                athleteId: l['athleteId'] as String,
                status: TrainerLinkStatusX.fromJson(l['status'] as String),
                entitlement: TrainerLinkEntitlementX.fromJson(
                  l['entitlement'] as String?,
                ),
                requestedAt: DateTime.utc(2026, 1, 1),
              ),
            )
            .toList();

        expect(
          computeWeightedLoad(links),
          (testCase['expected'] as num).toDouble(),
        );
      });
    }
  });
}
