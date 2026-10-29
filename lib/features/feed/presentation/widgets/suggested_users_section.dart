import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../../profile/domain/user_public_profile.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../application/follow_providers.dart' show followEdgeProvider;
import '../../application/suggested_users_providers.dart';
import '../../domain/follow.dart';
import 'post_avatar.dart';
import 'public_profile_follow_button.dart';

/// Ancho de la tarjeta. Entra "SIGUIENDO" en el pill compacto sin achicar el
/// texto; "SOLICITUD ENVIADA" se achica (ver [PublicProfileFollowButton.compact]).
const double _kCardWidth = 120;

/// Alto de la fila: avatar (56) + nombre de hasta 2 líneas + pill, con el
/// padding de la tarjeta. Antes eran 156 con sólo avatar + nombre, y la
/// tarjeta quedaba con ~40% de alto vacío abajo.
const double _kRowHeight = 176;

/// Same-gym profiles shown in one or two horizontal carousels (two from
/// [_kTwoRowsFrom] suggestions on, each row scrolling on its own).
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

/// Desde cuántas sugerencias se reparten en dos filas. Con menos, dos filas
/// de una o dos tarjetas se ven vacías: queda una sola.
const int _kTwoRowsFrom = 4;

/// Reparte las sugerencias en las filas que se muestran: una sola si son
/// pocas, y si no dos, alternando (1ª arriba, 2ª abajo, 3ª arriba…). Alternar
/// y no partir al medio deja las mejores sugerencias a la vista, a la
/// izquierda de las DOS filas. Pública para el test.
List<List<UserPublicProfile>> splitSuggestionRows(
    List<UserPublicProfile> profiles) {
  if (profiles.length < _kTwoRowsFrom) return [profiles];
  return [
    for (final parity in [0, 1])
      [
        for (var i = parity; i < profiles.length; i += 2) profiles[i],
      ],
  ];
}

class _SuggestedUsersContent extends StatelessWidget {
  const _SuggestedUsersContent({required this.profiles});

  final List<UserPublicProfile> profiles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final rows = splitSuggestionRows(profiles);

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
          for (final (i, row) in rows.indexed) ...[
            const SizedBox(height: 12),
            _SuggestedRow(key: Key('suggested_users_row_$i'), profiles: row),
          ],
        ],
      ),
    );
  }
}

/// Una fila de tarjetas con su PROPIO scroll horizontal: cada fila se mueve
/// sola.
class _SuggestedRow extends StatefulWidget {
  const _SuggestedRow({super.key, required this.profiles});

  final List<UserPublicProfile> profiles;

  @override
  State<_SuggestedRow> createState() => _SuggestedRowState();
}

class _SuggestedRowState extends State<_SuggestedRow> {
  /// `keepScrollOffset: false` NO es un detalle: es la corrección de un bug
  /// real. Por defecto un `Scrollable` guarda su offset en `PageStorage`, y el
  /// `CustomScrollView` del feed abre ese bucket con su
  /// `PageStorageKey('feed-scroll-position')`. Como el carrusel vive dentro de
  /// un sliver perezoso, al alejarse se destruye y al volver se reconstruye —
  /// restaurando el offset viejo. Resultado observado en device: la fila
  /// reaparecía scrolleada al final y las primeras sugerencias quedaban
  /// escondidas a la izquierda. Una fila de sugerencias SIEMPRE tiene que
  /// empezar por la primera. Un controller por fila: compartirlo ataría el
  /// scroll de las dos.
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
    final profiles = widget.profiles;
    return SizedBox(
      height: _kRowHeight,
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

    // El botón Seguir queda FUERA del área tappable que abre el perfil: dos
    // GestureDetector anidados compiten en el arena y, además, los dos
    // animarían el scale de presión.
    return Container(
      width: _kCardWidth,
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: palette.textMuted.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Semantics(
              key: Key('suggested_user_${profile.uid}'),
              container: true,
              button: true,
              label: l10n.a11ySuggestedUserButton(displayName),
              child: TreinoTappable(
                onTap: () => context.push('/feed/profile/${profile.uid}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      PostAvatar(
                        authorDisplayName: displayName,
                        authorAvatarUrl: profile.avatarUrl,
                        size: 56,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: _kCardWidth - 24,
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
            ),
          ),
          _SuggestedFollowButton(profile: profile),
        ],
      ),
    );
  }
}

/// Seguir sin salir del carrusel.
///
/// Lee las mismas DOS aristas que el perfil público (yo→él, él→yo) y se las
/// pasa al [PublicProfileFollowButton], así que los estados SEGUIR / SIGUIENDO /
/// SOLICITUD ENVIADA / ACEPTAR son los del perfil, no una copia. Al abrir, las
/// sugerencias no tienen arista en ningún sentido (`suggestedUsersProvider`
/// las excluye por presencia), o sea que arranca en SEGUIR; la tarjeta se queda
/// en el carrusel después de seguir y el pill pasa a SIGUIENDO por el stream.
class _SuggestedFollowButton extends ConsumerWidget {
  const _SuggestedFollowButton({required this.profile});

  final UserPublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewerUid = ref.watch(currentUidProvider);
    if (viewerUid == null || viewerUid == profile.uid) {
      return const SizedBox(height: 12);
    }

    final outgoing = ref
        .watch(followEdgeProvider(Follow.edgeId(viewerUid, profile.uid)))
        .valueOrNull;
    final incoming = ref
        .watch(followEdgeProvider(Follow.edgeId(profile.uid, viewerUid)))
        .valueOrNull;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: PublicProfileFollowButton(
        compact: true,
        outgoingFollow: outgoing,
        incomingFollow: incoming,
        viewerUid: viewerUid,
        targetUid: profile.uid,
        targetIsPublic: profile.isProfilePublic,
        targetDisplayName: profile.displayName,
      ),
    );
  }
}
