import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../widgets/coach_hub_widgets.dart';

/// Placeholder visual mostrado en el panel derecho cuando el PF no ha
/// seleccionado ninguna conversación todavía.
class ChatEmptyPane extends StatelessWidget {
  const ChatEmptyPane({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.bg,
      child: const TreinoEmptyState(
        icon: TreinoIcon.chatEmpty,
        title: 'Seleccioná una conversación', // i18n: Fase W2
        description:
            'Elegí un alumno a la izquierda para ver el chat.', // i18n: Fase W2
      ),
    );
  }
}
