import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
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
            TextButton(
              onPressed: () => ref.invalidate(pendingReportsProvider),
              child: const Text('Reintentar'), // i18n: Fase W3
            ),
          ],
        ),
      ),
      data: (reportes) {
        if (reportes.isEmpty) {
          return Center(
            child: Text(
              'No hay reportes esperando.', // i18n: Fase W3
              style: GoogleFonts.barlow(
                color: palette.textMuted,
                fontSize: AppTextSize.body,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: reportes.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s12),
            child: _Fila(reporte: reportes[i]),
          ),
        );
      },
    );
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.reporte});

  final PendingReport reporte;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Row(
            children: [
              TextButton(
                onPressed: () => _resolver(context, ref, 'dismissed', 'none'),
                child: const Text('Descartar'), // i18n: Fase W3
              ),
              const SizedBox(width: AppSpacing.s8),
              TextButton(
                onPressed: () =>
                    _resolver(context, ref, 'actioned', 'contentRemoved'),
                child: const Text('Contenido retirado'), // i18n: Fase W3
              ),
              const SizedBox(width: AppSpacing.s8),
              TextButton(
                onPressed: () =>
                    _resolver(context, ref, 'actioned', 'userWarned'),
                child: const Text('Usuario advertido'), // i18n: Fase W3
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
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos cerrar el reporte.'), // i18n: Fase W3
        ),
      );
    }
  }
}
