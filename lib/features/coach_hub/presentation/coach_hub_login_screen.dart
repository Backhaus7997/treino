import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/auth_failure.dart';

/// Login screen del Coach Hub web.
///
/// Solo email/password — sin Google Sign-In (decisión #2 del propose,
/// google_sign_in_web es scope aparte).
///
/// Layout: form centrado max-width 400px sobre fondo dark. Funciona ok
/// en desktop y tablet — sin breakpoints responsivos en MVP (decisión #4).
class CoachHubLoginScreen extends ConsumerStatefulWidget {
  const CoachHubLoginScreen({super.key});

  @override
  ConsumerState<CoachHubLoginScreen> createState() =>
      _CoachHubLoginScreenState();
}

class _CoachHubLoginScreenState extends ConsumerState<CoachHubLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    await ref.read(authNotifierProvider.notifier).signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    // El notifier captura errores internamente (AsyncValue.guard) y los
    // pone en state. Después del await leemos el state actual: si hay
    // error, lo mostramos; si no, el router redirige automáticamente al
    // /dashboard o /not-allowed via el authStateChangesProvider.
    if (!mounted) return;
    final state = ref.read(authNotifierProvider);
    if (state.hasError) {
      setState(() {
        _error = _humanizeError(state.error!);
        _submitting = false;
      });
    } else {
      setState(() => _submitting = false);
    }
  }

  /// Convierte el error del notifier a un mensaje legible para el user.
  ///
  /// Si el error es un `AuthFailure` (lo que tira `AuthService` cuando
  /// Firebase rechaza credentials), usamos su `userMessage` ya
  /// localizado en español Rioplatense. Sino, fallback genérico.
  String _humanizeError(Object e) {
    if (e is AuthFailure) {
      return e.userMessage;
    }
    return 'No pudimos ingresar. Probá de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
                        Text(
                          'TREINO',
                          style: GoogleFonts.barlowCondensed(
                            color: palette.highlight,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
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
                    'Ingresá con la cuenta que ya usás en la app móvil.',
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
                    decoration: _inputDecoration(palette, 'Email'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Ingresá tu email';
                      }
                      if (!v.contains('@')) {
                        return 'Email inválido';
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
                    decoration: _inputDecoration(palette, 'Contraseña'),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Ingresá tu contraseña';
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
                  ],
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.bg,
                            ),
                          )
                        : Text(
                            'INGRESAR',
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 1.4,
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '¿No tenés cuenta? Creala desde la app móvil TREINO.',
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
