// Columna derecha del Dashboard ("Hoy") — DashboardRightColumn.
//
// Extraído de `coach_hub_dashboard_screen.dart` (ADR-D2-05, extracción
// incremental) y rediseñado con el kit v2: TreinoSectionHeader (headers) +
// TreinoStateSwitcher (loading/empty/data/error) + TreinoListRow (filas +
// skeleton) + TreinoEmptyState. REQ-HOY-07, REQ-HOY-08, REQ-HOY-09.
//
// ELIMINA los CircularProgressIndicator crudos de Próximas sesiones y
// Vencimientos 7d (WU-05 fase-2) — todo estado de carga pasa por el shimmer
// del kit vía TreinoListRow(loading: true), igual que dashboard_pending.dart.
//
// NO se agrega TreinoFadeSlideIn en las filas: son data-driven (streams que
// re-emiten) — pero cada una de las 3 cards de nivel superior (Próximas
// sesiones / Vencimientos / Inactivos) SÍ se envuelve en TreinoFadeSlideIn
// (entrada staggered del ensamble, WU-06 fase-2). [startIndex] permite que
// el screen raíz continúe la secuencia de stagger tras sus propias
// secciones (alert banner, welcome card, KPI strip, columna izquierda).
//
// Sigue el contrato de sección: sin Scaffold/SafeArea, AppPalette/AppL10n
// (ADR-CHW-005).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_badge_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/coach_hub/presentation/widgets/empty_state/empty_state.dart';
import 'package:treino/features/coach_hub/presentation/widgets/list_row/list_row.dart';
import 'package:treino/features/coach_hub/presentation/widgets/section_header/section_header.dart';
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

/// Columna derecha: Próximas sesiones + Vencimientos 7 días + Alumnos
/// inactivos. REQ-HOY-07, REQ-HOY-08, REQ-HOY-09.
class DashboardRightColumn extends StatelessWidget {
  const DashboardRightColumn({super.key, this.startIndex = 0});

  /// Índice de stagger del primer card (`_ProximasSesiones`) — las otras dos
  /// cards continúan en `startIndex + 1` y `startIndex + 2`. Permite que el
  /// screen raíz encadene el stagger tras sus propias secciones (WU-06).
  final int startIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(startIndex),
          child: const _ProximasSesiones(),
        ),
        const SizedBox(height: AppSpacing.s18),
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(startIndex + 1),
          child: const _Vencimientos7d(),
        ),
        const SizedBox(height: AppSpacing.s18),
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(startIndex + 2),
          child: const _InactivosSection(),
        ),
      ],
    );
  }
}

// ─── Card wrapper compartido ────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

/// Skeleton compartido — dos filas [TreinoListRow] en shimmer.
class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        TreinoListRow(title: '', loading: true),
        SizedBox(height: AppSpacing.s8),
        TreinoListRow(title: '', loading: true),
      ],
    );
  }
}

/// Error compartido — mensaje + retry opcional (mismo patrón que
/// dashboard_pending.dart).
class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.s8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: palette.accent),
              child: Text(l10n.coachRetryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Próximas sesiones (REAL) ───────────────────────────────────────────────

/// Muestra hasta 4 próximas citas confirmadas. REQ-HOY-07.
class _ProximasSesiones extends ConsumerWidget {
  const _ProximasSesiones();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final now = DateTime.now().toUtc();
    // La key de un provider .family DEBE ser estable entre builds. Usar
    // DateTime.now() con precisión de microsegundos genera una key distinta
    // en cada build → nueva instancia del family → loop infinito (mismo
    // gotcha documentado en dashboard_pending.dart / diseño original).
    // Truncamos al día (estable dentro del día UTC); el filtro fino usa
    // `now` más abajo.
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final windowEnd = todayStart.add(const Duration(days: 30));
    final key = TrainerAppointmentsKey(
      trainerId: uid,
      fromDate: todayStart,
      toDate: windowEnd,
    );
    final appointmentsAsync = ref.watch(trainerAppointmentsStreamProvider(key));

    List<Appointment>? rows;
    appointmentsAsync.whenData((appointments) {
      final upcoming = appointments
          .where(
            (a) =>
                a.status == AppointmentStatus.confirmed &&
                a.startsAt.isAfter(now),
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      rows = upcoming.take(4).toList();
    });

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TreinoSectionHeader(
            title: l10n.dashboardProximasSesionesSectionLabel,
          ),
          const SizedBox(height: AppSpacing.s12),
          TreinoStateSwitcher(
            childKey: ValueKey(_stateKey(appointmentsAsync, rows)),
            child: _ProximasSesionesContent(
              hasError: appointmentsAsync.hasError,
              rows: rows,
              onRetry: () => ref.invalidate(trainerAppointmentsStreamProvider),
            ),
          ),
        ],
      ),
    );
  }

  String _stateKey(
    AsyncValue<List<Appointment>> async,
    List<Appointment>? rows,
  ) {
    if (async.hasError) return 'error';
    if (rows == null) return 'loading';
    if (rows.isEmpty) return 'empty';
    return 'data';
  }
}

class _ProximasSesionesContent extends StatelessWidget {
  const _ProximasSesionesContent({
    required this.hasError,
    required this.rows,
    required this.onRetry,
  });

  final bool hasError;
  final List<Appointment>? rows;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    if (hasError) {
      return _SectionError(
        message: l10n.coachHubSectionLoadError,
        onRetry: onRetry,
      );
    }

    final list = rows;
    if (list == null) {
      return const _RowsSkeleton();
    }

    if (list.isEmpty) {
      return TreinoEmptyState(
        icon: TreinoIcon.emptyState,
        title: l10n.dashboardProximasSesionesEmpty,
      );
    }

    return Column(
      children: [
        for (final a in list) ...[
          _SesionRow(appointment: a),
          if (a != list.last) const SizedBox(height: AppSpacing.s8),
        ],
      ],
    );
  }
}

class _SesionRow extends StatelessWidget {
  const _SesionRow({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final local = appointment.startsAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';

    // La lista de próximas sesiones abarca hasta 30 días. Cuando la sesión
    // no es hoy, prefijamos el día ("mañana · 09:00" / "14/7 · 09:00") para
    // que el orden no se lea salteado.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(local.year, local.month, local.day);
    final daysAhead = sessionDay.difference(today).inDays;
    final String label;
    if (daysAhead <= 0) {
      label = time;
    } else if (daysAhead == 1) {
      label = '${l10n.dashboardProximaSesionManana} · $time';
    } else {
      label = '${local.day}/${local.month} · $time';
    }

    return TreinoListRow(
      leading: PostAvatar(
        authorDisplayName: appointment.athleteDisplayName,
        authorAvatarUrl: null,
        size: 32,
      ),
      title: appointment.athleteDisplayName,
      trailing: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          color: palette.accent,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ─── Vencimientos 7 días (REAL) ─────────────────────────────────────────────

/// Muestra vencidos de [pagosBucketsProvider] + link "Ver todos". REQ-HOY-08.
class _Vencimientos7d extends ConsumerWidget {
  const _Vencimientos7d();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final bucketsAsync = ref.watch(pagosBucketsProvider);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TreinoSectionHeader(title: l10n.dashboardVencimientosTitle),
          const SizedBox(height: AppSpacing.s12),
          TreinoStateSwitcher(
            childKey: ValueKey(_stateKey(bucketsAsync)),
            child: _VencimientosContent(
              bucketsAsync: bucketsAsync,
              onRetry: () => ref.invalidate(pagosBucketsProvider),
            ),
          ),
        ],
      ),
    );
  }

  String _stateKey(AsyncValue<PagosBuckets> async) {
    if (async.hasError) return 'error';
    if (async.isLoading && !async.hasValue) return 'loading';
    final vencidos = async.valueOrNull?.vencidos ?? const <Payment>[];
    return vencidos.isEmpty ? 'empty' : 'data';
  }
}

class _VencimientosContent extends StatelessWidget {
  const _VencimientosContent({
    required this.bucketsAsync,
    required this.onRetry,
  });

  final AsyncValue<PagosBuckets> bucketsAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    if (bucketsAsync.hasError) {
      return _SectionError(
        message: l10n.coachHubSectionLoadError,
        onRetry: onRetry,
      );
    }

    final buckets = bucketsAsync.valueOrNull;
    if (buckets == null) {
      return const _RowsSkeleton();
    }

    final vencidos = buckets.vencidos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vencidos.isEmpty)
          TreinoEmptyState(
            icon: TreinoIcon.emptyState,
            title: l10n.dashboardVencimientosEmpty,
          )
        else
          Column(
            children: [
              for (final p in vencidos) ...[
                _VencimientoRow(payment: p),
                if (p != vencidos.last) const SizedBox(height: AppSpacing.s8),
              ],
            ],
          ),
        const SizedBox(height: AppSpacing.s12),
        // TreinoInteractiveState (resolver de Focus/Semantics del kit) —
        // REEMPLAZA al TreinoTappable crudo, que no exponía Focus ni
        // Semantics(button) (CRITICAL#2 sdd-verify fase-2).
        TreinoInteractiveState(
          onTap: () => context.go('/pagos'),
          builder: (ctx, states) => Text(
            key: const Key('vencimientos_ver_todos'),
            l10n.dashboardVencimientosVerTodos,
            style: TextStyle(
              color: AppPalette.of(context).accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

class _VencimientoRow extends ConsumerWidget {
  const _VencimientoRow({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeTokens = TreinoBadgeTokens.of(context);
    final daysOverdue =
        DateTime.now().toUtc().difference(payment.createdAt.toUtc()).inDays;

    // Payment sólo trae athleteId → resolvemos nombre + avatar del alumno.
    final profile =
        ref.watch(userPublicProfileProvider(payment.athleteId)).valueOrNull;
    final name = profile?.displayName ?? '…';

    return TreinoListRow(
      leading: PostAvatar(
        authorDisplayName: name,
        authorAvatarUrl: profile?.avatarUrl,
        size: 32,
      ),
      title: name,
      trailing: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.hairline,
        ),
        decoration: BoxDecoration(
          color: badgeTokens.background,
          borderRadius: BorderRadius.circular(TreinoBadgeTokens.borderRadius),
        ),
        child: Text(
          '+$daysOverdue d',
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            color: badgeTokens.foreground,
          ),
        ),
      ),
    );
  }
}

// ─── Alumnos inactivos (REAL — driven by inactivosProvider) ────────────────

/// Alumnos inactivos — REQ-HOY-09.
class _InactivosSection extends ConsumerWidget {
  const _InactivosSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final inactivosAsync = ref.watch(inactivosProvider);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TreinoSectionHeader(title: l10n.dashboardInactivosTitle),
          const SizedBox(height: AppSpacing.s12),
          TreinoStateSwitcher(
            childKey: ValueKey(_stateKey(inactivosAsync)),
            child: _InactivosContent(
              inactivosAsync: inactivosAsync,
              onRetry: () => ref.invalidate(inactivosProvider),
            ),
          ),
        ],
      ),
    );
  }

  String _stateKey(AsyncValue<InactivosResult> async) {
    if (async.hasError) return 'error';
    if (async.isLoading && !async.hasValue) return 'loading';
    final ids = async.valueOrNull?.inactiveAthleteIds ?? const <String>[];
    return ids.isEmpty ? 'empty' : 'data';
  }
}

class _InactivosContent extends StatelessWidget {
  const _InactivosContent({
    required this.inactivosAsync,
    required this.onRetry,
  });

  final AsyncValue<InactivosResult> inactivosAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    if (inactivosAsync.hasError) {
      return _SectionError(
        message: l10n.coachHubSectionLoadError,
        onRetry: onRetry,
      );
    }

    final result = inactivosAsync.valueOrNull;
    if (result == null) {
      return const _RowsSkeleton();
    }

    final ids = result.inactiveAthleteIds;
    if (ids.isEmpty) {
      return TreinoEmptyState(
        icon: TreinoIcon.emptyState,
        title: l10n.dashboardInactivosEmpty,
      );
    }

    return Column(
      children: [
        for (final id in ids) ...[
          _InactivoRow(athleteId: id),
          if (id != ids.last) const SizedBox(height: AppSpacing.s8),
        ],
      ],
    );
  }
}

/// Fila de un alumno inactivo — resuelve el nombre vía
/// [userPublicProfileProvider] (mismo patrón que [_VencimientoRow]).
class _InactivoRow extends ConsumerWidget {
  const _InactivoRow({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final name = ref
            .watch(userPublicProfileProvider(athleteId))
            .valueOrNull
            ?.displayName ??
        '…';

    return TreinoListRow(
      leading: Icon(TreinoIcon.tabProfile, size: 20, color: palette.textMuted),
      title: name,
    );
  }
}
