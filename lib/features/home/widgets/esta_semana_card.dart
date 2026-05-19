import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../insights/presentation/widgets/body_silhouette_placeholder.dart';

/// Card "Esta Semana" del Home. En esta etapa solo expone el tap →
/// `InsightsScreen`. Los datos reales (streak, muscle map coloreado,
/// dots por día, stats SEMANA/MES) los llena Etapa 6.
class EstaSemanaCard extends StatelessWidget {
  const EstaSemanaCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GestureDetector(
      onTap: () => context.push('/home/insights'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ESTA SEMANA',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 1.4,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              const BodySilhouettePlaceholder(
                width: double.infinity,
                height: 140,
                label: 'Tocá para ver tus insights',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
