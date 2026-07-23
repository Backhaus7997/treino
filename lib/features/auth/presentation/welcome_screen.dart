import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../application/auth_providers.dart';
import '../domain/auth_failure.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/account_deletion_notifier.dart';
import 'widgets/auth_failure_banner.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_secondary_button.dart';
import 'widgets/terms_notice_text.dart';
import 'widgets/treino_logo.dart';

/// Identifies which social provider button is currently awaiting its OAuth
/// round-trip, so only that button shows an in-flight spinner.
enum _SocialProvider { google, apple }

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  /// The provider button the user last tapped. Used to scope the loading
  /// spinner to the tapped button while authNotifierProvider.isLoading is true.
  _SocialProvider? _pendingProvider;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final authState = ref.watch(authNotifierProvider);
    // El spinner del botón tapeado sigue girando después de un OAuth exitoso:
    // la pantalla queda montada hasta que `authRedirect` resuelve el perfil, y
    // un botón que vuelve a su glifo en ese hueco lee como que el tap no hizo
    // nada (issue #499). Estando logueado en una ruta pública el único
    // desenlace es el redirect.
    final isLoading = authState.isLoading || authState.valueOrNull != null;
    final failure = authState.hasError && authState.error is AuthFailure
        ? authState.error as AuthFailure
        : null;

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
          // SliverFillRemaining(hasScrollBody: false) sizes the content to fill
          // the viewport so the CTAs sit at the bottom, but lets it grow and
          // scroll when the viewport is short or text is scaled up. This is the
          // safe replacement for the old `IntrinsicHeight + Spacer` pattern,
          // where the Spacers had no intrinsic height (could throw "RenderBox
          // was not laid out") and the nested IntrinsicHeight was O(N²) (F2).
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ── Top block: eyebrow + logo + headline + body ──────
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 48),
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
                              // Flexible + ellipsis so the eyebrow never
                              // overflows on narrow screens or with large OS
                              // text scaling.
                              Flexible(
                                child: Text(
                                  l10n.authWelcomeEyebrow,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.barlowCondensed(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.5,
                                    color: palette.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const TreinoLogo(size: 120),
                          const SizedBox(height: 24),
                          // Headline with a left accent bar. A left Border on a
                          // DecoratedBox spans the child's height automatically
                          // — no IntrinsicHeight needed (replaces the old nested
                          // IntrinsicHeight + full-height Container, F2).
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                left:
                                    BorderSide(width: 3, color: palette.accent),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                        ],
                      ),
                      // ── Bottom block: CTA + social + sign-in link ────────
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Surface social sign-in failures (and OAuth
                          // cancellations) — previously swallowed silently.
                          if (failure != null) ...[
                            AuthFailureBanner(failure: failure),
                            const SizedBox(height: 12),
                          ],
                          AuthPillButton(
                            label: l10n.authWelcomeCta,
                            onPressed: isLoading
                                ? null
                                : () => context.push('/register'),
                            showArrow: false,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: AuthSecondaryButton(
                                  icon: FontAwesomeIcons.google,
                                  // Swap the brand glyph for a spinner while
                                  // this provider's OAuth round-trip is in
                                  // flight, so the screen is not frozen with no
                                  // feedback.
                                  iconWidget: isLoading &&
                                          _pendingProvider ==
                                              _SocialProvider.google
                                      ? _buttonSpinner(palette)
                                      : SvgPicture.asset(
                                          'assets/logo/google_g.svg',
                                          width: 18,
                                          height: 18,
                                        ),
                                  label: l10n.authGoogleLabel,
                                  onPressed:
                                      isLoading ? null : _signInWithGoogle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AuthSecondaryButton(
                                  icon: FontAwesomeIcons.apple,
                                  iconWidget: isLoading &&
                                          _pendingProvider ==
                                              _SocialProvider.apple
                                      ? _buttonSpinner(palette)
                                      : null,
                                  label: l10n.authAppleLabel,
                                  onPressed:
                                      isLoading ? null : _signInWithApple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // QA-AUTH-001 (issue #434): Google/Apple create a
                          // TREINO account just like Register — the user must
                          // be told before tapping the social button.
                          const TermsNoticeText(),
                          const SizedBox(height: 18),
                          // Wrap (not a min-size Row) so the line flows to a
                          // second line instead of overflowing when the text is
                          // long, the screen is narrow, or the font is scaled.
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
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
                          const SizedBox(height: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small spinner shown in place of a social button's brand glyph while its
  /// OAuth call is in flight. Mirrors AuthPillButton's loading indicator.
  Widget _buttonSpinner(AppPalette palette) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(palette.textPrimary),
      ),
    );
  }

  // La navegación post-OAuth NO vive acá: la resuelve `authRedirect`
  // (app/router.dart). Ni bien authNotifier emite el user, RouterRefreshNotifier
  // re-dispara el redirect; ese gate se bloquea mientras userProfileProvider
  // carga y recién con el snapshot real manda a /profile-setup (alta nueva por
  // OAuth) o a /home (usuario existente). El viejo `context.go('/home')` manual
  // corría una carrera contra ese stream: adelantaba el redirect, HomeScreen
  // alcanzaba a pintar y el gate rebotaba a /profile-setup — flicker visible en
  // el 100% de los registros nuevos (issue #499). Mismo criterio que ya se
  // aplicó en ProfileSetupFlow (audit F3).

  Future<void> _signInWithGoogle() async {
    // No intent gating on Welcome — el mismo botón sirve para alta y para
    // login; el destino lo decide el redirect según el perfil que llegue.
    setState(() => _pendingProvider = _SocialProvider.google);
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
  }

  Future<void> _signInWithApple() async {
    setState(() => _pendingProvider = _SocialProvider.apple);
    await ref.read(authNotifierProvider.notifier).signInWithApple();
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
