/// Tarjeta de estado de cuenta de un alumno (cobros pendientes + acción Marcar
/// pagado) para la sección Pagos del Coach Hub.
///
/// Extraído de `alumno_detail_screen.dart` (PR1 — refactor puro). El guard
/// `_inFlight` contra doble-cobro se preserva VERBATIM — sin cambio de lógica.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show CobroPendiente;

import 'payment_format.dart';

/// Tarjeta de estado de cuenta: muestra cobros pendientes y permite marcarlos
/// como pagados. Incluye el guard `_inFlight` para evitar doble-cobro mientras
/// la escritura viaja a Firestore.
class EstadoCuentaCard extends StatefulWidget {
  const EstadoCuentaCard({
    super.key,
    required this.palette,
    required this.pending,
    required this.onMarcarPagado,
  });

  final AppPalette palette;
  final List<CobroPendiente> pending;
  final Future<void> Function(CobroPendiente) onMarcarPagado;

  @override
  State<EstadoCuentaCard> createState() => _EstadoCuentaCardState();
}

class _EstadoCuentaCardState extends State<EstadoCuentaCard> {
  // Cobros con una escritura en vuelo. Deshabilita "Marcar pagado" mientras el
  // settle viaja a Firestore (write → snapshot → providers → rebuild oculta la
  // fila): sin esto, volver a tocar el botón en esa ventana doble-cobra.
  final _inFlight = <String>{};

  String _key(CobroPendiente c) =>
      '${c.athleteId}|${c.cadence.name}|${c.concept}|${c.amountArs}';

  Future<void> _tap(CobroPendiente c) async {
    final k = _key(c);
    if (_inFlight.contains(k)) return;
    setState(() => _inFlight.add(k));
    try {
      await widget.onMarcarPagado(c);
    } finally {
      if (mounted) setState(() => _inFlight.remove(k));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final pending = widget.pending;
    final Widget inner;
    if (pending.isEmpty) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sin cobros pendientes', // i18n
              style: TextStyle(color: palette.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Al día', // i18n
              style: TextStyle(
                  color: palette.accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
        ],
      );
    } else {
      final total = pending.fold<int>(0, (sum, c) => sum + c.amountArs);
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pendiente de cobro', // i18n
              style: TextStyle(color: palette.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(fmtArs(total),
              style: TextStyle(
                  color: palette.warning,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final c in pending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.concept,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: palette.textPrimary, fontSize: 14)),
                        Text(fmtArs(c.amountArs),
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed:
                        _inFlight.contains(_key(c)) ? null : () => _tap(c),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accent,
                      side: BorderSide(color: palette.border),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Marcar pagado', // i18n
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: inner,
    );
  }
}
