import 'package:flutter/material.dart';

import 'wear_pager.dart';
import 'wear_round_scaffold.dart';
import 'wear_routine_list.dart';
import 'wear_today_page.dart';
import 'wear_view_models.dart';

/// La pantalla principal: HOY, y hacia la derecha los planes y las plantillas.
///
/// ## Por qué el orden cambió respecto de watchOS
///
/// Allá HOY está al MEDIO, con planes a la izquierda. Acá HOY es la PRIMERA
/// página y todo lo demás queda a la derecha, y no es capricho:
///
/// En Wear OS el gesto **izquierda→derecha** cierra la app, desde cualquier
/// punto de la pantalla. Con HOY al medio, llegar a los planes exigía
/// exactamente ese gesto — el dueño lo reportó como *"cuando quiero moverme a la
/// izquierda no funciona y se cierra la app"*.
///
/// Poniendo todo hacia la derecha, avanzar usa el dedo de derecha a izquierda,
/// que es la dirección libre. **El conflicto no se esquiva: deja de existir.**
///
/// HOY sigue siendo lo primero que ve el atleta, que es lo que importaba del
/// diseño original: abre el reloj en el gimnasio y lo que necesita es empezar.
///
/// Cada página scrollea sola, y la corona la maneja — ver [WearRoundScaffold].
class WearHome extends StatelessWidget {
  const WearHome({
    super.key,
    required this.today,
    required this.plans,
    required this.templates,
    required this.onStartToday,
    required this.onSelectRoutine,
  });

  final WearTodayState today;
  final WearRoutineList plans;
  final WearRoutineList templates;
  final VoidCallback onStartToday;
  final void Function(WearRoutineSummary, WearRoutineListKind) onSelectRoutine;

  @override
  Widget build(BuildContext context) {
    return WearPager(
      pages: [
        WearRoundScaffold.list(
          firstItem: WearItemType.text,
          lastItem: WearItemType.card,
          children: [
            WearTodaySection(state: today, onStart: onStartToday),
          ],
        ),
        WearRoundScaffold.list(
          firstItem: WearItemType.text,
          lastItem: WearItemType.card,
          children: [
            WearRoutineSection(
              kind: WearRoutineListKind.plans,
              routines: plans.routines,
              isLoading: plans.isLoading,
              failed: plans.failed,
              onSelect: (r) => onSelectRoutine(r, WearRoutineListKind.plans),
            ),
          ],
        ),
        WearRoundScaffold.list(
          firstItem: WearItemType.text,
          lastItem: WearItemType.card,
          children: [
            WearRoutineSection(
              kind: WearRoutineListKind.templates,
              routines: templates.routines,
              isLoading: templates.isLoading,
              failed: templates.failed,
              onSelect: (r) =>
                  onSelectRoutine(r, WearRoutineListKind.templates),
            ),
          ],
        ),
      ],
    );
  }
}
