import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';

/// Qué eje del plan free se tocó. Cambia sólo el cuerpo del mensaje: el título
/// y la acción son los mismos.
enum FreePlanLimit { days, weeks }

/// Hoja que explica por qué no se pudo agregar un día (o una semana) más.
///
/// Se abre desde el editor de rutinas cuando el alumno está en `free` y toca
/// el "+" que cruzaría el tope. La abre el TAP, no el guardado, a propósito:
/// es el instante exacto en que el tope muerde, y frenar recién al guardar
/// —después de que cargó ejercicios y series— haría que pierda el trabajo.
///
/// **No tiene botón de pago todavía.** El checkout web del alumno no existe
/// (`docs/paywall-alumno-suelto.md` §7.1), y un CTA que no lleva a ningún lado
/// es peor que no tenerlo: promete una salida que no está. Cuando el checkout
/// exista, [onUpgrade] deja de ser `null` y la hoja dibuja el botón sola.
Future<void> showFreePlanLimitSheet(
  BuildContext context, {
  required FreePlanLimit limit,
  VoidCallback? onUpgrade,
}) {
  final palette = AppPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) => _FreePlanLimitBody(limit: limit, onUpgrade: onUpgrade),
  );
}

class _FreePlanLimitBody extends StatelessWidget {
  const _FreePlanLimitBody({required this.limit, this.onUpgrade});

  final FreePlanLimit limit;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s18,
          AppSpacing.s12,
          AppSpacing.s18,
          AppSpacing.s18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                key: const Key('free_plan_limit_grabber'),
                width: 40,
                height: AppSpacing.hairline,
                decoration: BoxDecoration(
                  color: palette.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s18),
            Row(
              children: [
                Icon(TreinoIcon.lock, size: 18, color: palette.textMuted),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    l10n.paywallFreePlanLimitTitle,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              switch (limit) {
                FreePlanLimit.days => l10n.paywallFreePlanLimitDaysBody,
                FreePlanLimit.weeks => l10n.paywallFreePlanLimitWeeksBody,
              },
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.s18),
            if (onUpgrade != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('free_plan_limit_upgrade'),
                  onPressed: onUpgrade,
                  child: Text(l10n.paywallFreePlanLimitUpgrade),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('free_plan_limit_dismiss'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.paywallFreePlanLimitDismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
