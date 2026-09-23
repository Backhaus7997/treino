import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/coach_hub/presentation/widgets/section_hero/section_hero.dart';
import 'package:treino/features/moderation/application/moderation_queue_providers.dart';
import 'package:treino/features/moderation/domain/pending_report.dart';

/// La cola de revisión de reportes.
///
/// `docs/legal/normas-de-comunidad.md:123` dice, publicado y aceptado por el
/// usuario, que revisamos todo reporte dentro de las 24 horas. Esta pantalla es
/// el lugar donde eso se hace: sin ella la promesa era una afirmación falsa.
///
/// **No es linda a propósito.** Es una herramienta interna para una persona;
/// lo que tiene que hacer es existir, mostrar lo que espera, y dejar cerrarlo.
///
/// ## Esconder el ítem del sidebar NO es el control de acceso
///
/// Esta ruta existe y se puede escribir a mano en la barra del navegador. Lo
/// que protege de verdad es `assertModerator`, del otro lado de los tres
/// callables, donde hay Admin SDK y las rules no participan. Acá no se lee
/// `reports` ni `report_reviews`: las dos siguen con `allow read: if false`
/// para TODO cliente, moderador incluido.
class ModeracionScreen extends ConsumerWidget {
  const ModeracionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final esModerador = ref.watch(isModeratorProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s20,
        vertical: AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CoachHubSectionHero(
            title: 'Moderación', // i18n: Fase W3
            subtitle: 'Reportes sin resolver · 24 horas', // i18n: Fase W3
          ),
          const SizedBox(height: AppSpacing.s20),
          if (!esModerador)
            Expanded(child: _SinPermiso(palette: palette))
          else ...[
            const _Resumen(),
            const SizedBox(height: AppSpacing.s18),
            const Expanded(child: _Cola()),
          ],
        ],
      ),
    );
  }
}

/// Lo que ve quien entra a la ruta sin el claim.
///
/// Mensaje sobrio y sin detalle: quien llegó acá sin permiso no necesita saber
/// qué hay del otro lado.
class _SinPermiso extends StatelessWidget {
  const _SinPermiso({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TreinoIcon.shieldCheck, size: 32, color: palette.textMuted),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Esta sección es del equipo de TREINO.', // i18n: Fase W3
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: AppTextSize.body,
            ),
          ),
        ],
      ),
    );
  }
}

/// Las tres cifras que permiten PROBAR que se cumple la promesa.
class _Resumen extends ConsumerWidget {
  const _Resumen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final stats = ref.watch(moderationStatsProvider);

    return stats.when(
      loading: () => const SizedBox(height: AppSpacing.s20),
      error: (_, __) => Text(
        'No pudimos leer el resumen.', // i18n: Fase W3
        style: GoogleFonts.barlow(
          color: palette.textMuted,
          fontSize: AppTextSize.caption,
        ),
      ),
      data: (s) {
        if (s == null) return const SizedBox.shrink();
        return Wrap(
          spacing: AppSpacing.s12,
          runSpacing: AppSpacing.s8,
          children: [
            _Cifra(label: 'Pendientes', valor: '${s.pending}'), // i18n
            _Cifra(
              label: 'El más viejo', // i18n
              valor: s.oldestPendingHours == null
                  ? '—'
                  : '${s.oldestPendingHours} h',
            ),
            _Cifra(
              label: 'Fuera de plazo', // i18n
              valor: '${s.breachingSla}',
              // El único que se pinta: si no es cero, la promesa publicada
              // está incumplida AHORA, y eso tiene que saltar a la vista.
              alerta: s.breachingSla > 0,
            ),
          ],
        );
      },
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({
    required this.label,
    required this.valor,
    this.alerta = false,
  });

  final String label;
  final String valor;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = alerta ? palette.danger : palette.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: alerta ? palette.danger : palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: AppTextSize.caption,
              fontWeight: FontWeight.w700,
              letterSpacing: AppFonts.headingTracking,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            valor,
            style: GoogleFonts.barlow(
              color: color,
              fontSize: AppTextSize.title,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cola extends ConsumerWidget {
  const _Cola();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final cola = ref.watch(pendingReportsProvider);

    return cola.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No pudimos abrir la cola.', // i18n: Fase W3
              style: GoogleFonts.barlow(
                color: palette.textPrimary,
                fontSize: AppTextSize.body,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            TreinoButton(
              label: 'Reintentar', // i18n: Fase W3
              variant: TreinoButtonVariant.ghost,
              size: TreinoButtonSize.sm,
              onPressed: () => ref.invalidate(pendingReportsProvider),
            ),
          ],
        ),
      ),
      data: (cola) {
        final reportes = cola.reportes;

        // «Vacía» e «incompleta» NO se dicen igual. El servidor escanea hasta
        // un tope y avisa cuando lo alcanza; mostrar «no hay reportes
        // esperando» sobre una lista cortada es afirmar que no hay nada cuando
        // lo que pasó es que dejamos de buscar.
        if (reportes.isEmpty) {
          return Center(
            child: Text(
              cola.incompleta
                  ? 'No pudimos terminar de revisar la cola. '
                      'Volvé a intentar.' // i18n: Fase W3
                  : 'No hay reportes esperando.', // i18n: Fase W3
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                color: cola.incompleta ? palette.danger : palette.textMuted,
                fontSize: AppTextSize.body,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: reportes.length + (cola.incompleta ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == reportes.length) {
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s8),
                child: Text(
                  'La lista está incompleta: el servidor dejó de buscar '
                  'antes de llegar al final.', // i18n: Fase W3
                  style: GoogleFonts.barlow(
                    color: palette.danger,
                    fontSize: AppTextSize.caption,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: _Fila(reporte: reportes[i]),
            );
          },
        );
      },
    );
  }
}

class _Fila extends ConsumerStatefulWidget {
  const _Fila({required this.reporte});

  final PendingReport reporte;

  @override
  ConsumerState<_Fila> createState() => _FilaState();
}

class _FilaState extends ConsumerState<_Fila> {
  @override
  void initState() {
    super.initState();
    // Marca el reporte como MIRADO cuando la fila entra en pantalla.
    //
    // Acá y no al traer la página: el `ListView` es perezoso, así que esto
    // corre para las filas que el moderador de verdad tiene delante. Estampar
    // `firstViewedAt` al listar marcaba los 50 de la página —incluidos los que
    // ni se renderizaban— y `moderationStats` los contaba dentro del plazo
    // PARA SIEMPRE: el tablero podía declarar cumplimiento sin que nadie
    // hubiera leído nada.
    //
    // Es best-effort a propósito. Si falla, el reporte queda sin marcar y
    // aparece como no mirado, que es el lado correcto del error: la métrica se
    // equivoca acusándonos, no absolviéndonos.
    final id = widget.reporte.id;
    if (widget.reporte.firstViewedAt != null || id.isEmpty) return;
    Future<void>.microtask(() async {
      try {
        await ref.read(moderationQueueServiceProvider).markViewed(id);
      } catch (_) {
        // Ver arriba: no marcar es el error seguro.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reporte = widget.reporte;
    final palette = AppPalette.of(context);
    final tarde = reporte.rompioElPlazo;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tarde ? palette.danger : palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${reporte.reason.toUpperCase()} · '
                '${reporte.targetKind.toUpperCase()}',
                style: GoogleFonts.barlowCondensed(
                  color: palette.textPrimary,
                  fontSize: AppTextSize.body,
                  fontWeight: FontWeight.w700,
                  letterSpacing: AppFonts.headingTracking,
                ),
              ),
              const Spacer(),
              Text(
                reporte.horasDesdeQueEntro == null
                    ? '—'
                    : 'hace ${reporte.horasDesdeQueEntro} h', // i18n
                style: GoogleFonts.barlow(
                  color: tarde ? palette.danger : palette.textMuted,
                  fontSize: AppTextSize.caption,
                  fontWeight: tarde ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          // La RUTA del contenido, no el contenido. Quien modera abre el
          // documento en la consola de Firebase, autenticado. Traerlo acá
          // seria una copia mas de datos de terceros.
          SelectableText(
            reporte.contentPath ?? 'No se pudo ubicar el contenido.', // i18n
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: AppTextSize.bodyDense,
            ),
          ),
          if (reporte.detail != null && reporte.detail!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              reporte.detail!,
              style: GoogleFonts.barlow(
                color: palette.textPrimary,
                fontSize: AppTextSize.bodyDense,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          // `Wrap` y no `Row`: con los cuatro botones no siempre entran en el
          // ancho del Coach Hub, y la separación tiene que seguir siendo FIJA
          // — nada de `spaceBetween` para llenar el ancho. `spacing` cubre el
          // gap horizontal entre botones de una misma fila, `runSpacing` el
          // gap vertical cuando envuelven. Mismo patrón que `_Resumen`, arriba.
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              // `ghost` para descartar, `secondary` para las que accionan y
              // `danger` para la baja: cerrar sin hacer nada no puede verse
              // igual de consecuente que retirar contenido ajeno, y dar de
              // baja una cuenta no puede verse igual que las otras dos —
              // es la única de las cuatro que es irreversible desde acá.
              TreinoButton(
                label: 'Descartar', // i18n: Fase W3
                variant: TreinoButtonVariant.ghost,
                size: TreinoButtonSize.sm,
                onPressed: () => _resolver(context, ref, 'dismissed', 'none'),
              ),
              TreinoButton(
                label: 'Contenido retirado', // i18n: Fase W3
                variant: TreinoButtonVariant.secondary,
                size: TreinoButtonSize.sm,
                onPressed: () =>
                    _resolver(context, ref, 'actioned', 'contentRemoved'),
              ),
              TreinoButton(
                label: 'Usuario advertido', // i18n: Fase W3
                variant: TreinoButtonVariant.secondary,
                size: TreinoButtonSize.sm,
                onPressed: () =>
                    _resolver(context, ref, 'actioned', 'userWarned'),
              ),
              TreinoButton(
                label: 'Dar de baja', // i18n: Fase W3
                variant: TreinoButtonVariant.danger,
                size: TreinoButtonSize.sm,
                onPressed: () => _confirmarBaja(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resolver(
    BuildContext context,
    WidgetRef ref,
    String status,
    String action,
  ) async {
    final reporte = widget.reporte;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(moderationQueueServiceProvider).resolve(
            reportId: reporte.id,
            status: status,
            action: action,
          );
      // Se invalidan las DOS: el resumen cuenta lo mismo que la lista, y
      // dejarlo viejo haria que el numero de pendientes contradiga lo que se
      // ve abajo.
      ref.invalidate(pendingReportsProvider);
      ref.invalidate(moderationStatsProvider);
    } on FirebaseFunctionsException catch (e) {
      // Las acciones ahora pueden fallar por motivos DISTINTOS y accionables
      // (contenido ya borrado, no aplica a un perfil, es otro moderador). El
      // mensaje del HttpsError ya viene en castellano desde el backend — el
      // genérico de abajo es sólo el resguardo para cuando no viene ninguno.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'No pudimos cerrar el reporte.', // i18n: Fase W3
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos cerrar el reporte.'), // i18n: Fase W3
        ),
      );
    }
  }

  /// Pide confirmación antes de dar de baja la cuenta reportada.
  ///
  /// Es irreversible DESDE ACÁ — revertirla requiere la consola de Firebase—,
  /// así que se confirma antes de disparar, mismo criterio que
  /// `BlockConfirmationSheet` (`moderation/presentation/widgets/`).
  Future<void> _confirmarBaja(BuildContext context, WidgetRef ref) async {
    final palette = AppPalette.of(context);

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _SuspendConfirmationSheet(
        onConfirm: () => _resolver(context, ref, 'actioned', 'userSuspended'),
      ),
    );
  }
}

/// Confirmación antes de dar de baja una cuenta desde la cola de moderación.
///
/// Copia el molde de `BlockConfirmationSheet`
/// (`features/moderation/presentation/widgets/block_confirmation_sheet.dart`):
/// drag handle + título + cuerpo + fila de dos botones, [onConfirm] se invoca
/// SÓLO al confirmar. No se reutiliza ese widget tal cual porque su copy es
/// específico de bloquear a otro usuario — acá la consecuencia es otra
/// (deshabilitar la cuenta) y los botones son [TreinoButton], como el resto
/// de esta pantalla, en vez del `_SheetButton` privado de aquel archivo.
class _SuspendConfirmationSheet extends StatelessWidget {
  const _SuspendConfirmationSheet({required this.onConfirm});

  /// Se invoca sólo al confirmar. El botón "Cancelar" cierra el sheet sin
  /// llamarlo.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: TreinoFadeSlideIn(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s18),
            Text(
              '¿Dar de baja esta cuenta?', // i18n: Fase W3
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.title,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'La cuenta queda deshabilitada y no va a poder iniciar sesión. '
              'Revertirlo requiere la consola de Firebase — esta acción no '
              'se deshace desde acá.', // i18n: Fase W3
              style: GoogleFonts.barlow(
                fontSize: AppTextSize.bodyDense,
                color: palette.textMuted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s20),
            Row(
              children: [
                Expanded(
                  child: TreinoButton(
                    label: 'Cancelar', // i18n: Fase W3
                    variant: TreinoButtonVariant.ghost,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: TreinoButton(
                    // Distinto del botón que abre este sheet A PROPÓSITO: el
                    // mismo label en el trigger y en la confirmación es
                    // ambiguo — para quien lee la pantalla y para un test que
                    // busque por texto.
                    label: 'Sí, dar de baja', // i18n: Fase W3
                    variant: TreinoButtonVariant.danger,
                    expand: true,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onConfirm();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
