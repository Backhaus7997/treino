import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/auth_notifier.dart';
import '../application/auth_providers.dart';
import '../../../l10n/app_l10n.dart';
import '../domain/auth_failure.dart';
import '../domain/email_password_validator.dart';
import 'widgets/auth_failure_banner.dart';
import 'widgets/auth_input.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_screen_header.dart';
import 'widgets/auth_social_buttons.dart';
import 'widgets/auth_switch_link.dart';
import 'widgets/password_strength_bar.dart';
import 'widgets/terms_checkbox.dart';
import 'widgets/terms_notice_text.dart';
import 'widgets/trainer_inquiry_card.dart';
import 'package:treino/core/widgets/treino_toast.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  /// Qué botón social dispara el OAuth en curso (spinner en ese botón).
  AuthSocialProvider? _pendingProvider;

  /// Error del último intento disparado DESDE ESTA pantalla. Es estado local a
  /// propósito: el `AsyncError` de `authNotifierProvider` es global y sobrevive
  /// a la navegación, así que leído directo pegaba «Email o contraseña
  /// incorrectos» de Login en Registro hasta el próximo login exitoso (QA 07).
  /// Al ser del `State`, se va con la pantalla: salir, volver atrás o cambiar
  /// de pantalla de auth lo limpia sin tocar el notifier ni el router.
  AuthFailure? _failure;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _termsAccepted = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_onFieldChanged);
    _passwordCtrl.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String _lastEmail = '';
  String _lastPassword = '';

  /// Editar email o contraseña invalida el error del intento anterior. Sólo
  /// cuenta el TEXTO: el controller también notifica cambios de selección
  /// (tocar el campo), y eso no tiene por qué borrar el aviso.
  void _onFieldChanged() {
    final edited =
        _emailCtrl.text != _lastEmail || _passwordCtrl.text != _lastPassword;
    _lastEmail = _emailCtrl.text;
    _lastPassword = _passwordCtrl.text;
    setState(() {
      if (edited) _failure = null;
    });
  }

  /// Corre una acción del notifier y se queda con SU resultado. Se lee el
  /// estado justo después del `await`, antes de que otra pantalla pueda
  /// disparar nada, así que el error es el de este intento y no uno heredado.
  Future<void> _attempt(Future<void> Function(AuthNotifier n) action) async {
    setState(() => _failure = null);
    await action(ref.read(authNotifierProvider.notifier));
    if (!mounted) return;
    final state = ref.read(authNotifierProvider);
    setState(() {
      _failure = state.hasError && state.error is AuthFailure
          ? state.error as AuthFailure
          : null;
    });
  }

  bool get _fieldsEmpty =>
      _emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty;

  bool get _canSubmit => !_fieldsEmpty && _termsAccepted;

  // La navegación post-registro NO vive acá: la resuelve `authRedirect`
  // (app/router.dart). Ni bien authNotifier emite el user, RouterRefreshNotifier
  // re-dispara el redirect; ese gate se bloquea mientras userProfileProvider
  // carga y recién con el snapshot real manda a /profile-setup (perfil
  // incompleto, que es SIEMPRE el caso recién registrado) o a /home. El viejo
  // `context.go('/home')` manual corría una carrera contra ese stream:
  // adelantaba el redirect, HomeScreen alcanzaba a pintar y el gate rebotaba a
  // /profile-setup — flicker visible en el 100% de los registros nuevos
  // (issue #499). Mismo criterio que ya se aplicó en ProfileSetupFlow (audit F3).

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // No displayName at signup — populated by ProfileSetup in Etapa 6 (REQ-AUTH-002).
    await _attempt(
      (n) => n.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    // Terms must be accepted even when registering with Google — the OAuth
    // flow still creates a TREINO account. Surface a snackbar instead of
    // silently doing nothing so the user knows what is missing.
    if (!_termsAccepted) {
      showTreinoToast(
        context,
        'Aceptá los Términos y la Política de Privacidad para continuar',
        type: TreinoToastType.error,
      );
      return;
    }
    setState(() => _pendingProvider = AuthSocialProvider.google);
    await _attempt((n) => n.signInWithGoogle());
  }

  Future<void> _signInWithApple() async {
    // Same Terms gate as Google: Apple Sign-In also creates a TREINO account
    // on first sign-in, so the user must accept Terms first.
    if (!_termsAccepted) {
      showTreinoToast(
        context,
        'Aceptá los Términos y la Política de Privacidad para continuar',
        type: TreinoToastType.error,
      );
      return;
    }
    setState(() => _pendingProvider = AuthSocialProvider.apple);
    await _attempt((n) => n.signInWithApple());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    // El spinner sigue girando después de un alta exitosa: la pantalla queda
    // montada hasta que `authRedirect` resuelve el perfil, y un CTA que vuelve
    // a "listo" en ese hueco lee como que el tap no hizo nada (issue #499).
    // Estando logueado en una ruta pública el único desenlace es el redirect.
    final isLoading = authState.isLoading || authState.valueOrNull != null;
    final failure = _failure;

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: AppBackground(
        child: SafeArea(
          // Mismo patrón que Login: el bloque de abajo queda al pie en pantallas
          // altas y todo scrollea en teléfonos chicos o con el teclado.
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TreinoFadeSlideIn(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              AuthScreenHeader(
                                title: l10n.authRegisterHeaderTitle,
                                onBack: () => context.canPop()
                                    ? context.pop()
                                    : context.go('/welcome'),
                              ),
                              const SizedBox(height: 20),
                              // Email (sin nombre: lo pide ProfileSetup).
                              AuthInput(
                                controller: _emailCtrl,
                                label: l10n.authRegisterEmailLabel,
                                leadingIcon: TreinoIcon.mail,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                focusNode: _emailFocus,
                                nextFocusNode: _passwordFocus,
                                autofillHints: const [AutofillHints.email],
                                validator: EmailPasswordValidator.validateEmail,
                              ),
                              const SizedBox(height: 14),
                              AuthInput(
                                controller: _passwordCtrl,
                                label: l10n.authRegisterPasswordLabel,
                                leadingIcon: TreinoIcon.lock,
                                obscureText: true,
                                suffixToggle: true,
                                textInputAction: TextInputAction.done,
                                focusNode: _passwordFocus,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                validator:
                                    EmailPasswordValidator.validatePassword,
                              ),
                              const SizedBox(height: 4),
                              // Strength bar — pegada al input por diseño.
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _passwordCtrl,
                                builder: (_, value, __) =>
                                    PasswordStrengthBar(password: value.text),
                              ),
                              const SizedBox(height: 14),
                              TermsCheckbox(
                                value: _termsAccepted,
                                onChanged: (v) =>
                                    setState(() => _termsAccepted = v),
                              ),
                              const SizedBox(height: 20),
                              if (failure != null) ...[
                                AuthFailureBanner(failure: failure),
                                const SizedBox(height: 12),
                              ],
                              AuthPillButton(
                                label: l10n.authRegisterCta,
                                onPressed: _canSubmit ? _submit : null,
                                isLoading: isLoading,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                l10n.authRegisterOrSignUpWith,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.barlow(
                                  fontSize: AppTextSize.body,
                                  color: palette.textMuted,
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Google/Apple quedan habilitados sin importar el
                              // checkbox para que el tap dé feedback explícito
                              // (toast) en vez de parecer un control apagado;
                              // el gate de Términos vive en _signInWith*.
                              AuthSocialButtons(
                                onGoogle: isLoading ? null : _signInWithGoogle,
                                onApple: isLoading ? null : _signInWithApple,
                                pending: isLoading ? _pendingProvider : null,
                              ),
                              const SizedBox(height: 14),
                              const TermsNoticeText(),
                            ],
                          ),
                        ),
                        TreinoFadeSlideIn(
                          delay: AppMotion.stagger(1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 20),
                              const TrainerInquiryCard(),
                              const SizedBox(height: 8),
                              // `pushReplacement`: ver el comentario en Login.
                              AuthSwitchLink(
                                prompt: l10n.authRegisterHaveAccount,
                                action: l10n.authRegisterSignInLink,
                                onTap: () => context.pushReplacement('/login'),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
