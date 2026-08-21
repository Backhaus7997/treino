import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/feed_screen_providers.dart'
    show myFollowingFeedProvider;
import '../../application/follow_providers.dart' show followRepositoryProvider;
import '../../data/follow_repository.dart' show FollowRepository;
import '../../domain/follow.dart';
import '../../domain/follow_status.dart';
import 'unfriend_confirmation_sheet.dart';

/// Pill de 4 estados del perfil público.
///
/// **Lee DOS aristas, no una relación** (design §6). Antes tomaba un solo
/// `Friendship?` y desambiguaba con `requesterId`; eso funcionaba sólo porque
/// el documento era el par. Con el grafo dirigido "yo lo sigo" y "él me sigue"
/// son documentos distintos, y este botón habla exclusivamente de la primera.
///
/// | Estado | Condición | onTap |
/// |---|---|---|
/// | SEGUIR | `outgoing == null` (y no hay entrante pendiente) | `follow(...)` |
/// | SIGUIENDO | `outgoing.status == accepted` | sheet → `deleteEdge(outgoing.id)` |
/// | SOLICITUD ENVIADA | `outgoing.status == pending` | `null` (cancelar entra en PR4) |
/// | ACEPTAR | `outgoing == null && incoming.status == pending` | `acceptRequest(incoming.id)` |
///
/// **Precedencia: la arista saliente manda.** Si yo lo sigo y además él me
/// mandó solicitud, el pill muestra mi estado saliente y la solicitud entrante
/// se resuelve desde el inbox. Sin esa regla los dos estados compiten por el
/// mismo control.
///
/// Corolario que arregla un bug de producto: que alguien te siga **no** te
/// muestra SIGUIENDO en su perfil. Antes sí, porque era el mismo documento.
///
/// Stream conversion (REQ-FPS-008): `followEdgeProvider` es
/// `StreamProvider.family.autoDispose` y se auto-actualiza ante mutaciones de
/// Firestore — no hace falta invalidarlo a mano. La invalidación de
/// `myFollowingFeedProvider` se conserva (sigue siendo un FutureProvider que
/// requiere refresh explícito, ADR-FPS-006).
class PublicProfileFollowButton extends ConsumerStatefulWidget {
  const PublicProfileFollowButton({
    super.key,
    required this.outgoingFollow,
    required this.incomingFollow,
    required this.viewerUid,
    required this.targetUid,
    this.targetIsPublic = false,
  });

  /// `follows/{viewer}_{target}` — ¿yo lo sigo? Es la que gobierna este pill.
  final Follow? outgoingFollow;

  /// `follows/{target}_{viewer}` — ¿él me sigue? Sólo se mira para ofrecer
  /// ACEPTAR cuando llegó una solicitud y yo todavía no lo sigo.
  final Follow? incomingFollow;

  final String viewerUid;
  final String targetUid;

  /// When `true`, tapping SEGUIR auto-accepts (Instagram-style public profile).
  /// When `false` (default) the edge is created as `pending` and the target
  /// must approve. See [FollowRepository.follow].
  final bool targetIsPublic;

  @override
  ConsumerState<PublicProfileFollowButton> createState() =>
      _PublicProfileFollowButtonState();
}

class _PublicProfileFollowButtonState
    extends ConsumerState<PublicProfileFollowButton> {
  /// In-flight guard for the SEGUIR / ACEPTAR writes. Mirrors the `_busy`
  /// pattern on [FriendRequestInboxTile]: while an edge mutation is
  /// pending the pill is disabled and shows a spinner so the user can't
  /// double-fire and isn't left staring at an unchanged, silent control.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(followRepositoryProvider);
    final outgoing = widget.outgoingFollow;
    final incoming = widget.incomingFollow;

    // La saliente manda: se evalúa entera antes de mirar la entrante.
    if (outgoing != null) {
      if (outgoing.status == FollowStatus.accepted) {
        return _FollowPill(
          label: 'SIGUIENDO',
          style: _FollowPillStyle.outlined,
          leadingIcon: TreinoIcon.check,
          semanticsLabel: AppL10n.of(context).feedFollowButtonFollowingA11y,
          onTap: () => _showUnfriendSheet(outgoing),
        );
      }
      // pending → yo mandé la solicitud y todavía no me aceptaron.
      //
      // REQ-FOLLOW-006: hasta PR4 esto tenía `onTap: null`, o sea que mandabas
      // una solicitud a una cuenta privada y NO HABÍA NINGUNA FORMA de
      // arrepentirte desde la app. Ahora abre el mismo sheet, con copy de
      // cancelar: se borra la MISMA arista saliente, pero para el usuario no es
      // "eliminar" nada — todavía no hay vínculo que eliminar.
      return _FollowPill(
        label: 'SOLICITUD ENVIADA',
        style: _FollowPillStyle.outlinedMuted,
        semanticsLabel: AppL10n.of(context).feedFollowButtonRequestedA11y,
        onTap: () => _showUnfriendSheet(
          outgoing,
          mode: UnfollowSheetMode.cancelRequest,
        ),
      );
    }

    // Sin arista saliente. Sólo acá tiene sentido mirar la entrante.
    if (incoming != null && incoming.status == FollowStatus.pending) {
      return _FollowPill(
        label: 'ACEPTAR',
        style: _FollowPillStyle.mintFilled,
        busy: _busy,
        semanticsLabel: AppL10n.of(context).feedFollowButtonAcceptA11y,
        onTap: _busy ? null : () => _onAccept(repo, incoming),
      );
    }

    // Incluye el caso "me sigue pero yo no a él": la entrante aceptada no me
    // convierte en seguidor suyo, así que el pill ofrece SEGUIR.
    return _FollowPill(
      label: 'SEGUIR',
      style: _FollowPillStyle.mintFilled,
      busy: _busy,
      semanticsLabel: AppL10n.of(context).feedFollowButtonFollowA11y,
      onTap: _busy ? null : () => _onRequest(repo),
    );
  }

  /// Sends a follow request, surfacing success/failure to the user.
  ///
  /// Previously this was a fire-and-forget `catch (_)` that left the SEGUIR
  /// pill unchanged on failure (the user assumed success). It now reports both
  /// outcomes via the root [ScaffoldMessenger] and gates re-taps with [_busy].
  Future<void> _onRequest(FollowRepository repo) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture container + messenger + copy BEFORE the await: the profile route
    // may be popped during the write, after which `context` is unmounted. The
    // root container and messenger survive disposal (ADR-FPS-006), so the
    // invalidation y el SnackBar llegan igual.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    // Auto-accept path (public target) surfaces the same "started following"
    // copy the accept flow uses. The pending path keeps the existing
    // "request sent" copy. i18n: Fase W2 — both strings already exist.
    // Dos caminos, dos mensajes: sobre cuenta pública la arista nace aceptada
    // (ya la seguís), sobre cuenta privada queda pendiente de aprobación.
    // Antes los dos decían "Ahora son amigos", que con el modelo dirigido
    // sería directamente falso en el caso pendiente.
    final successMessage = widget.targetIsPublic
        ? l10n.feedFollowStartedSuccess
        : l10n.feedRequestSentSuccess;
    final errorMessage = l10n.feedFriendActionError;
    try {
      await repo.follow(
        widget.viewerUid,
        widget.targetUid,
        targetIsPublic: widget.targetIsPublic,
      );
      // followEdgeProvider se auto-actualiza vía .snapshots() — no hace falta
      // invalidarlo. Sobre cuenta privada SEGUIR sólo crea una arista pending,
      // que no entra en myFollowingFeedProvider; sobre cuenta pública nace
      // accepted, así que ahí sí hay que refrescar el feed.
      if (widget.targetIsPublic) {
        container.invalidate(myFollowingFeedProvider);
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      // The pill stays as SEGUIR (the stream won't emit on failure); tell the
      // user the request did not go through so they can retry instead of
      // assuming it succeeded.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Accepts a received request, surfacing success/failure to the user.
  Future<void> _onAccept(FollowRepository repo, Follow incoming) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture the root container + messenger BEFORE the await: accepting
    // changes the accepted-friends list and the profile route may be popped
    // during the write, after which `ref`/`context` from this widget can
    // silently no-op (ADR-FPS-006). The container and messenger live at the
    // root and survive disposal.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    final successMessage = l10n.feedRequestAcceptedSuccess;
    final errorMessage = l10n.feedFriendActionError;
    try {
      await repo.acceptRequest(incoming.id, widget.viewerUid);
      // followEdgeProvider se auto-actualiza ante la mutación de Firestore.
      // myFollowingFeedProvider (still a FutureProvider) MUST be invalidated
      // explicitly — Riverpod does NOT auto-cascade to providers with no
      // active listener at the moment (ADR-FPS-006).
      container.invalidate(myFollowingFeedProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      // On failure the feed is NOT invalidated and the pill stays as ACEPTAR;
      // surface the error so the user can retry instead of silently swallowing.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the unfriend confirmation bottom sheet.
  ///
  /// Resolves the display name from [userPublicProfileProvider] with a fallback
  /// of "Usuario anónimo". On ELIMINAR, calls [FollowRepository.deleteEdge]
  /// sobre la arista SALIENTE — **nunca toca la inversa**: dejar de seguir
  /// corta un solo sentido, y si el otro me sigue eso queda intacto.
  /// Stream providers self-update — sólo [myFollowingFeedProvider] necesita
  /// invalidación explícita.
  Future<void> _showUnfriendSheet(
    Follow outgoing, {
    UnfollowSheetMode mode = UnfollowSheetMode.unfollow,
  }) async {
    final palette = AppPalette.of(context);
    final profileAsync = ref.read(userPublicProfileProvider(widget.targetUid));
    final friendDisplayName =
        profileAsync.valueOrNull?.displayName ?? 'Usuario anónimo';

    final repo = ref.read(followRepositoryProvider);
    // Capture the root container + messenger + copy BEFORE awaiting the sheet:
    // the delete runs from the sheet's onConfirm (a root route that outlives
    // this profile) and the profile may already be popped by then. This
    // widget's `ref` THROWS once the State is disposed ("Cannot use ref after
    // the widget was disposed"), and the catch below would report a committed
    // delete as a failure while Feed AMIGOS keeps the ex-friend. Same capture
    // as _onAccept (ADR-FPS-006); the container and messenger live at the root
    // and survive disposal.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final errorMessage = AppL10n.of(context).feedFriendActionError;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => UnfriendConfirmationSheet(
        friendDisplayName: friendDisplayName,
        mode: mode,
        onConfirm: () async {
          try {
            await repo.deleteEdge(outgoing.id);
            // Stream providers self-update on Firestore mutation.
            // myFollowingFeedProvider (FutureProvider) MUST be invalidated
            // explicitly — accepted friends list changed, Feed AMIGOS must
            // refresh.
            container.invalidate(myFollowingFeedProvider);
          } catch (_) {
            // La arista sigue viva (el delete no commiteó);
            // surface the failure so the user can retry instead of swallowing.
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(errorMessage)));
          }
        },
      ),
    );
  }
}

enum _FollowPillStyle { mintFilled, outlined, outlinedMuted }

class _FollowPill extends StatelessWidget {
  const _FollowPill({
    required this.label,
    required this.style,
    required this.onTap,
    required this.semanticsLabel,
    this.leadingIcon,
    this.busy = false,
  });

  final String label;
  final _FollowPillStyle style;
  final VoidCallback? onTap;

  /// Lo que anuncia el lector de pantalla. Distinto por estado — el label
  /// visible es una sola palabra y no dice qué pasa al tocar.
  final String semanticsLabel;

  final IconData? leadingIcon;

  /// When true the pill shows an inline spinner in place of the leading icon,
  /// signalling the edge write is in flight (the caller also nulls
  /// [onTap] to block re-taps).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final Color bg;
    final Color textColor;
    final Color borderColor;
    switch (style) {
      case _FollowPillStyle.mintFilled:
        bg = palette.accent;
        textColor = palette.bg;
        borderColor = palette.accent;
        break;
      case _FollowPillStyle.outlined:
        bg = Colors.transparent;
        textColor = palette.textPrimary;
        borderColor = palette.border;
        break;
      case _FollowPillStyle.outlinedMuted:
        bg = Colors.transparent;
        textColor = palette.textMuted;
        borderColor = palette.border;
        break;
    }

    final pill = TreinoTappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              ),
              const SizedBox(width: 8),
            ] else if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 14, color: textColor),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.0,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );

    // El label visible es una sola palabra en mayúsculas ("SEGUIR"); el lector
    // de pantalla necesita saber QUÉ pasa al tocar, y los 4 estados tienen que
    // sonar distinto entre sí.
    final labelled = Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticsLabel,
      child: ExcludeSemantics(child: pill),
    );

    if (style == _FollowPillStyle.outlinedMuted) {
      return Opacity(opacity: 0.6, child: labelled);
    }
    return labelled;
  }
}
