// SC-PSD-31..33: cuántos alumnos se desvinculan al borrar la cuenta del PF.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/trainer_unlink_impact_provider.dart';

TrainerLink _link(String id, String athleteId, TrainerLinkStatus status) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

ProviderContainer _container(Stream<List<TrainerLink>> stream) {
  final c = ProviderContainer(
    overrides: [trainerLinksStreamProvider.overrideWith((ref) => stream)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('cuenta alumnos distintos con vínculo activo o pausado', () async {
    final c = _container(
      Stream.value([
        _link('1', 'a', TrainerLinkStatus.active),
        _link('2', 'a', TrainerLinkStatus.active), // mismo alumno, 2 docs
        _link('3', 'b', TrainerLinkStatus.paused),
        _link('4', 'c', TrainerLinkStatus.terminated),
        _link('5', 'd', TrainerLinkStatus.pending),
      ]),
    );
    final sub = c.listen(trainerUnlinkImpactProvider, (_, __) {});
    await c.read(trainerLinksStreamProvider.future);

    final v = sub.read();
    expect(v.hasValue, isTrue);
    expect(v.requireValue, 2);
  });

  test('sin vínculos devuelve 0 como valor cargado', () async {
    final c = _container(Stream.value(const []));
    final sub = c.listen(trainerUnlinkImpactProvider, (_, __) {});
    await c.read(trainerLinksStreamProvider.future);

    expect(sub.read().hasValue, isTrue);
    expect(sub.read().requireValue, 0);
  });

  test('mientras carga NO tiene valor (no afirma un conteo)', () {
    final c = _container(StreamController<List<TrainerLink>>().stream);
    final sub = c.listen(trainerUnlinkImpactProvider, (_, __) {});

    expect(sub.read().hasValue, isFalse);
    expect(sub.read().isLoading, isTrue);
  });

  test('si el stream falla NO tiene valor', () async {
    final c = _container(Stream.error(StateError('boom')));
    final sub = c.listen(trainerUnlinkImpactProvider, (_, __) {});
    await expectLater(
      c.read(trainerLinksStreamProvider.future),
      throwsA(isA<StateError>()),
    );

    expect(sub.read().hasValue, isFalse);
    expect(sub.read().hasError, isTrue);
  });
}
