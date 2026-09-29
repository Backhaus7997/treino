import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';

import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';

/// Rutas que el PF puede ver desde un TELÉFONO, excepción acotada al flujo de
/// pago (ADR-CHW-004 sólo bloquea, esto abre un agujero angosto adentro).
///
/// El mail del tope de plan (`trainerWebCheckout()`,
/// `functions/src/mail/templates.ts`) manda `app.gettreino.com/?to=facturacion`
/// — el PF lo abre desde el teléfono, y hasta ahora [MobileBanner] lo frenaba
/// ahí mismo, sin forma de pagar. El resto del Coach Hub sigue siendo
/// escritorio-only: esta excepción NO es "aflojar el breakpoint", es una
/// puerta angosta para UNA sola ruta.
///
/// `/facturacion/planes` alcanza: el `back_url` de Mercado Pago
/// (`createPreapproval`, `BACK_URL = trainerWebCheckout()`) es la MISMA URL
/// que trajo al PF la primera vez, así que la vuelta del pago cae en el mismo
/// destino fino — no hace falta una ruta aparte para "volver del checkout".
/// Las rutas de preview/dev (`/facturacion/preview*`) y el autoservicio de
/// alumnos bloqueados (`kBlockedStudentsRoutePath`) quedan afuera: no son
/// parte del camino de pago.
const Set<String> _kMobileAllowedRoutes = {'/facturacion/planes'};

/// `true` si [path] es una de las rutas que [CoachHubScaffold] deja pasar en
/// viewport `mobile` en vez de reemplazar todo por [MobileBanner].
bool isMobileFacturacionRoute(String path) =>
    _kMobileAllowedRoutes.any(path.startsWith);

/// Shell mínimo para el PF que llega a `/facturacion/planes` desde un
/// teléfono: sin sidebar ni top bar de escritorio (no caben, y no hay nada más
/// del Coach Hub para navegar desde acá — ver [isMobileFacturacionRoute]).
///
/// Sólo un encabezado con la marca y "cerrar sesión" — el mismo `signOut`
/// directo que usa `ajustes_screen.dart` y `coach_hub_not_allowed_screen.dart`
/// — y el `child` (la pantalla de planes) en el resto de la pantalla.
class MobileFacturacionShell extends StatelessWidget {
  const MobileFacturacionShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _MobileFacturacionHeader(palette: palette),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _MobileFacturacionHeader extends StatelessWidget {
  const _MobileFacturacionHeader({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Misma altura que `CoachHubTopBar` — no comparten widget porque esa
      // barra asume sidebar + título de sección, que acá no existen.
      height: CoachHubLayoutTokens.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
      child: Row(
        children: [
          Text(
            'TREINO',
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.highlight,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          TreinoIconButton(
            icon: TreinoIcon.signOut,
            tooltip: 'Cerrar sesión', // i18n: Fase W3
            color: palette.textMuted,
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
    );
  }
}
