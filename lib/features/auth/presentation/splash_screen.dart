import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../application/auth_providers.dart';
import 'widgets/treino_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Wait only for auth to resolve — no artificial minimum delay (audit Q8:
    // the 1500ms was an accidental placeholder, not a brand requirement). The
    // router's authRedirect does NOT move users off /splash (it is a public
    // route with no redirect rule for it), so this manual navigation is
    // load-bearing — without it the splash would never hand off.
    await ref.read(authNotifierProvider.future);
    if (!mounted) return;

    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user != null) {
      context.go('/home');
    } else {
      context.go('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Radial glow — subtle accent tint in center
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.7,
                colors: [
                  palette.accent.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TreinoLogo(size: 64),
                  const SizedBox(height: 20),
                  // Brand headline — Space Grotesk, mixed weights, centered.
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'MOVÉS ',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.3,
                            color: palette.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        TextSpan(
                          text: 'EL HIERRO.\n',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: palette.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        TextSpan(
                          text: 'NOSOTROS ',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.3,
                            color: palette.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        TextSpan(
                          text: 'EL RESTO.',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: palette.textPrimary,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
