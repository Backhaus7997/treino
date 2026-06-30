import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../../../app/theme/app_palette.dart';

/// Burbuja de un mensaje individual en el detail pane.
///
/// V1 = solo texto. Cuando el mensaje tiene `mediaUrl` no-null lo
/// renderea como `[Foto]` / `[Video]` placeholder por ahora — al PF en web
/// le sirve para SABER que llegó un media (no se le esconde el mensaje
/// completamente), pero la preview visual real llega en V2.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.text,
    required this.isOwn,
    required this.createdAt,
    this.mediaPlaceholderLabel,
  });

  final String text;
  final bool isOwn;
  final DateTime createdAt;

  /// Si el mensaje original tiene media (no soportado todavía en web V1),
  /// pasamos un label "📷 Foto" / "🎥 Video" como placeholder visible.
  /// Null → mensaje de texto puro.
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
