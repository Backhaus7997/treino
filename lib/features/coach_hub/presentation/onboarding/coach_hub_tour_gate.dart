import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../onboarding/application/onboarding_providers.dart';
import '../../../onboarding/domain/onboarding_surface.dart';
import '../../../onboarding/presentation/onboarding_card_content.dart';
import '../../../onboarding/presentation/onboarding_tour_view.dart';
import '../../../profile/application/user_providers.dart';
import '../../../profile/domain/user_role.dart';
import 'coach_hub_card_copy.dart';

/// Corre el tour del Coach Hub una sola vez, apenas el PF entra.
///
/// Renderiza `SizedBox.shrink()` y empuja el tour a pantalla completa sobre el
/// shell. Se monta DESPUÉS del early-return de `Viewport.mobile` en
/// [CoachHubScaffold]: si se montara antes, un browser angosto vería el tour
/// encima del `MobileBanner`.
///
/// No toca `coachHubRedirect`. En web no hay un momento "post-setup" — el PF
/// llega ya completo desde mobile — así que el disparador natural es el montaje
/// del shell, no una precondición de navegación. Y un gate de router sería peor
/// que en mobile: la única ruta pública del Hub es `/login`, y el "Salir" vive
/// en `CoachHubTopBar`, que una ruta top-level no renderiza.
///
/// Comparte con mobile el flag de Firestore, el controller y la vista del tour.
/// Lo único propio es el copy, en español hardcodeado (constraint del Hub).
class CoachHubTourGate extends ConsumerStatefulWidget {
  const CoachHubTourGate({super.key});

  @override
  ConsumerState<CoachHubTourGate> createState() => _CoachHubTourGateState();
}

class _CoachHubTourGateState extends ConsumerState<CoachHubTourGate> {
  /// Latch de instancia: `userProfileProvider` es un stream y re-emite.
  bool _presenting = false;

  @override
  Widget build(BuildContext context) {
    const surface = OnboardingSurface.trainerWeb;
    final shouldShow = ref.watch(shouldShowTourProvider(surface));
    // Defensivo: `coachHubRedirect` ya manda a `/not-allowed` a cualquiera que
    // no sea trainer, pero el chequeo es barato.
    final role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    if (shouldShow && role == UserRole.trainer && !_presenting) {
      _presenting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final slides = <OnboardingCardContent>[
          for (final module in surface.slides)
            if (coachHubCardContent(module) case final c?) c,
        ];
        if (slides.isEmpty) return;

        ref.read(onboardingTourOpenProvider.notifier).state = true;
        try {
          await Navigator.of(context, rootNavigator: true).push<void>(
            PageRouteBuilder<void>(
              opaque: true,
              barrierDismissible: false,
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              pageBuilder: (routeContext, __, ___) => OnboardingTourView(
                slides: slides,
                // El context de la RUTA, no el de este widget: el gate vive en
                // el shell, y popear con su context cerraría la pantalla.
                onFinish: () => Navigator.of(routeContext).pop(),
                onSkip: () => Navigator.of(routeContext).pop(),
                skipLabel: 'SALTAR', // i18n: Fase W1
                nextLabel: 'SIGUIENTE', // i18n: Fase W1
                finishLabel: 'COMENZAR', // i18n: Fase W1
                stepSemanticsLabel: (c, t) => 'Paso $c de $t', // i18n: Fase W1
              ),
            ),
          );
        } finally {
          if (mounted) {
            ref.read(onboardingTourOpenProvider.notifier).state = false;
          }
          await ref.read(onboardingControllerProvider).markSeen(surface);
        }
      });
    }

    return const SizedBox.shrink();
  }
}
