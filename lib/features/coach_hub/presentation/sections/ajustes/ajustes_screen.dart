import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_focus_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_transparent_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_tab.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

/// Tabs internos de la sección «Configuración» (Ajustes) del Coach Hub web.
///
/// «Datos y privacidad» se omite a propósito en el hub web: la eliminación de
/// cuenta vive en la app mobile (donde se crea la cuenta y donde aplican las
/// políticas de las stores). Se puede reintroducir si se decide tener el flujo
/// también en web.
enum AjustesTab { cuenta, notificaciones, facturacion }

extension AjustesTabX on AjustesTab {
  String get label => switch (this) {
        AjustesTab.cuenta => 'Cuenta', // i18n: Fase W3
        AjustesTab.notificaciones => 'Notificaciones', // i18n: Fase W3
        AjustesTab.facturacion => 'Facturación TREINO', // i18n: Fase W3
      };

  IconData get icon => switch (this) {
        AjustesTab.cuenta => TreinoIcon.users,
        AjustesTab.notificaciones => TreinoIcon.bell,
        AjustesTab.facturacion => TreinoIcon.sidebarPagos,
      };
}

/// Tab seleccionado dentro de Configuración. `autoDispose`: vuelve a Cuenta al
/// salir y reentrar a `/ajustes`, consistente con el resto del Coach Hub web.
final _ajustesTabProvider = StateProvider.autoDispose<AjustesTab>(
  (_) => AjustesTab.cuenta,
);

/// Sección «Configuración» del Coach Hub web (`/ajustes`, Fase W3).
///
/// Header + sub-nav vertical (Cuenta · Notificaciones · Facturación) y el
/// cuerpo del tab activo. Renderiza DENTRO del shell — sin Scaffold propio
/// (ADR-CHW-005). Cuenta y Notificaciones están implementadas; Facturación es
/// placeholder hasta W3.4.
class AjustesScreen extends ConsumerWidget {
  const AjustesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final selected = ref.watch(_ajustesTabProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TreinoSectionHeader(title: 'CONFIGURACIÓN'), // i18n: Fase W3
          const SizedBox(height: 4),
          Text(
            'Cuenta · Negocio · Preferencias', // i18n: Fase W3
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SubNav(
                  selected: selected,
                  onSelect: (t) =>
                      ref.read(_ajustesTabProvider.notifier).state = t,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: SingleChildScrollView(child: _TabBody(tab: selected)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Candidato futuro a componente del kit: es el único rail vertical del hub
// hoy — si aparece un segundo caso de uso, extraer a coach_hub_widgets.
class _SubNav extends StatelessWidget {
  const _SubNav({required this.selected, required this.onSelect});

  final AjustesTab selected;
  final ValueChanged<AjustesTab> onSelect;

  @override
  Widget build(BuildContext context) {
    const tabs = AjustesTab.values;
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tabs.length; i++)
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(i),
              child: _SubNavItem(
                tab: tabs[i],
                selected: tabs[i] == selected,
                onTap: () => onSelect(tabs[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Item de la sub-nav vertical de Ajustes — interacción vía
/// [TreinoInteractiveState] (fuente única de verdad, ADR-SH-002): hover,
/// pressed, focus por teclado + Semantics(button) + activación por
/// Enter/Space. `selected` se expone también en Semantics para que el
/// estado de selección sea consultable por lectores de pantalla y tests.
class _SubNavItem extends StatelessWidget {
  const _SubNavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AjustesTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final focusTokens = TreinoFocusTokens.of(context);

    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: TreinoInteractiveState(
          onTap: onTap,
          builder: (ctx, states) {
            final soft = states.hovered || states.pressed;

            final Color background = selected
                ? palette.bgCard
                : soft
                    ? palette.bgCard.withValues(alpha: 0.6)
                    : TreinoTransparentTokens.value;

            final Color borderColor =
                selected ? palette.accent : TreinoTransparentTokens.value;

            return AnimatedContainer(
              key: Key('ajustes_subnav_${tab.name}'),
              duration: AppMotion.resolve(ctx, AppMotion.fast),
              curve: AppMotion.standard,
              margin: const EdgeInsets.only(bottom: AppSpacing.hairline),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s14,
                vertical: AppSpacing.s12,
              ),
              decoration: BoxDecoration(
                color: background,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                boxShadow: states.focused
                    ? [
                        BoxShadow(
                          color: focusTokens.ring.withValues(alpha: 0.5),
                          spreadRadius: TreinoFocusTokens.ringWidth,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    tab.icon,
                    size: 18,
                    color: selected ? palette.accent : palette.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            selected ? palette.textPrimary : palette.textMuted,
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({required this.tab});

  final AjustesTab tab;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      AjustesTab.cuenta => const CuentaTab(),
      AjustesTab.notificaciones => const NotificacionesTab(),
      AjustesTab.facturacion => const FacturacionTab(),
    };
  }
}
