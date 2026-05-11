import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Botón circular para elegir avatar. Si [localPath] es null muestra un círculo
/// con gradient accent → highlight y la inicial del username (o "?" si vacío).
/// Cuando hay path, muestra la foto. Siempre con un badge "+" en bottom-right.
///
/// Debajo se muestra el subtítulo `SUBÍ UNA FOTO`.
class AvatarPickerButton extends StatelessWidget {
  const AvatarPickerButton({
    super.key,
    required this.localPath,
    required this.usernameInitial,
    required this.onTap,
  });

  /// Path local de la foto elegida del image_picker. `null` = sin foto.
  final String? localPath;

  /// Primera letra del username para mostrar como placeholder cuando no hay foto.
  final String usernameInitial;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: localPath == null
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [palette.accent, palette.highlight],
                        )
                      : null,
                  image: localPath != null
                      ? DecorationImage(
                          image: FileImage(File(localPath!)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: localPath == null
                    ? Text(
                        usernameInitial.toUpperCase(),
                        style: GoogleFonts.barlowCondensed(
                          color: palette.bg,
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.bg, width: 2),
                  ),
                  child: Icon(TreinoIcon.plus, color: palette.bg, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'SUBÍ UNA FOTO',
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
