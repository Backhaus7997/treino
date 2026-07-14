import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

/// Pantalla completa que reemplaza el shell del Coach Hub en viewports móviles
/// (`< 768 px`, ADR-CHW-004, REQ-CHW-RESPONSIVE-002).
///
/// El Coach Hub es una herramienta de escritorio; en móvil el PF usa la app
/// nativa. Sin sidebar, sin top bar, sin chrome del shell — solo el mensaje.
class MobileBanner extends StatelessWidget {
  const MobileBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Coach Hub en escritorio', // i18n: Fase W1
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Coach Hub no está optimizado para móvil — usá la app.', // i18n: Fase W1
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
