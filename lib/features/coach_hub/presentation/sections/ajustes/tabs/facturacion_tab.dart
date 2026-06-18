import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

/// Tab «Facturación TREINO» (Fase W3.4) — vista previa del mockup completo.
///
/// Facturación de la SUSCRIPCIÓN del PF a TREINO (su plan + comprobantes de lo
/// que le paga a la app). La facturación de alumnos (PF → alumnos) vive en la
/// sección Pagos, no acá.
///
/// No hay backend de suscripción/billing todavía (monetización = Fase 7): el
/// plan, el límite, el historial y los comprobantes son DATOS DE EJEMPLO,
/// marcados explícitamente con un footnote. El único dato REAL es el uso
/// (alumnos activos, de `trainerLinksStreamProvider`). Cuando Fase 7 traiga el
/// billing, se cablea acá (CAMBIAR PLAN, PDFs e historial reales).
class FacturacionTab extends ConsumerWidget {
  const FacturacionTab({super.key});

  /// Historial de ejemplo — placeholder hasta Fase 7. (fecha, monto)
  static const _ejemploHistorial = <(String, String)>[
    ('29 ene 2025', '\$12.000'),
    ('29 dic 2024', '\$12.000'),
    ('29 nov 2024', '\$12.000'),
    ('29 oct 2024', '\$12.000'),
  ];

  /// Límite de alumnos del plan — de ejemplo (no hay plan real hasta Fase 7).
  static const _planLimite = 40;

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Próximamente')), // i18n: Fase W3
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final links = ref.watch(trainerLinksStreamProvider).valueOrNull ?? const [];
    final activos = links
        .where((l) => l.status == TrainerLinkStatus.active)
        .map((l) => l.athleteId)
        .toSet()
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FACTURACIÓN TREINO', // i18n: Fase W3
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tu plan y comprobantes de TREINO.', // i18n: Fase W3
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _PlanCard(
          activos: activos,
          limite: _planLimite,
          onCambiar: () => _soon(context),
        ),
        const SizedBox(height: 16),
        _HistorialCard(
          rows: _ejemploHistorial,
          onPdf: () => _soon(context),
        ),
        const SizedBox(height: 14),
        Text(
          // Honestidad: ver doc de la clase. Marca los datos como ejemplo.
          'Vista previa con datos de ejemplo — el plan y la facturación reales '
          'se habilitan con los pagos (próximamente).', // i18n: Fase W3
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.activos,
    required this.limite,
    required this.onCambiar,
  });

  final int activos;
  final int limite;
  final VoidCallback onCambiar;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final ratio = limite <= 0 ? 0.0 : (activos / limite).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
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
                    Text(
                      'PLAN ACTUAL', // i18n: Fase W3
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'TREINO Coach Solo', // i18n: Fase W3 (ejemplo)
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onCambiar,
                child: const Text('CAMBIAR PLAN'), // i18n: Fase W3
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '$activos / $limite alumnos', // i18n: Fase W3
            style: TextStyle(color: palette.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: palette.bg,
              color: palette.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorialCard extends StatelessWidget {
  const _HistorialCard({required this.rows, required this.onPdf});

  final List<(String, String)> rows;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HISTORIAL DE FACTURACIÓN', // i18n: Fase W3
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          for (final (fecha, monto) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fecha,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    monto,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 14),
                  _PagadoBadge(palette: palette),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onPdf,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.accent,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('PDF'), // i18n: Fase W3
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PagadoBadge extends StatelessWidget {
  const _PagadoBadge({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.accent),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'PAGADO', // i18n: Fase W3
        style: TextStyle(
          color: palette.accent,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
