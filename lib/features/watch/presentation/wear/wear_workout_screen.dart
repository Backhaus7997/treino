import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/domain/set_spec.dart';
import '../../application/wear_rest_providers.dart';
import '../../domain/watch_effort.dart';
import 'wear_round_scaffold.dart';
import 'wear_set_format.dart';
import 'wear_strings.dart';
import 'wear_workout_view_model.dart';

/// La pantalla de entrenamiento del companion de Wear OS.
///
/// **Réplica de `ios/TreinoWatch Watch App/WorkoutView.swift`.** No es una
/// pantalla nueva: es la misma, portada. Que el atleta vea lo mismo en las dos
/// muñecas es parte de la promesa del producto — *"el reloj es un complemento
/// 100x100"*.
///
/// Prioridad de diseño, copiada de allá: **lo que el atleta necesita leer entre
/// series, con las manos ocupadas.** Eso es el ejercicio actual y qué serie va.
/// Todo lo demás es secundario y va más chico.
///
/// ## Lo único que se adapta, y por qué
///
/// * **Spacing**: watchOS usa 6/2/10/4 px. El design system de TREINO sólo
///   admite `8 · 12 · 14 · 18 · 20`, así que se mapea al valor más cercano. La
///   pantalla queda un poco más aireada que la de Apple; es el precio de tener
///   una sola escala en todo el producto.
/// * **Pantalla redonda**: watchOS es rectangular. Acá el contenido usa casi
///   todo el ancho y el recorte del bisel se resuelve con márgenes verticales
///   y un desvanecido — ver [WearRoundScaffold].
class WearWorkoutScreen extends ConsumerWidget {
  const WearWorkoutScreen({
    super.key,
    required this.snapshot,
    required this.onLogSet,
  });

  final WearWorkoutSnapshot snapshot;

  /// Marca la serie. **Sin esto la pantalla no hace nada**: durante un rato el
  /// tap sólo arrancaba el descanso y el círculo nunca se llenaba.
  ///
  /// Lleva el `exerciseId` del snapshot que se dibujó, y no se resuelve del
  /// cursor al marcar: entre que la fila aparece y el atleta la toca puede
  /// llegar un snapshot del teléfono que mueva el cursor, y la serie quedaría
  /// escrita en OTRO ejercicio.
  final void Function(String exerciseId, int setNumber) onLogSet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rest = ref.watch(wearRestProvider).valueOrNull;
    // `nada()` mientras carga: NO se dibuja fila. Mostrar un hueco reservado
    // mientras se resuelve haria saltar el layout al llegar el primer pulso.
    final effort = ref.watch(wearEffortProvider).valueOrNull ??
        const WatchEffortDisplay.nada();
    final service = ref.read(wearWorkoutServiceProvider);

    return WearRoundScaffold.list(
      firstItem: WearItemType.text,
      lastItem: WearItemType.text,
      children: [
        _Header(snapshot: snapshot),
        const SizedBox(height: 8),
        _EffortRow(effort: effort),
        if (rest != null) ...[
          const SizedBox(height: 8),
          _RestRing(
            remainingMs: rest.remainingMs,
            totalMs: _restSecondsFor(1) * 1000,
            finished: rest.finished,
            onSkip: service.cancelRest,
          ),
        ],
        const SizedBox(height: 8),
        _SetsList(
          snapshot: snapshot,
          onLog: (setNumber) {
            // En el reloj la confirmación táctil no es adorno: el atleta
            // marca sin mirar, con la mano ocupada.
            HapticFeedback.selectionClick();
            onLogSet(snapshot.exerciseId, setNumber);
            service.startRest(_restSecondsFor(setNumber));
          },
        ),
        if (snapshot.pendingUploadCount > 0) ...[
          const SizedBox(height: 8),
          _PendingUpload(count: snapshot.pendingUploadCount),
        ],
        const SizedBox(height: 12),
        const _FinishHint(),
      ],
    );
  }

  /// TODO(wear): tiene que salir de `exercise.restSeconds`, como en watchOS.
  /// Fijo hasta que se cablee la sesión real.
  int _restSecondsFor(int setNumber) => 90;
}

/// Nombre del ejercicio y su posición. Lo más grande de la pantalla.
class _Header extends StatelessWidget {
  const _Header({required this.snapshot});

  final WearWorkoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      children: [
        // `minimumScaleFactor(0.7)` de Swift → FittedBox. Un nombre largo se
        // achica antes que cortarse: leer "Press de banca incl…" de reojo no
        // sirve de nada.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            snapshot.exerciseName,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: palette.textPrimary,
            ),
          ),
        ),
        Text(
          '${snapshot.exerciseIndex + 1} de ${snapshot.exerciseCount}'
          ' · ${snapshot.dayName}',
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
        ),
      ],
    );
  }
}

/// Pulso y calorías en UNA fila.
///
/// Van juntos porque son lo mismo para el atleta —cuánto se está esforzando— y
/// en una pantalla de reloj cada fila que se suma empuja las series fuera de
/// vista, que es lo que de verdad necesita leer entre series.
///
/// **Si NINGUNO de los dos tiene dato no se dibuja fila, ni vacía**: el hueco
/// también ocupa. Y si falta uno solo, se dibuja el otro nada más — nunca un
/// guion ni un cero. Ver [WearEffort] para el porqué medido.
class _EffortRow extends StatelessWidget {
  const _EffortRow({required this.effort});

  /// `WatchEffortDisplay` y no un tipo propio: es el MISMO modelo que usa el
  /// teléfono para el reloj de Apple. Un solo tipo para las dos plataformas.
  final WatchEffortDisplay effort;

  @override
  Widget build(BuildContext context) {
    if (effort.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (effort.bpm != null)
          _EffortStat(
            icon: TreinoIcon.heartRate,
            iconColor: palette.danger,
            value: effort.bpm!,
            unit: WearStrings.bpmUnit,
          ),
        if (effort.bpm != null && effort.kcal != null)
          const SizedBox(width: 12),
        if (effort.kcal != null)
          _EffortStat(
            icon: TreinoIcon.calories,
            iconColor: palette.warning,
            value: effort.kcal!,
            unit: WearStrings.kcalUnit,
          ),
      ],
    );
  }
}

class _EffortStat extends StatelessWidget {
  const _EffortStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final Color iconColor;
  final int value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 8),
        Text(
          '$value',
          style: GoogleFonts.barlow(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
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

/// El descanso, como ANILLO.
///
/// ## Por qué se fue la píldora
///
/// La versión anterior era una píldora ancha: contador a la izquierda, `Spacer`,
/// y "Saltar" a la derecha. El dueño lo dijo sin vueltas: *"el botón de
/// temporizador está feo"*. Y tenía razón — es una toolbar de escritorio metida
/// en una pantalla redonda de 206 dp. Ocupaba el 23% del alto, obligaba a un
/// `Spacer` que dejaba un agujero sin área táctil en el medio, y no hablaba el
/// idioma de la pantalla.
///
/// Un anillo dice lo mismo con menos: el arco ES el tiempo que queda, se lee de
/// reojo sin procesar dígitos, y todo el círculo es tocable — sin `Spacer`, sin
/// hack de área mínima.
class _RestRing extends StatelessWidget {
  const _RestRing({
    required this.remainingMs,
    required this.totalMs,
    required this.finished,
    required this.onSkip,
  });

  static const double _size = 64;

  final int remainingMs;
  final int totalMs;
  final bool finished;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Vencido pinta con `highlight`: el cambio de color se lee de reojo, sin
    // enfocar la vista, que es como se mira un reloj a mitad de entreno.
    final color = finished ? palette.highlight : palette.accent;
    final progress =
        totalMs <= 0 ? 0.0 : (remainingMs / totalMs).clamp(0.0, 1.0);

    return Center(
      child: GestureDetector(
        onTap: onSkip,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  // El arco se VACÍA a medida que pasa el tiempo, no se llena:
                  // "lo que queda" es la pregunta del atleta, no "lo que pasó".
                  backgroundColor: color.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Text(
                '${(remainingMs / 1000).ceil()}',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Las series del ejercicio actual.
class _SetsList extends StatelessWidget {
  const _SetsList({required this.snapshot, required this.onLog});

  final WearWorkoutSnapshot snapshot;
  final void Function(int setNumber) onLog;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final next = snapshot.nextSetNumber;

    return Column(
      children: [
        for (var i = 0; i < snapshot.sets.length; i++)
          _SetRow(
            setNumber: i + 1,
            spec: snapshot.sets[i],
            done: snapshot.isLogged(i + 1),
            // Ni las hechas ni las que están más adelante que la próxima.
            tappable: !snapshot.isLogged(i + 1) && (i + 1) == next,
            onTap: () => onLog(i + 1),
            palette: palette,
          ),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.setNumber,
    required this.spec,
    required this.done,
    required this.tappable,
    required this.onTap,
    required this.palette,
  });

  final int setNumber;
  final SetSpec spec;
  final bool done;
  final bool tappable;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            done ? TreinoIcon.checkCircleFill : TreinoIcon.checkCircleEmpty,
            size: 18,
            color: done ? palette.accent : palette.textMuted,
          ),
          const SizedBox(width: 8),
          Text(
            '$setNumber',
            style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
          ),
          const Spacer(),
          Text(
            describeSetSpec(spec),
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    // Una serie ya cargada no se re-toca: cargarla de nuevo es un no-op
    // idempotente, pero dejarla apagada lo hace evidente. Y una que todavía no
    // toca queda apagada para no dejar huecos.
    return Opacity(
      opacity: tappable ? 1 : 0.5,
      child: tappable ? _WearTapTarget(onTap: onTap, child: row) : row,
    );
  }
}

/// Series marcadas que todavía no subieron.
class _PendingUpload extends StatelessWidget {
  const _PendingUpload({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(TreinoIcon.arrowRight, size: 11, color: palette.warning),
        const SizedBox(width: 8),
        Text(
          '$count ${WearStrings.pendingUpload}',
          style: GoogleFonts.barlow(fontSize: 11, color: palette.warning),
        ),
      ],
    );
  }
}

/// "Terminar" aparece SOLO con todas las series de TODOS los ejercicios.
///
/// Pedido del dueño, documentado en watchOS: tenerlo siempre a la vista invita
/// a cerrar el entreno de más, sobre todo con la muñeca mojada y el botón a un
/// toque del último círculo que se marcó.
///
/// Hasta que se cablee la sesión completa acá sólo se sabe del ejercicio
/// actual, que NO alcanza. Así que por ahora siempre se muestra la leyenda.
class _FinishHint extends StatelessWidget {
  const _FinishHint();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      WearStrings.finishHint,
      textAlign: TextAlign.center,
      style: GoogleFonts.barlow(fontSize: 10, color: palette.textMuted),
    );
  }
}

/// Objetivo de toque acotado, con el área mínima que pide Wear OS.
///
/// Existe porque una versión anterior le colgaba el `onTap` a la pantalla
/// entera y en el reloj físico se disparaba solo: el log mostró
/// `startRest → cancelRest → startRest` con un segundo entre medio. Un roce del
/// vidrio cancelaba el descanso del atleta.
class _WearTapTarget extends StatelessWidget {
  const _WearTapTarget({required this.onTap, required this.child});

  /// Mínimo recomendado por las guías de Wear OS. Por debajo, con la muñeca en
  /// movimiento y el dedo transpirado, el tap se pierde.
  ///
  /// OJO con dónde se aplica: en la cápsula del descanso, forzar 48 dp de alto
  /// la hacía ocupar el 23% de una pantalla de 206 dp. Ahí el área táctil la da
  /// el ANCHO del texto "Saltar" más su padding, no el alto.
  static const double _minTouch = 48;

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // `opaque` sobre un área ACOTADA. La distinción importa y costó dos
      // bugs opuestos en el reloj:
      //
      // * `opaque` sobre la PANTALLA ENTERA se dispara solo. El log mostró
      //   `startRest → cancelRest → startRest` con un segundo entre medio:
      //   cualquier roce del vidrio alternaba.
      // * `deferToChild` sobre una fila con un `Spacer` en el medio deja un
      //   agujero: sólo registra donde hay algo PINTADO, así que tocar entre
      //   el número de serie y el peso no hacía nada.
      //
      // O sea que el problema nunca fue `opaque`, fue el TAMAÑO del área.
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minTouch),
        // El `Center` NO es cosmético: sin él, el hijo se pega arriba del área
        // de 48dp y en la cápsula del descanso "Saltar" saltaba a otro renglón,
        // separado del cronómetro con el que forma una sola fila.
        child: Center(child: child),
      ),
    );
  }
}
