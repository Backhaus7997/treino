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
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show paymentRepositoryProvider, trainerPaymentsProvider;
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

import '../../widgets/coach_hub_widgets.dart'
    show
        CoachHubPager,
        CoachHubSectionHero,
        TreinoFilterChips,
        TreinoPopupMenuButton,
        TreinoInteractiveState,
        pageOf;
import 'widgets/registrar_pago_dialog.dart';
import 'widgets/marcar_pagado_actions.dart';
import 'package:treino/core/utils/argentina_time.dart';

import 'widgets/pagos_buckets_provider.dart';
import 'widgets/pagos_estado.dart';
import 'widgets/pagos_periodo_provider.dart';
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

  /// Pagina visible, 0-based. Vuelve a 0 cuando cambia el filtro o el orden:
  /// quedarse en la pagina 3 despues de cambiar de pestaña muestra un tramo
  /// del medio de otra lista, sin nada que explique por que arranca ahi.
  int _page = 0;

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
      'vencimiento' => (a.dueAt ?? a.createdAt).compareTo(
        b.dueAt ?? b.createdAt,
      ),
      // Por el ESTADO QUE SE VE, no por `Payment.status`. El badge de la fila
      // sale de `pagoEstadoOf`, que distingue vencido de por-vencer mirando
      // `dueAt` contra la hora; `status` sólo sabe `pending` vs `paid` y
      // dejaria a un vencido y a uno que vence en 20 dias en el mismo grupo.
      // Ordenar por una cosa distinta de la que la columna muestra es la clase
      // de detalle que se lee como un bug.
      //
      // El orden del enum ya es el util: vencido → porVencer → pagado, o sea
      // lo urgente primero en ascendente.
      'estado' => pagoEstadoOf(a, argentinaNow())
          .estado
          .index
          .compareTo(pagoEstadoOf(b, argentinaNow()).estado.index),
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
    final result = await showDialog<RegistrarPagoResult>(
      context: context,
      builder: (_) => const RegistrarPagoDialog(),
    );
    if (result == null || !context.mounted) return;

    final trainerId = ref.read(currentUidProvider);
    if (trainerId == null) return;

    final now = DateTime.now().toUtc();
    final payment = Payment(
      id: '',
      trainerId: trainerId,
      athleteId: result.athleteId,
      amountArs: result.amount,
      concept: result.concept,
      status: result.status,
      createdAt: now,
      paidAt: result.status == PaymentStatus.paid ? now : null,
      dueAt: result.status == PaymentStatus.pending ? result.dueAt : null,
    );

    try {
      await ref.read(paymentRepositoryProvider).add(payment);
      if (mounted) {
        pagoSnack(context, 'Pago registrado.'); // i18n
      }
    } catch (_) {
      if (mounted) {
        pagoSnack(context, 'No pudimos guardar. Intentá de nuevo.'); // i18n
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bucketsAsync = ref.watch(pagosBucketsProvider);
    final filtro = ref.watch(pagosFiltroProvider);
    final periodo = ref.watch(pagosPeriodoProvider);

    // Alias de pago del trainer, para el mensaje de recordatorio (WU-07).
    final paymentAlias = ref.watch(
      userProfileProvider.select((s) => s.valueOrNull?.paymentAlias),
    );

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

    // Scrolleable, como Alumnos.
    //
    // Antes esto era un `Column` con la tabla adentro de un `Expanded`, y ahí
    // se perdía el scroll: `CoachHubDataTable` NO tiene scroller propio (es un
    // `Column` de filas), así que el `Expanded` le daba una caja del alto de
    // la pantalla y las filas que no entraban quedaban afuera. No se veía como
    // un overflow de Flutter —nada de las rayas amarillas— porque el
    // `ClipRRect` de la tabla las recorta en silencio: simplemente la lista se
    // cortaba abajo y no había forma de bajar. Con 11 pagos, el PF veía 7.
    //
    // El fix es scrollear la página entera y no la tabla, que es lo que hace
    // `alumnos_screen` con el mismo widget. La alternativa —meterle un
    // `ListView` adentro a `CoachHubDataTable`— rompería a Alumnos, que lo
    // monta dentro de su propio `SingleChildScrollView` y quedaría con un
    // scrollable sin alto acotado.
    //
    // Se van con el scroll el hero, los KPI y los chips. Es lo mismo que pasa
    // en Alumnos, y son ~200px de chrome fijo que en una laptop se comen media
    // tabla.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header + action (staggered, ADR-F9-04: sin "Exportar" —
          // no hay exportador real) ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: TreinoFadeSlideIn(
              delay: AppMotion.stagger(0),
              child: CoachHubSectionHero(
                title: 'Pagos', // i18n
                subtitle: 'Cobros, vencimientos e ingresos', // i18n
                trailing: _RegistrarPagoButton(onTap: _onRegistrarPago),
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

          // ── Filtro (chips) + ventana de tiempo ──────────────────────────────
          //
          // El selector de periodo va en la MISMA fila que los chips y no en
          // una barra propia: son dos recortes de la misma lista —por estado y
          // por fecha— y separarlos haria pensar que uno manda sobre el otro.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: TreinoFadeSlideIn(
              delay: AppMotion.stagger(2),
              child: Row(
                children: [
                  Expanded(
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
                      // Cambiar de pestaña es cambiar de lista. Sin esto, el
                      // PF sale de la página 3 de «Todos» y entra en la
                      // página 3 de «Vencidos», que puede tener 2 filas: ve
                      // una tabla vacía y nada que explique por qué.
                      setState(() => _page = 0);
                      break;
                    }
                  }
                },
                  ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  _PeriodoSelector(
                    periodo: periodo,
                    onChanged: (p) {
                      ref.read(pagosPeriodoProvider.notifier).state = p;
                      // Igual que el cambio de pestaña: achicar la ventana
                      // cambia la lista, y la pagina 3 de la anterior puede no
                      // existir en la nueva.
                      setState(() => _page = 0);
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Tabla (según filtro activo) ────────────────────────────────────
          //
          // `Padding` y no `Expanded`: adentro de un scroll view el alto lo pone
          // el contenido. Se agrega aire abajo para que la última fila no quede
          // pegada al borde al llegar al final.
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, AppSpacing.s20),
            child: TreinoStateSwitcher(
              // El periodo entra en la key: sin el, achicar la ventana
              // reemplaza el contenido bajo la misma key y el switcher lo
              // trata como el mismo widget — el cambio queda seco, sin el
              // cross-fade que si tiene el cambio de pestaña.
              childKey: ValueKey('pagos_${filtro.name}_${periodo.name}'),
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
                periodo: periodo,
                paymentAlias: paymentAlias,
              ),
            ),
          ),
        ],
      ),
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
    required PagosPeriodo periodo,
    required String? paymentAlias,
  }) {
    final todos = bucketsAsync.valueOrNull != null
        ? getPayments(bucketsAsync.valueOrNull!)
        : const <Payment>[];

    // La ventana recorta ANTES que todo lo demás: el conteo del pie, el «hay
    // más de una página» y el `showActions` tienen que hablar de la lista que
    // el PF está viendo, no de la que habría sin filtro.
    final payments = filtrarPorPeriodo(todos, periodo);

    // La columna ACCIONES aparece si ALGUNA fila tiene algo para ofrecer, y
    // eso lo dicen los datos — no la pestaña en la que estas parado.
    //
    // Antes era `filtro != PagosFiltro.pagados`. La regla de fondo era la
    // correcta ("un pago cobrado no necesita recordatorio ni marcar pagado de
    // nuevo") pero aplicada un nivel demasiado arriba: vale por FILA, y
    // "Todos" mezcla filas de los dos tipos. Con los 12 pagos cobrados, la
    // campanita aparecia sobre las 12 en "Todos" y sobre ninguna en "Pagados".
    //
    // Derivarlo asi conserva el efecto visible que ya estaba bien —en
    // "Pagados" la columna sigue sin aparecer— pero como CONSECUENCIA de que
    // ninguna fila tiene accion, no como una regla escrita aparte que se
    // desincroniza de la de la fila.
    final showActions = payments.any((p) => p.status == PaymentStatus.pending);

    // fbf4e6af: la vacuidad va DENTRO de la key. Sin esto, marcar pagado el
    // ultimo vencido reemplaza la tabla por el empty state bajo la misma key
    // 'data' — AnimatedSwitcher lo trata como el mismo widget y el swap queda
    // seco, sin el cross-fade que si tienen las pantallas hermanas.
    //
    // Se conserva envolviendo la tabla nueva del kit (fase 9), que ademas trae
    // loading/error/retry, ordenamiento y acciones de fila propias.
    return TreinoStateSwitcher(
      childKey: ValueKey(
        bucketsAsync.when(
          loading: () => 'loading',
          error: (_, __) => 'error',
          data: (b) => filtrarPorPeriodo(getPayments(b), periodo).isEmpty
              ? 'empty'
              : 'data',
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PagosWebTable(
        payments: pageOf(_sorted(payments, profiles), page: _page),
        profiles: profiles,
        emptyMessage: emptyMessage,
        loading: bucketsAsync.isLoading,
        errorMessage: bucketsAsync.hasError
            ? 'Error al cargar pagos.'
            : null, // i18n
        onRetry: () => ref.invalidate(trainerPaymentsProvider),
        sortColumnKey: _sortColumnKey,
        sortAscending: _sortAscending,
        onSort: (key, ascending) => setState(() {
          _sortColumnKey = key;
          _sortAscending = ascending;
          // Reordenar cambia QUE filas caen en cada pagina. Quedarse en la 3
          // deja al PF mirando un tramo del medio de una lista que acaba de
          // cambiar de orden, sin nada que explique por que arranca ahi.
          _page = 0;
        }),
        showActions: showActions,
        onMarcarPagado: (p) => marcarPagadoDoc(context, ref, p),
        onRecordar: (p) => recordar(context, ref, p, paymentAlias),
          ),
          // El pie se dibuja solo si hay mas de una pagina — se esconde a si
          // mismo. Va con el TOTAL sin recortar, que es el `de 112`.
          CoachHubPager(
            total: payments.length,
            page: _page,
            onPageChanged: (p) => setState(() => _page = p),
          ),
        ],
      ),
    );
  }
}

// ── _PeriodoSelector ────────────────────────────────────────────────────────

/// Ventana de tiempo del listado. Un menú y no cuatro chips más: la fila ya
/// tiene cuatro chips de estado, y sumarle cuatro de fecha convierte el filtro
/// en la mitad de la pantalla.
class _PeriodoSelector extends StatelessWidget {
  const _PeriodoSelector({required this.periodo, required this.onChanged});

  final PagosPeriodo periodo;
  final ValueChanged<PagosPeriodo> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoPopupMenuButton<PagosPeriodo>(
      key: const Key('pagos_periodo_selector'),
      tooltip: 'Ventana de tiempo', // i18n
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final p in PagosPeriodo.values)
          PopupMenuItem(
            key: Key('pagos_periodo_${p.name}'),
            value: p,
            child: Text(p.label),
          ),
      ],
      icon: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.calendar, size: 14, color: palette.textMuted),
            const SizedBox(width: AppSpacing.hairline),
            Text(
              periodo.label,
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontSize: AppTextSize.caption,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.hairline),
            Icon(TreinoIcon.chevronDown, size: 12, color: palette.textMuted),
          ],
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
              Icon(
                TreinoIcon.plus,
                size: 16,
                color: TreinoButtonTokens.foreground(context),
              ),
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
