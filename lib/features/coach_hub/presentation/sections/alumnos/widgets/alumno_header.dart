import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../alumnos_screen.dart' show AlumnoEstado, AlumnoEstadoX;

/// Header de perfil del detalle de Alumno — Fase 3 WU-04.
///
/// Extraído de `_Header` (`alumno_detail_screen.dart`, ADR-A3-04). Avatar
/// magenta (`palette.highlight`) + nombre CAPS Barlow Condensed + badge de
/// estado (dot + label) + meta-chips reales (gym / inicio del vínculo / plan
/// · cadencia / próximo cobro — solo los que tienen dato detrás, ADR-A3-01:
/// el mockup pide Objetivo/Plan/Edad pero esos campos no existen todavía en
/// [UserPublicProfile], así que NO se inventan) + CTA "Pago".
///
/// El CTA sigue siendo un `OutlinedButton` sin envolver en `TreinoTappable`
/// (ya maneja su propio feedback de Material — envolverlo duplicaría el
/// gesture recognizer, ver docs de `TreinoTappable`).
class AlumnoHeader extends StatelessWidget {
  const AlumnoHeader({
    super.key,
    required this.profile,
    required this.link,
    required this.estado,
    required this.gymName,
    required this.billing,
    required this.onPago,
    required this.palette,
  });

  final UserPublicProfile? profile;
  final TrainerLink? link;
  final AlumnoEstado? estado;
  final String? gymName;
  final AthleteBilling? billing;
  final VoidCallback onPago;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? 'Atleta'; // i18n: Fase W2
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final avatarUrl = profile?.avatarUrl;
    final desde = link?.acceptedAt;
    final b = billing;
    // .toUtc() para compartir reloj con el pipeline de billing (monthKey/weekKey
    // de pagosPorCobrarProvider y las escrituras usan UTC); evita un desfase de
    // 1 día en el borde del período en AR (UTC-3).
    final proxCobro = b == null ? null : nextDueDate(b, DateTime.now().toUtc());

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: palette.highlight.withValues(alpha: 0.15),
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? NetworkImage(avatarUrl)
                : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Text(
                    initial,
                    style: TextStyle(
                      color: palette.highlight,
                      fontSize: 24,
                      fontWeight: AppFonts.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: AppSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toUpperCase(),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontFamily: AppFonts.barlowCondensed,
                    fontWeight: AppFonts.w700,
                    fontSize: 22,
                    letterSpacing: AppFonts.headingTracking,
                  ),
                ),
                const SizedBox(height: AppSpacing.hairline),
                Wrap(
                  spacing: AppSpacing.s12,
                  runSpacing: AppSpacing.hairline,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (estado != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _EstadoDot(color: estado!.color(palette)),
                          const SizedBox(width: AppSpacing.hairline),
                          Text(
                            estado!.label(AppL10n.of(context)),
                            style: TextStyle(
                              color: estado!.color(palette),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    if (gymName != null)
                      Text(
                        gymName!,
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 13),
                      ),
                    if (desde != null)
                      Text(
                        'Desde ${fmtDate(desde)}', // i18n: Fase W2
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 13),
                      ),
                    if (b != null && b.cadence != BillingCadence.suelto)
                      Text(
                        '${fmtArs(b.amountArs)} · ${_cadenciaLabel(b.cadence)}', // i18n: Fase W2
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 13),
                      ),
                    if (proxCobro != null)
                      Text(
                        'Próx. cobro: ${fmtDayMonth(proxCobro)}', // i18n: Fase W2
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 13),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          OutlinedButton(
            onPressed: onPago,
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.accent,
              side: BorderSide(color: palette.border),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s14,
                vertical: AppSpacing.s8,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Pago', // i18n: Fase W2
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoDot extends StatelessWidget {
  const _EstadoDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

String _cadenciaLabel(BillingCadence c) => switch (c) {
      BillingCadence.mensual => 'Mensual', // i18n: Fase W2
      BillingCadence.semanal => 'Semanal',
      BillingCadence.porSesion => 'Por sesión',
      BillingCadence.suelto => 'Suelto',
    };
