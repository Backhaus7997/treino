import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import 'wear_strings.dart';
import 'wear_view_models.dart';
import 'wear_widgets.dart';

/// Una de las listas laterales: planes a la izquierda, plantillas a la derecha.
///
/// **Réplica de `RoutineListView`** de
/// `ios/TreinoWatch Watch App/RoutineListView.swift`.
///
/// Lo que ya se mostraba NO se borra mientras recarga: cambiar la lista por un
/// spinner cada vez que el atleta pasa por la página parpadearía sin darle nada
/// a cambio. Y una recarga fallida con datos viejos en pantalla es mejor que un
/// cartel de error tapando la lista que estaba mirando — por eso el aviso de
/// falla sólo sale si no hay NADA que mostrar.
class WearRoutineList extends StatelessWidget {
  const WearRoutineList({
    super.key,
    required this.kind,
    required this.routines,
    required this.onSelect,
    this.isLoading = false,
    this.failed = false,
  });

  final WearRoutineListKind kind;
  final List<WearRoutineSummary> routines;
  final void Function(WearRoutineSummary) onSelect;
  final bool isLoading;
  final bool failed;

  String get _title => switch (kind) {
        WearRoutineListKind.plans => WearStrings.myPlans,
        WearRoutineListKind.templates => WearStrings.templates,
      };

  String get _emptyMessage => switch (kind) {
        WearRoutineListKind.plans => WearStrings.noPlans,
        WearRoutineListKind.templates => WearStrings.noTemplates,
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Centrado, a diferencia de watchOS. Allá la pantalla es rectangular y
        // el título va a la izquierda; en un círculo la esquina superior
        // izquierda es el punto MÁS angosto y el texto se recorta ahí.
        Center(child: WearSectionTitle(_title)),
        const SizedBox(height: 8),
        if (isLoading && routines.isEmpty)
          const Center(child: WearLoading(text: WearStrings.loading))
        else if (failed && routines.isEmpty)
          Text(
            WearStrings.loadFailed,
            style: GoogleFonts.barlow(fontSize: 11, color: palette.warning),
          )
        else if (routines.isEmpty)
          Text(
            _emptyMessage,
            style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
          )
        else
          for (final routine in routines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RoutineRow(
                routine: routine,
                onTap: () => onSelect(routine),
              ),
            ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Una fila de la lista.
///
/// Sin el detalle del plan: en una pantalla de reloj, el nombre y una chapita es
/// todo lo que se lee de un vistazo.
class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.routine, required this.onTap});

  final WearRoutineSummary routine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 48dp mínimo de área táctil, guías de Wear OS.
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              routine.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (routine.badge != null) ...[
                  Text(
                    routine.badge!,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    routine.subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.barlow(
                      fontSize: 10,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Qué hacer con una rutina de la lista.
///
/// **Réplica de `RoutineDetailView`.** Las dos acciones son distintas a propósito
/// y el dueño las pidió separadas: **empezar** arranca ese entreno sin tocar
/// nada, y **activar** cambia cuál es la rutina del atleta en TODA la app —
/// teléfono incluido. Mezclarlas haría que probar una plantilla le pisara el
/// plan que le armó su PF.
///
/// ⚠️ **«Activar» SÓLO se ofrece sobre planes, nunca sobre plantillas.**
/// `resolveActiveRoutineId` busca el marcador `activeRoutineId` dentro de las
/// listas de asignadas y auto-creadas: una plantilla no está en ninguna de las
/// dos, así que escribir su id ahí es una escritura que sale bien y **no hace
/// nada** — el atleta ve "listo" y HOY le sigue mostrando la rutina de antes.
/// Es el mismo criterio del teléfono, donde "Marcar como activa" aparece en
/// RUTINAS y no en PLANTILLAS.
class WearRoutineDetail extends StatelessWidget {
  const WearRoutineDetail({
    super.key,
    required this.routine,
    required this.kind,
    required this.onStart,
    required this.onActivate,
    required this.onClose,
    this.busy = false,
    this.errorMessage,
  });

  final WearRoutineSummary routine;
  final WearRoutineListKind kind;
  final VoidCallback onStart;
  final VoidCallback onActivate;
  final VoidCallback onClose;
  final bool busy;
  final String? errorMessage;

  /// Sólo los planes pueden ser la rutina activa — ver la nota de la clase.
  bool get _canActivate => kind == WearRoutineListKind.plans;

  String get _hint =>
      _canActivate ? WearStrings.hintPlans : WearStrings.hintTemplates;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.deferToChild,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  TreinoIcon.arrowLeft,
                  size: 16,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            routine.name,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (busy)
          const Center(child: WearLoading(text: WearStrings.loading))
        else ...[
          WearButton(label: WearStrings.start, onTap: onStart),
          if (_canActivate) ...[
            const SizedBox(height: 8),
            // `highlight` (magenta) y no `accent`: activar NO es empezar, y que
            // se distingan de color evita el toque equivocado con la muñeca
            // apurada.
            WearButton(
              label: WearStrings.activate,
              onTap: onActivate,
              tint: palette.highlight,
            ),
          ],
        ],
        const SizedBox(height: 12),
        Text(
          _hint,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(fontSize: 10, color: palette.textMuted),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(fontSize: 11, color: palette.warning),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}
