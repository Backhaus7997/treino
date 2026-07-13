import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_entitlement.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/weighted_load.dart';

TrainerLink _link(
  String athleteId,
  TrainerLinkStatus status, {
  TrainerLinkEntitlement entitlement = TrainerLinkEntitlement.entitled,
}) =>
    TrainerLink(
      id: '$athleteId-link',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      entitlement: entitlement,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('computeWeightedLoad (client mirror of the TS fn)', () {
    test('active=1.0, paused=0.5, terminated=0', () {
      expect(
        computeWeightedLoad([
          _link('a', TrainerLinkStatus.active),
          _link('b', TrainerLinkStatus.paused),
          _link('c', TrainerLinkStatus.terminated),
        ]),
        1.5,
      );
    });

    test('pending does not count (not following yet)', () {
      expect(computeWeightedLoad([_link('a', TrainerLinkStatus.pending)]), 0);
    });

    test('blocked links are excluded (parked excess, ADR-5)', () {
      expect(
        computeWeightedLoad([
          _link('a', TrainerLinkStatus.active),
          _link('b', TrainerLinkStatus.active,
              entitlement: TrainerLinkEntitlement.blocked),
        ]),
        1.0,
      );
    });

    test('dedupes by athlete, keeping the heaviest status', () {
      expect(
        computeWeightedLoad([
          _link('a', TrainerLinkStatus.terminated),
          _link('a', TrainerLinkStatus.active),
        ]),
        1.0,
      );
    });

    test('6 active + 2 paused = exactly 7.0', () {
      final links = [
        for (final id in ['a', 'b', 'c', 'd', 'e', 'f'])
          _link(id, TrainerLinkStatus.active),
        _link('g', TrainerLinkStatus.paused),
        _link('h', TrainerLinkStatus.paused),
      ];
      expect(computeWeightedLoad(links), 7.0);
    });

    test('empty → 0', () {
      expect(computeWeightedLoad(const []), 0);
    });

    test('no float drift over many halves', () {
      final links = [
        for (var i = 0; i < 21; i++) _link('p$i', TrainerLinkStatus.paused),
      ];
      expect(computeWeightedLoad(links), 10.5);
    });
  });

  group('roundToHalf', () {
    test('snaps to nearest half', () {
      expect(roundToHalf(6.9999999), 7.0);
      expect(roundToHalf(0.3), 0.5);
      expect(roundToHalf(0.2), 0.0);
    });
  });
}
