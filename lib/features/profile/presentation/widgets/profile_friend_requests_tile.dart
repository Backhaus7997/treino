import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../auth/application/auth_providers.dart';
import '../../../feed/application/friendship_providers.dart';

/// A persistent tile in [ProfileScreen] that shows the count of pending
/// friend requests and navigates to the inbox on tap.
///
/// Always visible, even when count == 0 (locked decision #3 / ADR-FRI-005).
/// Returns 0 during loading/error so the tile never flickers (ADR-FRI-007).
class ProfileFriendRequestsTile extends ConsumerWidget {
  const ProfileFriendRequestsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final myUid =
        ref.watch(authStateChangesProvider).valueOrNull?.uid;
    final count = ref.watch(pendingRequestCountProvider(myUid ?? ''));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GestureDetector(
        onTap: () => context.push('/profile/friend-requests'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: palette.textMuted.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Icon(TreinoIcon.users, size: 20, color: palette.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Solicitudes de amistad ($count)',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Icon(TreinoIcon.chevronRight, size: 16, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
