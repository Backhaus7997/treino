import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';

/// Trainer-specific workout tab — replaces the athlete WORKOUT body (rutina /
/// plantillas / historial) with a "Crear planes" surface. The trainer should
/// not see athlete-mode controls (no EMPEZAR, no historial propio); their
/// workout tab is dedicated to building and assigning routines.
///
/// v1 scope: visual scaffold + explainer + CTA that routes to ALUMNOS. The
/// trainer's existing assignment flow (`/workout/routine-editor/:athleteId`)
/// is reached from there. A future iteration can surface the trainer's own
/// template library directly here.
class TrainerWorkoutView extends StatelessWidget {
  const TrainerWorkoutView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        physics: const ClampingScrollPhysics(),
        children: [
          Text(
            'CREAR PLANES',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              letterSpacing: 0.5,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tu espacio para armar plantillas de rutina y asignarlas a tus alumnos.',
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          _AssignFromAlumnoCard(palette: palette),
          const SizedBox(height: 12),
          _TemplateLibraryPlaceholder(palette: palette),
        ],
      ),
    );
  }
}

/// Card explaining how to start a plan today (via the alumno selection flow)
/// + a CTA that jumps to ALUMNOS.
class _AssignFromAlumnoCard extends StatelessWidget {
  const _AssignFromAlumnoCard({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.accent, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(TreinoIcon.users, size: 20, color: palette.accent),
              const SizedBox(width: 8),
              Text(
                'ASIGNAR A UN ALUMNO',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: palette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Elegí un alumno y armale el plan en su perfil. La plantilla queda guardada y la podés reutilizar.',
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              height: 1.4,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/coach?tab=alumnos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: Text(
                'VER ALUMNOS',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual placeholder for the future template library section. Communicates
/// intent without committing to a data shape yet.
class _TemplateLibraryPlaceholder extends StatelessWidget {
  const _TemplateLibraryPlaceholder({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TU BIBLIOTECA DE PLANTILLAS',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Próximamente vas a poder crear plantillas reutilizables sin asignarlas a un alumno específico — para tu propio catálogo.',
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              height: 1.4,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
