import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../application/auth_providers.dart';
import 'auth_strings.dart';
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TreinoLogo(size: 64),
                const SizedBox(height: 12),
                Text(
                  AuthStrings.splashTagline,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
