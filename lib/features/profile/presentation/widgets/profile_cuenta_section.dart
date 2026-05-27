import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../auth/application/auth_providers.dart';
import '../../../feed/application/friendship_providers.dart';
import '../../../feed/domain/gym_name.dart';
import '../../application/user_providers.dart';
import 'profile_section_tile.dart';

/// The "CUENTA" section of [ProfileScreen].
///
/// Renders 4 tiles in locked order per REQ-PSR-007:
///   1. Solicitudes de amistad → /profile/friend-requests
///   2. Datos personales → /profile/edit-personal
///   3. Gimnasio → /profile/gym
///   4. Mis rutinas → /profile/routines
///
/// Historial tile is explicitly excluded per scope decision 2026-05-27.
/// // i18n: Fase 6 Etapa 3
class ProfileCuentaSection extends ConsumerWidget {
  const ProfileCuentaSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
    final profileAsync = ref.watch(userProfileProvider);
    final requestCount = ref.watch(pendingRequestCountProvider(myUid ?? ''));

    final gymId = profileAsync.valueOrNull?.gymId;

    // PR#1 stub: assignedRoutinesCountProvider arrives in PR#3.
    // Count defaults to 0 until the provider is wired.
    const int routinesCount = 0;

    final solicitudesSubtitle =
        requestCount > 0 ? '$requestCount nuevas' : null; // i18n: Fase 6 Etapa 3
    final gymSubtitle = gymId == null
        ? 'Sin gym' // i18n: Fase 6 Etapa 3
        : gymNameFromId(gymId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'CUENTA', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.4,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // 1. Solicitudes de amistad
          ProfileSectionTile(
            icon: TreinoIcon.users,
            title: 'Solicitudes de amistad', // i18n: Fase 6 Etapa 3
            subtitle: solicitudesSubtitle,
            onTap: () => context.push('/profile/friend-requests'),
          ),

          // 2. Datos personales
          ProfileSectionTile(
            icon: TreinoIcon.edit,
            title: 'Datos personales', // i18n: Fase 6 Etapa 3
            subtitle: 'Editá tu info', // i18n: Fase 6 Etapa 3
            onTap: () => context.push('/profile/edit-personal'),
          ),

          // 3. Gimnasio
          ProfileSectionTile(
            icon: TreinoIcon.gym,
            title: 'Gimnasio', // i18n: Fase 6 Etapa 3
            subtitle: gymSubtitle,
            onTap: () => context.push('/profile/gym'),
          ),

          // 4. Mis rutinas (count stub — real provider arrives in PR#3)
          ProfileSectionTile(
            icon: TreinoIcon.dumbbell,
            title: 'Mis rutinas', // i18n: Fase 6 Etapa 3
            subtitle:
                '$routinesCount activas', // i18n: Fase 6 Etapa 3
            onTap: () => context.push('/profile/routines'),
          ),
        ],
      ),
    );
  }
}
