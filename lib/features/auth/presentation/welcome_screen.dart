import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/contact/quiero_ser_entrenador.dart';
import '../../../core/widgets/treino_toast.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import 'legal/legal_content.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/account_deletion_notifier.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/terms_notice_text.dart';
import 'widgets/trainer_inquiry_card.dart';
import '../../../core/widgets/treino_logo.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.abrirUrl = launchUrl});

  /// Abre el `mailto:` de «Quiero ser entrenador». Seam para probarlo sin
  /// plataforma, igual que en `CoachHubNotAllowedScreen`.
  final Future<bool> Function(Uri url) abrirUrl;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Show "Tu cuenta fue eliminada" SnackBar when the deletion flag is set.
    ref.listen<bool>(accountDeletedFlagProvider, (_, isDeleted) {
      if (!isDeleted) return;
      // Reset flag immediately so the snackbar only shows once.
      ref.read(accountDeletedFlagProvider.notifier).state = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          showTreinoToast(
            context,
            'Tu cuenta fue eliminada', // i18n: Fase 6 Etapa 3
            type: TreinoToastType.success,
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
                      TreinoFadeSlideIn(
                        child: Column(
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
                                  left: BorderSide(
                                      width: 3, color: palette.accent),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _headlineLine(
                                      palette,
                                      light: l10n.authBrandHeadline1Light,
                                      bold: l10n.authBrandHeadline1Bold,
                                    ),
                                    _headlineLine(
                                      palette,
                                      light: l10n.authBrandHeadline2Light,
                                      bold: l10n.authBrandHeadline2Bold,
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
                      ),
                      // ── Bottom block: EMPEZAR + INICIAR SESIÓN + tarjeta ─
                      // Sin social acá: Google/Apple viven en Login y Registro,
                      // donde el usuario ya eligió qué quiere hacer.
                      TreinoFadeSlideIn(
                        delay: AppMotion.stagger(1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthPillButton(
                              label: l10n.authWelcomeCta,
                              onPressed: () => context.push('/register'),
                              showArrow: false,
                            ),
                            const SizedBox(height: 12),
                            AuthPillButton(
                              key: const Key('welcome-sign-in'),
                              label: l10n.authWelcomeSignIn,
                              onPressed: () => context.push('/login'),
                              showArrow: false,
                              outlined: true,
                            ),
                            const SizedBox(height: 24),
                            // Misma tarjeta violeta que Login y Registro, pero
                            // abre el mail directo (ver _contactarParaSerEntrenador).
                            Semantics(
                              button: true,
                              child: TrainerInquiryCard(
                                onTap: _contactarParaSerEntrenador,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // EMPEZAR lleva a crear la cuenta: el aviso de lo
                            // que se acepta va también acá, no sólo en Registro.
                            const TermsNoticeText(
                              lead: TermsNoticeText.leadGeneric,
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
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

  /// Acceso «Quiero ser entrenador». No hay alta self-service de PF —el rol lo
  /// asigna el equipo por Admin SDK—, así que lleva al mismo mail de contacto
  /// que la pantalla de no-autorizado del Coach Hub, no a un registro.
  Future<void> _contactarParaSerEntrenador() async {
    final l10n = AppL10n.of(context);
    var abierto = false;
    try {
      abierto = await widget.abrirUrl(
        mailtoQuieroSerEntrenador(l10n.coachHubNotAllowedMailSubject),
      );
    } catch (_) {
      // Sin handler de `mailto:` la plataforma lanza o devuelve false; los dos
      // casos se tratan igual: avisar con la dirección escrita.
      abierto = false;
    }
    if (abierto || !mounted) return;
    showTreinoToast(
      context,
      l10n.authWelcomeBecomeTrainerFallback(kLegalContactEmail),
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
