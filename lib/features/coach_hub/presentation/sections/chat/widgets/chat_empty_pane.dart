import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/treino_icon.dart';

/// Placeholder visual mostrado en el panel derecho cuando el PF no ha
/// seleccionado ninguna conversación todavía.
class ChatEmptyPane extends StatelessWidget {
  const ChatEmptyPane({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      color: palette.bg,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            TreinoIcon.sidebarChat,
            size: 64,
            color: palette.textMuted.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Seleccioná una conversación', // i18n: Fase W2
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Elegí un alumno a la izquierda para ver el chat.', // i18n: Fase W2
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontWeight: FontWeight.w400,
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
