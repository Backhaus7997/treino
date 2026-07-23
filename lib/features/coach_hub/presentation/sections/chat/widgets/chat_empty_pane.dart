import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../widgets/coach_hub_widgets.dart';

/// Placeholder visual mostrado en el panel derecho cuando el PF no ha
/// seleccionado ninguna conversación todavía.
///
/// El ícono lleva un halo mint sutil detrás — mismo patrón de glow que
/// `AppBackground` (radial `accent` @18%→transparente, SIN blur pesado),
/// a escala de ícono en vez de pantalla completa. Contenido en este archivo:
/// NO se toca `TreinoEmptyState` (componente compartido por todo el kit
/// Coach Hub), así el halo queda acotado al empty state de Chat.
class ChatEmptyPane extends StatelessWidget {
  const ChatEmptyPane({super.key});

  /// Diámetro del halo — valor decorativo puro (igual que el `radius: 0.7`
  /// fraccional de `AppBackground`), no pertenece a la escala de spacing
  /// `AppSpacing` (que gobierna padding/gaps, no dimensiones de un glow).
  static const double _glowDiameter = 220;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.bg,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            key: const Key('chat_empty_pane_glow'),
            width: _glowDiameter,
            height: _glowDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  palette.accent.withValues(alpha: 0.18),
                  palette.accent.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.85],
              ),
            ),
          ),
          const TreinoEmptyState(
            icon: TreinoIcon.chatEmpty,
            title: 'Seleccioná una conversación', // i18n: Fase W2
            description:
                'Elegí un alumno a la izquierda para ver el chat.', // i18n: Fase W2
          ),
        ],
      ),
    );
  }
}
