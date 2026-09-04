// Hero de sección del Coach Hub Web.
//
// El dashboard abría con una welcome card que las demás secciones no tenían:
// glow mint en diagonal, saludo grande con el dato resaltado en accent y una
// fila de pills. El resto de las pantallas arrancaba con un label de 12 px y
// una línea muted — la misma información, sin ninguna jerarquía.
//
// Este widget es esa welcome card generalizada. NO duplica el kit: el título
// sigue siendo `TreinoSectionHeader`, ahora en su variante `hero`.
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/tokens.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../preview_wrapper.dart';
import '../section_header/section_header.dart';
import '../treino_interactive_state.dart';

/// Previews del kit.
@Preview(name: 'SectionHero — título + subtítulo', wrapper: coachHubPreviewWrapper)
Widget sectionHeroPreview() => const CoachHubSectionHero(
      title: 'Mis alumnos',
      count: 24,
      subtitle: '24 alumnos · 19 activos esta semana',
    );

@Preview(name: 'SectionHero — con acciones', wrapper: coachHubPreviewWrapper)
Widget sectionHeroActionsPreview() => CoachHubSectionHero(
      title: 'Biblioteca',
      subtitle: '128 ejercicios · 12 templates',
      actions: [
        CoachHubHeroAction(
          label: 'Nuevo ejercicio',
          icon: TreinoIcon.plus,
          onTap: () {},
          primary: true,
        ),
        CoachHubHeroAction(
          label: 'Importar plan',
          icon: TreinoIcon.upload,
          onTap: () {},
        ),
      ],
    );

/// Acción del [CoachHubSectionHero] — se renderiza como pill.
///
/// [primary] `true` la pinta filled en [AppPalette.accent] (la "+ Nuevo
/// alumno" de la welcome card); `false` la deja outlined. Como máximo una
/// acción por hero debería ser primaria.
@immutable
class CoachHubHeroAction {
  const CoachHubHeroAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
}

/// Cabecera hero de una sección del Coach Hub.
///
/// Lleva el lenguaje visual de la welcome card del dashboard
/// (`dashboard_hero.dart`) al resto de las secciones:
/// - card con glow mint en diagonal desde la esquina superior izquierda,
/// - título 28 px Barlow Condensed UPPERCASE con el [count] en accent,
/// - subtítulo muted,
/// - fila de pills ([actions]) y/o un [trailing] a la derecha.
///
/// Contrato de sección: sin Scaffold/SafeArea, todo por tokens (ADR-CHW-005).
///
/// Uso:
/// ```dart
/// CoachHubSectionHero(
///   title: 'Mis alumnos',
///   count: roster.length,
///   subtitle: l10n.coachHubAlumnosSummary(roster.length, activos),
/// )
/// ```
class CoachHubSectionHero extends StatelessWidget {
  const CoachHubSectionHero({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.actions = const [],
    this.trailing,
  });

  /// Título de la sección. Se uppercasea automáticamente.
  final String title;

  /// Dato principal junto al título (ej: cantidad de alumnos). Se resalta en
  /// [AppPalette.accent], como el nombre en el saludo del dashboard.
  final int? count;

  /// Línea de contexto bajo el título.
  final String? subtitle;

  /// Pills de acción rápida bajo el título.
  final List<CoachHubHeroAction> actions;

  /// Widget libre a la derecha del título (botón propio de la sección, un
  /// anillo, un selector). Convive con [actions].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      key: const Key('section_hero_root'),
      padding: const EdgeInsets.all(AppSpacing.s20),
      // Mismo glow que la welcome card (#341): BoxDecoration no admite
      // `color` y `gradient` a la vez, así que el fondo de la card pasa a ser
      // los dos últimos stops — fuera del glow se ve idéntico a una card lisa.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
        border: Border.all(color: TreinoCardTokens.border(context)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent.withValues(alpha: 0.12),
            TreinoCardTokens.background(context),
            TreinoCardTokens.background(context),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TreinoSectionHeader(
                      title: title,
                      count: count,
                      variant: TreinoSectionHeaderVariant.hero,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.hairline),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: AppFonts.barlow,
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.s18),
                trailing!,
              ],
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s18),
            Wrap(
              key: const Key('hero_actions'),
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (var i = 0; i < actions.length; i++)
                  _HeroActionPill(action: actions[i], index: i),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Pill de una [CoachHubHeroAction].
///
/// La primaria va envuelta en [TreinoInteractiveState] (resolver único de
/// hover/pressed/focus/Semantics del kit, ADR-SH-002). Las secundarias usan
/// `OutlinedButton`, que ya trae su propio foco y Semantics vía Material — no
/// se envuelven, evita el doble recognizer.
class _HeroActionPill extends StatelessWidget {
  const _HeroActionPill({required this.action, required this.index});

  final CoachHubHeroAction action;
  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    const labelStyle = TextStyle(
      fontFamily: AppFonts.barlowCondensed,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    );

    if (!action.primary) {
      return OutlinedButton.icon(
        key: Key('hero_action_$index'),
        onPressed: action.onTap,
        icon: Icon(action.icon, size: 15, color: palette.textPrimary),
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.border),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          shape: const StadiumBorder(),
        ),
        label: Text(action.label, style: labelStyle),
      );
    }

    return TreinoInteractiveState(
      onTap: action.onTap,
      builder: (ctx, states) => Container(
        key: Key('hero_action_$index'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              action.icon,
              size: 15,
              color: TreinoButtonTokens.foreground(context),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              action.label,
              style: labelStyle.copyWith(
                color: TreinoButtonTokens.foreground(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
