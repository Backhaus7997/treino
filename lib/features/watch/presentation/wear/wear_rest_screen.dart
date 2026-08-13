import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../application/wear_rest_providers.dart';
import '../../data/wear_workout_service.dart';
import 'wear_round_scaffold.dart';
import 'wear_strings.dart';

/// Duración por defecto del descanso entre series.
///
/// TODO(wear): tiene que salir del `SetSpec` de la rutina, no de una constante.
/// Queda fijo hasta que la pantalla se conecte al entreno real.
const _defaultRestSeconds = 90;

/// Pantalla de descanso del companion de Wear OS.
///
/// Es la pantalla que justifica todo el mecanismo de abajo: el foreground
/// service que mantiene vivo el proceso, el deadline persistido que sobrevive a
/// que el proceso muera, y el wakelock acotado que hace que la vibración llegue
/// a tiempo aunque el reloj esté durmiendo.
///
/// ## La regla de diseño que manda acá
///
/// El número grande se deriva de un DEADLINE, nunca de acumular ticks. Con la
/// muñeca baja el SoC se suspende y el timer de Dart no corre: medido, 108 de
/// 522 callbacks en una ventana real. Un contador habría mostrado ~8 minutos
/// restantes cuando quedaba 1:18. Acá el próximo tick que sí corra ya trae el
/// número correcto, porque lo calcula restando contra el reloj del sistema.
class WearRestScreen extends ConsumerWidget {
  const WearRestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rest = ref.watch(wearRestProvider);

    return rest.when(
      loading: () => const _WearMessage(WearStrings.loading),
      error: (e, _) => const _WearMessage(WearStrings.noData),
      data: (state) => state == null
          ? _WearIdle(onMark: () => _startRest(ref))
          : _WearResting(
              state: state,
              onSkip: () => ref.read(wearWorkoutServiceProvider).cancelRest(),
            ),
    );
  }

  void _startRest(WidgetRef ref) {
    ref.read(wearWorkoutServiceProvider).startRest(_defaultRestSeconds);
  }
}

/// Sin descanso en curso: el atleta está haciendo la serie.
class _WearIdle extends StatelessWidget {
  const _WearIdle({required this.onMark});

  final VoidCallback onMark;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return WearRoundScaffold.centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WearTapTarget(
            onTap: onMark,
            child: Icon(
              TreinoIcon.checkCircleEmpty,
              size: 40,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            WearStrings.markSet,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Descanso corriendo, o recién vencido.
class _WearResting extends StatelessWidget {
  const _WearResting({required this.state, required this.onSkip});

  final WearRestState state;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Vencido pinta con `highlight` (magenta) en vez de `accent` (mint): el
    // cambio de color se lee de reojo, sin enfocar la vista, que es como se
    // mira un reloj a mitad de entreno.
    final done = state.finished;
    final heroColor = done ? palette.highlight : palette.accent;

    return WearRoundScaffold.centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            done ? WearStrings.restDone : WearStrings.restTitle,
            style: GoogleFonts.barlowCondensed(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: heroColor,
            ),
          ),
          const SizedBox(height: 8),
          // Hero numérico: Barlow Condensed 700, según el design system.
          Text(
            _format(state.remainingMs),
            style: GoogleFonts.barlowCondensed(
              fontSize: 56,
              fontWeight: FontWeight.w700,
              height: 1,
              color: heroColor,
              // Tabular: sin esto los dígitos cambian de ancho al contar y el
              // número "baila" en la muñeca.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          const _EffortRow(),
          const SizedBox(height: 8),
          _WearTapTarget(
            onTap: onSkip,
            child: Text(
              WearStrings.restSkip,
              style: GoogleFonts.barlow(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `m:ss`. Sin horas: un descanso de más de una hora es un bug, no un caso.
  static String _format(int ms) {
    final total = (ms / 1000).ceil();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Objetivo de toque acotado, con el area minima que pide Wear OS.
///
/// Existe porque la primera version le colgaba el `onTap` a la pantalla
/// entera y en el reloj fisico se disparaba solo: el log mostro
/// `startRest -> cancelRest -> startRest` con un segundo entre medio. Un roce
/// del vidrio cancelaba el descanso del atleta.
class _WearTapTarget extends StatelessWidget {
  const _WearTapTarget({required this.onTap, required this.child});

  /// Minimo recomendado por las guias de Wear OS. Por debajo, con la muneca en
  /// movimiento y el dedo transpirado, el tap se pierde.
  static const double _minTouch = 48;

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // `deferToChild`, NO `opaque`: el area sensible es este widget y nada
      // mas. Lo envuelve un ConstrainedBox para que igual llegue a 48dp.
      behavior: HitTestBehavior.deferToChild,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: _minTouch,
          minHeight: _minTouch,
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// Ritmo cardíaco y calorías, con la misma unidad que el reloj de Apple.
class _EffortRow extends StatelessWidget {
  const _EffortRow();

  @override
  Widget build(BuildContext context) {
    // TODO(wear): cablear a Health Services `ExerciseClient`. Hasta que exista,
    // se muestra el placeholder y NO un valor viejo: un pulso vencido
    // presentado como actual es peor que no mostrar nada.
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _EffortStat(icon: TreinoIcon.heartRate, unit: WearStrings.bpmUnit),
        SizedBox(width: 18),
        _EffortStat(icon: TreinoIcon.calories, unit: WearStrings.kcalUnit),
      ],
    );
  }
}

class _EffortStat extends StatelessWidget {
  const _EffortStat({required this.icon, required this.unit});

  final IconData icon;
  final String unit;

  /// Todavía no hay fuente de datos: falta cablear Health Services
  /// `ExerciseClient`. Se deja explícito en null en vez de recibirlo por
  /// parámetro para que el analizador no acepte en silencio un widget que
  /// nadie alimenta — cuando llegue el dato, esto pasa a ser un campo.
  int? get value => null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: palette.textMuted),
        const SizedBox(width: 8),
        Text(
          value?.toString() ?? WearStrings.noData,
          style: GoogleFonts.barlow(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          unit,
          style: GoogleFonts.barlow(fontSize: 10, color: palette.textMuted),
        ),
      ],
    );
  }
}

class _WearMessage extends StatelessWidget {
  const _WearMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return WearRoundScaffold.centered(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
      ),
    );
  }
}
