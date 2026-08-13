import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../../profile/domain/user_public_profile.dart';
import '../../application/suggested_users_providers.dart';
import 'post_avatar.dart';

/// Same-gym profiles shown in a horizontal carousel.
///
/// Loading, errors, no-gym, and an empty result are intentionally silent: the
/// existing feed empty state remains the complete fallback in those cases.
class SuggestedUsersSection extends ConsumerWidget {
  const SuggestedUsersSection({super.key, required this.gymId})
      : profiles = null;

  const SuggestedUsersSection.profiles({
    super.key,
    required List<UserPublicProfile> this.profiles,
  }) : gymId = null;

  final String? gymId;
  final List<UserPublicProfile>? profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedProfiles = profiles;
    if (resolvedProfiles != null) {
      return resolvedProfiles.isEmpty
          ? const SizedBox.shrink()
          : _SuggestedUsersContent(profiles: resolvedProfiles);
    }

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

class _SuggestedUsersContent extends StatefulWidget {
  const _SuggestedUsersContent({required this.profiles});

  final List<UserPublicProfile> profiles;

  @override
  State<_SuggestedUsersContent> createState() => _SuggestedUsersContentState();
}

class _SuggestedUsersContentState extends State<_SuggestedUsersContent> {
  /// `keepScrollOffset: false` NO es un detalle: es la corrección de un bug
  /// real. Por defecto un `Scrollable` guarda su offset en `PageStorage`, y el
  /// `CustomScrollView` del feed abre ese bucket con su
  /// `PageStorageKey('feed-scroll-position')`. Como el carrusel vive dentro de
  /// un sliver perezoso, al alejarse se destruye y al volver se reconstruye —
  /// restaurando el offset viejo. Resultado observado en device: la fila
  /// reaparecía scrolleada al final y las primeras sugerencias quedaban
  /// escondidas a la izquierda. Una fila de sugerencias SIEMPRE tiene que
  /// empezar por la primera.
  late final ScrollController _controller = ScrollController(
    keepScrollOffset: false,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final profiles = widget.profiles;

    return Padding(
      key: const Key('suggested_users_section'),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              l10n.suggestedUsersTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 0.8,
                color: AppPalette.of(context).textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 156,
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: profiles.length * 2 - 1,
              itemBuilder: (context, index) {
                if (index.isOdd) return const SizedBox(width: 12);
                return _SuggestedUserCard(profile: profiles[index ~/ 2]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedUserCard extends StatelessWidget {
  const _SuggestedUserCard({required this.profile});

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
          width: 104,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: palette.textMuted.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            children: [
              PostAvatar(
                authorDisplayName: displayName,
                authorAvatarUrl: profile.avatarUrl,
                size: 56,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 80,
                    child: Text(
                      displayName.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
