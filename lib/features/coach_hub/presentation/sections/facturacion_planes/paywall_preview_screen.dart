import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../coach/domain/subscription_tier.dart';
import 'keep_students_screen.dart';
import 'plan_limit_paywall.dart';

/// Pantalla PREVIEW de dev/smoke para las pantallas del paywall que se
/// disparan desde el backend (PR4/PR5), que aún no existe. Sin item de
/// sidebar — solo accesible por URL directa `/facturacion/preview`.
///
/// TODO(PR4/PR5): cuando el enforcement/downgrade real dispare estos modals,
/// esta pantalla puede quitarse (o dejarse escondida para regresión visual).
class PaywallPreviewScreen extends StatelessWidget {
  const PaywallPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAYWALL — PREVIEW (dev)',
            style: GoogleFonts.barlowCondensed(
              color: palette.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Dispara cada pantalla del paywall en sus distintos estados. '
            'Solo para smoke — el trigger real llega con PR4/PR5.',
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _PreviewButton(
            label: 'Bloqueo desde FREE (upsell → Plan 1)',
            palette: palette,
            onTap: () => showPlanLimitPaywall(
              context,
              currentTier: SubscriptionTier.free,
            ),
          ),
          _PreviewButton(
            label: 'Bloqueo desde PLAN 1 (upsell → Plan 2)',
            palette: palette,
            onTap: () => showPlanLimitPaywall(
              context,
              currentTier: SubscriptionTier.plan1,
            ),
          ),
          _PreviewButton(
            label: 'Bloqueo desde PLAN 2 (tope → plan a medida)',
            palette: palette,
            onTap: () => showPlanLimitPaywall(
              context,
              currentTier: SubscriptionTier.plan2,
            ),
          ),
          const SizedBox(height: 16),
          _PreviewButton(
            label: 'Keep-2 (elegir 2 al degradar)',
            palette: palette,
            onTap: () => context.push('/facturacion/preview/keep2'),
          ),
        ],
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            border: Border.all(color: palette.accent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              color: palette.accent,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Preview del keep-2 con alumnos de ejemplo.
class KeepStudentsPreview extends StatelessWidget {
  const KeepStudentsPreview({super.key});

  @override
  Widget build(BuildContext context) {
    const students = [
      KeepableStudent(athleteId: 'a1', displayName: 'Lucas Pérez'),
      KeepableStudent(athleteId: 'a2', displayName: 'Sofía Gómez'),
      KeepableStudent(athleteId: 'a3', displayName: 'Martín Díaz'),
      KeepableStudent(athleteId: 'a4', displayName: 'Ana Ruiz'),
      KeepableStudent(athleteId: 'a5', displayName: 'Bruno Torres'),
    ];
    return KeepStudentsScreen(
      students: students,
      initialSelection: const {'a1', 'a2'}, // default: 2 más recientes
      onConfirm: (kept) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview: conservás ${kept.join(", ")}')),
        );
      },
    );
  }
}
