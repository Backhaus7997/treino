import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../application/auth_providers.dart';
import '../data/mail_verification_service.dart';
import '../domain/alta_reciente.dart';
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
/// Desde cuántos segundos de espera por el tope de envíos se muestra en horas
/// (90 min) y no en minutos.
const _segundosParaHoras = 90 * 60;

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

class _VerifyMailScreenState extends ConsumerState<VerifyMailScreen>
    with WidgetsBindingObserver {
  final _codigo = TextEditingController();
  Timer? _timer;

  /// Cuándo se puede pedir otro código. La cuenta regresiva se calcula contra
  /// esto y no restando por tick: un timer no repone los ticks que se pierde con
  /// la app en segundo plano, y con esperas de hasta 24 h el usuario que vuelve
  /// del mail vería una espera vieja.
  DateTime? _hasta;
  int _reenviarEn = 0;
  bool _enviando = false;
  bool _verificando = false;
  bool _verificado = false;

  /// Está corriendo el borrado de «Me equivoqué de mail». Bloquea todo lo demás.
  bool _borrando = false;

  /// El último pedido contestó «limitado»: la espera es de minutos u horas y se
  /// cuenta con [_reenviarEn], pero se muestra en minutos u horas (ver [build]).
  bool _limitado = false;
  String? _aviso;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _codigo.addListener(() => setState(() {}));
    // El pedido AUTOMÁTICO: si ya hay un código vigente el servidor no manda
    // otro, así el que el usuario tiene en la bandeja sigue sirviendo.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _pedir(reenviar: false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _codigo.dispose();
    super.dispose();
  }

  /// Los timers de Dart corren sobre un reloj monótono que NO avanza mientras el
  /// dispositivo duerme: con el tick a una hora de distancia, quien bloquea el
  /// teléfono dos horas volvería a una espera vieja y un botón bloqueado hasta
  /// que el timer por fin dispare. Al volver se recalcula contra el reloj y se
  /// vuelve a armar el tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _hasta == null || !mounted) {
      return;
    }
    setState(_recalcularEspera);
    _programarTick();
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
    _programarTick();
  }

  /// Un `Timer` de una sola vez, que se vuelve a armar en cada tick, en lugar de
  /// un `periodic` de 1 s: con una espera de horas, reconstruir la pantalla cada
  /// segundo solo para mostrar «4 h» gasta batería. El tick cae en el próximo
  /// momento en que cambia lo que se VE, y recién ahí recalcula contra el reloj:
  /// si la app estuvo en segundo plano, el primer tick al volver ya corrige la
  /// espera.
  ///
  /// El botón se habilita en el tick del vencimiento (`piso == 0`) y solo si el
  /// reloj ya lo pasó: un tick que cae antes no cambia nada y se vuelve a armar.
  void _programarTick() {
    _timer?.cancel();
    final hasta = _hasta;
    if (hasta == null || _reenviarEn == 0) return;

    // `piso`: el valor de `_reenviarEn` (segundos) hasta el cual se ve lo mismo.
    // Lo que se ve cambia cuando la espera baja a ese valor.
    final s = _reenviarEn;
    final int piso;
    if (!_limitado) {
      piso = s - 1; // «Reenviar código en N s»: cambia cada segundo.
    } else if (s >= _segundosParaHoras) {
      // En horas: cambia al bajar a la hora de abajo, o al pasar a minutos.
      piso = math.max(((s / 3600).ceil() - 1) * 3600, _segundosParaHoras - 1);
    } else {
      piso = ((s / 60).ceil() - 1) * 60; // En minutos; el último llega a 0.
    }

    final espera = hasta.difference(_ahora()) - Duration(seconds: piso);
    _timer = Timer(
      espera > Duration.zero ? espera : const Duration(milliseconds: 1),
      () {
        if (!mounted) return;
        setState(_recalcularEspera);
        _programarTick();
      },
    );
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

  /// «Me equivoqué de mail»: borra la cuenta recién creada (con el callable
  /// real, vía `cancelOnboarding`) para que el nombre elegido quede libre y la
  /// persona pueda registrarse de nuevo con el mail correcto.
  ///
  /// No navega: al cerrarse la sesión el router la saca solo, igual que con
  /// «Cerrar sesión». Navegar a mano acá correría una carrera con el redirect.
  Future<void> _equivocoDeMail() async {
    if (_borrando) return;
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        title: Text(l10n.verifyMailWrongEmailDialogTitle),
        content: Text(l10n.verifyMailWrongEmailDialogBody),
        actions: [
          TextButton(
            key: const Key('verify_mail_wrong_email_back'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.verifyMailWrongEmailDialogBack),
          ),
          TextButton(
            key: const Key('verify_mail_wrong_email_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.verifyMailWrongEmailDialogConfirm,
              style: TextStyle(color: palette.highlight),
            ),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted || _borrando) return;
    setState(() => _borrando = true);
    try {
      await ref.read(authNotifierProvider.notifier).cancelOnboarding();
      // Éxito: la sesión ya no existe y el router redirige. Se deja el estado
      // en «borrando» para que nada se pueda tocar mientras la pantalla sale.
    } catch (_) {
      if (!mounted) return;
      setState(() => _borrando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.verifyMailWrongEmailError),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final signingOut = ref.watch(authNotifierProvider).isLoading || _borrando;
    final puedeConfirmar = _codigo.text.trim().length == 6 &&
        !_verificando &&
        !_verificado &&
        !_borrando;
    final puedeReenviar =
        _reenviarEn == 0 && !_enviando && !_verificado && !_borrando;
    final enEsperaPorTope = _limitado && _reenviarEn > 0;
    // «Me equivoqué de mail» borra la cuenta entera sin reautenticar: solo para
    // un alta recién creada. A esta pantalla también llegan cuentas con
    // historia (promoción a entrenador, cambio de mail, el interruptor del gate
    // prendido para cuentas viejas); a esas se les esconde, y falla CERRADO
    // mientras el perfil carga. Ver `esAltaRecienCreada`.
    final altaReciente = esAltaRecienCreada(
      profile: ref.watch(userProfileProvider).valueOrNull,
      creadaEn:
          ref.watch(firebaseAuthProvider).currentUser?.metadata.creationTime,
      // `DateTime.now` y no `_ahora()`: el reloj inyectado es el de la cuenta
      // regresiva, y los tests cuentan cuántas veces lo lee la pantalla.
      ahora: DateTime.now(),
    );
    // Desde 90 min en horas (hacia arriba): «en 1440 min» no se lee.
    final cuanto = _reenviarEn >= _segundosParaHoras
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
                if (altaReciente || _borrando)
                  Center(
                    child: TextButton(
                      key: const Key('verify_mail_wrong_email'),
                      onPressed: signingOut ? null : _equivocoDeMail,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textMuted,
                      ),
                      child: _borrando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              AppL10n.of(context).verifyMailWrongEmailAction),
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
