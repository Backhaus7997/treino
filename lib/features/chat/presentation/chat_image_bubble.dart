import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../../l10n/app_l10n.dart';
import '../domain/message.dart';

/// Inline image bubble for chat messages with [MediaType.image].
///
/// Shows a [CachedNetworkImage] thumbnail with a loading skeleton and error
/// placeholder. Tap opens [PhotoViewerScreen] for fullscreen interaction.
/// Caption is rendered below the image when [message.text] is non-empty.
class ChatImageBubble extends StatelessWidget {
  const ChatImageBubble({super.key, required this.message, this.onLongPress});

  final Message message;

  /// Acción secundaria del long-press — hoy, reportar el mensaje
  /// (moderacion-reporte-y-bloqueo). `null` en los mensajes propios.
  ///
  /// Entra por parámetro en vez de envolver la burbuja desde afuera porque
  /// `TreinoTappable` ya maneja el tap de esta imagen, y su dartdoc lo dice:
  /// un `GestureDetector` por encima de un widget que ya maneja taps hace
  /// competir a los dos recognizers en el gesture arena. `onLongPress` es su
  /// acción secundaria justamente para este caso.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final url = message.mediaUrl ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TreinoTappable(
          onLongPress: onLongPress,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PhotoViewerScreen(imageUrl: url),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 220,
              fit: BoxFit.cover,
              placeholder: (context, _) => Container(
                width: 220,
                height: 165,
                color: palette.bgCard,
                alignment: Alignment.center,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: palette.textMuted,
                  ),
                ),
              ),
              errorWidget: (context, _, __) => Container(
                width: 220,
                height: 165,
                color: palette.bgCard,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(12),
                child: Text(
                  l10n.chatMediaImageLoadError,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
        if (message.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              message.text,
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
            ),
          ),
      ],
    );
  }
}
