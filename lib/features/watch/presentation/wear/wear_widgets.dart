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
  const WearEffortRow({
    super.key,
    required this.effort,
    this.mostrarSinDatos = false,
  });

  /// Si dibujar con guiones la métrica que todavía no midió.
  ///
  /// En la lista de series va en false: reservar un hueco haría saltar el
  /// layout al llegar el primer pulso, y ahí el atleta está mirando los
  /// círculos, no el esfuerzo. Con esto en false una métrica sin dato
  /// simplemente no se dibuja, exactamente como antes.
  ///
  /// En la pantalla del ejercicio por tiempo va en TRUE. Health Services tarda
  /// unos segundos en entregar la primera medición, y la fila oculta hacía
  /// pensar que el reloj no estaba midiendo nada — sobre todo entrando desde el
  /// teléfono, donde la pantalla aparece antes que el primer dato.
  final bool mostrarSinDatos;

  /// `WatchEffortDisplay` y no un tipo propio: es el MISMO modelo que usa el
  /// teléfono para el reloj de Apple. Un solo tipo para las dos plataformas.
  final WatchEffortDisplay effort;

  /// Si esta métrica ocupa un lugar en la fila.
  ///
  /// El placeholder se resuelve POR MÉTRICA y no por la fila entera, y esa es
  /// justamente la corrección. Los dos sensores no llegan juntos: las calorías
  /// aparecen enseguida y el pulso tarda unos segundos más. Atado a
  /// `effort.isEmpty`, una medición PARCIAL —kcal presente, bpm en null— no
  /// entraba por el camino del placeholder y cada métrica se dibujaba sólo si
  /// tenía dato. Resultado en la muñeca: `🔥 0 kcal` solo, sin corazón, que se
  /// lee como "este reloj no mide el pulso" en vez de "el sensor está
  /// calentando".
  bool _ocupaLugar(int? valor) => valor != null || mostrarSinDatos;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final hayPulso = _ocupaLugar(effort.bpm);
    final hayCalorias = _ocupaLugar(effort.kcal);
    if (!hayPulso && !hayCalorias) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hayPulso)
          _WearEffortCell(
            icon: TreinoIcon.heartRate,
            iconColor: palette.danger,
            value: effort.bpm,
            unit: WearStrings.bpmUnit,
          ),
        if (hayPulso && hayCalorias) const SizedBox(width: 12),
        if (hayCalorias)
          _WearEffortCell(
            icon: TreinoIcon.calories,
            iconColor: palette.warning,
            value: effort.kcal,
            unit: WearStrings.kcalUnit,
          ),
      ],
    );
  }
}

/// Una métrica de esfuerzo: ícono, número y unidad.
///
/// ## Por qué es UN widget y no dos
///
/// Antes eran dos —uno con dato y otro con guiones— y esa separación fue la que
/// dejó pasar el bug de la medición parcial: la decisión de cuál usar vivía
/// arriba, en la fila entera. Con un solo widget la pregunta se vuelve local y
/// trivial: si hay número se dibuja el número, y si no, `--`.
///
/// Y hay una razón de LAYOUT además de una de diseño. Las dos versiones tenían
/// tipografías y separadores distintos —16 condensada con huecos de 4 y 2 contra
/// 13 normal con huecos de 8—, algo que no se notaba mientras la fila era toda
/// dato o toda guiones. Con medición parcial conviven, y ahí la diferencia se ve
/// como dos columnas desalineadas. Misma métrica, misma caja.
class _WearEffortCell extends StatelessWidget {
  const _WearEffortCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final Color iconColor;

  /// El valor medido, o null mientras el sensor todavía no entregó nada.
  final int? value;

  final String unit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final medido = value != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 8),
        Text(
          medido ? '$value' : '--',
          style: GoogleFonts.barlow(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            // Apagado sin dato: el guion tiene que leerse como "todavía no",
            // no como una medición más.
            color: medido ? palette.textPrimary : palette.textMuted,
            // Cifras de ancho fijo: sin esto la fila se corre sola cada vez que
            // el pulso pasa de 99 a 100.
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
