import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../application/onboarding_providers.dart';
import '../domain/onboarding_surface.dart';
import 'custom_exercise_onboarding_slides.dart';
import 'onboarding_card_content.dart';
import 'custom_exercise_onboarding_view.dart';
import '../../../app/theme/tokens/primitives.dart';

/// Runs the "Creá tus propios ejercicios" onboarding once, the first time a
/// user opens the routine editor in CREATE mode.
///
/// Sin issue propia: nace del handoff de diseño "Onboarding Crear Ejercicios",
/// no de un ticket. No confundir con #628, que es otra feature (comentario y
/// foto por ejercicio durante la sesión).
///
/// Call it from `initState` behind an `addPostFrameCallback`: `initState` has no
/// `Localizations` ancestor resolved yet, and the navigator is not ready to
/// present mid-frame.
///
/// ── Why it is a function and not a gate widget ──────────────────────────────
/// The welcome tour uses `OnboardingGate`, an invisible widget in the home
/// shell's `Stack`, because it must fire on whatever screen the user lands on
/// after login. This one is anchored to exactly two screens and must NOT fire
/// on any other, so the trigger belongs at those two call sites. A widget would
/// have to re-derive "am I on the routine editor, in create mode" from state it
/// does not own.
///
/// Everything is `ref.read`, never `watch`: this runs once, imperatively, from
/// a post-frame callback. A `watch` here would rebuild nothing and only risk
/// re-entry when `userProfileProvider` re-emits.
/// [alCrearEjercicio] es lo que hace el CTA "CREAR MI EJERCICIO" al cerrar.
///
/// Lo inyecta el llamador porque el destino NO es el mismo en las dos
/// superficies: en el teléfono es una ruta (`/profile/my-exercises/new`), y en
/// el Coach Hub es un diálogo (`showCreateCustomExerciseDialog`) porque el
/// editor de ejercicios propios no está ruteado ahí. Resolverlo adentro del
/// gate obligaría a que `onboarding` importe `coach_hub`.
///
/// Cuando es null, el móvil usa su ruta por default.
Future<void> maybeShowCustomExerciseOnboarding({
  required BuildContext context,
  required WidgetRef ref,
  required OnboardingSurface surface,
  Future<void> Function()? alCrearEjercicio,
}) async {
  // Wait for the profile before deciding anything. `userProfileProvider` is a
  // STREAM: on the first post-frame it is usually still `AsyncLoading`, so
  // every guard below would read `valueOrNull == null`, conclude "nothing to
  // show" and return — permanently, because this runs once and never retries.
  // The welcome tour does not have this problem: `OnboardingGate` is a widget
  // that WATCHES and re-evaluates on each emission. A one-shot callback has to
  // await instead.
  try {
    await ref.read(userProfileProvider.future);
  } catch (_) {
    // An errored profile stream is already routed to `/profile-unavailable`
    // (#544). Nothing to onboard on top of.
    return;
  }
  if (!context.mounted) return;

  // The welcome tour owns the screen, or is about to. Two modals stacked on one
  // frame is the failure this provider exists to prevent, and it was found on a
  // device rather than in a test — a widget test happily renders both and
  // reports success.
  if (ref.read(onboardingBlocksProvider)) return;

  // En el Coach Hub, `onboardingBlocksProvider` NO alcanza: sólo mira el tour
  // MOBILE (`pendingMobileTourProvider`). Un PF que ya vio `trainerMobile`
  // pero no `trainerWeb`, y cuyo perfil resuelve después de que monta esta
  // pantalla, pasaba el guard de arriba, abría este diálogo, y recién ahí
  // `CoachHubTourGate` rebuildeaba y le empujaba el tour por encima.
  //
  // Se chequea acá y no dentro de `onboardingBlocksProvider` a propósito:
  // sumarlo allá bloquearía las superficies MOBILE por un tour WEB pendiente
  // que en el teléfono no se puede ver, que es peor que el bug original.
  if (surface == OnboardingSurface.customExerciseTrainerWeb &&
      ref.read(shouldShowTourProvider(OnboardingSurface.trainerWeb))) {
    return;
  }

  if (!ref.read(shouldShowTourProvider(surface))) return;

  final slides = customExerciseSlidesFor(surface);
  if (slides == null || slides.isEmpty) return;

  if (!context.mounted) return;
  final l10n = AppL10n.of(context);
  final palette = AppPalette.of(context);
  final isWeb = surface == OnboardingSurface.customExerciseTrainerWeb;

  // Capturados ANTES del await, igual que en `OnboardingGate` (#627). Si un
  // redirect de auth o un reemplazo de ruta desarma el editor con el modal
  // abierto, `context.mounted` es false y el cleanup guardado por él dejaba
  // `onboardingTourOpenProvider` —root-scoped— en `true` para siempre: a
  // partir de ahí `onboardingBlocksProvider` suprime TODO onboarding
  // posterior, incluido el de otro login, hasta reiniciar el proceso. Y el
  // `ref.read` de `markSeen` corría sobre un ref ya dispuesto.
  final tourOpen = ref.read(onboardingTourOpenProvider.notifier);
  final onboardingController = ref.read(onboardingControllerProvider);

  // El CTA dice "CREAR MI EJERCICIO" y hasta ahora sólo cerraba el modal: el
  // gate le pasaba el MISMO `onClose` a `onFinish` y a `onSkip`, así que
  // apretar el botón y saltar hacían lo mismo. Un botón que nombra una acción
  // y no la ejecuta es peor que no tenerlo — el usuario aprende a no creerle.
  //
  // `null` cuando se cerró por arrastre o por back: eso no es el CTA.
  bool? cerroPorCta;

  tourOpen.state = true;
  try {
    if (isWeb) {
      cerroPorCta = await showDialog<bool>(
        context: context,
        // Exits are SALTAR and the CTA. Both persist the flag; a stray click on
        // the scrim should not decide whether the user ever sees this.
        barrierDismissible: false,
        barrierColor: palette.scrimDark.withValues(alpha: 0.66),
        builder: (dialogContext) => _OnboardingDialog(
          slides: slides,
          l10n: l10n,
          onFinish: () => Navigator.of(dialogContext).pop(true),
          onSkip: () => Navigator.of(dialogContext).pop(false),
        ),
      );
    } else {
      cerroPorCta = await showModalBottomSheet<bool>(
        context: context,
        // Without this the sheet is pushed under `_ShellScaffold` and the
        // bottom bar sits on top of it.
        useRootNavigator: true,
        isScrollControlled: true,
        // Se arrastra para abajo con el grabber, como cualquier sheet de iOS.
        // Cerrar así cuenta como visto igual que SALTAR: el `markSeen` del
        // `finally` no distingue cómo se cerró, justamente para esto.
        enableDrag: true,
        // El tap en el scrim sí queda bloqueado: es el gesto que se dispara sin
        // querer, y a diferencia del arrastre no comunica intención.
        isDismissible: false,
        backgroundColor: Colors.transparent,
        barrierColor: palette.scrimDark.withValues(alpha: 0.66),
        builder: (sheetContext) => _OnboardingSheet(
          slides: slides,
          l10n: l10n,
          onFinish: () => Navigator.of(sheetContext).pop(true),
          onSkip: () => Navigator.of(sheetContext).pop(false),
        ),
      );
    }
  } finally {
    tourOpen.state = false;
    // Persist however it closed — CTA, SALTAR, Android back, or a route torn
    // down under us. Marking only on the two buttons is how an onboarding comes
    // back forever for anyone who pressed back once.
    //
    // The controller swallows write failures behind its session flag, so this
    // never throws into the caller's `initState`.
    await onboardingController.markSeen(surface);
  }

  // Después del `finally`: el flag se persiste igual, se navegue o no.
  if (cerroPorCta != true || !context.mounted) return;
  if (alCrearEjercicio != null) {
    await alCrearEjercicio();
    return;
  }
  if (isWeb) {
    // Sin callback y en web no hay a dónde ir: `coach_hub_router.dart` no
    // rutea el editor de ejercicios propios. Antes esto era el único camino;
    // ahora el llamador web inyecta el diálogo.
    return;
  }
  // `/profile/my-exercises/new` — `'new'` es el centinela que abre el editor
  // en blanco (ver `CustomExerciseEditorScreen.isEditing`).
  context.push('/profile/my-exercises/new');
}

/// Mobile presentation: bottom sheet, content owns its chrome.
///
/// Pattern A (transparent host + a `Container` that draws the radius) rather
/// than passing `shape:` to the host — passing both double-paints the corner.
class _OnboardingSheet extends StatelessWidget {
  const _OnboardingSheet({
    required this.slides,
    required this.l10n,
    required this.onFinish,
    required this.onSkip,
  });

  final List<OnboardingCardContent> slides;
  final AppL10n l10n;
  /// Separados a propósito: el CTA navega al editor de ejercicios y SALTAR no.
  /// Con un solo callback para los dos, el botón que dice "CREAR MI EJERCICIO"
  /// no se distinguía de saltear.
  final VoidCallback onFinish;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: CustomExerciseOnboardingView(
            slides: slides,
            onFinish: onFinish,
            onSkip: onSkip,
            skipLabel: l10n.onboardingTourSkip,
            nextLabel: l10n.onboardingTourNext,
            finishLabel: l10n.onboardingCustomExerciseCta,
            stepSemanticsLabel: (current, total) =>
                l10n.onboardingTourProgress(current, total),
          ),
        ),
      ),
    );
  }
}

/// Coach Hub presentation: a centred 780pt card.
class _OnboardingDialog extends StatelessWidget {
  const _OnboardingDialog({
    required this.slides,
    required this.l10n,
    required this.onFinish,
    required this.onSkip,
  });

  final List<OnboardingCardContent> slides;
  final AppL10n l10n;
  /// Separados a propósito: el CTA navega al editor de ejercicios y SALTAR no.
  /// Con un solo callback para los dos, el botón que dice "CREAR MI EJERCICIO"
  /// no se distinguía de saltear.
  final VoidCallback onFinish;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: CustomExerciseOnboardingView(
            slides: slides,
            layout: CustomExerciseOnboardingLayout.dialog,
            onFinish: onFinish,
            onSkip: onSkip,
            skipLabel: l10n.onboardingTourSkip,
            nextLabel: l10n.onboardingTourNext,
            finishLabel: l10n.onboardingCustomExerciseCta,
            stepSemanticsLabel: (current, total) =>
                l10n.onboardingTourProgress(current, total),
          ),
        ),
      ),
    );
  }
}
