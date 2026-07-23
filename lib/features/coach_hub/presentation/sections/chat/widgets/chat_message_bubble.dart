import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/firebase_storage_video_player.dart';

/// Burbuja de un mensaje individual en el detail pane.
///
/// V3 (2026-07-01): fotos se renderean con `Image.network` (pasás [imageUrl])
/// y videos se renderean con [FirebaseStorageVideoPlayer] (pasás [videoUrl]),
/// mismo widget que mobile. Attachments desconocidos siguen como
/// [mediaPlaceholderLabel] ("📎 Adjunto") — defensivo.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.text,
    required this.isOwn,
    required this.createdAt,
    this.imageUrl,
    this.videoUrl,
    this.mediaPlaceholderLabel,
  });

  final String text;
  final bool isOwn;
  final DateTime createdAt;

  /// URL HTTPS de la imagen a renderear inline. Non-null solo cuando
  /// `message.mediaType == image`. Se ignora si también hay
  /// [mediaPlaceholderLabel] (defensivo: no debería pasar).
  final String? imageUrl;

  /// URL HTTPS del video a renderear inline con [FirebaseStorageVideoPlayer].
  /// Non-null solo cuando `message.mediaType == video`. Reusa el mismo widget
  /// que mobile para mantener UX consistente (tap-to-toggle + scrubbing).
  final String? videoUrl;

  /// Label placeholder para media que aún NO se renderea inline (attachments
  /// desconocidos). Null → sin media.
  final String? mediaPlaceholderLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Burbuja propia: fondo mint SÓLIDO (mockup), sin alpha. Burbuja
    // recibida: bgCard, como antes.
    final bg = isOwn ? palette.accent : palette.bgCard;
    // Texto sobre mint sólido necesita un tono "tinta" (near-black) para
    // contraste alto en AMBOS temas. `palette.bg` es near-black solo en
    // dark (ink950) — en light es near-white (paper50), así que ahí usamos
    // `palette.textPrimary` (inkText900, near-black en light). Ninguno de
    // los dos por sí solo sirve en ambos temas; se elige según brightness.
    final ownFg = Theme.of(context).brightness == Brightness.dark
        ? palette.bg
        : palette.textPrimary;
    final fg = isOwn ? ownFg : palette.textPrimary;
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          key: const Key('chat_bubble_container'),
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.hairline),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s14,
            AppSpacing.s12,
            AppSpacing.s14,
            AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: bg,
            // Los 4 corners comparten AppRadius.sm — la escala cerrada del
            // design system solo admite 12/16/20/full, así que la "cola"
            // asimétrica de la burbuja (antes con AppSpacing.hairline, un
            // token de SPACING reusado indebidamente como radio) queda
            // pareja con el resto en vez de introducir una excepción fuera
            // de escala (remediación CRITICAL-2, verify report Fase 8).
            borderRadius: BorderRadius.circular(AppRadius.sm),
            // Burbuja propia es sólida (sin borde); recibida mantiene el
            // borde sutil sobre bgCard.
            border: isOwn ? null : Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
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
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      color: palette.bg.withValues(alpha: 0.4),
                      child: Text(
                        'No pudimos cargar la imagen', // i18n: Fase W2
                        style: const TextStyle(
                          fontFamily: AppFonts.barlow,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ).copyWith(color: palette.textMuted),
                      ),
                    ),
                  ),
                ),
                if (text.isNotEmpty)
                  const SizedBox(height: AppSpacing.hairline),
              ],
              if (videoUrl != null) ...[
                SizedBox(
                  width: 320,
                  child: FirebaseStorageVideoPlayer(
                    url: videoUrl!,
                    palette: palette,
                  ),
                ),
                if (text.isNotEmpty)
                  const SizedBox(height: AppSpacing.hairline),
              ],
              if (mediaPlaceholderLabel != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.hairline,
                  ),
                  decoration: BoxDecoration(
                    color: palette.bg.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    mediaPlaceholderLabel!,
                    style: const TextStyle(
                      fontFamily: AppFonts.barlow,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ).copyWith(color: palette.textMuted),
                  ),
                ),
                if (text.isNotEmpty)
                  const SizedBox(height: AppSpacing.hairline),
              ],
              if (text.isNotEmpty)
                Text(
                  text,
                  style: const TextStyle(
                    fontFamily: AppFonts.barlow,
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    height: 1.35,
                  ).copyWith(color: fg),
                ),
              const SizedBox(height: AppSpacing.hairline),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  DateFormat('HH:mm').format(createdAt.toLocal()),
                  style: const TextStyle(
                    fontFamily: AppFonts.barlow,
                    fontWeight: FontWeight.w400,
                    fontSize: 10,
                  ).copyWith(
                    color: isOwn
                        ? ownFg.withValues(alpha: 0.6)
                        : palette.textMuted,
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
