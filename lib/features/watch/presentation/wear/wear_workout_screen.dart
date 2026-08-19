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
import 'wear_widgets.dart';
import 'wear_workout_view_model.dart';
import 'wear_fitted_text.dart';

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
    required this.onFinish,
    required this.onAbandon,
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

  /// Cierra el entreno como completado.
  final VoidCallback onFinish;

  /// Lo abandona sin completarlo. Ya viene confirmado.
  final VoidCallback onAbandon;

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
          _RestBar(
            remainingMs: rest.remainingMs,
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
            // El descanso del ejercicio que se está DIBUJANDO. Se toma del
            // snapshot y no se busca al marcar porque la última serie arranca
            // el descanso y acto seguido el cursor avanza: leerlo después daría
            // el del ejercicio siguiente.
            service.startRest(snapshot.restSeconds);
          },
        ),
        const SizedBox(height: 12),
        _FinishHint(
          puedeTerminar: snapshot.isFullyCompleted,
          onFinish: onFinish,
          onAbandon: () => _confirmarAbandono(context, onAbandon),
        ),
      ],
    );
  }
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
        // Envuelve primero y achica después, con piso. El `FittedBox` que
        // había acá medía el texto como UNA línea infinita y lo escalaba sin
        // límite: "movilidad de hombros rotación interna por espalda con
        // baston" terminaba diminuto, de borde a borde y metido en la curva de
        // la pantalla. Ver [wearFittedFontSize].
        WearFittedText(
          snapshot.exerciseName,
          maxLines: 3,
          maxSize: 20,
          minSize: 13,
          // El título vive en la franja ALTA, donde el círculo ya se cierra.
          // Ocupar todo el ancho disponible lo empuja contra el borde curvo.
          widthFactor: 0.88,
          styleFor: (size) => GoogleFonts.barlowCondensed(
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: palette.textPrimary,
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
/// El descanso, como una barra sobre las series.
///
/// **Réplica de `restBanner` de `WorkoutView.swift`**: ícono, los segundos que
/// quedan, y «Saltar». Antes era un anillo de 64 px centrado, que se comía la
/// altura justo donde tienen que estar las series que el atleta va a marcar —
/// en una pantalla de 206 dp eso es medio entreno fuera de vista.
///
/// El separador es FIJO y la fila va centrada, en vez de empujar «Saltar» al
/// borde con un `Spacer` como hace el Swift. Es preferencia del dueño, y acá
/// además ayuda: pegado al bisel, en una pantalla redonda, el objetivo de toque
/// se recorta.
///
/// Vencido cambia de color en vez de desaparecer: el atleta mira el reloj de
/// reojo, sin enfocar, y el color se lee antes que un número.
class _RestBar extends StatelessWidget {
  const _RestBar({
    required this.remainingMs,
    required this.finished,
    required this.onSkip,
  });

  final int remainingMs;
  final bool finished;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Como en watchOS: el tiempo es texto NORMAL y sólo «Saltar» va en acento.
    // Pintarlo todo de verde competía con los círculos de las series, que son
    // lo que el atleta viene a tocar.
    //
    // La única divergencia es al VENCER, que allá no existe: ahí sí cambia de
    // color, porque el reloj se mira de reojo y el color se lee antes que un
    // número.
    final color = finished ? palette.highlight : palette.textPrimary;
    final segundos = (remainingMs / 1000).ceil();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(TreinoIcon.timer, size: 14, color: color),
        const SizedBox(width: 8),
        Text(
          '${segundos}s',
          style: GoogleFonts.barlow(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1,
            color: color,
            // Tabulares: sin esto el ancho baila al pasar de 100 a 99 y la
            // fila entera se corre sola.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 18),
        _WearTapTarget(
          onTap: onSkip,
          child: Center(
            child: Text(
              WearStrings.restSkip,
              style: GoogleFonts.barlow(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.accent,
              ),
            ),
          ),
        ),
      ],
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

/// "Terminar" aparece SOLO con todas las series de TODOS los ejercicios.
///
/// Pedido del dueño, documentado en watchOS: tenerlo siempre a la vista invita
/// a cerrar el entreno de más, sobre todo con la muñeca mojada y el botón a un
/// toque del último círculo que se marcó.
///
/// Pregunta antes de abandonar, y sólo entonces avisa.
///
/// Abandonar no se deshace: cierra la sesión con `wasFullyCompleted: false`. En
/// una muñeca, con la mano transpirada, un toque perdido no puede costar un
/// entreno.
Future<void> _confirmarAbandono(
  BuildContext context,
  VoidCallback onAbandon,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (_) => const _AbandonDialog(),
  );
  if (confirmado ?? false) onAbandon();
}

/// La confirmación, a pantalla completa.
///
/// No es un diálogo chico con dos botones al lado: en 438 px eso deja objetivos
/// de toque por debajo del mínimo. Ocupa la pantalla y apila, con «seguir
/// entrenando» PRIMERO — es la salida segura, y es la que el pulgar encuentra.
class _AbandonDialog extends StatelessWidget {
  const _AbandonDialog();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog.fullscreen(
      backgroundColor: palette.bg,
      child: WearRoundScaffold.centered(
        children: [
          Text(
            WearStrings.abandonConfirm,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          WearButton(
            label: WearStrings.abandonNo,
            onTap: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: 12),
          WearButton(
            label: WearStrings.abandonYes,
            tint: palette.warning,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}

/// El cierre del entreno: Terminar cuando se puede, y siempre una salida.
///
/// **Terminar exige TODAS las series de TODOS los ejercicios**, no las del
/// ejercicio actual. Es pedido del dueño y la razón es de producto: tenerlo a
/// la vista antes invita a cerrar el entreno de más. Por eso `isFullyCompleted`
/// mira el entreno entero — y por eso un snapshot de un solo ejercicio nunca
/// pudo calcularlo.
///
/// **Abandonar está siempre**, y es la otra mitad del pedido. Sin él, el atleta
/// que se lesiona sin el teléfono a mano deja la sesión abierta para siempre:
/// era la deuda §8.3 del companion de Apple. Va chico, gris y sin tinte
/// destructivo —existe para un imprevisto, no para usarse por costumbre— y pide
/// confirmación, porque no se deshace.
class _FinishHint extends StatelessWidget {
  const _FinishHint({
    required this.puedeTerminar,
    required this.onFinish,
    required this.onAbandon,
  });

  final bool puedeTerminar;
  final VoidCallback onFinish;
  final VoidCallback onAbandon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      children: [
        if (puedeTerminar)
          WearButton(label: WearStrings.finish, onTap: onFinish)
        else
          Text(
            WearStrings.finishHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(fontSize: 10, color: palette.textMuted),
          ),
        const SizedBox(height: 18),
        _AbandonLink(onTap: onAbandon),
      ],
    );
  }
}

/// La salida discreta. Deliberadamente poco vistosa.
class _AbandonLink extends StatelessWidget {
  const _AbandonLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _WearTapTarget(
      onTap: onTap,
      child: Center(
        child: Text(
          WearStrings.abandon,
          style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
        ),
      ),
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
