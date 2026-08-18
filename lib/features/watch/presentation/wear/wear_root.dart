import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import 'wear_home.dart';
import 'wear_round_scaffold.dart';
import 'wear_routine_list.dart';
import 'wear_strings.dart';
import 'wear_view_models.dart';
import 'wear_widgets.dart';
import 'wear_workout_screen.dart';
import 'wear_workout_view_model.dart';

/// Pantalla raíz: estado del emparejamiento, y una vez emparejado, la app.
///
/// **Réplica de `ContentView`** de `ios/TreinoWatch Watch App/ContentView.swift`.
///
/// El orden de las ramas no es casual: **un entreno en curso gana sobre todo lo
/// demás**, y en ese caso NO se muestran las páginas laterales. Es para no
/// ofrecerle al atleta arrancar otra rutina mientras está a mitad de ésta.
class WearRoot extends StatelessWidget {
  const WearRoot({
    super.key,
    required this.pairing,
    required this.session,
    required this.today,
    required this.plans,
    required this.templates,
    required this.onStartToday,
    required this.onSelectRoutine,
    required this.selectedRoutine,
    required this.onCloseDetail,
    required this.onStartRoutine,
    required this.onActivateRoutine,
    required this.onLogSet,
    required this.onFinish,
    required this.onAbandon,
  });

  final WearPairingState pairing;

  /// Entreno EN CURSO, o null. Si no es null, gana sobre todo.
  final WearWorkoutSnapshot? session;

  /// Estado de la pantalla HOY: cargando, sin plan activo, falló, o el entreno.
  final WearTodayState today;
  final List<WearRoutineSummary> plans;
  final List<WearRoutineSummary> templates;

  final VoidCallback onStartToday;
  final void Function(WearRoutineSummary, WearRoutineListKind) onSelectRoutine;

  /// Rutina abierta en el detalle, o null.
  final (WearRoutineSummary, WearRoutineListKind)? selectedRoutine;
  final VoidCallback onCloseDetail;
  final VoidCallback onStartRoutine;
  final VoidCallback onActivateRoutine;

  /// Marca una serie del entreno en curso.
  ///
  /// El `exerciseId` viaja con el toque; ver `WearWorkoutScreen.onLogSet`.
  final void Function(String exerciseId, int setNumber) onLogSet;

  /// Cierra el entreno como completado.
  final VoidCallback onFinish;

  /// Lo abandona sin completarlo. La pantalla ya confirma antes de llamarlo.
  final VoidCallback onAbandon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    switch (pairing) {
      case WearPairingState.waitingForPairing:
        return const WearRoundScaffold.centered(
          children: [
            WearStatusMessage(
              icon: TreinoIcon.phone,
              text: WearStrings.openOnPhone,
            ),
          ],
        );

      case WearPairingState.exchanging:
        return const WearRoundScaffold.centered(
          children: [WearLoading(text: WearStrings.linking)],
        );

      case WearPairingState.failed:
        return WearRoundScaffold.centered(
          children: [
            WearStatusMessage(
              icon: TreinoIcon.warning,
              text: WearStrings.linkFailed,
              tint: palette.warning,
            ),
          ],
        );

      case WearPairingState.ready:
        // El detalle es una hoja: se cierra hacia abajo y no pelea con el
        // paginado horizontal. En el reloj, un push se cierra deslizando de
        // costado, que es el MISMO gesto que cambia de página.
        final selected = selectedRoutine;
        if (selected != null) {
          // `WearRoutineDetail` ya trae su propio andamio.
          return WearRoutineDetail(
            routine: selected.$1,
            kind: selected.$2,
            onStart: onStartRoutine,
            onActivate: onActivateRoutine,
            onClose: onCloseDetail,
          );
        }

        final current = session;
        if (current != null) {
          // Entreno en curso: sin páginas laterales.
          return WearWorkoutScreen(
            snapshot: current,
            onLogSet: onLogSet,
            onFinish: onFinish,
            onAbandon: onAbandon,
          );
        }

        return WearHome(
          today: today,
          plans: plans,
          templates: templates,
          onStartToday: onStartToday,
          onSelectRoutine: onSelectRoutine,
        );
    }
  }
}
