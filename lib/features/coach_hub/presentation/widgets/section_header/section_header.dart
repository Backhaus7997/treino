import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../../app/theme/tokens/components/treino_focus_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_section_header_tokens.dart';
import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../preview_wrapper.dart';
import '../treino_interactive_state.dart';

/// Previews del kit — Finding W3.
@Preview(name: 'SectionHeader — normal', wrapper: coachHubPreviewWrapper)
Widget sectionHeaderPreview() =>
    const TreinoSectionHeader(title: 'Mis alumnos', count: 24);

@Preview(name: 'SectionHeader — con acción', wrapper: coachHubPreviewWrapper)
Widget sectionHeaderActionPreview() => TreinoSectionHeader(
      title: 'Mis alumnos',
      count: 24,
      action: TreinoSectionHeaderAction(label: 'Ver todos', onTap: () {}),
    );

/// Escala visual del [TreinoSectionHeader].
///
/// - [label] — 12 px, count apagado. Es la cabecera de una sub-sección
///   dentro de una pantalla ("Pendientes", "Próximas sesiones"). Es el
///   default histórico y el que usa la app mobile: NO cambiar su render.
/// - [hero] — 28 px con el count resaltado en [AppPalette.accent]. Es el
///   título de la pantalla, con el mismo peso visual que el saludo de la
///   welcome card del dashboard ("BUENAS, MATEO"). Lo usa
///   `CoachHubSectionHero`, no se instancia suelto.
enum TreinoSectionHeaderVariant { label, hero }

/// Datos de la acción opcional del [TreinoSectionHeader].
@immutable
class TreinoSectionHeaderAction {
  const TreinoSectionHeaderAction({
    required this.label,
    required this.onTap,
  });

  /// Texto del botón de acción (ej: "Ver todos").
  final String label;

  /// Callback cuando se toca la acción.
  final VoidCallback onTap;
}

/// Cabecera de sección del kit Coach Hub Web — Fase 1.
///
/// Reemplaza al `section_header.dart` del shell con tokens formalizados.
/// Tipografía Barlow Condensed 700 UPPERCASE, acción opcional y count opcional.
///
/// Estados:
/// - Normal: título UPPERCASE + count opcional.
/// - Con acción: botón de texto a la derecha — focusable, activable por
///   teclado (Enter/Space) y con Semantics(button: true) vía
///   TreinoInteractiveState (fuente única de verdad, ADR-SH-002).
/// - Disabled: sin interacción, colores apagados.
///
/// Tokens: TreinoSectionHeaderTokens.of(context) — nunca hex inline.
///
/// Uso:
/// ```dart
/// TreinoSectionHeader(
///   title: 'Mis alumnos',
///   count: 24,
///   action: TreinoSectionHeaderAction(
///     label: 'Ver todos',
///     onTap: () => nav.push('/alumnos'),
///   ),
/// )
/// ```
/// Tamaño del título en [TreinoSectionHeaderVariant.hero] — el mismo 28 px
/// del saludo de la welcome card (`dashboard_hero.dart`), para que las dos
/// piezas lean como una sola familia.
const double _heroFontSize = 28.0;

class TreinoSectionHeader extends StatelessWidget {
  const TreinoSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.action,
    this.disabled = false,
    this.variant = TreinoSectionHeaderVariant.label,
  });

  /// Título de la sección. Se transforma a UPPERCASE automáticamente.
  final String title;

  /// Conteo opcional mostrado junto al título (ej: número de alumnos).
  final int? count;

  /// Acción opcional (botón de texto a la derecha del header).
  final TreinoSectionHeaderAction? action;

  /// `true` = sin interactividad, colores apagados.
  final bool disabled;

  /// Escala visual — ver [TreinoSectionHeaderVariant].
  final TreinoSectionHeaderVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoSectionHeaderTokens.of(context);
    final titleColor = disabled ? tokens.disabledColor : tokens.titleColor;
    final isHero = variant == TreinoSectionHeaderVariant.hero;
    final fontSize =
        isHero ? _heroFontSize : TreinoSectionHeaderTokens.fontSize;
    // En hero el count es el dato que se resalta, igual que el nombre en el
    // saludo de la welcome card. En label queda apagado (comportamiento
    // histórico, lo asume la app mobile).
    final countColor = isHero && !disabled
        ? AppPalette.of(context).accent
        : tokens.disabledColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          key: const Key('sh_title'),
          title.toUpperCase(),
          style: TextStyle(
            fontFamily: TreinoSectionHeaderTokens.fontFamily,
            fontWeight: TreinoSectionHeaderTokens.fontWeight,
            fontSize: fontSize,
            color: titleColor,
            letterSpacing: isHero ? 1.2 : 0.5,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: AppSpacing.s8),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: isHero ? AppFonts.barlowCondensed : AppFonts.barlow,
              fontWeight: isHero ? AppFonts.w700 : FontWeight.w600,
              fontSize: fontSize,
              letterSpacing: isHero ? 1.2 : null,
              color: countColor,
            ),
          ),
        ],
        const Spacer(),
        if (action != null)
          _ActionButton(
            label: action!.label,
            onTap: disabled ? null : action!.onTap,
            tokens: tokens,
          ),
      ],
    );
  }
}

/// Botón de acción del [TreinoSectionHeader].
///
/// Con `onTap` — estado de interacción vía [TreinoInteractiveState] (fuente
/// única de verdad, ADR-SH-002): focusable, activable por teclado
/// (Enter/Space), expone Semantics(button: true) y subraya el label en
/// hover. Sin `onTap` → texto estático deshabilitado, sin gesto.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final VoidCallback? onTap;
  final TreinoSectionHeaderTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          fontWeight: FontWeight.w600,
          fontSize: TreinoSectionHeaderTokens.fontSize,
          color: tokens.disabledColor,
        ),
      );
    }

    final focusTokens = TreinoFocusTokens.of(context);

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        return Container(
          key: const Key('sh_action'),
          padding: const EdgeInsets.all(AppSpacing.s8),
          decoration: BoxDecoration(
            border: states.focused ? Border.all(color: focusTokens.ring) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontWeight: FontWeight.w600,
              fontSize: TreinoSectionHeaderTokens.fontSize,
              color: tokens.actionColor,
              decoration: states.hovered
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          ),
        );
      },
    );
  }
}
