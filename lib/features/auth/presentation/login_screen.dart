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
import 'widgets/terms_notice_text.dart';
import 'widgets/trainer_inquiry_card.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// Qué botón social dispara el OAuth en curso (spinner en ese botón).
  AuthSocialProvider? _pendingProvider;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(() => setState(() {}));
    _passwordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _fieldsEmpty =>
      _emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty;

  // La navegación post-login NO vive acá: la resuelve `authRedirect`
  // (app/router.dart). Ni bien authNotifier emite el user, RouterRefreshNotifier
  // re-dispara el redirect; ese gate se bloquea mientras userProfileProvider
  // carga y recién con el snapshot real manda a /profile-setup (perfil
  // incompleto) o a /home. El viejo `context.go('/home')` manual corría una
  // carrera contra ese stream: adelantaba el redirect, HomeScreen alcanzaba a
  // pintar y el gate rebotaba a /profile-setup — flicker visible en el 100% de
  // los registros nuevos (issue #499). Mismo criterio que ya se aplicó en
  // ProfileSetupFlow (audit F3).

  Future<void> _submit() async {
    // Error prevention (Nielsen): validate format client-side before the
    // network round-trip, mirroring register_screen.dart.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authNotifierProvider.notifier).signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _pendingProvider = AuthSocialProvider.google);
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
  }

  Future<void> _signInWithApple() async {
    setState(() => _pendingProvider = AuthSocialProvider.apple);
    await ref.read(authNotifierProvider.notifier).signInWithApple();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    // El spinner sigue girando después de un login exitoso: la pantalla queda
    // montada hasta que `authRedirect` resuelve el perfil, y un CTA que vuelve
    // a "listo" en ese hueco lee como que el tap no hizo nada (issue #499).
    // Estando logueado en una ruta pública el único desenlace es el redirect.
    final isLoading = authState.isLoading || authState.valueOrNull != null;
    final failure = authState.hasError && authState.error is AuthFailure
        ? authState.error as AuthFailure
        : null;

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: AppBackground(
        child: SafeArea(
          // SliverFillRemaining(hasScrollBody: false): el bloque de abajo (tarjeta
          // de entrenador + cambio a Registro) queda al pie cuando la pantalla
          // es alta, y todo scrollea en teléfonos chicos o con el teclado.
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
                                title: l10n.authLoginHeaderTitle,
                                onBack: () => context.canPop()
                                    ? context.pop()
                                    : context.go('/welcome'),
                              ),
                              const SizedBox(height: 20),
                              AuthInput(
                                controller: _emailCtrl,
                                hint: l10n.authLoginEmailHint,
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
                                leadingIcon: TreinoIcon.lock,
                                obscureText: true,
                                suffixToggle: true,
                                textInputAction: TextInputAction.done,
                                focusNode: _passwordFocus,
                                onFieldSubmitted: (_) =>
                                    _fieldsEmpty ? null : _submit(),
                                autofillHints: const [AutofillHints.password],
                              ),
                              // Forgot password — right aligned
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () =>
                                      context.push('/forgot-password'),
                                  child: Text(
                                    l10n.authLoginForgot,
                                    style: GoogleFonts.barlow(
                                      fontSize: 14,
                                      color: palette.accent,
                                    ),
                                  ),
                                ),
                              ),
                              if (failure != null) ...[
                                AuthFailureBanner(failure: failure),
                                const SizedBox(height: 12),
                              ],
                              AuthPillButton(
                                label: l10n.authLoginCta,
                                onPressed: _fieldsEmpty ? null : _submit,
                                isLoading: isLoading,
                              ),
                              const SizedBox(height: 20),
                              // Texto plano centrado, sin líneas (como Spotify).
                              Text(
                                l10n.authLoginOrSignInWith,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.barlow(
                                  fontSize: AppTextSize.body,
                                  color: palette.textMuted,
                                ),
                              ),
                              const SizedBox(height: 14),
                              AuthSocialButtons(
                                onGoogle: isLoading ? null : _signInWithGoogle,
                                onApple: isLoading ? null : _signInWithApple,
                                pending: isLoading ? _pendingProvider : null,
                              ),
                              const SizedBox(height: 14),
                              // QA-AUTH-001 (issue #434): Google/Apple crean una
                              // cuenta TREINO igual que Registro — el usuario
                              // tiene que saberlo antes de tocar el botón.
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
                              // `pushReplacement`: reemplaza Login por Registro
                              // y deja la bienvenida abajo. Con `push`, ir y
                              // venir apilaba login→registro→login sin fin.
                              AuthSwitchLink(
                                prompt: l10n.authLoginNoAccount,
                                action: l10n.authLoginRegisterLink,
                                onTap: () =>
                                    context.pushReplacement('/register'),
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
