import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_l10n.dart';
import '../application/auth_providers.dart';
import 'widgets/treino_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Surfaces the error state when auth resolution fails so the user is never
  // stranded on a frozen brand screen (finding: AsyncValue error case unhandled).
  bool _hasError = false;

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
    if (_hasError && mounted) {
      setState(() => _hasError = false);
    }
    try {
      await ref.read(authNotifierProvider.future);
    } catch (_) {
      // The Firebase auth stream rejected (network failure on token refresh,
      // init error, etc.). Without this branch the await throws, _navigate()
      // aborts before any context.go(), and the user is stranded forever.
      // Surface an inline error + Reintentar instead of freezing.
      if (!mounted) return;
      setState(() => _hasError = true);
      return;
    }
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
    final l10n = AppL10n.of(context);

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
                  const SizedBox(height: 32),
                  // Visibility of system status: show an error + Reintentar when
                  // auth resolution fails, otherwise a subtle loading spinner so
                  // a slow resolve never looks like a frozen brand screen.
                  if (_hasError)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.authGenericErrorFallback,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: palette.textMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _navigate,
                          style: TextButton.styleFrom(
                            foregroundColor: palette.accent,
                          ),
                          child: Text(l10n.coachRetryLabel),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.accent,
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
