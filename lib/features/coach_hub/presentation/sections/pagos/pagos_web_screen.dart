// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR2a — PagosScreen shell: header + KPI row + 4 tabs (Vencidos/Por vencer/
// Pagados/Todos) con tab bodies mínimos. La tabla rica y las acciones de fila
// (Marcar pagado / Recordar) llegan en PR2b.
//
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';

import 'widgets/pagos_buckets_provider.dart';
import 'widgets/pagos_kpi_row.dart';
import 'widgets/registrar_pago_dialog.dart';

// ── PagosScreen ───────────────────────────────────────────────────────────────

/// Sección Pagos del Coach Hub web.
///
/// Sigue el contrato de sección (ADR-CHW-005): sin Scaffold propio, sin
/// SafeArea. El shell [CoachHubScaffold] provee el chrome.
///
/// REQ-PAGW-SHELL-001, REQ-PAGW-SHELL-002, REQ-PAGW-KPI-001,
/// REQ-PAGW-TAB-001, REQ-PAGW-TAB-002, REQ-PAGW-EMPTY-001.
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
    // Result wiring (actual persistence with athlete picker) lands in PR2b.
    // The dialog already handles its own cancellation/submission display.
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bucketsAsync = ref.watch(pagosBucketsProvider);

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
      'Todos · $todosN', // i18n (note: no dot for "Todos" — shown for symmetry)
    ];

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
              bucketsAsync.when(
                data: (b) => _TabBody(
                  payments: b.vencidos,
                  emptyLabel: 'No hay pagos vencidos', // i18n
                  palette: palette,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error al cargar pagos.', // i18n
                      style: TextStyle(color: palette.danger)),
                ),
              ),
              // Por vencer tab
              bucketsAsync.when(
                data: (b) => _TabBody(
                  payments: b.porVencer,
                  emptyLabel: 'No hay pagos pendientes', // i18n
                  palette: palette,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error al cargar pagos.', // i18n
                      style: TextStyle(color: palette.danger)),
                ),
              ),
              // Pagados tab
              bucketsAsync.when(
                data: (b) => _TabBody(
                  payments: b.pagados,
                  emptyLabel: 'No hay pagos registrados', // i18n
                  palette: palette,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error al cargar pagos.', // i18n
                      style: TextStyle(color: palette.danger)),
                ),
              ),
              // Todos tab
              bucketsAsync.when(
                data: (b) => _TabBody(
                  payments: b.todos,
                  emptyLabel: 'No hay pagos', // i18n
                  palette: palette,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error al cargar pagos.', // i18n
                      style: TextStyle(color: palette.danger)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── _TabBody ──────────────────────────────────────────────────────────────────

/// Cuerpo mínimo de cada tab en PR2a: muestra el empty-state o una lista
/// simple (alumno-id + monto). La tabla rica con acciones llega en PR2b.
class _TabBody extends StatelessWidget {
  const _TabBody({
    required this.payments,
    required this.emptyLabel,
    required this.palette,
  });

  final List<dynamic> payments;
  final String emptyLabel;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      );
    }
    // Minimal list: replaced by PagosWebTable in PR2b.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: payments.length,
      itemBuilder: (_, i) {
        final p = payments[i] as dynamic;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(
                p.athleteId as String,
                style: TextStyle(color: palette.textPrimary),
              ),
              const Spacer(),
              Text(
                '\$${p.amountArs}',
                style: TextStyle(color: palette.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}
