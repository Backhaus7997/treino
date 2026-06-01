import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/handle_derivation.dart';
import '../../../feed/domain/gym_name.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../application/user_providers.dart';

/// Displays the current user's avatar, display name, derived @handle, and
/// optional gym chip. **Read-only**: edit access lives in the "Datos
/// personales" tile of CUENTA section, not on this card (decision
/// 2026-05-27 — single edit entry point).
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
      error: (_, __) => _CardSkeleton(palette: palette),
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
    if (profile == null) return _CardSkeleton(palette: palette);

    final displayName = profile.displayName as String?;
    final avatarUrl = profile.avatarUrl as String?;
    final gymId = profile.gymId as String?;
    final handle = deriveHandle(displayName);

    return Padding(
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
                    // Uppercase per mockup parity 2026-06-01 polish pass —
                    // matches "ANA NÚÑEZ" treatment in the design comp.
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
          ],
        ),
      ),
    );
  }
}

// ── Gym chip ──────────────────────────────────────────────────────────────────

class _GymChip extends StatelessWidget {
  const _GymChip({required this.gymId, required this.palette});

  final String gymId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final name = gymNameFromId(gymId);
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
  const _CardSkeleton({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}
