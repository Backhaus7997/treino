import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../auth/application/auth_providers.dart';
import '../../../feed/application/friendship_providers.dart';
import '../../../gyms/application/gym_providers.dart';
import '../../../gyms/domain/gym_display_name.dart';
import '../../application/assigned_routines_providers.dart';
import '../../application/user_providers.dart';
import 'profile_section_group.dart';
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
    final l10n = AppL10n.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
    final profileAsync = ref.watch(userProfileProvider);
    final requestCount = ref.watch(pendingRequestCountProvider(myUid ?? ''));

    final gymId = profileAsync.valueOrNull?.gymId;

    // Derives count from assignedRoutinesProvider (one-shot Future per mount).
    // Returns 0 during loading/error — no flicker on the tile subtitle.
    final routinesCount = ref.watch(assignedRoutinesCountProvider(myUid ?? ''));

    final solicitudesSubtitle = requestCount > 0
        ? l10n.profileCuentaSolicitudesSubtitle(requestCount)
        : null;
    // DETAIL context (self) — UserProfile has no denormalized gymName, so
    // resolve live via gymByIdProvider. gyms-foundation Phase 3.
    final gymSubtitle = gymId == null
        ? l10n.profileCuentaNoGym
        : gymDisplayNameFromGym(ref.watch(gymByIdProvider(gymId)).valueOrNull);

    return ProfileSectionGroup(
      title: l10n.profileCuentaTitle,
      tiles: [
        // 1. Solicitudes de amistad
        ProfileSectionTile(
          icon: TreinoIcon.users,
          title: l10n.profileCuentaSolicitudesTitle,
          subtitle: solicitudesSubtitle,
          inGroup: true,
          onTap: () => context.push('/profile/friend-requests'),
        ),

        // 2. Datos personales
        ProfileSectionTile(
          icon: TreinoIcon.edit,
          title: l10n.profileCuentaDatosPersonalesTitle,
          subtitle: l10n.profileCuentaDatosPersonalesSubtitle,
          inGroup: true,
          onTap: () => context.push('/profile/edit-personal'),
        ),

        // 3. Gimnasio
        ProfileSectionTile(
          icon: TreinoIcon.gym,
          title: l10n.profileCuentaGimnasioTitle,
          subtitle: gymSubtitle,
          inGroup: true,
          onTap: () => context.push('/profile/gym'),
        ),

        // 4. Mis rutinas
        ProfileSectionTile(
          icon: TreinoIcon.dumbbell,
          title: l10n.profileCuentaMisRutinasTitle,
          subtitle: l10n.profileCuentaRutinasSubtitle(routinesCount),
          inGroup: true,
          onTap: () => context.push('/profile/routines'),
        ),
      ],
    );
  }
}
