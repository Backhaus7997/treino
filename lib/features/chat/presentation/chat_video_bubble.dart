import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/firebase_storage_video_player.dart';
import '../domain/message.dart';

/// Inline video bubble for chat messages with [MediaType.video].
///
/// Renders a [FirebaseStorageVideoPlayer] for the message's [mediaUrl].
/// Caption is displayed below the player when [message.text] is non-empty.
class ChatVideoBubble extends StatelessWidget {
  const ChatVideoBubble({super.key, required this.message, this.onLongPress});

  final Message message;

  /// Acción secundaria del long-press — hoy, reportar el mensaje
  /// (moderacion-reporte-y-bloqueo). `null` en los mensajes propios.
  ///
  /// Acá sí va un `GestureDetector`, al revés que en [ChatImageBubble]: esta
  /// burbuja no registra ningún tap propio, así que no hay dos recognizers
  /// compitiendo. Envuelve la Column entera para que el epígrafe también se
  /// pueda reportar.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          child: FirebaseStorageVideoPlayer(
            url: message.mediaUrl ?? '',
            palette: palette,
            // Tap-to-load: este bubble vive en el `ListView.builder` de la
            // conversación, así que con el auto-init cada video que pasa por
            // pantalla dispara una descarga — y otra cada vez que volvés a
            // scrollear, porque es un `State` nuevo. Egress a USD 0,12/GB sin
            // CDN, y datos móviles del usuario, por videos que nadie pidió.
            autoInicializar: false,
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

    if (onLongPress == null) return content;
    return GestureDetector(onLongPress: onLongPress, child: content);
  }
}
