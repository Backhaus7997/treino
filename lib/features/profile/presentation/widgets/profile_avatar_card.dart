import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/handle_derivation.dart';
import '../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../../gyms/application/gym_providers.dart';
import '../../../gyms/domain/gym_display_name.dart';
import '../../application/user_providers.dart';

/// Displays the current user's avatar, display name, derived @handle, and
/// optional gym chip.
///
/// Tapping the card opens the user's OWN public profile
/// (`/feed/profile/{uid}`) — the "view as others see me" flow. That screen
/// already detects `isSelf` and hides the SEGUIR / MENSAJE buttons and the
/// privacy gate, so the user sees exactly their public routines + activity.
/// Editing still lives only in the "Datos personales" tile of the CUENTA
/// section (decision 2026-05-27 — single edit entry point); the tap here is
/// a read-only preview, not an edit affordance.
///
/// Uses [userProfileProvider] (StreamProvider) — always reflects the latest
/// Firestore state without manual invalidation. // i18n: Fase 6 Etapa 3
class ProfileAvatarCard extends ConsumerWidget {
  const ProfileAvatarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);

    return profileAsync.when(
      data: (profile) => _CardBody(profile: profile, palette: palette),
      loading: () => _CardSkeleton(palette: palette),
      // Error NO shimmerea: el stream ya falló (p. ej. offline) — un barrido
      // infinito quemaría batería y mentiría ("sigue cargando").
      error: (_, __) => _CardSkeleton(palette: palette, shimmer: false),
    );
  }
}

// ── Data state ────────────────────────────────────────────────────────────────

class _CardBody extends StatelessWidget {
  const _CardBody({required this.profile, required this.palette});

  final dynamic profile; // UserProfile?
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // profile == null es un estado ESTABLE (dato resuelto, sin perfil), no
    // transitorio — sin shimmer: nada está cargando.
    if (profile == null) {
      return _CardSkeleton(palette: palette, shimmer: false);
    }

    final uid = profile.uid as String?;
    final displayName = profile.displayName as String?;
    final avatarUrl = profile.avatarUrl as String?;
    final gymId = profile.gymId as String?;
    final handle = deriveHandle(displayName);

    // Tap → own public profile. Guarded on a non-empty uid so a half-hydrated
    // profile can't push `/feed/profile/` with an empty segment.
    final canOpenPublicProfile = uid != null && uid.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Semantics(
        button: canOpenPublicProfile,
        label: canOpenPublicProfile
            ? 'Ver mi perfil público' // i18n: Fase W3
            : null,
        // Fuse the descendant nodes (avatar image, name text, InkWell) into a
        // single semantic button so the "Ver mi perfil público" label wins for
        // screen readers instead of the raw name/handle text.
        excludeSemantics: canOpenPublicProfile,
        child: Material(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canOpenPublicProfile
                ? () => context.push('/feed/profile/$uid')
                : null,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: palette.textMuted.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  PostAvatar(
                    authorDisplayName: displayName ?? '',
                    authorAvatarUrl: avatarUrl,
                    size: 64,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          // Uppercase per mockup parity 2026-06-01 polish pass
                          // — matches "ANA NÚÑEZ" treatment in the design comp.
                          (displayName ?? 'Sin nombre')
                              .toUpperCase(), // i18n: Fase 6 Etapa 3
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: palette.textPrimary,
                          ),
                        ),
                        if (handle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '@$handle', // i18n: Fase 6 Etapa 3
                            style: GoogleFonts.barlow(
                              fontWeight: FontWeight.w400,
                              fontSize: 13,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                        if (gymId != null) ...[
                          const SizedBox(height: 6),
                          _GymChip(gymId: gymId, palette: palette),
                        ],
                      ],
                    ),
                  ),
                  // Chevron affordance — signals the card is tappable.
                  if (canOpenPublicProfile)
                    Icon(
                      Icons.chevron_right,
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Gym chip ──────────────────────────────────────────────────────────────────

/// DETAIL context (single self-user) — resolves the gym name live via
/// [gymByIdProvider] rather than a denormalized field, since `UserProfile`
/// (unlike `UserPublicProfile`) has no `gymName`. gyms-foundation Phase 3.
class _GymChip extends ConsumerWidget {
  const _GymChip({required this.gymId, required this.palette});

  final String gymId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymAsync = ref.watch(gymByIdProvider(gymId));
    final name = gymDisplayNameFromGym(gymAsync.valueOrNull);
    if (name.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const Key('profile_avatar_gym_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: palette.textMuted.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        name,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

// ── Skeleton (loading / error / null profile) ─────────────────────────────────

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.palette, this.shimmer = true});

  final AppPalette palette;

  /// `false` cuando el skeleton representa un estado estable (error del
  /// stream, perfil null) — se propaga a [TreinoShimmer.enabled].
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    return TreinoShimmer(
      enabled: shimmer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: palette.textMuted.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              // Avatar placeholder
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.textMuted.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 16,
                      width: 120,
                      decoration: BoxDecoration(
                        color: palette.textMuted.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 80,
                      decoration: BoxDecoration(
                        color: palette.textMuted.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
