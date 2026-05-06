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
    // Await both: minimum 1500ms AND auth state resolved.
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 1500)),
      ref.read(authNotifierProvider.future).then<void>((_) {}),
    ]);
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
