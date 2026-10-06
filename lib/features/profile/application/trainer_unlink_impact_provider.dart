import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import '../../coach/domain/trainer_link_status.dart';

/// Cuántos alumnos quedan desvinculados si el entrenador elimina su cuenta:
/// alumnos DISTINTOS con vínculo `active` o `paused` (pendientes y terminados
/// no cuentan como alumnos).
///
/// Devuelve el [AsyncValue] tal cual: quien lo lea tiene que mirar `hasValue`,
/// NO `valueOrNull`. Mientras carga o si el stream falla no hay conteo, y
/// mostrar «0» o cualquier número sería afirmar algo que no sabemos. La baja
/// nunca depende de este valor.
final trainerUnlinkImpactProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
  return ref.watch(trainerLinksStreamProvider).whenData(
        (links) => links
            .where(
              (l) =>
                  l.status == TrainerLinkStatus.active ||
                  l.status == TrainerLinkStatus.paused,
            )
            .map((l) => l.athleteId)
            .toSet()
            .length,
      );
});
