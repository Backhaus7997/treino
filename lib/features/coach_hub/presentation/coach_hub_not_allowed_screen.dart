import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';

/// Screen que se muestra cuando un athlete (o user sin role=trainer)
/// entra al Coach Hub web.
///
/// Le explica que el hub es solo para PFs y le ofrece sign-out para
/// volver al login (donde podría usar otra cuenta) o cerrar la pestaña.
class CoachHubNotAllowedScreen extends ConsumerWidget {
  const CoachHubNotAllowedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    // El router redirige automáticamente al /login.
                  },
                  icon: Icon(
                    TreinoIcon.signOut,
                    color: palette.textPrimary,
                    size: 18,
                  ),
                  label: Text(
                    'Cerrar sesión',
                    style: TextStyle(color: palette.textPrimary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.border),
                    minimumSize: const Size.fromHeight(44),
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
