import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import 'auth_strings.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_secondary_button.dart';
import 'widgets/treino_logo.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          // ── Top block: eyebrow + logo ────────────────────
                          Row(
                            children: [
                              Icon(
                                TreinoIcon.sparkle,
                                color: palette.accent,
                                size: 12,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AuthStrings.welcomeEyebrow,
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                  color: palette.accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const TreinoLogo(size: 56),
                          // ── Spacer pushes the headline toward the middle ─
                          const Spacer(flex: 2),
                          // ── Middle block: headline + body ────────────────
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(width: 3, color: palette.accent),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _headlineLine(
                                        palette,
                                        light: 'MOVÉS ',
                                        bold: 'EL HIERRO.',
                                      ),
                                      _headlineLine(
                                        palette,
                                        light: 'NOSOTROS ',
                                        bold: 'EL RESTO.',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            AuthStrings.welcomeBody,
                            style: GoogleFonts.barlow(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: palette.textMuted,
                              height: 1.5,
                            ),
                          ),
                          // ── Spacer pushes CTAs toward the bottom ─────────
                          const Spacer(flex: 3),
                          // ── Bottom block: CTA + social + sign-in link ────
                          AuthPillButton(
                            label: AuthStrings.welcomeCta,
                            onPressed: () => context.push('/register'),
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Expanded(
                                child: AuthSecondaryButton(
                                  icon: FontAwesomeIcons.google,
                                  label: AuthStrings.googleLabel,
                                  onPressed: null,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: AuthSecondaryButton(
                                  icon: FontAwesomeIcons.apple,
                                  label: AuthStrings.appleLabel,
                                  onPressed: null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${AuthStrings.welcomeHaveAccount} · ',
                                  style: GoogleFonts.barlow(
                                    fontSize: 14,
                                    color: palette.textMuted,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => context.push('/login'),
                                  child: Text(
                                    AuthStrings.welcomeSignIn,
                                    style: GoogleFonts.barlow(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: palette.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _headlineLine(AppPalette palette,
      {required String light, required String bold}) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: light,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
              color: palette.textPrimary,
              height: 1.15,
            ),
          ),
          TextSpan(
            text: bold,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: palette.textPrimary,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
