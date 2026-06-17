import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_tab.dart';
import 'package:treino/features/coach_hub/presentation/shell/section_header.dart';

/// Tabs internos de la sección «Configuración» (Ajustes) del Coach Hub web.
enum AjustesTab { cuenta, notificaciones, facturacion, datos }

extension AjustesTabX on AjustesTab {
  String get label => switch (this) {
        AjustesTab.cuenta => 'Cuenta', // i18n: Fase W3
        AjustesTab.notificaciones => 'Notificaciones', // i18n: Fase W3
        AjustesTab.facturacion => 'Facturación TREINO', // i18n: Fase W3
        AjustesTab.datos => 'Datos y privacidad', // i18n: Fase W3
      };

  IconData get icon => switch (this) {
        AjustesTab.cuenta => TreinoIcon.users,
        AjustesTab.notificaciones => TreinoIcon.bell,
        AjustesTab.facturacion => TreinoIcon.sidebarPagos,
        AjustesTab.datos => TreinoIcon.shieldCheck,
      };
}

/// Tab seleccionado dentro de Configuración. `autoDispose`: vuelve a Cuenta al
/// salir y reentrar a `/ajustes`, consistente con el resto del Coach Hub web.
final _ajustesTabProvider = StateProvider.autoDispose<AjustesTab>(
  (_) => AjustesTab.cuenta,
);

/// Sección «Configuración» del Coach Hub web (`/ajustes`, Fase W3).
///
/// Header + sub-nav vertical (Cuenta · Notificaciones · Facturación · Datos) y
/// el cuerpo del tab activo. Renderiza DENTRO del shell — sin Scaffold propio
/// (ADR-CHW-005). W3.1 entrega el scaffold + la tab Cuenta; las otras tres son
/// placeholders hasta W3.2–W3.4.
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
          const SectionHeader(title: 'CONFIGURACIÓN'), // i18n: Fase W3
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

class _SubNav extends StatelessWidget {
  const _SubNav({required this.selected, required this.onSelect});

  final AjustesTab selected;
  final ValueChanged<AjustesTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tab in AjustesTab.values)
            _SubNavItem(
              icon: tab.icon,
              label: tab.label,
              selected: tab == selected,
              onTap: () => onSelect(tab),
              palette: palette,
            ),
        ],
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  const _SubNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? palette.bgCard : Colors.transparent,
          border: Border.all(
            color: selected ? palette.accent : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? palette.accent : palette.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? palette.textPrimary : palette.textMuted,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
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
      AjustesTab.facturacion => const _Proximamente(
          tab: AjustesTab.facturacion,
        ),
      AjustesTab.datos => const _Proximamente(tab: AjustesTab.datos),
    };
  }
}

class _Proximamente extends StatelessWidget {
  const _Proximamente({required this.tab});

  final AjustesTab tab;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          '${tab.label} · Próximamente', // i18n: Fase W3
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      ),
    );
  }
}
