import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/primitives.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/moderation_providers.dart';
import 'moderation_actions.dart';

/// «Usuarios bloqueados»: a quién bloqueó el usuario, con «Desbloquear» en cada
/// fila (#1698: bloquear no tenía vuelta).
///
/// Ruta de go_router `/profile/settings/bloqueados`, colgada de `/profile` junto
/// a `settings/privacidad`. Abre para el atleta y para el PF —los dos llegan a
/// Privacidad—, así que no está en la lista de rutas sólo-PF del router.
///
/// **Vacío ≠ error**: una lista que no cargó no se muestra como «No bloqueaste
/// a nadie» (el mismo agujero del feed sin red). Por eso mira
/// [blockedUidsProvider] y no [myBlockedUidsProvider], que ante error devuelve
/// `[]` a propósito.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  /// A dónde vuelve Atrás cuando esta pantalla es la única ruta del stack
  /// (recarga en web, deep link): la pantalla desde la que se abre.
  static const _parentPath = '/profile/settings/privacidad';

  static void _volver(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    // Sin nada que sacar `pop` no hace nada y la pantalla queda sin salida.
    GoRouter.maybeOf(context)?.go(_parentPath);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final uid = ref.watch(currentUidProvider);
    final muted = GoogleFonts.barlow(
      fontSize: AppTextSize.body,
      color: palette.textMuted,
    );

    Widget body() => ref.watch(blockedUidsProvider(uid!)).when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: palette.accent)),
          error: (_, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.blockedUsersLoadError, style: muted),
                TextButton(
                  onPressed: () => ref.invalidate(blockedUidsProvider(uid)),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.accentText,
                  ),
                  child: Text(l10n.coachRetryLabel),
                ),
              ],
            ),
          ),
          data: (uids) => uids.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  child: Text(l10n.blockedUsersEmpty, style: muted),
                )
              : ListView.separated(
                  // El shell corre con `extendBody: true`: sin sumar
                  // `padding.bottom` la última fila queda bajo la barra.
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.s20,
                    0,
                    AppSpacing.s20,
                    AppSpacing.s20 + MediaQuery.paddingOf(context).bottom,
                  ),
                  // Índice 0 = la explicación; 1..n = un bloqueado por fila.
                  itemCount: uids.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.s12),
                  itemBuilder: (_, i) => i == 0
                      ? Text(
                          l10n.blockedUsersExplainer,
                          style: muted.copyWith(
                            fontSize: AppTextSize.bodyDense,
                            height: 1.45,
                          ),
                        )
                      : _BlockedUserTile(
                          key: ValueKey('blocked-user-${uids[i - 1]}'),
                          uid: uids[i - 1],
                        ),
                ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: mismo patrón que PrivacyScreen.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: TreinoTappable(
            onTap: () => _volver(context),
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  l10n.blockedUsersTitle.toUpperCase(),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.titleLarge,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: uid == null ? const SizedBox.shrink() : body()),
      ],
    );
  }
}

/// Avatar + nombre + «Desbloquear». El nombre sale de `userPublicProfiles/{uid}`;
/// si el doc no existe la cuenta se eliminó y se dice. En `loading`/`error` no se
/// afirma nada: cae a «Usuario».
class _BlockedUserTile extends ConsumerWidget {
  const _BlockedUserTile({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(uid));
    final pub = pubAsync.valueOrNull;
    final name = pubAsync.hasValue && pub == null
        ? l10n.chatListDeletedUser
        : pub?.displayName ?? l10n.chatScreenTitleFallback;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.textMuted.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            PostAvatar(
              authorDisplayName: name,
              authorAvatarUrl: pub?.avatarUrl,
              size: 40,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTextSize.bodyLarge,
                  color: palette.textPrimary,
                ),
              ),
            ),
            TextButton(
              key: ValueKey('unblock-$uid'),
              // Sin estado de "ocupado": el delete es idempotente y el stream
              // saca la fila apenas Firestore lo aplica en su caché.
              onPressed: () => unblockUser(
                context,
                ref,
                targetUid: uid,
                targetDisplayName: name,
              ),
              style: TextButton.styleFrom(foregroundColor: palette.accentText),
              child: Text(l10n.moderationUnblockAction),
            ),
          ],
        ),
      ),
    );
  }
}
