import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../domain/rest_rules.dart';

/// Cuenta regresiva del descanso entre series, en el teléfono (#1510).
///
/// Hasta acá el descanso configurado en la rutina («3:30») sólo corría en el
/// reloj: en el teléfono, después de marcar la serie no aparecía nada.
///
/// Cuenta contra un instante FIJO ([endsAt]) y no restando ticks: si el
/// atleta pasa la app a segundo plano, los timers de Dart se frenan, y un
/// contador por ticks volvería atrasado. El tick de un segundo sólo redibuja.
/// La hora sale de `clock`, no de `DateTime.now()`, para que los tests puedan
/// adelantarla.
class RestTimerBar extends StatefulWidget {
  const RestTimerBar({
    super.key,
    required this.endsAt,
    required this.totalSeconds,
    required this.onSkip,
    required this.onAddSeconds,
    required this.onDone,
  });

  /// Cuándo termina el descanso.
  final DateTime endsAt;

  /// Duración total, para la barra de progreso (cuenta los +15 s sumados).
  final int totalSeconds;

  /// SALTAR: termina el descanso ya.
  final VoidCallback onSkip;

  /// +15 s: corre [endsAt] para adelante.
  final ValueChanged<int> onAddSeconds;

  /// Llegó a cero. Ya vibró; el llamador saca la barra.
  final VoidCallback onDone;

  /// Cuánto se suma con el botón «+15 s». Sale de la regla compartida con el
  /// reloj (#1616): el +15 s del teléfono se ve en la muñeca, y si cada lado
  /// sumara su propio número dejarían de coincidir.
  static const int extraSeconds = RestRules.extraSeconds;

  @override
  State<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends State<RestTimerBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    // Lector de pantalla: UN aviso al empezar y otro al terminar. Un
    // `liveRegion` con la cuenta en el label anunciaría cada segundo — 90
    // anuncios en un descanso de 1:30.
    // Post-frame: en initState todavía no se puede leer Directionality.
    final inicial = _restante;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _anunciar('Descanso de ${_hablado(inicial)}');
    });
  }

  void _anunciar(String mensaje) {
    final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
    // ignore: deprecated_member_use
    SemanticsService.announce(mensaje, dir);
  }

  static String _hablado(int segundos) {
    final m = segundos ~/ 60;
    final s = segundos % 60;
    final partes = [
      if (m > 0) '$m ${m == 1 ? 'minuto' : 'minutos'}',
      if (s > 0 || m == 0) '$s ${s == 1 ? 'segundo' : 'segundos'}',
    ];
    return partes.join(' ');
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Redondeo para ARRIBA: «0:01» se ve hasta que de verdad llega a cero.
  ///
  /// Con la regla compartida con el reloj (#1616), al microsegundo. La cuenta
  /// anterior truncaba la diferencia a milisegundos, y con un instante de fin
  /// que no cae justo en el milisegundo la barra daba «terminó» hasta 1 ms
  /// ANTES del fin. Ese `onDone` adelantado le llegaba a `RestEndAlerts` como
  /// un fin todavía por venir —o sea, un SALTAR— y cancelaba la notificación
  /// de #1617 en vez de dejarla salir.
  int get _restante =>
      RestRules.remaining(endsAt: widget.endsAt, now: clock.now());

  void _onTick() {
    if (!mounted) return;
    if (_restante <= 0) {
      _tick?.cancel();
      HapticFeedback.vibrate();
      _anunciar('Terminó el descanso');
      widget.onDone();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final restante = _restante;
    final mm = restante ~/ 60;
    final ss = (restante % 60).toString().padLeft(2, '0');
    final progreso = widget.totalSeconds <= 0
        ? 0.0
        : (restante / widget.totalSeconds).clamp(0.0, 1.0);

    // Label FIJO: la cuenta la anuncian [_anunciar] al empezar y al terminar.
    return Semantics(
      container: true,
      label: 'Descanso',
      child: Container(
        key: const Key('rest_timer_bar'),
        margin: const EdgeInsets.fromLTRB(
            AppSpacing.s20, AppSpacing.s8, AppSpacing.s20, 0),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.s14, AppSpacing.s8, AppSpacing.s8, AppSpacing.s8),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: palette.accent),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Text(
                    'DESCANSO', // i18n: mismo pendiente que el resto del player
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTextSize.caption,
                      letterSpacing: 1.2,
                      color: palette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                ExcludeSemantics(
                  child: Text(
                    '$mm:$ss',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTextSize.heading,
                      color: palette.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      widget.onAddSeconds(RestTimerBar.extraSeconds),
                  child: const Text('+15 s'),
                ),
                TextButton(
                  onPressed: widget.onSkip,
                  child: const Text('SALTAR'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 4,
                color: palette.accent,
                backgroundColor: palette.border,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
