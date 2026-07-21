/// Selector de alumno para el CTA "+ Registrar pago" trainer-wide de la
/// sección Pagos (`pagos_web_screen.dart`).
///
/// ADR-F9-06 (remediación CRITICAL-1, verify ronda 1): a diferencia de
/// `alumno_detail_screen.dart` — donde el `athleteId` ya viene de la ruta —
/// el CTA del header de `/pagos` no tiene un alumno de contexto. Antes de
/// esta pieza, `_onRegistrarPago` abría `RegistrarPagoDialog` y descartaba el
/// resultado (botón fantasma: no persistía nada). Este picker resuelve el
/// roster REAL del trainer (`trainerLinksStreamProvider`, mismo stream que
/// `AlumnosScreen`) para que el trainer elija el alumno antes de abrir
/// `RegistrarPagoDialog`, permitiendo que `registrarPago` (helper ya
/// cableado a `paymentRepositoryProvider.add`) persista de verdad.
///
/// Solo se listan vínculos `active`/`paused` (alumnos actualmente vinculados)
/// — `pending` (solicitud sin aceptar) y `terminated` (vínculo cerrado) no
/// son destinos válidos para registrar un cobro.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;

/// Abre el diálogo de selección de alumno; devuelve el `athleteId` elegido,
/// o `null` si el trainer cancela / no hay alumnos vinculados.
Future<String?> pickAthleteForPago(BuildContext context, WidgetRef ref) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _AthletePickerDialog(),
  );
}

class _AthletePickerDialog extends ConsumerWidget {
  const _AthletePickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text(
        'Elegí un alumno', // i18n
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: TreinoStateSwitcher(
          childKey: ValueKey(_stateKeyOf(linksAsync)),
          child: linksAsync.when(
            loading: () => const _PickerSkeleton(),
            error: (e, _) => Text(
              'No pudimos cargar tus alumnos.', // i18n
              style: TextStyle(color: palette.textMuted),
            ),
            data: (links) => _AthleteList(links: links),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar', // i18n
            style: TextStyle(color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}

String _stateKeyOf(AsyncValue<Object?> value) {
  if (value.hasError) return 'error';
  if (value.isLoading && !value.hasValue) return 'loading';
  return 'data';
}

/// Skeleton de 3 filas placeholder mientras resuelve el stream de vínculos.
class _PickerSkeleton extends StatelessWidget {
  const _PickerSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Widget bar() => Container(
          height: 40,
          margin: const EdgeInsets.only(bottom: AppSpacing.hairline),
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        );

    return TreinoShimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [bar(), bar(), bar()],
      ),
    );
  }
}

/// Lista de alumnos elegibles (`active`/`paused`, deduplicados por
/// `athleteId` — el stream viene `requestedAt` DESC, así que el primer link
/// visto por alumno es el más reciente).
class _AthleteList extends ConsumerWidget {
  const _AthleteList({required this.links});

  final List<TrainerLink> links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    final seen = <String>{};
    final roster = [
      for (final l in links)
        if ((l.status == TrainerLinkStatus.active ||
                l.status == TrainerLinkStatus.paused) &&
            seen.add(l.athleteId))
          l,
    ];

    if (roster.isEmpty) {
      return Text(
        'Todavía no tenés alumnos vinculados.', // i18n
        style: TextStyle(color: palette.textMuted),
      );
    }

    final ids = roster.map((l) => l.athleteId).toList()..sort();
    final profilesAsync =
        ref.watch(userPublicProfilesBatchProvider(ids.join(',')));
    final profiles = profilesAsync.valueOrNull ?? const {};

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: roster.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.hairline),
        itemBuilder: (_, i) {
          final link = roster[i];
          final name =
              profiles[link.athleteId]?.displayName?.isNotEmpty == true
                  ? profiles[link.athleteId]!.displayName!
                  : 'Alumno'; // i18n fallback

          return ListTile(
            key: Key('pagos_athlete_picker_${link.athleteId}'),
            contentPadding: EdgeInsets.zero,
            title: Text(name, style: TextStyle(color: palette.textPrimary)),
            onTap: () => Navigator.of(context).pop(link.athleteId),
          );
        },
      ),
    );
  }
}
