import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/check_in_providers.dart';

/// Full-screen dialog shown on FeedScreen mount once per session when the user
/// has not yet checked in today. REQ-WRC-005.
///
/// Accepts [gymId] and [gymName] pre-resolved by FeedScreen from the user's
/// profile — NO GPS lookup inside this widget (ADR-WRS-17).
class CheckInDialog extends ConsumerWidget {
  const CheckInDialog({
    super.key,
    required this.gymId,
    required this.gymName,
  });

  /// The user's configured gym id, or null if not set. REQ-WRC-009.
  final String? gymId;

  /// The gym display name resolved by the caller (see
  /// `gyms/domain/gym_display_name.dart`), or null.
  final String? gymName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    final l10n = AppL10n.of(context);
    final subtext = (gymId != null && gymName != null && gymName!.isNotEmpty)
        ? l10n.checkInGymSubtext(gymName!)
        : l10n.checkInNeutralSubtext;

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.mapPin, color: palette.accent, size: 48),
            const SizedBox(height: 18),
            Text(
              l10n.checkInHeader,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtext,
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _NoButton(
                    onPressed: () => Navigator.of(context).pop(),
                    palette: palette,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SiButton(
                    gymId: gymId,
                    gymName: gymName,
                    palette: palette,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoButton extends StatelessWidget {
  const _NoButton({required this.onPressed, required this.palette});

  final VoidCallback onPressed;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: palette.border),
        foregroundColor: palette.textPrimary,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        AppL10n.of(context).checkInNoButton,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _SiButton extends ConsumerWidget {
  const _SiButton({
    required this.gymId,
    required this.gymName,
    required this.palette,
  });

  final String? gymId;
  final String? gymName;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Disable while the confirm() write is in flight so a rapid double-tap
    // cannot fire two confirm() calls before the first completes.
    final isLoading = ref.watch(checkInNotifierProvider).isLoading;

    return ElevatedButton(
      onPressed: isLoading
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final errorText = AppL10n.of(context).checkInError;

              await ref
                  .read(checkInNotifierProvider.notifier)
                  .confirm(gymId: gymId, gymName: gymName);

              // confirm() swallows write failures into AsyncValue.guard, so the
              // only signal of failure is the notifier state. Surface errors
              // instead of closing on a write that never persisted; keep the
              // dialog open so the user can retry.
              if (ref.read(checkInNotifierProvider).hasError) {
                messenger.showSnackBar(SnackBar(content: Text(errorText)));
                return;
              }
              navigator.pop();
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.bg,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        AppL10n.of(context).checkInSiButton,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}
