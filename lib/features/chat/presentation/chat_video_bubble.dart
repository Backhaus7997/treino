import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/firebase_storage_video_player.dart';
import '../domain/message.dart';

/// Inline video bubble for chat messages with [MediaType.video].
///
/// Renders a [FirebaseStorageVideoPlayer] for the message's [mediaUrl].
/// Caption is displayed below the player when [message.text] is non-empty.
class ChatVideoBubble extends StatelessWidget {
  const ChatVideoBubble({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          child: FirebaseStorageVideoPlayer(
            url: message.mediaUrl ?? '',
            palette: palette,
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
