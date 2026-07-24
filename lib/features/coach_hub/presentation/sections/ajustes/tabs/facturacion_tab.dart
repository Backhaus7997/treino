import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

/// Tab «Facturación TREINO» (Fase W3.4 / Fase 12 WU-06).
///
/// Facturación de la SUSCRIPCIÓN del PF a TREINO (su plan + comprobantes de lo
/// que le paga a la app). La facturación de alumnos (PF → alumnos) vive en la
/// sección Pagos, no acá.
///
/// No hay backend de suscripción/billing todavía (monetización = Fase 7,
/// ADR-F12-01/F12-05). Antes esto mostraba un mockup con plan, límite y
/// facturas de EJEMPLO; se reemplazó por un [TreinoEmptyState] honesto para
/// NO simular funcionalidad inexistente. El único dato real disponible hoy es
/// el uso (alumnos activos), mostrado en un [KpiCard] con loading real vía
/// [TreinoStateSwitcher]. Cuando Fase 7 traiga el billing, se cablea acá
/// (plan real, CAMBIAR PLAN, PDFs e historial).
class FacturacionTab extends ConsumerWidget {
  const FacturacionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    // hasValue-first (pulido-post-revision, mismo defecto que el picker de
    // alumnos, commit cf1cc143): `trainerLinksStreamProvider` es un
    // StreamProvider en vivo — Riverpod 2.5+ preserva el valor previo
    // dentro de un `AsyncError` subsiguiente (copyWithPrevious/"seamless"),
    // así que `hasValue==true` Y `hasError==true` pueden darse a la vez
    // tras un error transitorio. `switch`/`.when()` despachan por SUBTIPO
    // runtime (ignoran `hasValue`) — se prioriza el valor cacheado.
    final stateKey = linksAsync.hasValue
        ? const ValueKey('data')
        : linksAsync.hasError
            ? const ValueKey('error')
            : const ValueKey('loading');

    final Widget kpiChild;
    if (linksAsync.hasValue) {
      final activos = linksAsync.requireValue
          .where((l) => l.status == TrainerLinkStatus.active)
          .map((l) => l.athleteId)
          .toSet()
          .length;
      kpiChild = KpiCard(value: '$activos', label: 'Alumnos activos'); // i18n
    } else if (linksAsync.hasError) {
      kpiChild = const KpiCard(value: '—', label: 'Alumnos activos');
    } else {
      kpiChild = const KpiCard(value: '', label: '', loading: true);
    }

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
        // Único dato REAL: uso actual del PF (alumnos activos).
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(0),
          child: TreinoStateSwitcher(
            childKey: stateKey,
            child: kpiChild,
          ),
        ),
        const SizedBox(height: 16),
        // Empty state honesto (sin plan/historial/PDFs falsos, Fase 7
        // pendiente de backend) — estático, no depende del stream de arriba.
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(1),
          child: const TreinoEmptyState(
            icon: TreinoIcon.money,
            title: 'Facturación próximamente', // i18n: Fase W3
            description: 'La suscripción y los comprobantes se habilitan '
                'con los pagos (Fase 7).', // i18n: Fase W3
          ),
        ),
      ],
    );
  }
}
