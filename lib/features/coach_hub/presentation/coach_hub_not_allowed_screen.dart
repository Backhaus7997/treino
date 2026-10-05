import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';

Future<void> _cerrarSesionFirebase() => FirebaseAuth.instance.signOut();

/// Screen que se muestra cuando un athlete (o user sin role=trainer)
/// entra al Coach Hub web.
///
/// Le explica que la web es solo para entrenadores, le nombra App Store y
/// Play Store SIN links (la app todavía no está publicada, no hay URL que
/// apuntar), le ofrece contactar al equipo por `mailto:` y cerrar sesión.
/// Nada más es usable desde acá.
///
/// Los dos efectos entran por seams para poder probarla sin plataforma:
/// - [abrirUrl]: abre el `mailto:`.
/// - [cerrarSesion]: va DIRECTO a Firebase Auth. NO pasa por
///   `AuthService.signOut()`/`AuthNotifier.signOut()`: ese camino espera
///   `GoogleSignIn` web, cuyo `initialize()` el Hub nunca llama, y se cuelga.
class CoachHubNotAllowedScreen extends ConsumerStatefulWidget {
  const CoachHubNotAllowedScreen({
    super.key,
    this.abrirUrl = launchUrl,
    this.cerrarSesion = _cerrarSesionFirebase,
  });

  final Future<bool> Function(Uri url) abrirUrl;
  final Future<void> Function() cerrarSesion;

  @override
  ConsumerState<CoachHubNotAllowedScreen> createState() =>
      _CoachHubNotAllowedScreenState();
}

class _CoachHubNotAllowedScreenState
    extends ConsumerState<CoachHubNotAllowedScreen> {
  bool _signingOut = false;
  String? _error;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await widget.cerrarSesion();
      // El router redirige automáticamente al /login via refreshListenable.
      // No reseteamos _signingOut: la screen se desmonta en el redirect.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppL10n.of(context).coachHubSignOutError;
        _signingOut = false;
      });
    }
  }

  void _contactar() {
    final asunto = AppL10n.of(context).coachHubNotAllowedMailSubject;
    // `query:` + `encodeComponent`, NO `queryParameters`: éste codifica el
    // espacio como `+`, que en un `mailto:` los clientes muestran literal.
    widget.abrirUrl(
      Uri(
        scheme: 'mailto',
        path: kLegalContactEmail,
        query: 'subject=${Uri.encodeComponent(asunto)}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  TreinoIcon.lock,
                  color: palette.textMuted,
                  size: 64,
                ),
                const SizedBox(height: AppSpacing.s18),
                Text(
                  'COACH HUB',
                  style: GoogleFonts.barlowCondensed(
                    color: palette.highlight,
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  l10n.coachHubNotAllowedTitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: AppTextSize.display,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    height: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.s14),
                Text(
                  l10n.coachHubNotAllowedBody,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: AppTextSize.body,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),
                Text(
                  l10n.coachHubNotAllowedContactPrompt,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: AppTextSize.body,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                TreinoButton(
                  label: l10n.coachHubNotAllowedContactCta,
                  icon: TreinoIcon.mail,
                  expand: true,
                  onPressed: _contactar,
                ),
                const SizedBox(height: AppSpacing.s8),
                // Visible como texto: sin cliente de mail configurado el
                // `mailto:` no hace nada y la dirección hay que poder copiarla.
                SelectableText(
                  kLegalContactEmail,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    color: palette.textPrimary,
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),
                TreinoButton(
                  label: l10n.authProfileSignOut,
                  icon: TreinoIcon.signOut,
                  variant: TreinoButtonVariant.secondary,
                  expand: true,
                  loading: _signingOut,
                  onPressed: _signOut,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.s14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.barlow(
                      color: palette.danger,
                      fontSize: AppTextSize.bodyDense,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
