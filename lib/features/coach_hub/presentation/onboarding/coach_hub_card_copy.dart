import '../../../../core/widgets/treino_icon.dart';
import '../../../onboarding/domain/onboarding_module.dart';
import '../../../onboarding/presentation/onboarding_card_content.dart';
import '../../../onboarding/presentation/onboarding_illustration.dart';

/// Copy for the eight visible sidebar sections.
///
/// Spanish hardcoded with `// i18n` markers — the Hub's constraint
/// (openspec/specs/coach-hub/spec.md, Hard Constraint 5 and C-6 per section),
/// not an oversight. `AppL10n` is deliberately NOT used in this module; when
/// the deferred web-i18n SDD runs, this copy migrates with the rest.
///
/// The section list is the 8 items of `sidebar_registry.dart` after the "W2
/// reduce" — not the ~20 directories on disk, and not the 19 the openspec doc
/// still claims.
OnboardingCardContent? coachHubCardContent(OnboardingModule module) {
  switch (module) {
    case OnboardingModule.webDashboard:
      return const OnboardingCardContent(
        icon: TreinoIcon.sidebarDashboard,
        illustration: OnboardingIllustration.webDashboard(),
        title: 'TU MESA DE TRABAJO', // i18n: Fase W1
        body:
            'El Hub y la app mobile comparten los mismos datos, al instante:', // i18n: Fase W1
        bullets: [
          'Acá ves tu día: sesiones, actividad de tus alumnos y cobros', // i18n: Fase W1
          'El menú de la izquierda se colapsa para ganar ancho', // i18n: Fase W1
          'Lo que edites acá lo ve tu alumno en su teléfono', // i18n: Fase W1
        ],
      );

    case OnboardingModule.webAlumnos:
      return const OnboardingCardContent(
        icon: TreinoIcon.sidebarAlumnos,
        illustration: OnboardingIllustration.webAlumnos(),
        title: 'TUS ALUMNOS', // i18n: Fase W1
        body:
            'Tu lista está acá, pero las solicitudes nuevas no:', // i18n: Fase W1
        bullets: [
          'Las solicitudes de vínculo llegan a la campana, arriba a la derecha', // i18n: Fase W1
          'Abrí un alumno para ver su plan, sus series y su progresión', // i18n: Fase W1
          'Sus medidas y datos personales, solo si te los compartió', // i18n: Fase W1
        ],
      );

    case OnboardingModule.webAgenda:
      return const OnboardingCardContent(
        icon: TreinoIcon.sidebarAgenda,
        illustration: OnboardingIllustration.webAgenda(),
        title: 'TU AGENDA', // i18n: Fase W1
        body:
            'Los turnos con tus alumnos se organizan desde acá:', // i18n: Fase W1
        bullets: [
          'Creás sesiones sueltas o series que se repiten', // i18n: Fase W1
          'Podés bloquear días para que no entren turnos nuevos', // i18n: Fase W1
          'Tu disponibilidad horaria se configura en la app mobile', // i18n: Fase W1
        ],
      );

    case OnboardingModule.webChat:
      return const OnboardingCardContent(
        icon: TreinoIcon.sidebarChat,
        illustration: OnboardingIllustration.webChat(),
        title: 'TUS CONVERSACIONES', // i18n: Fase W1
        body: 'Hablás con cada alumno sin salir del Hub. El chat es el mismo '
            'que ven en su teléfono, así que no se pierde nada.', // i18n: Fase W1
      );

    case OnboardingModule.webBiblioteca:
      return const OnboardingCardContent(
        icon: TreinoIcon.sidebarBiblioteca,
        illustration: OnboardingIllustration.webBiblioteca(),
        title: 'TU BIBLIOTECA', // i18n: Fase W1
        body:
            'El catálogo de ejercicios que usás para armar rutinas:', // i18n: Fase W1
        bullets: [
          'Cada ejercicio trae su video y su técnica', // i18n: Fase W1
          'Podés agregar los tuyos y dejarles notas', // i18n: Fase W1
          'Tus notas las ve el alumno durante la sesión', // i18n: Fase W1
        ],
      );

    case OnboardingModule.webRutinas:
      return const OnboardingCardContent(
        icon: TreinoIcon.sidebarRutinas,
        illustration: OnboardingIllustration.webRutinas(),
        title: 'ARMÁ Y ASIGNÁ PLANES', // i18n: Fase W1
        body:
            'Acá está el editor completo, el trabajo pesado del escritorio:', // i18n: Fase W1
        bullets: [
          'Elegí un alumno y armale la rutina día por día', // i18n: Fase W1
          'También podés importar un plan hecho en Excel', // i18n: Fase W1
          'Al guardar, le aparece en su app', // i18n: Fase W1
        ],
      );

    case OnboardingModule.webPagos:
      return const OnboardingCardContent(
        icon: TreinoIcon.sidebarPagos,
        illustration: OnboardingIllustration.webPagos(),
        title: 'LO QUE TE DEBEN', // i18n: Fase W1
        body: 'El seguimiento de cobros de tus alumnos:', // i18n: Fase W1
        bullets: [
          'Registrás lo que ya cobraste y lo que está pendiente', // i18n: Fase W1
          'TREINO no procesa el pago: lo arreglás con el alumno', // i18n: Fase W1
        ],
      );

    case OnboardingModule.webAjustes:
      return const OnboardingCardContent(
        icon: TreinoIcon.sidebarAjustes,
        illustration: OnboardingIllustration.webAjustes(),
        title: 'TU CUENTA', // i18n: Fase W1
        body:
            'Tus datos, tu foto y lo que ven los alumnos que te buscan. Es la '
            'misma cuenta que usás en la app mobile.', // i18n: Fase W1
      );

    // Mobile modules never reach this resolver — the app owns its own copy,
    // translated through AppL10n.
    case OnboardingModule.home:
    case OnboardingModule.workout:
    case OnboardingModule.feed:
    case OnboardingModule.coach:
    case OnboardingModule.profile:
      return null;
  }
}
