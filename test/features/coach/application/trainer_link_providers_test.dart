import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

// pendingTrainerLinkCountProvider — backs the Coach Hub top-bar bell badge
// (`/solicitudes`). Mirrors friendship_providers_test.dart's coverage of
// pendingRequestCountProvider.

TrainerLink _link(String id, TrainerLinkStatus status) => TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-$id',
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('returns 0 while trainerLinksStreamProvider is loading', () {
    final container = ProviderContainer(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(pendingTrainerLinkCountProvider), equals(0));
  });

  test('returns the count of pending links only', () async {
    final links = [
      _link('r1', TrainerLinkStatus.pending),
      _link('r2', TrainerLinkStatus.pending),
      _link('a1', TrainerLinkStatus.active),
      _link('p1', TrainerLinkStatus.paused),
    ];

    final container = ProviderContainer(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      ],
    );
    addTearDown(container.dispose);

    final sub = container.listen(trainerLinksStreamProvider, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(pendingTrainerLinkCountProvider), equals(2));

    sub.close();
  });

  test('returns 0 when there are no pending links', () async {
    final links = [_link('a1', TrainerLinkStatus.active)];

    final container = ProviderContainer(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      ],
    );
    addTearDown(container.dispose);

    final sub = container.listen(trainerLinksStreamProvider, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(pendingTrainerLinkCountProvider), equals(0));

    sub.close();
  });
}
