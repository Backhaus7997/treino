import 'package:flutter/material.dart';

import '../../../../../app/theme/tokens/components/treino_focus_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_section_header_tokens.dart';
import '../treino_interactive_state.dart';

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
class TreinoSectionHeader extends StatelessWidget {
  const TreinoSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.action,
    this.disabled = false,
  });

  /// Título de la sección. Se transforma a UPPERCASE automáticamente.
  final String title;

  /// Conteo opcional mostrado junto al título (ej: número de alumnos).
  final int? count;

  /// Acción opcional (botón de texto a la derecha del header).
  final TreinoSectionHeaderAction? action;

  /// `true` = sin interactividad, colores apagados.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoSectionHeaderTokens.of(context);
    final titleColor = disabled ? tokens.disabledColor : tokens.titleColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          key: const Key('sh_title'),
          title.toUpperCase(),
          style: TextStyle(
            fontFamily: TreinoSectionHeaderTokens.fontFamily,
            fontWeight: TreinoSectionHeaderTokens.fontWeight,
            fontSize: TreinoSectionHeaderTokens.fontSize,
            color: titleColor,
            letterSpacing: 0.5,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Barlow',
              fontWeight: FontWeight.w600,
              fontSize: TreinoSectionHeaderTokens.fontSize,
              color: tokens.disabledColor,
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
          fontFamily: 'Barlow',
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
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            border:
                states.focused ? Border.all(color: focusTokens.ring) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Barlow',
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
