import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import 'auth_strings.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_secondary_button.dart';
import 'widgets/welcome_glitch_logo.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Radial glow background
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, -0.4),
                radius: 0.8,
                colors: [
                  palette.accent.withValues(alpha: 0.14),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Eyebrow
                  Row(
                    children: [
                      Icon(
                        TreinoIcon.sparkle,
                        color: palette.accent,
                        size: 12,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AuthStrings.welcomeEyebrow,
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Glitch logo (Welcome-screen exclusive)
                  const WelcomeGlitchLogo(fontSize: 52),
                  const SizedBox(height: 18),
                  // Headline block: vertical accent line + mixed-weight text
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Vertical accent line
                        Container(
                          width: 3,
                          color: palette.accent,
                        ),
                        const SizedBox(width: 14),
                        // Headline column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Line 1: "MOVÉS " lighter + "EL HIERRO." bolder
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'MOVÉS ',
                                      style: GoogleFonts.barlowCondensed(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: 0.5,
                                        color: palette.textPrimary,
                                        height: 1.1,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'EL HIERRO.',
                                      style: GoogleFonts.barlowCondensed(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        color: palette.textPrimary,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Line 2: "NOSOTROS " lighter + "EL RESTO." bolder
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'NOSOTROS ',
                                      style: GoogleFonts.barlowCondensed(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: 0.5,
                                        color: palette.textPrimary,
                                        height: 1.1,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'EL RESTO.',
                                      style: GoogleFonts.barlowCondensed(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        color: palette.textPrimary,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Body
                  Text(
                    AuthStrings.welcomeBody,
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: palette.textMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // CTA
                  AuthPillButton(
                    label: AuthStrings.welcomeCta,
                    onPressed: () => context.push('/register'),
                  ),
                  const SizedBox(height: 12),
                  // Social buttons row
                  const Row(
                    children: [
                      Expanded(
                        child: AuthSecondaryButton(
                          icon: TreinoIcon.googleLogo,
                          label: AuthStrings.googleLabel,
                          onPressed: null,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: AuthSecondaryButton(
                          icon: TreinoIcon.appleLogo,
                          label: AuthStrings.appleLabel,
                          onPressed: null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Sign in row
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
        ],
      ),
    );
  }
}
