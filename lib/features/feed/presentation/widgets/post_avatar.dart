import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

class PostAvatar extends StatelessWidget {
  const PostAvatar({
    super.key,
    required this.authorDisplayName,
    required this.authorAvatarUrl,
    this.size = 40,
  });

  final String authorDisplayName;
  final String? authorAvatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final initial = _computeInitial(authorDisplayName);

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: authorAvatarUrl != null
            ? CachedNetworkImage(
                imageUrl: authorAvatarUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _InitialFallback(
                    initial: initial, palette: palette, size: size),
                errorWidget: (_, __, ___) => _InitialFallback(
                    initial: initial, palette: palette, size: size),
              )
            : _InitialFallback(initial: initial, palette: palette, size: size),
      ),
    );
  }
}

String _computeInitial(String displayName) {
  if (displayName.isEmpty || displayName == 'Anónimo') return '?';
  return displayName.characters.first.toUpperCase();
}

class _InitialFallback extends StatelessWidget {
  const _InitialFallback({
    required this.initial,
    required this.palette,
    required this.size,
  });

  final String initial;
  final AppPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.accent, palette.highlight],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: size * 0.45,
          color: palette.bg,
        ),
      ),
    );
  }
}
