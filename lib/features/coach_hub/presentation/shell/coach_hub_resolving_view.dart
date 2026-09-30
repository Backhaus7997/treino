import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_brand_logo.dart';

/// Alto del wordmark — el mismo que le da el splash móvil (`splash_screen.dart`)
/// a su pantalla de marca mientras se resuelve la sesión.
const double _kBrandLogoSize = 64;

/// Vista de carga que ocupa el lugar del `MobileBanner` en un teléfono mientras
/// el Coach Hub todavía no sabe quién entró (ver
/// `coachHubSessionResolvingProvider`).
///
/// Es deliberadamente neutra: fondo del tema, el wordmark oficial centrado y un
/// indicador de progreso chico, sin ningún mensaje. El banner, en cambio, le
/// pedía al PF que se fuera a la app justo cuando el router estaba por llevarlo
/// a la pantalla de planes.
///
/// Es una pantalla completa, sin sidebar ni top bar, igual que el banner al que
/// reemplaza.
class CoachHubResolvingView extends StatelessWidget {
  const CoachHubResolvingView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CoachHubBrandLogo(size: _kBrandLogoSize),
            const SizedBox(height: AppSpacing.s20),
            // `textMuted` y no `accent`: es una carga discreta, y el mint pleno
            // sobre un fondo claro compone 1,57:1 (`AGENTS.md` §2). `textMuted`
            // mide 6,24:1 contra `bg` en dark y 5,67:1 en light.
            SizedBox(
              width: AppSpacing.s20,
              height: AppSpacing.s20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.textMuted,
                semanticsLabel: 'Cargando', // i18n: Fase W1
              ),
            ),
          ],
        ),
      ),
    );
  }
}
