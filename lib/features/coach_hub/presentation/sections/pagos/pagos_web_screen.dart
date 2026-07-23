// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PagosScreen shell: header + KPI row + filtro (TreinoFilterChips,
// Vencidos/Por vencer/Pagados/Todos, WU-05 Fase 9). Tabla vía
// CoachHubDataTable con celdas ricas, estados completos y acciones de fila
// (Marcar pagado / Recordar, WU-07 Fase 9).
//
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_focus_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';

import '../../widgets/coach_hub_widgets.dart'
    show TreinoFilterChips, TreinoInteractiveState, TreinoSectionHeader;
import 'widgets/athlete_picker_dialog.dart';
import 'widgets/marcar_pagado_actions.dart';
import 'widgets/pagos_buckets_provider.dart';
import 'widgets/pagos_filtro_provider.dart';
import 'widgets/pagos_kpi_row.dart';
import 'widgets/pagos_web_table.dart';

/// Etiquetas (es-AR) de cada [PagosFiltro], en el orden en que se muestran
/// los chips.
const _kFiltroLabels = {
  PagosFiltro.vencidos: 'Vencidos', // i18n
  PagosFiltro.porVencer: 'Por vencer', // i18n
  PagosFiltro.pagados: 'Pagados', // i18n
  PagosFiltro.todos: 'Todos', // i18n
};

// ── PagosScreen ───────────────────────────────────────────────────────────────

/// Sección Pagos del Coach Hub web.
///
/// Sigue el contrato de sección (ADR-CHW-005): sin Scaffold propio, sin
/// SafeArea. El shell [CoachHubScaffold] provee el chrome.
///
/// REQ-PAGW-SHELL-001, REQ-PAGW-SHELL-002, REQ-PAGW-KPI-001,
/// REQ-PAGW-TAB-001, REQ-PAGW-TAB-002, REQ-PAGW-EMPTY-001,
/// REQ-PAGW-TABLE-001, REQ-PAGW-ACTION-001, REQ-PAGW-ACTION-002,
/// REQ-PAGW-ACTION-003.
class PagosScreen extends ConsumerStatefulWidget {
  const PagosScreen({super.key});

  @override
  ConsumerState<PagosScreen> createState() => _PagosScreenState();
}

class _PagosScreenState extends ConsumerState<PagosScreen> {
  // Estado de orden de la tabla (WU-06) — owned por el screen, no por
  // PagosWebTable: el ordenamiento depende de `profiles` (nombre de alumno)
  // que ya se resuelve acá.
  String? _sortColumnKey;
  bool _sortAscending = true;

  /// Ordena [payments] según [_sortColumnKey]/[_sortAscending]. Sin columna
  /// activa, devuelve la lista tal cual (orden del bucket, DESC createdAt).
  List<Payment> _sorted(
    List<Payment> payments,
    Map<String, UserPublicProfile> profiles,
  ) {
    final key = _sortColumnKey;
    if (key == null) return payments;

    String nameOf(Payment p) =>
        (profiles[p.athleteId]?.displayName?.isNotEmpty == true
                ? profiles[p.athleteId]!.displayName!
                : 'Alumno') // i18n fallback, igual que PagosWebTable
            .toLowerCase();

    int cmp(Payment a, Payment b) => switch (key) {
          'alumno' => nameOf(a).compareTo(nameOf(b)),
          'monto' => a.amountArs.compareTo(b.amountArs),
          'vencimiento' =>
            (a.dueAt ?? a.createdAt).compareTo(b.dueAt ?? b.createdAt),
          _ => 0,
        };

    final sorted = List<Payment>.of(payments);
    sorted.sort(_sortAscending ? cmp : (a, b) => cmp(b, a));
    return sorted;
  }

  /// CTA "+ Registrar pago" (trainer-wide, sin alumno de contexto).
  ///
  /// ADR-F9-06 (remediación CRITICAL-1, verify ronda 1): primero elige el
  /// alumno vía [pickAthleteForPago] (roster real del trainer) y recién
  /// entonces delega en `registrarPago`, que abre `RegistrarPagoDialog` y
  /// persiste el resultado con `paymentRepositoryProvider.add` — el mismo
  /// helper que ya usa `alumno_detail_screen.dart`. Antes de esta pieza el
  /// diálogo se abría y el resultado se descartaba (botón fantasma, no
  /// persistía nada).
  Future<void> _onRegistrarPago() async {
    final athleteId = await pickAthleteForPago(context, ref);
    if (athleteId != null && mounted) {
      await registrarPago(context, ref, athleteId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bucketsAsync = ref.watch(pagosBucketsProvider);
    final filtro = ref.watch(pagosFiltroProvider);

    // Alias de pago del trainer, para el mensaje de recordatorio (WU-07).
    final paymentAlias = ref
        .watch(userProfileProvider.select((s) => s.valueOrNull?.paymentAlias));

    // Counts for chip badges (reactive).
    int vencidosN = 0;
    int porVencerN = 0;
    int pagadosN = 0;
    bucketsAsync.whenData((b) {
      vencidosN = b.vencidos.length;
      porVencerN = b.porVencer.length;
      pagadosN = b.pagados.length;
    });

    // Collect all unique athlete ids across all payments to resolve profiles
    // in a single batch fetch (no N+1). ADR-PGW design section 3.
    final allPayments = bucketsAsync.valueOrNull?.todos ?? const [];
    final athleteIds = allPayments.map((p) => p.athleteId).toSet().toList()
      ..sort();
    final batchKey = athleteIds.join(',');
    final profilesAsync = ref.watch(userPublicProfilesBatchProvider(batchKey));
    final profiles = profilesAsync.valueOrNull ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header + action (staggered, ADR-F9-04: sin "Exportar" —
        // no hay exportador real) ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TreinoSectionHeader(title: 'Pagos'), // i18n
                      const SizedBox(height: AppSpacing.hairline),
                      Text(
                        'Cobros, vencimientos e ingresos', // i18n
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                _RegistrarPagoButton(onTap: _onRegistrarPago),
              ],
            ),
          ),
        ),

        // ── KPI row ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: const PagosKpiRow(),
          ),
        ),

        // ── Filtro (chips) ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: TreinoFadeSlideIn(
            delay: AppMotion.stagger(2),
            child: TreinoFilterChips(
              options: _kFiltroLabels.values.toList(),
              selected: {_kFiltroLabels[filtro]!},
              badgeCounts: {
                _kFiltroLabels[PagosFiltro.vencidos]!: vencidosN,
                _kFiltroLabels[PagosFiltro.porVencer]!: porVencerN,
                _kFiltroLabels[PagosFiltro.pagados]!: pagadosN,
              },
              onChanged: (newSelected) {
                // Single-select: un tap que vacía la selección (chip activo
                // desmarcado) es un no-op — siempre necesitamos un filtro
                // activo (mismo patrón que solicitudTabProvider).
                if (newSelected.isEmpty) return;
                final label = newSelected.first;
                for (final entry in _kFiltroLabels.entries) {
                  if (entry.value == label) {
                    ref.read(pagosFiltroProvider.notifier).state = entry.key;
                    break;
                  }
                }
              },
            ),
          ),
        ),

        // ── Tabla (según filtro activo) ────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            child: TreinoStateSwitcher(
              childKey: ValueKey('pagos_filtro_${filtro.name}'),
              child: _tabBody(
                bucketsAsync: bucketsAsync,
                getPayments: switch (filtro) {
                  PagosFiltro.vencidos => (b) => b.vencidos,
                  PagosFiltro.porVencer => (b) => b.porVencer,
                  PagosFiltro.pagados => (b) => b.pagados,
                  PagosFiltro.todos => (b) => b.todos,
                },
                emptyMessage: switch (filtro) {
                  PagosFiltro.vencidos => 'No hay pagos vencidos', // i18n
                  PagosFiltro.porVencer => 'No hay pagos pendientes', // i18n
                  PagosFiltro.pagados => 'No hay pagos registrados', // i18n
                  PagosFiltro.todos => 'No hay pagos', // i18n
                },
                profiles: profiles,
                // Tab Pagados no ofrece acciones — un pago ya cobrado no
                // necesita recordatorio ni "marcar pagado" de nuevo.
                showActions: filtro != PagosFiltro.pagados,
                paymentAlias: paymentAlias,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Construye la tabla del filtro activo. Loading / error / vacío ya no se
  /// resuelven acá (WU-06): [PagosWebTable] delega esos tres estados a
  /// `CoachHubDataTable` (shimmer / mensaje+retry / TreinoEmptyState).
  Widget _tabBody({
    required AsyncValue<PagosBuckets> bucketsAsync,
    required List<Payment> Function(PagosBuckets) getPayments,
    required String emptyMessage,
    required Map<String, UserPublicProfile> profiles,
    required bool showActions,
    required String? paymentAlias,
  }) {
    final payments = bucketsAsync.valueOrNull != null
        ? getPayments(bucketsAsync.valueOrNull!)
        : const <Payment>[];

    return PagosWebTable(
      payments: _sorted(payments, profiles),
      profiles: profiles,
      emptyMessage: emptyMessage,
      loading: bucketsAsync.isLoading,
      errorMessage:
          bucketsAsync.hasError ? 'Error al cargar pagos.' : null, // i18n
      onRetry: () => ref.invalidate(trainerPaymentsProvider),
      sortColumnKey: _sortColumnKey,
      sortAscending: _sortAscending,
      onSort: (key, ascending) => setState(() {
        _sortColumnKey = key;
        _sortAscending = ascending;
      }),
      showActions: showActions,
      onMarcarPagado: (p) => marcarPagadoDoc(context, ref, p),
      onRecordar: (p) => recordar(context, ref, p, paymentAlias),
    );
  }
}

// ── _RegistrarPagoButton ────────────────────────────────────────────────────

/// CTA accent del header de Pagos — abre [RegistrarPagoDialog].
///
/// Construido con [TreinoInteractiveState] (hover/pressed/focus + Semantics +
/// activación por teclado) en lugar de un `TextButton`/`ElevatedButton` ad-hoc
/// — mismo patrón que el resto del kit Coach Hub Web (ADR-SH-002).
class _RegistrarPagoButton extends StatelessWidget {
  const _RegistrarPagoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final focusTokens = TreinoFocusTokens.of(context);

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final highlighted = states.hovered || states.pressed;

        return AnimatedContainer(
          key: const Key('pagos_registrar_pago_cta'),
          duration: AppMotion.resolve(ctx, AppMotion.micro),
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s18,
            vertical: AppSpacing.s12,
          ),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: highlighted ? 0.88 : 1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            boxShadow: states.focused
                ? [
                    BoxShadow(
                      color: focusTokens.ring.withValues(alpha: 0.5),
                      spreadRadius: TreinoFocusTokens.ringWidth,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TreinoIcon.plus, size: 16, color: palette.bg),
              const SizedBox(width: AppSpacing.hairline),
              Text(
                'Registrar pago', // i18n
                style: TextStyle(
                  color: palette.bg,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
