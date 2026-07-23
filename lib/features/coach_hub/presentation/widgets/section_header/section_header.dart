import 'package:flutter/material.dart';

import '../../../../../app/theme/tokens/components/treino_section_header_tokens.dart';
import '../../../../../core/widgets/motion/treino_tappable.dart';

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
/// - Con acción: botón de texto a la derecha.
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
    final color = onTap != null ? tokens.actionColor : tokens.disabledColor;

    if (onTap == null) {
      return Text(
        label,
        style: TextStyle(
          fontFamily: 'Barlow',
          fontWeight: FontWeight.w600,
          fontSize: TreinoSectionHeaderTokens.fontSize,
          color: color,
        ),
      );
    }

    return TreinoTappable(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Barlow',
          fontWeight: FontWeight.w600,
          fontSize: TreinoSectionHeaderTokens.fontSize,
          color: color,
        ),
      ),
    );
  }
}
