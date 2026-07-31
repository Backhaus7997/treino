import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../../profile/domain/user_public_profile.dart';
import '../../application/suggested_users_providers.dart';
import 'post_avatar.dart';

/// Up to five same-gym profiles shown below the empty AMIGOS feed state.
///
/// Loading, errors, no-gym, and an empty result are intentionally silent: the
/// existing feed empty state remains the complete fallback in those cases.
class SuggestedUsersSection extends ConsumerWidget {
  const SuggestedUsersSection({super.key, required this.gymId});

  final String? gymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedGymId = gymId;
    if (resolvedGymId == null ||
        resolvedGymId.isEmpty ||
        resolvedGymId == kNoGymId) {
      return const SizedBox.shrink();
    }

    final suggestions = ref.watch(suggestedUsersProvider(resolvedGymId));
    return suggestions.maybeWhen(
      data: (profiles) => profiles.isEmpty
          ? const SizedBox.shrink()
          : _SuggestedUsersContent(profiles: profiles),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _SuggestedUsersContent extends StatelessWidget {
  const _SuggestedUsersContent({required this.profiles});

  final List<UserPublicProfile> profiles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return Padding(
      key: const Key('suggested_users_section'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.suggestedUsersTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.8,
              color: AppPalette.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < profiles.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _SuggestedUserRow(profile: profiles[index]),
          ],
        ],
      ),
    );
  }
}

class _SuggestedUserRow extends StatelessWidget {
  const _SuggestedUserRow({required this.profile});

  final UserPublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final displayName = profile.displayName ?? l10n.suggestedUserAnonymous;

    return Semantics(
      key: Key('suggested_user_${profile.uid}'),
      container: true,
      button: true,
      label: l10n.a11ySuggestedUserButton(displayName),
      child: TreinoTappable(
        onTap: () => context.push('/feed/profile/${profile.uid}'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: palette.textMuted.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              PostAvatar(
                authorDisplayName: displayName,
                authorAvatarUrl: profile.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  displayName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                TreinoIcon.chevronRight,
                size: 16,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
