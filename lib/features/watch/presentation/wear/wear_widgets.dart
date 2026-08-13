/// Piezas compartidas por las pantallas del companion de Wear OS.
///
/// Réplica de los componentes sueltos de `ContentView.swift` y
/// `RoutineListView.swift`, unificados acá para que el estilo no se copie a
/// mano en cada pantalla y derive.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

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
