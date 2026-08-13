import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import 'wear_round_scaffold.dart';
import 'wear_routine_list.dart';
import 'wear_today_page.dart';
import 'wear_view_models.dart';

/// Las tres páginas de la app, con HOY en el medio.
///
/// **Réplica de `WatchHome`** de `ios/TreinoWatch Watch App/ContentView.swift`.
///
/// El atleta abre el reloj en el gimnasio y lo que necesita es empezar: por eso
/// HOY es la página inicial y las otras dos se buscan a propósito, deslizando.
/// Poner planes o plantillas al arranque le cobraría un gesto al caso común.
///
/// ## Lo que NO hace falta portar
///
/// watchOS relee al cambiar de página, y tiene un `refreshToken` para eso. La
/// razón está escrita allá: *"El reloj habla Firestore por REST y no tiene
/// listeners —es el costo de que Firestore no exista en watchOS—, así que nadie
/// le avisa que el atleta cambió su rutina activa desde el teléfono."*
///
/// En Wear OS esa restricción NO existe: el SDK de Firebase corre, con listeners
/// en vivo. Medido en este mismo reloj: los snapshots llegan empujados con una
/// mediana de 206 ms. Así que las listas se actualizan solas y todo el mecanismo
/// de `refreshToken` sobra. Es el primer lugar donde el replanteo se ve en la UI.
class WearHome extends StatefulWidget {
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
  State<WearHome> createState() => _WearHomeState();
}

class _WearHomeState extends State<WearHome> {
  /// Arranca en 1 = HOY. Ver el doc de la clase.
  static const _todayIndex = 1;

  final _controller = PageController(initialPage: _todayIndex);
  int _page = _todayIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WearRoundScaffold.inscribed(
      child: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                WearRoutineList(
                  kind: WearRoutineListKind.plans,
                  routines: widget.plans,
                  onSelect: (r) =>
                      widget.onSelectRoutine(r, WearRoutineListKind.plans),
                ),
                WearTodayPage(
                  workout: widget.workout,
                  failed: widget.workoutFailed,
                  onStart: widget.onStartToday,
                ),
                WearRoutineList(
                  kind: WearRoutineListKind.templates,
                  routines: widget.templates,
                  onSelect: (r) =>
                      widget.onSelectRoutine(r, WearRoutineListKind.templates),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _PageDots(count: 3, current: _page),
        ],
      ),
    );
  }
}

/// Puntitos de página.
///
/// watchOS los dibuja solo con `.tabViewStyle(.page)`; en Flutter hay que
/// ponerlos a mano. **No son decoración**: sin ellos nada sugiere que hay dos
/// páginas más al costado, y el atleta no las descubre nunca.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current ? palette.accent : palette.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}
