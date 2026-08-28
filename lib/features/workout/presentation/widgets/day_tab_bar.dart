import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Estado de un día, tal como lo comunica su pestaña.
enum DayTabStatus {
  /// Sin problemas: no dibuja punto.
  ok,

  /// El día no tiene ningún ejercicio. Es un aviso, no un error bloqueante:
  /// el usuario puede estar por agregarlo.
  empty,

  /// El día tiene sets sin completar. Bloquea el guardado.
  invalid,
}

/// Fila de pestañas de día, con scroll horizontal.
///
/// Reemplaza a la pila de acordeones donde cada día ocupaba lugar aunque
/// estuviera cerrado. Se renderiza UN día a la vez: el scroll vertical pasa a
/// ser el de un día, no el de la rutina entera.
///
/// El punto de estado aparece **sólo en las pestañas inactivas**: en la activa
/// el problema ya se ve en el contenido, y repetirlo arriba es ruido.
class DayTabBar extends StatelessWidget {
  const DayTabBar({
    super.key,
    required this.labels,
    required this.statuses,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAddDay,
  });

  /// Nombre visible de cada día, en orden.
  final List<String> labels;

  /// Estado de cada día, en el mismo orden que [labels].
  final List<DayTabStatus> statuses;

  final int selectedIndex;
  final void Function(int index) onSelect;

  /// `null` cuando ya se llegó al tope de días.
  final VoidCallback? onAddDay;

  /// Tope de caracteres del label. Un día llamado "Pecho, hombro y tríceps"
  /// empujaría el resto de las pestañas fuera de la pantalla.
  static const int _kMaxChars = 15;

  String _truncar(String s) =>
      s.length <= _kMaxChars ? s : '${s.substring(0, _kMaxChars)}…';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
        itemCount: labels.length + 1,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AppSpacing.hairline * 2),
        itemBuilder: (context, i) {
          if (i == labels.length) {
            return _BotonAgregar(palette: palette, onTap: onAddDay);
          }
          return _Pestana(
            key: Key('day_tab_$i'),
            label: _truncar(labels[i]),
            status: statuses[i],
            selected: i == selectedIndex,
            palette: palette,
            onTap: () => onSelect(i),
          );
        },
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    super.key,
    required this.label,
    required this.status,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final DayTabStatus status;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Texto ink sobre el relleno mint, NUNCA `palette.bg`: en tema claro ese
    // par compone 1,57:1. Ver AGENTS.md, regla 2.
    final fg =
        selected ? TreinoButtonTokens.foreground(context) : palette.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
          decoration: BoxDecoration(
            color: selected ? palette.accent : palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
            ),
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: fg,
                  ),
                ),
                // Sólo en las inactivas: en la activa el problema ya se ve
                // abajo, en el contenido del día.
                if (!selected && status != DayTabStatus.ok) ...[
                  const SizedBox(width: AppSpacing.hairline + 2),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: status == DayTabStatus.invalid
                          ? palette.danger
                          : palette.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonAgregar extends StatelessWidget {
  const _BotonAgregar({required this.palette, required this.onTap});

  final AppPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    return InkWell(
      key: const Key('day_tab_add'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 44,
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: habilitado ? palette.borderStrong : palette.border,
          ),
        ),
        child: Center(
          child: Icon(
            TreinoIcon.plus,
            size: 15,
            color: habilitado ? palette.textMuted : palette.textFaint,
          ),
        ),
      ),
    );
  }
}
