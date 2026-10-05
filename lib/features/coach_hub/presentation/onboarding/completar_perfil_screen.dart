import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/application/hub_onboarding_controller.dart';
import 'package:treino/features/coach_hub/domain/hub_onboarding_stage.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/onboarding_widgets.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/paso_edad.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/paso_identidad.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/paso_perfil_pf.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_resolving_view.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile_setup/presentation/widgets/born_at_field.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Ancho máximo del contenido: el de `_VerifyMailEnElHub` y las otras
/// pantallas sin shell del Hub, pero con más aire porque acá hay formularios.
const double _kAnchoMaximo = 560;

Future<void> _cerrarSesionFirebase() => FirebaseAuth.instance.signOut();

/// `/completar-perfil`: el onboarding de un PF que entra al Coach Hub con el
/// perfil incompleto (cuenta web promovida a trainer, #1331).
///
/// Es UNA sola pantalla (design D3): el paso sale de [hubOnboardingStage]
/// aplicado al perfil VIVO, no de la ruta ni de un estado propio. Así un PF
/// que solo falla la edad ve únicamente `age`, y el paso siguiente aparece
/// solo cuando la escritura se refleja en el perfil.
///
/// Sin shell: ni sidebar ni navegación a otras secciones mientras falte algo.
/// Por eso el único escape es «Cerrar sesión», que va DIRECTO a Firebase Auth.
/// NO pasa por `AuthService.signOut()` ni `AuthNotifier.signOut()`: ese camino
/// espera `GoogleSignIn` web, cuyo `initialize()` el Hub nunca llama, y se
/// cuelga (mismo motivo que `CoachHubNotAllowedScreen`).
///
/// No hay «Cancelar cuenta» ni salida a `/welcome`: el PF promovido ya tiene
/// alumnos y pagos asociados; borrar la cuenta no es una decisión que se tome
/// desde un onboarding.
class CompletarPerfilScreen extends ConsumerStatefulWidget {
  const CompletarPerfilScreen({
    super.key,
    this.cerrarSesion = _cerrarSesionFirebase,
    this.elegirFecha = pickBornAt,
  });

  /// Seam del efecto de cerrar sesión, para probar sin plataforma.
  final Future<void> Function() cerrarSesion;

  /// Seam del date picker del paso `age`.
  final ElegirFecha elegirFecha;

  @override
  ConsumerState<CompletarPerfilScreen> createState() =>
      _CompletarPerfilScreenState();
}

class _CompletarPerfilScreenState extends ConsumerState<CompletarPerfilScreen> {
  bool _cerrando = false;
  String? _errorAlCerrar;

  /// Etapa que se está mostrando. Mientras hay una escritura en curso (o fallada)
  /// queda FIJA: el perfil optimista puede saltar a otra etapa (o a `done`) antes
  /// de que el servidor confirme, y si lo rechaza el perfil revierte. Desmontar
  /// el paso en el medio perdería lo que el PF tipeó (el estado vive en el
  /// `State` del paso). Se suelta cuando la escritura termina bien.
  HubOnboardingStage? _etapaFijada;

  Future<void> _cerrarSesion() async {
    if (_cerrando) return;
    setState(() {
      _cerrando = true;
      _errorAlCerrar = null;
    });
    try {
      await widget.cerrarSesion();
      // El router manda al /login por el refreshListenable; la pantalla se
      // desmonta en el redirect, así que no se resetea `_cerrando`.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorAlCerrar = AppL10n.of(context).coachHubSignOutError;
        _cerrando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(userProfileProvider).valueOrNull;
    final escritura = ref.watch(hubOnboardingControllerProvider);
    final viva = perfil == null ? null : hubOnboardingStage(perfil);
    final fijar = (escritura.isLoading || escritura.hasError) &&
        _etapaFijada != null &&
        _etapaFijada != HubOnboardingStage.done;
    if (!fijar) _etapaFijada = viva;
    final etapa = _etapaFijada;
    // Sin perfil todavía, o con la etapa `done` (el gate está por soltarlo):
    // la vista de carga neutra, no un formulario vacío.
    if (etapa == null || etapa == HubOnboardingStage.done) {
      return const CoachHubResolvingView();
    }

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s20),
          child: ConstrainedBox(
            key: const ValueKey('completar-perfil-contenido'),
            constraints: const BoxConstraints(maxWidth: _kAnchoMaximo),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                switch (etapa) {
                  HubOnboardingStage.age =>
                    PasoEdad(elegirFecha: widget.elegirFecha),
                  HubOnboardingStage.identity => const PasoIdentidad(),
                  HubOnboardingStage.pf => const PasoPerfilPf(),
                  HubOnboardingStage.done => const SizedBox.shrink(),
                },
                const SizedBox(height: AppSpacing.s20),
                TreinoButton(
                  label: l10n.authProfileSignOut,
                  icon: TreinoIcon.signOut,
                  variant: TreinoButtonVariant.secondary,
                  expand: true,
                  loading: _cerrando,
                  onPressed: _cerrarSesion,
                ),
                if (_errorAlCerrar != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  OnboardingError(_errorAlCerrar!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
