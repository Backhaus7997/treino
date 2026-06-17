import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';

/// Screen que se muestra cuando un athlete (o user sin role=trainer)
/// entra al Coach Hub web.
///
/// Le explica que el hub es solo para PFs y le ofrece sign-out para
/// volver al login (donde podría usar otra cuenta) o cerrar la pestaña.
class CoachHubNotAllowedScreen extends ConsumerStatefulWidget {
  const CoachHubNotAllowedScreen({super.key});

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
      await FirebaseAuth.instance.signOut();
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
                const SizedBox(height: 18),
                Text(
                  'COACH HUB',
                  style: GoogleFonts.barlowCondensed(
                    color: palette.highlight,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SOLO PARA PFs',
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'El Coach Hub es una herramienta de gestión solo para entrenadores profesionales. Si querés usar TREINO como atleta, descargá la app móvil para Android o iOS.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _signingOut ? null : _signOut,
                  icon: _signingOut
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.textPrimary,
                          ),
                        )
                      : Icon(
                          TreinoIcon.signOut,
                          color: palette.textPrimary,
                          size: 18,
                        ),
                  label: Text(
                    AppL10n.of(context).authProfileSignOut,
                    style: TextStyle(color: palette.textPrimary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.border),
                    minimumSize: const Size.fromHeight(44),
                    shape: const StadiumBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.danger, fontSize: 13),
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
