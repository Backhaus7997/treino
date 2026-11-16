import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import '../../workout/application/routine_providers.dart' show routinesProvider;
import '../../workout/domain/routine.dart';

/// La plantilla del catálogo que el atleta SIGUE sin haberla copiado
/// (`activeRoutineId` apuntando a una plantilla `source == 'system'`), o null
/// si no sigue ninguna.
///
/// Existe porque seguir una plantilla no crea ningún documento del atleta:
/// `_FollowTemplateBar` (routine_detail_screen.dart) sólo escribe
/// `users/{uid}.activeRoutineId`. Para quien no tiene rutinas propias ni plan
/// de un PF, ESA plantilla es toda su rutina, y las dos listas que Home mira
/// para decidir si es un primer arranque (`userCreatedRoutinesProvider` y
/// `assignedRoutinesProvider`) vienen vacías. Sin esta mirada, Home le
/// mostraba la bienvenida de «todavía no tenés rutina» a alguien que ya la
/// estaba siguiendo (#1698).
///
/// Devuelve un `AsyncValue` y no un `Routine?` a propósito: «todavía no sé» y
/// «confirmado que no sigue ninguna» son decisiones distintas para quien
/// dibuja. Home sólo muestra la bienvenida con lo segundo — mientras el
/// catálogo carga, o si falla, mantiene la card de entrenar en vez de
/// esconder una rutina real detrás de una lectura incompleta.
///
/// Sin marcador no se toca el catálogo: el atleta nuevo, que es el caso común
/// de la bienvenida, resuelve en el mismo frame y sin una lectura de las 7
/// plantillas. Con marcador que no es del catálogo (una propia o una del PF,
/// que ya cubren las otras dos listas, o un id obsoleto) la respuesta es null.
final followedTemplateProvider = Provider.autoDispose<AsyncValue<Routine?>>(
  (ref) {
    final activeId = ref.watch(
      userProfileProvider.select((a) => a.valueOrNull?.activeRoutineId),
    );
    if (activeId == null || activeId.isEmpty) {
      return const AsyncData<Routine?>(null);
    }

    return ref.watch(routinesProvider).whenData((catalog) {
      for (final r in catalog) {
        if (r.id == activeId) return r;
      }
      return null;
    });
  },
);
