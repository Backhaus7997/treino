import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Shows a modal bottom sheet explaining why location permission is needed.
///
/// Returns `true` if the user tapped "ACEPTAR", `false` if "Ahora no".
/// The caller is responsible for then invoking [AthleteLocationNotifier.requestPermission]
/// when the result is `true`.
///
/// Per design D8: rationale sheet shown BEFORE the OS system dialog.
/// REQ-COACH-DISC-UI-011.
Future<bool> showLocationPermissionRationaleSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _LocationRationaleSheet(),
  );
  return result ?? false;
}

/// Class-style wrapper for [showLocationPermissionRationaleSheet] so callers
/// can use `LocationPermissionRationaleSheet.show(context)`.
class LocationPermissionRationaleSheet {
  const LocationPermissionRationaleSheet._();

  static Future<bool> show(BuildContext context) =>
      showLocationPermissionRationaleSheet(context);
}

class _LocationRationaleSheet extends StatelessWidget {
  const _LocationRationaleSheet();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.espresso,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: palette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Icon(TreinoIcon.mapPin, size: 48, color: palette.accent),
          const SizedBox(height: 16),
          Text(
            l10n.coachLocationSheetTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 22,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.coachLocationSheetBody,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                l10n.coachLocationSheetAccept,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              l10n.coachLocationSheetDeny,
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
