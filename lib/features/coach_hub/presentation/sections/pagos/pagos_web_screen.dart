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
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';

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
        // ── Section header + action ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            children: [
              Text(
                'PAGOS', // i18n
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _onRegistrarPago,
                style: TextButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '+ Registrar pago', // i18n
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // ── KPI row ─────────────────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: PagosKpiRow(),
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
