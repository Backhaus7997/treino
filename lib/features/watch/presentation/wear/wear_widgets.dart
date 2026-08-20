/// Piezas compartidas por las pantallas del companion de Wear OS.
///
/// Réplica de los componentes sueltos de `ContentView.swift` y
/// `RoutineListView.swift`, unificados acá para que el estilo no se copie a
/// mano en cada pantalla y derive.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/watch_effort.dart';
import 'wear_strings.dart';

/// Ícono + texto centrados, para los estados que no son la app en sí.
///
/// Réplica de `StatusMessage` de watchOS.
class WearStatusMessage extends StatelessWidget {
  const WearStatusMessage({
    super.key,
    required this.icon,
    required this.text,
    this.tint,
  });

  final IconData icon;
  final String text;

  /// Null = color de texto normal. Se usa [AppPalette.warning] para los
  /// estados de falla, igual que el `.orange` de watchOS.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = tint ?? palette.textPrimary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 12, color: palette.textPrimary),
        ),
      ],
    );
  }
}

/// Spinner + leyenda, para las cargas.
class WearLoading extends StatelessWidget {
  const WearLoading({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
        ),
      ],
    );
  }
}

/// Encabezado de sección: "EJERCICIOS", "MIS PLANES", "PLANTILLAS".
///
/// Barlow Condensed 700 UPPERCASE, según el design system. En watchOS es
/// `.caption2` secundario; el equivalente acá es el heading más chico.
class WearSectionTitle extends StatelessWidget {
  const WearSectionTitle(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: color ?? palette.textMuted,
      ),
    );
  }
}

/// Botón del reloj.
///
/// ## Por qué un botón propio y no `FilledButton`
///
/// Dos razones medidas en el dispositivo:
///
/// 1. **El área de toque tiene que llegar a 48dp.** Es el mínimo de las guías
///    de Wear OS: por debajo, con la muñeca en movimiento y el dedo transpirado,
///    el tap se pierde.
/// 2. **El área sensible tiene que estar ACOTADA.** Costó dos bugs opuestos:
///    `opaque` sobre la pantalla entera se disparaba solo (el log mostró
///    `startRest → cancelRest → startRest` con un segundo entre medio, un roce
///    del vidrio cancelaba el descanso), y `deferToChild` sobre una fila con un
///    `Spacer` dejaba un agujero en el medio donde el toque no registraba.
///    La regla es el TAMAÑO del área, no el `HitTestBehavior`.
class WearButton extends StatelessWidget {
  const WearButton({
    super.key,
    required this.label,
    required this.onTap,
    this.tint,
    this.enabled = true,
  });

  static const double _minTouch = 48;

  final String label;
  final VoidCallback onTap;

  /// Color de acento del botón. Null = [AppPalette.accent].
  final Color? tint;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = tint ?? palette.accent;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: _minTouch),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulso y calorías en UNA fila.
///
/// Vive acá y no dentro de la pantalla de entreno porque la usan DOS pantallas:
/// la de series y la del temporizador de ejercicio por tiempo. Duplicarla haría
/// que la segunda se quedara vieja la próxima vez que se toque la primera.
class WearEffortRow extends StatelessWidget {
  const WearEffortRow({super.key, required this.effort});

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
          _WearEffortStat(
            icon: TreinoIcon.heartRate,
            iconColor: palette.danger,
            value: effort.bpm!,
            unit: WearStrings.bpmUnit,
          ),
        if (effort.bpm != null && effort.kcal != null)
          const SizedBox(width: 12),
        if (effort.kcal != null)
          _WearEffortStat(
            icon: TreinoIcon.calories,
            iconColor: palette.warning,
            value: effort.kcal!,
            unit: WearStrings.kcalUnit,
          ),
      ],
    );
  }
}

class _WearEffortStat extends StatelessWidget {
  const _WearEffortStat({
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
