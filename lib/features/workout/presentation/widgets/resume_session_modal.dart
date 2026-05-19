import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/session.dart';

class ResumeSessionModal extends StatelessWidget {
  const ResumeSessionModal({
    super.key,
    required this.session,
    required this.onContinue,
    required this.onDiscard,
  });

  final Session session;
  final VoidCallback onContinue;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final localStart = session.startedAt.toLocal();
    final hh = localStart.hour.toString().padLeft(2, '0');
    final mm = localStart.minute.toString().padLeft(2, '0');

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Entrenamiento en curso',
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: 0.8,
          color: palette.textPrimary,
        ),
      ),
      content: Text(
        'Tenés un entrenamiento en curso desde $hh:$mm. ¿Querés continuarlo o descartarlo?',
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.textPrimary,
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: onDiscard,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.highlight, width: 1),
            foregroundColor: palette.highlight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            'Descartar',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: onContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            'Continuar',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}
