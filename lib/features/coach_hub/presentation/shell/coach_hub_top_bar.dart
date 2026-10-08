import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';

import 'sidebar_registry.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';

/// Top bar del Coach Hub web (REQ-SH-007). 64 px de alto.
///
/// - El toggle contraer/expandir del sidebar vive en el footer del sidebar
///   (ver `CoachHubSidebar`). El breadcrumb de sección se reemplaza por el
///   título de la sección activa (Barlow Condensed 700 UPPERCASE), derivado
///   de `sidebarRegistry` vía [activeSidebarItem] — sin nueva capa de datos.
/// - **Centro**: vacío. Vivía ahí un campo de búsqueda `enabled: false`, con
///   su lupa y su placeholder «Buscar alumnos, rutinas, plan…», esperando «una
///   fase posterior» que nunca llegó. Un control que se ve operable y no hace
///   NADA es peor que la ausencia: el PF lo tipeaba y no pasaba nada. Cuando la
///   búsqueda exista de verdad, vuelve — con su lógica.
/// - **Derecha**: campana inerte (ODQ-4, sin badge). La cuenta vive solamente
///   en la fila de perfil del sidebar; duplicarla acá creaba tres accesos a la
///   misma pantalla y repartía preferencias entre superficies distintas.
class CoachHubTopBar extends StatelessWidget {
  const CoachHubTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final location = GoRouterState.of(context).uri.toString();
    final title = activeSidebarItem(location)?.label.toUpperCase() ?? '';

    return Container(
      height: CoachHubLayoutTokens.topBarHeight,
      color: palette.bg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
      child: Row(
        children: [
          // `Expanded` y NO `Flexible` + `Spacer`.
          //
          // Los dos parecen equivalentes acá y no lo son: `Flexible` y `Spacer`
          // tienen ambos `flex: 1`, así que se REPARTEN el espacio libre en
          // partes iguales — el título usa lo que necesita, el resto de SU
          // mitad se pierde, y la campana queda a media barra en vez de pegada
          // al borde. Medido: 461 px de distancia al borde derecho.
          //
          // Con `Expanded` el título se lleva todo el sobrante y empuja la
          // campana hasta el final. El ellipsis sigue haciendo falta: hoy los
          // rótulos salen de `sidebarRegistry` y son cortos, pero traducidos no
          // hay número que podamos fijar.
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: AppFonts.w700,
                fontSize: 24,
                letterSpacing: 0.5,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s20),
          TreinoIconButton(
            icon: TreinoIcon.bell,
            tooltip: 'Notificaciones', // i18n: Fase W1
            color: palette.textMuted,
            onPressed: () {}, // ODQ-4: visible pero inerte en W1
          ),
        ],
      ),
    );
  }
}
