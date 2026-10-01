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
  const VerifyMailScreen({super.key, @visibleForTesting this.ahora});

  /// Reloj de la cuenta regresiva. `null` ⇒ `DateTime.now`. Se inyecta en los
  /// tests porque `pump` adelanta el tiempo falso pero no `DateTime.now`.
  final DateTime Function()? ahora;

  /// Tiene que coincidir con `REENVIO_COOLDOWN_MS` del backend: si fuera más
  /// corto, el botón diría «enviado» y el servidor no mandaría nada.
  static const cooldown = Duration(seconds: 60);

  @override
  ConsumerState<VerifyMailScreen> createState() => _VerifyMailScreenState();
}

class _VerifyMailScreenState extends ConsumerState<VerifyMailScreen> {
  final _codigo = TextEditingController();
  Timer? _timer;

  /// Cuándo se puede pedir otro código. La cuenta regresiva se calcula contra
  /// esto y no restando por tick: un `Timer.periodic` no repone los ticks que
  /// se pierde con la app en segundo plano, y con esperas de hasta 24 h el
  /// usuario que vuelve del mail vería una espera vieja.
  DateTime? _hasta;
  int _reenviarEn = 0;
  bool _enviando = false;
  bool _verificando = false;
  bool _verificado = false;

  /// El último pedido contestó «limitado»: la espera es de minutos u horas y se
  /// cuenta con [_reenviarEn], pero se muestra en minutos u horas (ver [build]).
  bool _limitado = false;
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

  DateTime _ahora() => (widget.ahora ?? DateTime.now)();

  /// Segundos que faltan hasta [_hasta], hacia arriba: el botón nunca se
  /// habilita antes de lo que dijo el servidor.
  void _recalcularEspera() {
    final faltan = _hasta?.difference(_ahora()).inMilliseconds ?? 0;
    _reenviarEn = faltan <= 0 ? 0 : (faltan / 1000).ceil();
  }

  /// [tope] acota un valor absurdo del servidor. El cooldown es de 60 s; los
  /// topes de envíos del backend esperan hasta 24 h.
  void _arrancarCuentaRegresiva(
    Duration espera, {
    Duration tope = const Duration(minutes: 10),
  }) {
    _timer?.cancel();
    final segundos = (espera.inMilliseconds / 1000).ceil();
    _hasta = _ahora().add(Duration(seconds: segundos.clamp(1, tope.inSeconds)));
    setState(_recalcularEspera);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(_recalcularEspera);
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
        _limitado = r.estado == SolicitudDeCodigo.limitado;
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
          case SolicitudDeCodigo.limitado:
            // Mientras corre la espera, `build` muestra los minutos que faltan;
            // este es el texto que queda cuando termina.
            _aviso = 'Ya podés pedir otro código.'; // i18n
          case SolicitudDeCodigo.noSalio:
            _error = 'No pudimos mandar el código. Probá de nuevo.'; // i18n
        }
      });
      if (r.estado == SolicitudDeCodigo.enviado) {
        _arrancarCuentaRegresiva(VerifyMailScreen.cooldown);
      } else if (r.estado == SolicitudDeCodigo.enfriando) {
        _arrancarCuentaRegresiva(r.reintentarEn ?? VerifyMailScreen.cooldown);
      } else if (r.estado == SolicitudDeCodigo.limitado) {
        _arrancarCuentaRegresiva(
          r.reintentarEn ?? VerifyMailScreen.cooldown,
          tope: const Duration(hours: 24),
        );
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
            // Ya no hay nada que esperar: sin esto, el «Pediste muchos
            // códigos…» taparía este aviso.
            _timer?.cancel();
            _hasta = null;
            _reenviarEn = 0;
            _limitado = false;
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
    final enEsperaPorTope = _limitado && _reenviarEn > 0;
    // Desde 90 min en horas (hacia arriba): «en 1440 min» no se lee.
    final cuanto = _reenviarEn >= 90 * 60
        ? '${(_reenviarEn / 3600).ceil()} h'
        : '${(_reenviarEn / 60).ceil()} min';
    final aviso = enEsperaPorTope
        ? 'Pediste muchos códigos. Probá de nuevo en $cuanto.' // i18n
        : _aviso;

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
                  aviso ??
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
                      _reenviarEn > 0 && !enEsperaPorTope
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
