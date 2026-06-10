import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../application/auth_providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/account_deletion_notifier.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_secondary_button.dart';
import 'widgets/treino_logo.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    // Show "Tu cuenta fue eliminada" SnackBar when the deletion flag is set.
    ref.listen<bool>(accountDeletedFlagProvider, (_, isDeleted) {
      if (!isDeleted) return;
      // Reset flag immediately so the snackbar only shows once.
      ref.read(accountDeletedFlagProvider.notifier).state = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tu cuenta fue eliminada', // i18n: Fase 6 Etapa 3
              ),
            ),
          );
        }
      });
    });

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
                          const Spacer(flex: 3),
                          // ── Top block: eyebrow + logo ────────────────────
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.authWelcomeEyebrow,
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
                          const TreinoLogo(size: 120),
                          const SizedBox(height: 24),
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
                            l10n.authWelcomeBody,
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
                            label: l10n.authWelcomeCta,
                            onPressed: () => context.push('/register'),
                            showArrow: false,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: AuthSecondaryButton(
                                  icon: FontAwesomeIcons.google,
                                  iconWidget: SvgPicture.asset(
                                    'assets/logo/google_g.svg',
                                    width: 18,
                                    height: 18,
                                  ),
                                  label: l10n.authGoogleLabel,
                                  onPressed: isLoading
                                      ? null
                                      : () => _signInWithGoogle(context, ref),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AuthSecondaryButton(
                                  icon: FontAwesomeIcons.apple,
                                  label: l10n.authAppleLabel,
                                  onPressed: isLoading
                                      ? null
                                      : () => _signInWithApple(context, ref),
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
                                  '${l10n.authWelcomeHaveAccount} · ',
                                  style: GoogleFonts.barlow(
                                    fontSize: 14,
                                    color: palette.textMuted,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => context.push('/login'),
                                  child: Text(
                                    l10n.authWelcomeSignIn,
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

  Future<void> _signInWithGoogle(BuildContext context, WidgetRef ref) async {
    // No intent gating on Welcome — both new and existing users land in /home.
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (!context.mounted) return;
    final s = ref.read(authNotifierProvider);
    if (s.hasValue && s.valueOrNull != null) {
      context.go('/home');
    }
  }

  Future<void> _signInWithApple(BuildContext context, WidgetRef ref) async {
    await ref.read(authNotifierProvider.notifier).signInWithApple();
    if (!context.mounted) return;
    final s = ref.read(authNotifierProvider);
    if (s.hasValue && s.valueOrNull != null) {
      context.go('/home');
    }
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
