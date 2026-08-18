import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/assigned_routine_providers.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/application/user_routines_providers.dart';
import '../../profile/application/user_providers.dart'
    show userRepositoryProvider;
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_source.dart';
import '../presentation/wear/wear_view_models.dart';

/// La chapita de origen, derivada de `Routine.source`.
///
/// Misma tabla que `RoutineOrigin.badge` de `RoutineCatalog.swift`, para que el
/// atleta lea lo mismo en los dos relojes:
///
/// | origen | chapita |
/// |---|---|
/// | plan que le asignó su PF | `COACH` |
/// | rutina que se armó él | `MÍA` |
/// | plantilla publicada por un entrenador | `PF` |
/// | catálogo de TREINO | (ninguna) |
///
/// El catálogo no lleva chapita a propósito: es el fondo de la lista, no el
/// titular, y marcarlo todo sería ruido.
String? wearRoutineBadge(RoutineSource source) => switch (source) {
      RoutineSource.trainerAssigned => 'COACH',
      RoutineSource.userCreated => 'MÍA',
      RoutineSource.trainerTemplate => 'PF',
      RoutineSource.system => null,
    };

/// Traduce una rutina a su fila en las listas del reloj.
///
/// Pura: no resuelve qué día toca ni lee nada. Esa resolución recién pasa al
/// tocar «Empezar», y con la posición de ESA rutina.
WearRoutineSummary wearRoutineSummaryFrom(Routine routine) =>
    WearRoutineSummary(
      id: routine.id,
      name: routine.name,
      dayCount: routine.days.length,
      numWeeks: routine.numWeeks,
      badge: wearRoutineBadge(routine.source),
    );

/// MIS PLANES: los que le asignó el PF y los que el atleta se armó.
///
/// ⚠️ **NO se usa `unifiedRoutinesProvider`**, que es lo que compone estas dos
/// listas del lado del teléfono. Ese provider ESCRIBE `activeRoutineId` al
/// leerse —adopción perezosa— así que el reloj podría cambiarle la rutina activa
/// al atleta con sólo deslizar a esta página. Acá se componen a mano los dos
/// providers que no escriben nada.
///
/// Los del PF van primero: es el plan que alguien le armó, y pesa más que las
/// propias.
final wearPlansProvider = Provider.autoDispose<WearRoutineList>((ref) {
  final uid = ref.watch(currentUidProvider) ?? '';
  if (uid.isEmpty) return const WearRoutineList.loading();

  return _combinar([
    ref.watch(assignedRoutinesProvider(uid)),
    ref.watch(userCreatedRoutinesProvider(uid)),
  ]);
});

/// PLANTILLAS: para arrancar algo sin que sea un plan propio.
///
/// Las publicadas por entrenadores van primero y el catálogo de TREINO después,
/// igual que en el grid del teléfono y que en watchOS.
///
/// No incluye las que un PF comparte SÓLO con sus atletas: ésas exigen resolver
/// el vínculo atleta–entrenador primero, y son otra cosa que «las publicadas».
final wearTemplatesProvider = Provider.autoDispose<WearRoutineList>((ref) {
  return _combinar([
    ref.watch(publishedTemplatesProvider),
    ref.watch(routinesProvider),
  ]);
});

/// Junta varias fuentes en una lista, respetando el orden en que vienen.
///
/// Reglas de estado, y las tres importan:
///
/// * **Si alguna trajo datos, se muestran.** Media lista es mejor que un cartel:
///   el atleta puede entrenar con lo que hay.
/// * **Cargando sólo si TODAS están cargando.** Si una ya respondió, mostrar el
///   spinner esconderia datos que ya estan.
/// * **Falló sólo si TODAS fallaron y no hay nada.** Es la política que
///   `WearRoutineSection` ya documentaba: el aviso de error tapa la lista, así
///   que sale únicamente cuando no hay lista.
WearRoutineList _combinar(List<AsyncValue<List<Routine>>> fuentes) {
  final rutinas = <WearRoutineSummary>[];
  var alguna = false;
  var todasFallaron = true;

  for (final f in fuentes) {
    final datos = f.valueOrNull;
    if (datos != null) {
      alguna = true;
      todasFallaron = false;
      rutinas.addAll(datos.map(wearRoutineSummaryFrom));
    } else if (!f.hasError) {
      todasFallaron = false;
    }
  }

  if (rutinas.isNotEmpty || alguna) {
    return WearRoutineList(routines: rutinas);
  }
  if (todasFallaron) return const WearRoutineList.failed();
  return const WearRoutineList.loading();
}

/// Marca una rutina como la activa del atleta.
///
/// Escribe el MISMO campo que el teléfono (`users/{uid}.activeRoutineId`), así
/// que el cambio se ve en los dos lados. HOY se actualiza solo: su provider
/// escucha el perfil, no hace falta invalidar nada.
///
/// **No arranca el entreno**, y eso es deliberado —regla portada de
/// `RoutineListView.swift`—: activar es cambiar una preferencia, y encadenarle
/// un entreno haría imposible cambiar de plan sin ponerte a entrenar.
///
/// ⚠️ Sólo tiene sentido sobre PLANES. `resolveActiveRoutineId` busca el
/// marcador dentro de las listas de asignadas y auto-creadas, así que escribir
/// el id de una PLANTILLA es una escritura que sale bien y **no hace nada**: el
/// atleta ve "listo" y HOY le sigue mostrando la rutina de antes. El gate está
/// en la UI (`WearRoutineDetail` sólo ofrece Activar en planes) y se documenta
/// acá para que nadie lo llame desde otro lado.
final wearActivateRoutineProvider =
    Provider<Future<void> Function(String routineId)>((ref) {
  return (routineId) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null || uid.isEmpty) {
      throw StateError('no hay sesión para activar una rutina');
    }
    await ref.read(userRepositoryProvider).update(uid, {
      'activeRoutineId': routineId,
    });
  };
});
