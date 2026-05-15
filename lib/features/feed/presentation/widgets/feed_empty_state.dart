import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

class FeedEmptyState extends StatelessWidget {
  const FeedEmptyState({super.key});

  static const _kCopy = 'Aún no hay posts de tus amigos';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TreinoIcon.users, size: 48, color: palette.textMuted),
          const SizedBox(height: 12),
          Text(
            _kCopy,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
