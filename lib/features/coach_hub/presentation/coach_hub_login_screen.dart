import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/primitives.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../../app/theme/tokens/components/treino_button_tokens.dart';
import '../../auth/domain/auth_failure.dart';
import '../../auth/presentation/legal/legal_content.dart';
import '../../auth/presentation/widgets/terms_notice_text.dart';
import '../../../core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_brand_logo.dart';

/// Alto del wordmark sobre el título «COACH HUB» (32 px): 1,5× el título, para
/// que la marca encabece y el nombre del producto no quede chico. El login
/// móvil usa 56 sobre un titular de 28; acá el título es más grande.
const double _kBrandLogoSize = 48;

/// Login screen del Coach Hub web.
///
/// Tres caminos de ingreso: email/password, Google y Apple. Google y Apple
/// entran por popup de Firebase Auth (`signInWithPopup`), no por redirect:
/// el Hub se sirve desde dos hosts y, según el análisis del change, el
/// redirect sufre el particionado de storage de terceros mientras el popup
/// funciona cross-origin. El popup exige que `signInWithPopup` se invoque
/// sin ningún `await` previo al tap, o el navegador lo bloquea.
///
/// La pantalla NO decide a dónde se va después del ingreso: lo decide el
/// router (`coachHubRedirect`) al cambiar el estado de auth.
///
/// Ver `openspec/changes/coach-hub-login-google-apple/`, que supera la
/// decisión #2 de `coach-hub-bootstrap` (solo email/password).
///
/// Layout: form centrado max-width 400px sobre fondo dark. Funciona ok
/// en desktop y tablet — sin breakpoints responsivos en MVP (decisión #4).
class CoachHubLoginScreen extends ConsumerStatefulWidget {
  const CoachHubLoginScreen({super.key});

  @override
  ConsumerState<CoachHubLoginScreen> createState() =>
      _CoachHubLoginScreenState();
}

/// Qué método de ingreso tiene una operación en curso.
enum _Metodo { email, google, apple }

class _CoachHubLoginScreenState extends ConsumerState<CoachHubLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  _Metodo? _enCurso;
  String? _error;

  /// `true` cuando el error mostrado es `providerUnavailable`: el copy manda
  /// a «escribinos al equipo» y el Hub no tiene otro canal que esta pantalla,
  /// así que mostramos la dirección (REQ-CHW-AUTH-004).
  bool _errorEsProveedorNoDisponible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_enCurso != null) return;
    if (!_formKey.currentState!.validate()) return;
    await _ingresar(
      _Metodo.email,
      () => ref.read(authNotifierProvider.notifier).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ),
    );
  }

  /// Google/Apple por popup. El navegador sólo concede la ventana si se abre
  /// dentro del gesto del usuario: NO puede haber un `await` entre el tap y
  /// la llamada al notifier. Por eso es un método síncrono que arranca la
  /// llamada de inmediato.
  void _entrarConGoogle() => _ingresar(
        _Metodo.google,
        () => ref.read(authNotifierProvider.notifier).signInWithGooglePopup(),
      );

  void _entrarConApple() => _ingresar(
        _Metodo.apple,
        () => ref.read(authNotifierProvider.notifier).signInWithApplePopup(),
      );

  /// Marca el método en curso, dispara [accion] (síncrono hasta su primer
  /// await) y espera el resultado.
  Future<void> _ingresar(_Metodo metodo, Future<void> Function() accion) async {
    if (_enCurso != null) return;
    setState(() {
      _enCurso = metodo;
      _error = null;
      _errorEsProveedorNoDisponible = false;
    });
    await accion();
    // El notifier captura errores internamente (AsyncValue.guard) y los
    // pone en state. Después del await leemos el state actual: si hay
    // error, lo mostramos; si no (éxito o cancel del popup, que el notifier
    // restaura en silencio), el router redirige solo al /dashboard o
    // /not-allowed via el authStateChangesProvider.
    if (!mounted) return;
    final state = ref.read(authNotifierProvider);
    if (state.hasError) {
      final l10n = AppL10n.of(context);
      setState(() {
        _error = _humanizeError(state.error!, l10n);
        _errorEsProveedorNoDisponible = state.error is AuthFailure &&
            (state.error! as AuthFailure).maybeWhen(
              providerUnavailable: () => true,
              orElse: () => false,
            );
        _enCurso = null;
      });
    } else {
      setState(() => _enCurso = null);
    }
  }

  /// Convierte el error del notifier a un mensaje legible para el user.
  ///
  /// Si el error es un `AuthFailure` (lo que tira `AuthService` cuando
  /// Firebase rechaza credentials), usamos su `userMessage` ya
  /// localizado — ADR-I18N-002: `AuthFailure.userMessage` queda hardcoded
  /// en es-AR porque el domain layer no tiene BuildContext. El fallback
  /// genérico sí es localizable via AppL10n.
  String _humanizeError(Object e, AppL10n l10n) {
    if (e is AuthFailure) {
      return e.userMessage;
    }
    return l10n.coachHubLoginGenericError;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand stack
                    Center(
                      child: Column(
                        children: [
                          // El wordmark oficial —el mismo de welcome, login y
                          // register del móvil y del sidebar—, no la palabra
                          // "TREINO" tipeada en Barlow Condensed. El color lo
                          // resuelve por tema: esta pantalla se ve en claro u
                          // oscuro según el sistema (ver [CoachHubBrandLogo]).
                          const CoachHubBrandLogo(size: _kBrandLogoSize),
                          const SizedBox(height: AppSpacing.s12),
                          Text(
                            'COACH HUB',
                            style: GoogleFonts.barlowCondensed(
                              color: palette.textPrimary,
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.coachHubLoginPrompt,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(
                        color: palette.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _emailController,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      style: TextStyle(color: palette.textPrimary),
                      decoration: _inputDecoration(
                          palette, l10n.coachHubLoginEmailLabel),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return l10n.coachHubLoginEmailRequired;
                        }
                        if (!v.contains('@')) {
                          return l10n.coachHubLoginEmailInvalid;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      style: TextStyle(color: palette.textPrimary),
                      decoration: _inputDecoration(
                          palette, l10n.coachHubLoginPasswordLabel),
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return l10n.coachHubLoginPasswordRequired;
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.danger, fontSize: 13),
                      ),
                      if (_errorEsProveedorNoDisponible) ...[
                        const SizedBox(height: AppSpacing.s8),
                        SelectableText(
                          kLegalContactEmail,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.accentText,
                            fontSize: AppTextSize.caption,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 18),
                    TreinoButton(
                      label: l10n.coachHubLoginSubmit,
                      expand: true,
                      loading: _enCurso == _Metodo.email,
                      onPressed: _enCurso == null ? _submit : null,
                    ),
                    const SizedBox(height: AppSpacing.s18),
                    Row(
                      children: [
                        Expanded(child: Divider(color: palette.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s12,
                          ),
                          child: Text(
                            l10n.authLoginContinueWith,
                            style: GoogleFonts.barlowCondensed(
                              fontSize: AppTextSize.caption,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: palette.border)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s14),
                    // Google/Apple crean una cuenta TREINO como el registro:
                    // el aviso va ANTES de los botones.
                    const TermsNoticeText(),
                    const SizedBox(height: AppSpacing.s14),
                    Row(
                      children: [
                        Expanded(
                          child: TreinoButton(
                            label: l10n.authGoogleLabel,
                            icon: TreinoIcon.googleLogo,
                            variant: TreinoButtonVariant.secondary,
                            expand: true,
                            loading: _enCurso == _Metodo.google,
                            onPressed:
                                _enCurso == null || _enCurso == _Metodo.google
                                    ? _entrarConGoogle
                                    : null,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: TreinoButton(
                            label: l10n.authAppleLabel,
                            icon: TreinoIcon.appleLogo,
                            variant: TreinoButtonVariant.secondary,
                            expand: true,
                            loading: _enCurso == _Metodo.apple,
                            onPressed:
                                _enCurso == null || _enCurso == _Metodo.apple
                                    ? _entrarConApple
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.coachHubLoginFooter,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(AppPalette palette, String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: palette.textMuted),
      filled: true,
      fillColor: palette.bgCard,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.danger, width: 1.5),
      ),
    );
  }
}
