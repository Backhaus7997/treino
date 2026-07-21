// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR2a — PagosScreen shell: header + KPI row + 4 tabs (Vencidos/Por vencer/
// Pagados/Todos). Tabla rica con acciones de fila (Marcar pagado / Recordar)
// implementada en PR2b reemplazando _TabBody con PagosWebTable.
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
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';

import '../../widgets/coach_hub_widgets.dart'
    show TreinoInteractiveState, TreinoSectionHeader;
import 'widgets/marcar_pagado_actions.dart';
import 'widgets/pagos_buckets_provider.dart';
import 'widgets/pagos_kpi_row.dart';
import 'widgets/pagos_web_table.dart';
import 'widgets/registrar_pago_dialog.dart';

// ── PagosScreen ───────────────────────────────────────────────────────────────

/// Sección Pagos del Coach Hub web.
///
/// Sigue el contrato de sección (ADR-CHW-005): sin Scaffold propio, sin
/// SafeArea. El shell [CoachHubScaffold] provee el chrome.
///
/// REQ-PAGW-SHELL-001, REQ-PAGW-SHELL-002, REQ-PAGW-KPI-001,
/// REQ-PAGW-TAB-001, REQ-PAGW-TAB-002, REQ-PAGW-EMPTY-001,
/// REQ-PAGW-TABLE-001, REQ-PAGW-ACTION-001, REQ-PAGW-ACTION-002.
class PagosScreen extends ConsumerStatefulWidget {
  const PagosScreen({super.key});

  @override
  ConsumerState<PagosScreen> createState() => _PagosScreenState();
}

class _PagosScreenState extends ConsumerState<PagosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _kTabs = ['Vencidos', 'Por vencer', 'Pagados', 'Todos']; // i18n

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kTabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onRegistrarPago() async {
    await showDialog<({int amount, String concept})>(
      context: context,
      builder: (_) => const RegistrarPagoDialog(),
    );
    // NOTE: RegistrarPagoDialog is a trainer-wide dialog without athlete picker.
    // The dialog itself handles cancellation/submission. Persistence happens
    // inside the dialog if an athleteId can be provided.
    // Full athlete-picker wiring for the trainer-wide context is tracked V2
    // (requires showing an athlete selection before the dialog).
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bucketsAsync = ref.watch(pagosBucketsProvider);

    // Trainer's paymentAlias for WhatsApp reminder messages.
    final paymentAlias = ref
        .watch(userProfileProvider.select((s) => s.valueOrNull?.paymentAlias));

    // Counts for tab labels (reactive).
    int vencidosN = 0;
    int porVencerN = 0;
    int pagadosN = 0;
    int todosN = 0;
    bucketsAsync.whenData((b) {
      vencidosN = b.vencidos.length;
      porVencerN = b.porVencer.length;
      pagadosN = b.pagados.length;
      todosN = b.todos.length;
    });

    final tabLabels = [
      'Vencidos · $vencidosN', // i18n
      'Por vencer · $porVencerN', // i18n
      'Pagados · $pagadosN', // i18n
      'Todos · $todosN', // i18n
    ];

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

        // ── TabBar ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: palette.accent,
            unselectedLabelColor: palette.textMuted,
            indicatorColor: palette.accent,
            indicatorWeight: 2,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            tabs: tabLabels.map((l) => Tab(text: l)).toList(),
          ),
        ),

        // ── Tab body ────────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Vencidos tab
              _tabBody(
                bucketsAsync: bucketsAsync,
                getPayments: (b) => b.vencidos,
                emptyLabel: 'No hay pagos vencidos', // i18n
                palette: palette,
                profiles: profiles,
                paymentAlias: paymentAlias,
                showActions: true,
              ),
              // Por vencer tab
              _tabBody(
                bucketsAsync: bucketsAsync,
                getPayments: (b) => b.porVencer,
                emptyLabel: 'No hay pagos pendientes', // i18n
                palette: palette,
                profiles: profiles,
                paymentAlias: paymentAlias,
                showActions: true,
              ),
              // Pagados tab
              _tabBody(
                bucketsAsync: bucketsAsync,
                getPayments: (b) => b.pagados,
                emptyLabel: 'No hay pagos registrados', // i18n
                palette: palette,
                profiles: profiles,
                paymentAlias: paymentAlias,
                showActions: false,
              ),
              // Todos tab
              _tabBody(
                bucketsAsync: bucketsAsync,
                getPayments: (b) => b.todos,
                emptyLabel: 'No hay pagos', // i18n
                palette: palette,
                profiles: profiles,
                paymentAlias: paymentAlias,
                showActions: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Construye el body de un tab: loading / error / tabla.
  Widget _tabBody({
    required AsyncValue<PagosBuckets> bucketsAsync,
    required List<Payment> Function(PagosBuckets) getPayments,
    required String emptyLabel,
    required AppPalette palette,
    required Map<String, UserPublicProfile> profiles,
    required String? paymentAlias,
    required bool showActions,
  }) {
    return bucketsAsync.when(
      data: (b) => PagosWebTable(
        payments: getPayments(b),
        profiles: profiles,
        emptyLabel: emptyLabel,
        onMarcarPagado:
            showActions ? (p) => marcarPagadoDoc(context, ref, p) : null,
        onRecordar:
            showActions ? (p) => recordar(context, ref, p, paymentAlias) : null,
        showActions: showActions,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error al cargar pagos.', // i18n
          style: TextStyle(color: palette.danger),
        ),
      ),
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
