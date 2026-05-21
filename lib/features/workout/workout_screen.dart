import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/widgets/historial_section.dart';
import 'presentation/widgets/mi_plan_section.dart';
import 'presentation/widgets/plantillas_section.dart';

class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No ref.watch here — sections own their own consumers.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        physics: const ClampingScrollPhysics(),
        children: const [
          MiPlanSection(),
          SizedBox(height: 20),
          PlantillasSection(),
          SizedBox(height: 20),
          HistorialSection(),
        ],
      ),
    );
  }
}
