import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/moderation/moderation_guard.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/gym_name_prompt_providers.dart';
import '../application/places_providers.dart';
import '../data/resolve_gym_place_service.dart' show ResolveGymPlaceResult;
import '../domain/gym.dart';
import 'gym_name_dialog.dart';

/// Aviso proactivo «Tu gimnasio necesita un nombre» (#1338).
///
/// Por la política de Places la migración deja los gyms que vinieron de
/// Google con `name: "Gimnasio"` y `nameNeeded: true`. Hasta ahora sólo se
/// pedía el nombre al RE-elegir el gym; quien ya estaba vinculado veía
/// «Gimnasio» sin forma de saber que le tocaba nombrarlo.
///
/// Colapsa a `SizedBox.shrink()` (espaciado incluido) salvo que el gym
/// vinculado esté `nameNeeded` y el usuario no lo haya descartado en esta
/// sesión. Cargando y error cuentan como «no mostrar». Es el mismo doc de
/// usuario para atletas y entrenadores, así que se monta en ambos Inicios.
///
/// Nombrar reutiliza [SelectGymAction.select] con `name`: ahí viven la
/// moderación, el `setName` y la carrera (si otro lo nombró antes, la regla
/// de Firestore niega el update y gana su nombre).
class GymNamePromptCard extends ConsumerWidget {
  const GymNamePromptCard({super.key});

  Future<void> _name(BuildContext context, WidgetRef ref, Gym gym) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    final typed = await showGymNameDialog(context);
    if (typed == null) return;

    // La card se desmonta sola apenas el stream ve el gym nombrado, y eso
    // puede pasar con la escritura todavía en vuelo: nada de `ref`/`context`
    // después de este punto. Se toma todo ahora.
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    final container = ProviderScope.containerOf(context);
    final notifier = container.read(selectGymActionProvider.notifier);

    final ok = await notifier.select(uid: uid, placeId: gym.id, name: typed);
    // El scope puede haberse desmontado durante el await (logout): no hay
    // nada que mostrar ni a quién.
    final ResolveGymPlaceResult? resolved;
    final Object? error;
    try {
      final state = container.read(selectGymActionProvider);
      resolved = state.valueOrNull;
      error = state.hasError ? (state.error ?? 'error') : null;
    } catch (_) {
      return;
    }

    String? message;
    if (error != null) {
      message = error is ModerationBlockedException
          ? l10n.moderationBlockedMessage
          : l10n.profileGymSaveError;
    } else if (ok) {
      final winner = resolved?.name;
      // Carrera perdida: el servicio devuelve el nombre del que llegó
      // primero. Si coincide con lo tipeado, fue un alta normal.
      if (winner != null && winner.isNotEmpty && winner != typed.trim()) {
        message = l10n.gymNamePromptRaceMessage(winner);
      }
    }
    if (message != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null || ref.watch(gymNamePromptDismissedProvider(uid))) {
      return const SizedBox.shrink();
    }
    final gym = ref.watch(gymNamePromptGymProvider).valueOrNull;
    if (gym == null) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Container(
        key: const Key('gym_name_prompt_card'),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: palette.accent, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.s18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(TreinoIcon.gym, size: 20, color: palette.accent),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.gymNamePromptTitle,
                          style: GoogleFonts.barlow(
                            fontSize: AppTextSize.body,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.hairline),
                        Text(
                          l10n.gymNamePromptBody,
                          style: GoogleFonts.barlow(
                            fontSize: AppTextSize.bodyDense,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                TextButton(
                  key: const Key('gym_name_prompt_dismiss'),
                  onPressed: () => ref
                      .read(gymNamePromptDismissedProvider(uid).notifier)
                      .state = true,
                  child: Text(l10n.gymNamePromptDismiss),
                ),
                ElevatedButton(
                  key: const Key('gym_name_prompt_cta'),
                  onPressed: () => _name(context, ref, gym),
                  child: Text(l10n.gymNamePromptCta),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
