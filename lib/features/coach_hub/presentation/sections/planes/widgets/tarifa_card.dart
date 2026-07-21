// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n. No se usa AppL10n
// (constraint C-6).
//
// Card de tarifa comercial — sección Planes comerciales del Coach Hub web
// (Fase 10, WU-04).
library;

import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';

import '../tarifas_model.dart';

// ── Labels es-AR ──────────────────────────────────────────────────────────────

/// Etiqueta es-AR de una [BillingCadence] para el badge de [TarifaCard].
String cadenceLabel(BillingCadence cadence) => switch (cadence) {
      BillingCadence.mensual => 'MENSUAL', // i18n
      BillingCadence.semanal => 'SEMANAL', // i18n
      BillingCadence.porSesion => 'POR SESIÓN', // i18n
      BillingCadence.suelto => 'SUELTO', // i18n
    };

/// Sufijo de precio es-AR de una [BillingCadence] (ej. `$15.000` + `/mes`).
String cadenceSuffix(BillingCadence cadence) => switch (cadence) {
      BillingCadence.mensual => '/mes', // i18n
      BillingCadence.semanal => '/semana', // i18n
      BillingCadence.porSesion => '/sesión', // i18n
      BillingCadence.suelto => 'único', // i18n
    };

// ── TarifaCard ────────────────────────────────────────────────────────────────

/// Card de una tarifa comercial real (grupo de alumnos con el mismo monto +
/// cadencia), derivada de [TarifaGroup] (`tarifas_model.dart`).
///
/// ADR-F10-01/02 (descope, honestidad de datos): NO hay nombre de plan,
/// features ni visibilidad pública/privada — solo lo que existe en
/// [AthleteBilling] (precio, cadencia, cantidad de alumnos). El chip "Más
/// usada" es honesto: refleja el grupo con más alumnos
/// (`TarifasResumen.masUsada`, la moda), no una métrica de conversión
/// inventada.
///
/// Read-only: [onTap] es opcional y por defecto `null` — sin acción real que
/// ofrecer todavía (no hay edición de tarifas cableada en esta fase). Con
/// `onTap: null`, [TreinoInteractiveState] entra en su modo "disabled": sin
/// hover, sin foco, sin `Semantics(button: true)` engañoso para el lector de
/// pantalla — mismo patrón que usa `KpiCard` cuando no se le pasa `onTap`.
class TarifaCard extends StatelessWidget {
  const TarifaCard({
    super.key,
    required this.group,
    this.masUsada = false,
    this.onTap,
  });

  final TarifaGroup group;

  /// `true` si este es el grupo con más alumnos de todo el resumen
  /// (`TarifasResumen.masUsada`).
  final bool masUsada;

  /// Acción al tocar la card. `null` = card puramente informativa (default).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final palette = AppPalette.of(ctx);
        final highlighted = states.hovered || states.pressed;

        return Semantics(
          key: const Key('tarifa_card_semantics'),
          label: '${cadenceLabel(group.cadence)}, '
              '${fmtArs(group.amountArs)}${cadenceSuffix(group.cadence)}, '
              '${group.alumnosCount} '
              '${pluralizarEs(group.alumnosCount, 'alumno', 'alumnos')}' // i18n
              '${masUsada ? ', más usada' : ''}', // i18n
          child: AnimatedContainer(
            key: const Key('tarifa_card_root'),
            duration: AppMotion.resolve(ctx, AppMotion.fast),
            curve: AppMotion.standard,
            padding: const EdgeInsets.all(AppSpacing.s18),
            decoration: BoxDecoration(
              color: highlighted
                  ? palette.accent.withValues(alpha: 0.06)
                  : palette.bgCard,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: highlighted ? palette.borderHover : palette.border,
              ),
              // Sin boxShadow — elevation-free, ADR-SH-006.
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CadenceBadge(label: cadenceLabel(group.cadence)),
                    if (masUsada) const _MasUsadaChip(),
                  ],
                ),
                const SizedBox(height: AppSpacing.s14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        fmtArs(group.amountArs),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.barlowCondensed,
                          fontWeight: AppFonts.w700,
                          fontSize: 30,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.hairline),
                    Text(
                      cadenceSuffix(group.cadence),
                      style: TextStyle(
                        fontFamily: AppFonts.barlow,
                        fontSize: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                Text(
                  '${group.alumnosCount} '
                  '${pluralizarEs(group.alumnosCount, 'alumno', 'alumnos')}', // i18n
                  style: TextStyle(
                    fontFamily: AppFonts.barlow,
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _CadenceBadge extends StatelessWidget {
  const _CadenceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline,
      ),
      decoration: BoxDecoration(
        color: palette.border,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.barlowCondensed,
          fontWeight: AppFonts.w700,
          fontSize: 11,
          letterSpacing: AppFonts.headingTracking,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

class _MasUsadaChip extends StatelessWidget {
  const _MasUsadaChip();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const Key('tarifa_card_mas_usada_chip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline,
      ),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: palette.accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Más usada', // i18n
        style: TextStyle(
          fontFamily: AppFonts.barlowCondensed,
          fontWeight: AppFonts.w700,
          fontSize: 11,
          color: palette.accent,
        ),
      ),
    );
  }
}
