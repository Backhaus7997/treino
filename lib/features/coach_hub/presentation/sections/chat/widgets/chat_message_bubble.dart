import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../../../app/theme/app_palette.dart';

/// Burbuja de un mensaje individual en el detail pane.
///
/// V2 (2026-07-01): las imágenes se renderean INLINE con `Image.network`
/// (pasás [imageUrl]). Videos y attachments no soportados siguen como
/// [mediaPlaceholderLabel] visible ("🎥 Video" / "📎 Adjunto") para que el
/// PF SEPA que llegó pero no colisione con el layout hasta V3.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.text,
    required this.isOwn,
    required this.createdAt,
    this.imageUrl,
    this.mediaPlaceholderLabel,
  });

  final String text;
  final bool isOwn;
  final DateTime createdAt;

  /// URL HTTPS de la imagen a renderear inline. Non-null solo cuando
  /// `message.mediaType == image`. Se ignora si también hay
  /// [mediaPlaceholderLabel] (defensivo: no debería pasar).
  final String? imageUrl;

  /// Label placeholder para media que aún NO se renderea inline (video en
  /// V2, attachments desconocidos). Null → sin media.
  final String? mediaPlaceholderLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bg = isOwn ? palette.accent.withValues(alpha: 0.2) : palette.bgCard;
    final fg = palette.textPrimary;
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isOwn ? 14 : 4),
              bottomRight: Radius.circular(isOwn ? 4 : 14),
            ),
            border: Border.all(
              color: isOwn
                  ? palette.accent.withValues(alpha: 0.3)
                  : palette.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl!,
                    // Cap max height so a portrait photo does not push the
                    // whole message list way past the fold. Storage may
                    // return large originals; we let the browser rescale.
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        height: 120,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.accent,
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                    progress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      height: 80,
                      padding: const EdgeInsets.all(12),
                      color: palette.bg.withValues(alpha: 0.4),
                      child: Text(
                        'No pudimos cargar la imagen', // i18n: Fase W2
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                if (text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (mediaPlaceholderLabel != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.bg.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    mediaPlaceholderLabel!,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: palette.textMuted,
                    ),
                  ),
                ),
                if (text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (text.isNotEmpty)
                Text(
                  text,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    height: 1.35,
                    color: fg,
                  ),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  DateFormat('HH:mm').format(createdAt.toLocal()),
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 10,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
