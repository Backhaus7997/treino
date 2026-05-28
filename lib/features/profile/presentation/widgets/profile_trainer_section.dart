import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../application/user_providers.dart';
import '../../domain/user_role.dart';
import 'profile_section_tile.dart';

/// Sección "ENTRENADOR" del perfil propio — solo visible cuando
/// `role == trainer`.
///
/// Renderiza un único tile que abre `/profile/edit-trainer` donde el PF
/// completa o edita su perfil público (bio, especialidad, ubicación,
/// precio mensual). Los campos viven en `users/{uid}` y se replican a
/// `trainerPublicProfiles/{uid}` via el dual-write atomic del repository.
///
/// El subtitle indica si el perfil está completo o le faltan campos —
/// pista visual para PFs nuevos que aún no aparecen en discovery.
class ProfileTrainerSection extends ConsumerWidget {
  const ProfileTrainerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.valueOrNull;
    if (profile == null || profile.role != UserRole.trainer) {
      return const SizedBox.shrink();
    }

    final missing = <String>[];
    if (profile.trainerBio == null || profile.trainerBio!.trim().isEmpty) {
      missing.add('bio');
    }
    if (profile.trainerSpecialty == null) missing.add('especialidad');
    if (profile.trainerMonthlyRate == null) missing.add('precio');
    // Multi-location: necesita al menos 1 ubicación física O ofrecer online.
    // Mismo invariante que valida UserRepository.update().
    final hasLocations = profile.trainerLocations.isNotEmpty;
    if (!hasLocations && !profile.trainerOffersOnline) {
      missing.add('ubicación o clases virtuales');
    }

    final subtitle = missing.isEmpty
        ? 'Perfil completo · visible en Discovery'
        : 'Faltan: ${missing.join(", ")}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'ENTRENADOR',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.4,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ProfileSectionTile(
            icon: TreinoIcon.specialty,
            title: 'Mi perfil de entrenador',
            subtitle: subtitle,
            onTap: () => context.push('/profile/edit-trainer'),
          ),
        ],
      ),
    );
  }
}
