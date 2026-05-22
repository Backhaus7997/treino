import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../application/friendship_providers.dart';
import '../domain/friendship.dart';
import 'widgets/friend_request_inbox_tile.dart';

/// Inbox screen listing pending friend requests received by the current user.
///
/// Does NOT own a [Scaffold] — relies on [_ShellScaffold] via the router
/// (REQ-FRI-CX-005 / design Section 5.2).
///
/// Subscriptions:
/// - [authStateChangesProvider] → myUid (null = anonymous race)
/// - [pendingRequestsStreamProvider(myUid)] → [AsyncValue<List<Friendship>>]
class FriendRequestsInboxScreen extends ConsumerWidget {
  const FriendRequestsInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final myUid =
        ref.watch(authStateChangesProvider).valueOrNull?.uid;

    final requestsAsync =
        ref.watch(pendingRequestsStreamProvider(myUid ?? ''));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InboxHeader(palette: palette),
        Expanded(
          child: requestsAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: palette.accent),
            ),
            error: (_, __) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'No pudimos cargar las solicitudes. Intentá de nuevo.',
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'No hay solicitudes pendientes',
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        color: palette.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.separated(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => FriendRequestInboxTile(
                  friendship: list[i],
                  viewerUid: myUid ?? '',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _InboxHeader extends StatelessWidget {
  const _InboxHeader({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
            child: Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
          ),
          const SizedBox(width: 14),
          Text(
            'SOLICITUDES',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
