import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/auth_providers.dart';
import '../data/mail_verification_service.dart';
import 'widgets/auth_input.dart';
import 'widgets/auth_pill_button.dart';

/// Gate obligatorio: confirmar el mail con el código de 6 dígitos.
///
/// Lo pasan TODAS las cuentas —también Google y Apple— antes de usar la app
/// (decisión de producto, 2026-10-01). El router lo exige mientras
/// `correoVerificadoParaElRol` dé false: no hay entrada de
/// `users/{uid}.emailVerification` para el rol de hoy con el mail de Auth de
/// hoy. La escribe solo la Cloud Function `verificarCodigoDeMail`
/// (`functions/src/auth/codigo-de-verificacion.ts`).
///
/// ── Lo que esta pantalla NO dice, a propósito ──
///
/// El mail que lleva el código también explica que los pagos van por mail y
/// trae un botón a los planes. Acá no se menciona NADA de eso: un «revisá el
/// mail para pagar» impreso en el binario es un llamado a comprar afuera, y
/// con eso se cae la exención 3.1.3(f). La pantalla solo pide el código; el
/// mail hace el resto. `verify_mail_screen_superficie_test.dart` lo vigila.
///
/// ── Salir de acá ──
///
/// No navega a mano después de validar: espera el snapshot del perfil con
/// `emailVerification`, y el router la saca sola (mismo criterio que
/// `BirthDateGateScreen`). Navegar antes que el dato correría una carrera con
/// el stream y podría rebotar de vuelta.
class VerifyMailScreen extends ConsumerStatefulWidget {
  const VerifyMailScreen({super.key});

  /// Tiene que coincidir con `REENVIO_COOLDOWN_MS` del backend: si fuera más
  /// corto, el botón diría «enviado» y el servidor no mandaría nada.
  static const cooldown = Duration(seconds: 60);

  @override
  ConsumerState<VerifyMailScreen> createState() => _VerifyMailScreenState();
}

class _VerifyMailScreenState extends ConsumerState<VerifyMailScreen> {
  final _codigo = TextEditingController();
  Timer? _timer;
  int _reenviarEn = 0;
  bool _enviando = false;
  bool _verificando = false;
  bool _verificado = false;
  String? _aviso;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codigo.addListener(() => setState(() {}));
    // El pedido AUTOMÁTICO: si ya hay un código vigente el servidor no manda
    // otro, así el que el usuario tiene en la bandeja sigue sirviendo.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _pedir(reenviar: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codigo.dispose();
    super.dispose();
  }

  String get _email =>
      ref.read(firebaseAuthProvider).currentUser?.email ?? 'tu mail';

  void _arrancarCuentaRegresiva(Duration espera) {
    _timer?.cancel();
    setState(() => _reenviarEn = espera.inSeconds.clamp(1, 600));
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _reenviarEn = _reenviarEn > 0 ? _reenviarEn - 1 : 0);
      if (_reenviarEn == 0) t.cancel();
    });
  }

  Future<void> _pedir({required bool reenviar}) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(mailVerificationServiceProvider)
          .solicitar(reenviar: reenviar);
      if (!mounted) return;
      setState(() {
        _enviando = false;
        switch (r.estado) {
          case SolicitudDeCodigo.enviado:
            _aviso = reenviar
                ? 'Te mandamos un código nuevo a $_email.' // i18n
                : 'Te mandamos un código de 6 dígitos a $_email.'; // i18n
            if (reenviar) _codigo.clear();
          case SolicitudDeCodigo.vigente:
            _aviso = 'Ya te mandamos un código a $_email. Si no lo '
                'encontrás, revisá spam o pedí otro.'; // i18n
          case SolicitudDeCodigo.yaVerificado:
            _aviso = 'Tu mail ya está confirmado.'; // i18n
          case SolicitudDeCodigo.enfriando:
            _aviso = 'Esperá un momento para pedir otro código.'; // i18n
          case SolicitudDeCodigo.noSalio:
            _error = 'No pudimos mandar el código. Probá de nuevo.'; // i18n
        }
      });
      if (r.estado == SolicitudDeCodigo.enviado) {
        _arrancarCuentaRegresiva(VerifyMailScreen.cooldown);
      } else if (r.estado == SolicitudDeCodigo.enfriando) {
        _arrancarCuentaRegresiva(r.reintentarEn ?? VerifyMailScreen.cooldown);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = 'No pudimos mandar el código. Revisá tu conexión y '
            'probá de nuevo.'; // i18n
      });
    }
  }

  Future<void> _verificar() async {
    final codigo = _codigo.text.trim();
    if (codigo.length != 6 || _verificando) return;
    setState(() {
      _verificando = true;
      _error = null;
    });
    try {
      final r =
          await ref.read(mailVerificationServiceProvider).verificar(codigo);
      if (!mounted) return;
      setState(() {
        _verificando = false;
        switch (r.estado) {
          case VerificacionDeCodigo.verificado:
            // El router la saca cuando llega el perfil con la marca.
            _verificado = true;
            _aviso = 'Listo, mail confirmado.'; // i18n
          case VerificacionDeCodigo.incorrecto:
            final n = r.intentosRestantes;
            _error = n == null
                ? 'El código no coincide.' // i18n
                : n == 1
                    ? 'El código no coincide. Te queda 1 intento.' // i18n
                    : 'El código no coincide. Te quedan $n intentos.'; // i18n
          case VerificacionDeCodigo.vencido:
            _error = 'El código venció. Pedí uno nuevo.'; // i18n
          case VerificacionDeCodigo.bloqueado:
            _error = 'Usaste todos los intentos de este código. Pedí uno '
                'nuevo.'; // i18n
          case VerificacionDeCodigo.sinCodigo:
            _error = 'No tenemos un código pendiente. Pedí uno nuevo.'; // i18n
          case VerificacionDeCodigo.formatoInvalido:
            _error = 'El código tiene 6 números.'; // i18n
          case VerificacionDeCodigo.desconocido:
            _error = 'No pudimos confirmar el código. Probá de nuevo.'; // i18n
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _error = 'No pudimos confirmar el código. Revisá tu conexión y '
            'probá de nuevo.'; // i18n
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final signingOut = ref.watch(authNotifierProvider).isLoading;
    final puedeConfirmar =
        _codigo.text.trim().length == 6 && !_verificando && !_verificado;
    final puedeReenviar = _reenviarEn == 0 && !_enviando && !_verificado;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CONFIRMÁ TU MAIL', // i18n
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: AppTextSize.displayLarge,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _aviso ??
                      'Te estamos mandando un código de 6 dígitos a '
                          '$_email.', // i18n
                  key: const Key('verify_mail_aviso'),
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: AppTextSize.body,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                AuthInput(
                  key: const Key('verify_mail_code_field'),
                  controller: _codigo,
                  hint: '000000', // i18n
                  leadingIcon: TreinoIcon.mail,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _verificar(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const Key('verify_mail_error'),
                    style: GoogleFonts.barlow(
                      color: palette.danger,
                      fontSize: AppTextSize.bodyDense,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                AuthPillButton(
                  key: const Key('verify_mail_confirm'),
                  label: 'CONFIRMAR', // i18n
                  isLoading: _verificando || _verificado,
                  showArrow: false,
                  onPressed: puedeConfirmar ? _verificar : null,
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    key: const Key('verify_mail_resend'),
                    onPressed:
                        puedeReenviar ? () => _pedir(reenviar: true) : null,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.textMuted,
                    ),
                    child: Text(
                      _reenviarEn > 0
                          ? 'Reenviar código en $_reenviarEn s' // i18n
                          : 'Reenviar código', // i18n
                    ),
                  ),
                ),
                Center(
                  child: TextButton.icon(
                    key: const Key('verify_mail_sign_out'),
                    onPressed: signingOut
                        ? null
                        : () =>
                            ref.read(authNotifierProvider.notifier).signOut(),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.textMuted,
                    ),
                    icon: const Icon(TreinoIcon.signOut, size: 18),
                    label: const Text('Cerrar sesión'), // i18n
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
