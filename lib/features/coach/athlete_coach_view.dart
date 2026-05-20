import 'package:flutter/material.dart';

import 'presentation/trainers_list_screen.dart';

/// Vista de la tab Coach cuando el usuario es athlete.
///
/// A partir de Fase 5 Etapa 2, monta [TrainersListScreen] (discovery de
/// entrenadores). El stub "COACH / Personal Trainers cerca tuyo" anterior
/// quedó deprecado.
class AthleteCoachView extends StatelessWidget {
  const AthleteCoachView({super.key});

  @override
  Widget build(BuildContext context) => const TrainersListScreen();
}
