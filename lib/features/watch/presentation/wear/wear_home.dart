import 'package:flutter/material.dart';

import 'wear_round_scaffold.dart';
import 'wear_routine_list.dart';
import 'wear_today_page.dart';
import 'wear_view_models.dart';

/// La pantalla principal: HOY arriba, y abajo las rutinas.
///
/// ## Por qué esto NO replica el `WatchHome` de watchOS
///
/// Allá son tres páginas deslizables horizontalmente con HOY al medio. Acá es
/// **una sola lista vertical**, y no es una licencia estética: son tres razones
/// que se suman y ninguna se puede esquivar.
///
/// 1. **En Wear OS el swipe izquierda→derecha cierra la app desde CUALQUIER
///    punto de la pantalla**, no desde un borde. Un pager horizontal compite
///    contra el gesto de salida en el 100% de la superficie. El dueño lo reportó
///    exacto: *"cuando quiero moverme a la izquierda no funciona y se cierra la
///    app"*. No era un bug: era la semántica del sistema.
/// 2. Aunque se "arregle" con `systemGestureExclusionRects`, el mejor caso deja
///    reservado el 20% del ancho para la salida, o exige apagar el gesto de
///    salida — que Google marca como no recomendado.
/// 3. **Y ésta decide**: la corona rotatoria mapea a scroll VERTICAL. Con todo
///    vertical, el hardware maneja la app entera. Con el pager horizontal, la
///    corona que el dueño reclamó no sirve para navegar entre páginas: te
///    quedás con un gesto roto Y un hardware inútil.
///
/// watchOS no tiene corona-para-navegar ni swipe-to-dismiss global. La réplica
/// 1:1 acá costaba las dos cosas.
class WearHome extends StatelessWidget {
  const WearHome({
    super.key,
    required this.workout,
    required this.plans,
    required this.templates,
    required this.onStartToday,
    required this.onSelectRoutine,
    this.workoutFailed = false,
  });

  final WearTodaysWorkout? workout;
  final List<WearRoutineSummary> plans;
  final List<WearRoutineSummary> templates;
  final VoidCallback onStartToday;
  final void Function(WearRoutineSummary, WearRoutineListKind) onSelectRoutine;
  final bool workoutFailed;

  @override
  Widget build(BuildContext context) {
    return WearRoundScaffold.list(
      // Arriba arranca con un título ("HOY"); abajo termina con tarjetas.
      firstItem: WearItemType.text,
      lastItem: WearItemType.card,
      children: [
        // HOY primero, y sin nada arriba: el atleta abre el reloj en el
        // gimnasio y lo que necesita es empezar. Las rutinas quedan abajo,
        // a un scroll de distancia, que es el gesto barato en un reloj.
        WearTodaySection(
          workout: workout,
          failed: workoutFailed,
          onStart: onStartToday,
        ),
        const SizedBox(height: 20),
        WearRoutineSection(
          kind: WearRoutineListKind.plans,
          routines: plans,
          onSelect: (r) => onSelectRoutine(r, WearRoutineListKind.plans),
        ),
        const SizedBox(height: 20),
        WearRoutineSection(
          kind: WearRoutineListKind.templates,
          routines: templates,
          onSelect: (r) => onSelectRoutine(r, WearRoutineListKind.templates),
        ),
      ],
    );
  }
}
