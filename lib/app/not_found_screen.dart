import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_l10n.dart';
import 'theme/app_background.dart';
import 'theme/app_palette.dart';

/// Router-level 404, shown by [buildRouter]'s `errorBuilder` when a location has
/// no matching route (an unknown path or a malformed deep-link). Replaces
/// go_router's default red "page not found" page with a branded screen and a
/// way back to Home. QA-NAV-002.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.notFoundTitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.notFoundBody,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: Text(l10n.notFoundCta),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
