import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

/// Tab «Facturación TREINO» (Fase W3.4).
///
/// Facturación de la SUSCRIPCIÓN del PF a TREINO (su plan + comprobantes de lo
/// que le paga a la app). La facturación de alumnos (PF → alumnos) vive en la
/// sección Pagos, no acá.
///
/// No hay backend de suscripción/billing todavía (monetización = Fase 7). Antes
/// esto mostraba un mockup con plan, límite y facturas de EJEMPLO; se reemplazó
/// por un empty state honesto para NO simular funcionalidad inexistente. El
/// único dato real disponible hoy es el uso (alumnos activos). Cuando Fase 7
/// traiga el billing, se cablea acá (plan real, CAMBIAR PLAN, PDFs e historial).
class FacturacionTab extends ConsumerWidget {
  const FacturacionTab({super.key});

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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: palette.bgCard,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(TreinoIcon.money, size: 40, color: palette.textMuted),
              const SizedBox(height: 12),
              Text(
                'Facturación próximamente', // i18n: Fase W3
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La suscripción y los comprobantes se habilitan con los '
                'pagos (Fase 7).', // i18n: Fase W3
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text(
                // Único dato REAL: uso actual del PF.
                activos == 1
                    ? '1 alumno activo' // i18n: Fase W3
                    : '$activos alumnos activos', // i18n: Fase W3
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
