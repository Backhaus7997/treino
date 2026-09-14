// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// BibliotecaWebScreen: la biblioteca de EJERCICIOS del PF.
//
// Tuvo una segunda tab, «Templates Rutinas», que se retiró: las plantillas del
// PF se listaban acá Y en la sección Rutinas, y las dos superficies no eran
// equivalentes —ésta las mostraba lindas pero inertes (tap → diálogo de
// detalle; publicar «se hace desde el editor»), mientras Rutinas tiene el menú
// completo: asignar, publicar, sacársela a un alumno, recuperar, eliminar.
// Rutinas quedó como superficie única (#1093 la partió en «Mis plantillas» y
// lo que entrena cada alumno). Con una sola tab, la TabBar se fue con ella.
//
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

import '../../shell/responsive.dart' as rsp;
import 'providers/biblioteca_providers.dart';
import 'widgets/exercise_detail_panel.dart';
import 'widgets/ejercicios_tab.dart';

/// Proporción del ancho disponible que ocupa el drawer de detalle.
///
/// Un cuarto de pantalla, como se pidió. Al superponerse no le saca ancho a la
/// grilla, asi que —a diferencia del layout anterior— no hace falta ningun piso
/// de ancho para que el detalle pueda aparecer.
const double kBibliotecaDrawerFraction = 0.25;

/// Sección Biblioteca del Coach Hub web.
///
/// Sigue el contrato de sección (ADR-CHW-005): sin Scaffold propio, sin
/// SafeArea. El shell [CoachHubScaffold] provee el chrome.
///
/// Una sola cosa: los ejercicios (catálogo + los propios del PF, mergeados).
/// El contador del hero es el total SIN filtrar, para que no baile mientras se
/// filtra la grilla.
///
/// REQ-BIBW-01, REQ-BIBW-02.
/// SCENARIO-BIBW-02a.
class BibliotecaWebScreen extends ConsumerStatefulWidget {
  const BibliotecaWebScreen({super.key});

  @override
  ConsumerState<BibliotecaWebScreen> createState() =>
      _BibliotecaWebScreenState();
}

class _BibliotecaWebScreenState extends ConsumerState<BibliotecaWebScreen> {
  @override
  Widget build(BuildContext context) {
    // Unfiltered exercise count for the stable tab label.
    final unfilteredAsync = ref.watch(bibliotecaUnfilteredCountProvider);
    final ejerciciosN = unfilteredAsync.valueOrNull ?? 0;

    final columna = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header + subtítulo honesto ──────────────────────────────
        // Bloque eager con stagger real (ADR-B7-03): header = índice 0.
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s20,
              AppSpacing.s20,
              0,
            ),
            child: CoachHubSectionHero(
              title: 'Biblioteca', // i18n
              subtitle: '$ejerciciosN ejercicios', // i18n
            ),
          ),
        ),

        // ── Cuerpo ──────────────────────────────────────────────────────────
        // Sin TabBar: quedaba una sola tab. Una TabBar de un solo tab es un
        // encabezado que promete una elección que no existe.
        const Expanded(child: EjerciciosTab()),
      ],
    );

    // El drawer se hospeda ACA y no adentro de `EjerciciosTab` a proposito:
    // pedido explicito de que ocupe todo el alto. Colgado del cuerpo arranca
    // abajo del hero y se queda corto — eran 193 px cuando ademas habia una
    // TabBar arriba.
    final seleccion = ref.watch(bibliotecaSelectedExerciseProvider);
    final esDesktop = rsp.viewportFor(MediaQuery.sizeOf(context).width) ==
        rsp.Viewport.desktop;
    final mostrarDrawer = seleccion != null && esDesktop;

    // El `Stack` va SIEMPRE, tambien con el detalle cerrado y tambien en
    // compact. Antes esto devolvia `columna` pelada cuando no habia seleccion,
    // y al abrir el detalle el arbol pasaba de `Column` en la raiz a
    // `Stack > Column`: Flutter ve otro tipo de widget en la misma posicion,
    // destruye el subarbol y remonta TODO — grilla, scroll y el texto del
    // buscador. Se veia como si la pantalla se reiniciara al cerrar.
    // Con la estructura fija, `columna` conserva su elemento y el drawer solo
    // entra y sale como segundo hijo del Stack.
    return LayoutBuilder(
      builder: (context, constraints) {
        final anchoDrawer = (constraints.maxWidth * kBibliotecaDrawerFraction)
            .clamp(kExerciseDetailPanelMinWidth, constraints.maxWidth);

        return Stack(
          children: [
            Positioned.fill(child: columna),
            if (mostrarDrawer)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: anchoDrawer,
                // Entra deslizando desde el borde derecho. La key es constante a
                // proposito: asi anima al abrir, y al pasar de un ejercicio a
                // otro el contenido se reemplaza en el lugar en vez de salir y
                // volver a entrar.
                child: TweenAnimationBuilder<double>(
                  key: const ValueKey('biblioteca_drawer_slide'),
                  tween: Tween<double>(begin: 1, end: 0),
                  duration: AppMotion.resolve(context, AppMotion.base),
                  curve: AppMotion.standard,
                  builder: (context, t, child) => FractionalTranslation(
                    translation: Offset(t, 0),
                    child: child,
                  ),
                  child: ExerciseDetailPanel(
                    key: const Key('biblioteca_detail_panel'),
                    width: anchoDrawer,
                    exerciseId: seleccion.exerciseId,
                    ownerId: seleccion.ownerId,
                    exerciseName: seleccion.exerciseName,
                    onClose: () {
                      ref
                          .read(bibliotecaSelectedExerciseProvider.notifier)
                          .state = null;
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
