// Zona hero del Dashboard ("Hoy") — alert banner + welcome card.
//
// Extraído de `coach_hub_dashboard_screen.dart` (ADR-D2-05, extracción
// incremental) para dejar el screen como raíz de composición. Sigue el
// contrato de sección: sin Scaffold/SafeArea, AppPalette, TreinoIcon,
// AppL10n (ADR-CHW-005).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/dashboard_day_counts.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ── Alert banner (REAL — composes vencidos + solicitudes + inactivos) ────────

/// Alert banner — REQ-HOY-03.
///
/// Watches three signals:
/// - [pagosBucketsProvider].vencidos count
/// - [trainerLinksStreamProvider] pending solicitudes
/// - [inactivosProvider].inactiveCount
///
/// Shows "Todo al día" (sin CTA) cuando todos los contadores son 0; en caso
/// contrario, muestra el resumen compuesto + un CTA que navega a la sección
/// más urgente (vencidos > solicitudes > inactivos).
class DashboardAlertBanner extends ConsumerWidget {
  const DashboardAlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final bucketsAsync = ref.watch(pagosBucketsProvider);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final inactivosAsync = ref.watch(inactivosProvider);

    final vencidosCount = bucketsAsync.valueOrNull?.vencidos.length ?? 0;
    final solicitudesCount = linksAsync.valueOrNull
            ?.where((l) => l.status == TrainerLinkStatus.pending)
            .length ??
        0;
    final inactivosCount = inactivosAsync.valueOrNull?.inactiveCount ?? 0;

    final allClear =
        vencidosCount == 0 && solicitudesCount == 0 && inactivosCount == 0;

    final text = allClear
        ? l10n.dashboardAlertBannerAllClear
        : l10n.dashboardAlertBannerSummary(
            vencidosCount,
            solicitudesCount,
            inactivosCount,
          );

    // Sección más urgente: vencidos tiene ruta propia (/pagos); solicitudes
    // e inactivos se gestionan ambos desde /alumnos (no hay ruta dedicada
    // por separado para cada uno).
    final String? urgentRoute = vencidosCount > 0
        ? '/pagos'
        : (solicitudesCount > 0 || inactivosCount > 0)
            ? '/alumnos'
            : null;

    return Container(
      key: const Key('alert_banner_root'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s18,
        vertical: AppSpacing.s14,
      ),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.s8),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              TreinoIcon.alertAttention,
              size: 16,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.6,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (urgentRoute != null) ...[
            const SizedBox(width: AppSpacing.s12),
            _AlertBannerCta(route: urgentRoute, l10n: l10n),
          ],
        ],
      ),
    );
  }
}

/// CTA "revisar todo" del alert banner — pill mint envuelta en
/// [TreinoTappable] (REEMPLAZA al OutlinedButton, sin doble recognizer).
///
/// No existe key l10n dedicada para el copy del mockup ("Revisar todo") — el
/// l10n está congelado (ADR-D2-03, cero keys nuevas). Se reusa
/// [AppL10n.workoutHistorialSeeAll] ("Ver todo"), el texto genérico más
/// cercano disponible en todo el árbol de l10n.
class _AlertBannerCta extends StatelessWidget {
  const _AlertBannerCta({required this.route, required this.l10n});

  final String route;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoTappable(
      onTap: () => context.go(route),
      child: Container(
        key: const Key('alert_banner_cta'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          l10n.workoutHistorialSeeAll,
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.6,
            color: palette.bg,
          ),
        ),
      ),
    );
  }
}

// ── Welcome card ──────────────────────────────────────────────────────────────

/// Welcome card — greeting + summary + quick actions + anillo de
/// adherencia. REQ-HOY-04.
class DashboardWelcomeCard extends ConsumerWidget {
  const DashboardWelcomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Name from userProfileProvider.
    final profileAsync = ref.watch(userProfileProvider);
    final displayName = profileAsync.valueOrNull?.displayName ?? '';
    final firstName = displayName.trim().split(RegExp(r'\s+')).first;

    // Unread message count.
    final unread = ref.watch(totalUnreadCountProvider);

    // Pending solicitudes count (para revisar).
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final pendingCount = linksAsync.valueOrNull
            ?.where((l) => l.status == TrainerLinkStatus.pending)
            .length ??
        0;

    // Sesiones hoy count via trainerAppointmentsStreamProvider + dashboardDayCounts.
    final uid = ref.watch(currentUidProvider) ?? '';
    final now = DateTime.now().toUtc();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final appointmentsAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: uid,
          fromDate: todayStart,
          toDate: todayEnd,
        ),
      ),
    );
    final sessionCounts = dashboardDayCounts(
      appointmentsAsync.valueOrNull ?? [],
      now,
    );

    // Vencidos count from pagosBucketsProvider.
    final bucketsAsync = ref.watch(pagosBucketsProvider);
    final vencidosCount = bucketsAsync.valueOrNull?.vencidos.length ?? 0;

    return Container(
      key: const Key('welcome_card_root'),
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting — el nombre se resalta en palette.accent (mockup).
          _Greeting(name: firstName.toUpperCase(), l10n: l10n),
          const SizedBox(height: AppSpacing.hairline),
          // Summary line
          Text(
            l10n.dashboardSummaryLine(
              sessionCounts.pending,
              pendingCount,
              vencidosCount,
            ),
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.s18),
          // Quick actions row + adherencia ring
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    _PrimaryQuickAction(
                      key: const Key('quick_action_nuevo_alumno'),
                      label: l10n.dashboardQuickActionNuevoAlumno,
                      onTap: () => context.go('/alumnos'),
                    ),
                    _QuickAction(
                      key: const Key('quick_action_crear_rutina'),
                      label: l10n.dashboardQuickActionCrearRutina,
                      onTap: () => context.go('/biblioteca'),
                    ),
                    _QuickAction(
                      key: const Key('quick_action_mensajes'),
                      label: l10n.dashboardQuickActionMensajes(unread),
                      onTap: () => context.go('/mensajes'),
                    ),
                    _QuickAction(
                      key: const Key('quick_action_importar_plan'),
                      label: l10n.dashboardQuickActionImportarPlan,
                      onTap: () => context.push('/upload-plan'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s18),
              const DashboardAdherenceRing(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Saludo "BUENAS, {NAME}" con el nombre resaltado en [AppPalette.accent].
///
/// El string completo viene de [AppL10n.dashboardGreeting] (l10n congelado,
/// ADR-D2-03) — se ubica la posición de [name] dentro del string resultante
/// para partirlo en spans sin hardcodear ningún literal ("BUENAS," no se
/// hardcodea acá, funciona para cualquier locale que reordene el copy).
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.l10n});

  final String name;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final greeting = l10n.dashboardGreeting(name);
    final baseStyle = TextStyle(
      fontFamily: AppFonts.barlowCondensed,
      color: palette.textPrimary,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );

    final nameIndex = name.isEmpty ? -1 : greeting.indexOf(name);
    if (nameIndex == -1) {
      return Text(greeting, style: baseStyle);
    }

    final before = greeting.substring(0, nameIndex);
    final after = greeting.substring(nameIndex + name.length);

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: before),
          TextSpan(
              text: name, style: baseStyle.copyWith(color: palette.accent)),
          TextSpan(text: after),
        ],
      ),
    );
  }
}

/// Acción primaria ("+ Nuevo alumno") — pill mint filled envuelta en
/// [TreinoTappable] (press scale). El resto de las quick actions usan
/// [_QuickAction] (OutlinedButton, que ya maneja su propio tap — NO se
/// envuelve con TreinoTappable, evita doble recognizer).
class _PrimaryQuickAction extends StatelessWidget {
  const _PrimaryQuickAction(
      {super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            color: palette.bg,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Quick action secundaria — OutlinedButton (ya maneja su propio tap).
class _QuickAction extends StatelessWidget {
  const _QuickAction({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppFonts.barlowCondensed,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Anillo de adherencia — agregado real de [aggregateAdherenceProvider].
/// REQ-HOY-04B.
///
/// Gauge determinado (`value: pct`), no un spinner de carga — degrada a
/// "--" vía `valueOrNull` (ADR-D2-07). No existen keys l10n para labels
/// "ADHER."/"PROMEDIO" del mockup — se deja el % solo (ADR-D2-03, no se
/// inventan literales).
class DashboardAdherenceRing extends ConsumerWidget {
  const DashboardAdherenceRing({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // valueOrNull: resuelve a null mientras carga → muestra "--" (sin hang
    // de pumpAndSettle).
    final adherence = ref.watch(aggregateAdherenceProvider).valueOrNull;

    final String label;
    final double ringValue;
    if (adherence == null) {
      label = l10n.dashboardAdherenceRingPlaceholder; // "--"
      ringValue = 0;
    } else {
      label = l10n.dashboardAdherenceValue(adherence.round());
      ringValue = (adherence / 100).clamp(0.0, 1.0);
    }

    return SizedBox(
      key: const Key('adherence_ring_root'),
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: ringValue,
            strokeWidth: 6,
            backgroundColor: palette.border,
            color: adherence == null
                ? palette.accent.withValues(alpha: 0.3)
                : palette.accent,
          ),
          Text(
            label,
            style: TextStyle(
              color:
                  adherence == null ? palette.textMuted : palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
