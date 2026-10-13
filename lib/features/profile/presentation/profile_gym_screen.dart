import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/moderation/moderation_guard.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../gyms/application/places_providers.dart';
import '../../gyms/domain/gym.dart' show hasRealGym, kNoGymId;
import '../../gyms/presentation/gym_name_dialog.dart';
import '../../profile_setup/presentation/widgets/gym_search_box.dart';
import '../application/user_providers.dart';
import 'widgets/nearby_gyms_list.dart';
import 'widgets/pinned_current_gym.dart';

/// Allows the authenticated athlete to search and select a gym via Google
/// Places Text Search (AD-12), then persist the selection to their profile.
///
/// REQ-PSR-019: search + selection + `UserRepository.update({'gymId': ...})`.
/// Reuses [GymSearchBox] — shared with `step_3_gym.dart` per spec gym-catalog
/// "Onboarding and profile-edit pickers share behavior" (single-search-box
/// contract, ADR-PSR-011).
///
/// A Google Places tap only stages el borrador locally — the resolve
/// (client-side Details call, billable) happens on explicit "GUARDAR" tap,
/// not on every suggestion tap, to avoid unnecessary Places billing on
/// accidental selections. `kNoGymId` needs no resolution.
///
/// Ese contrato vale para TODOS los caminos de selección de la pantalla
/// (issue #814): buscador tipeado, "OTRO GYM / SIN GYM" y lista de cercanos
/// ([NearbyGymsList]) mueven únicamente el borrador. Hasta #814 el tap
/// en un cercano resolvía y escribía en el acto, así que cambiaba el
/// gimnasio del atleta —dato que alimenta rankings y feed por gimnasio— sin
/// que apretara GUARDAR y sin forma de arrepentirse. [_save] es el único
/// método que toca el repositorio.
class ProfileGymScreen extends ConsumerStatefulWidget {
  const ProfileGymScreen({super.key});

  @override
  ConsumerState<ProfileGymScreen> createState() => _ProfileGymScreenState();
}

class _ProfileGymScreenState extends ConsumerState<ProfileGymScreen> {
  /// Borrador del gym elegido. `null` == SIN GYM (nunca el sentinel
  /// [kNoGymId]: se normaliza al tocar). Sólo vale si [_touched].
  ///
  /// Antes el borrador se inicializaba "perezoso" en el primer `build` con lo
  /// que hubiera en `userProfileProvider`; si el perfil todavía cargaba, el
  /// borrador quedaba clavado en `null` para siempre y GUARDAR se habilitaba
  /// sin tocar nada (un tap pisaba el gym real con `null`). Ahora el efectivo
  /// se deriva en cada build: sin tocar nada, es siempre el gym vigente.
  String? _draftGymId;
  bool _touched = false;
  bool _saving = false;

  void _onGymIdSelected(String? gymId) => setState(() {
        _touched = true;
        _draftGymId = hasRealGym(gymId) ? gymId : null;
      });

  Future<void> _save(String uid, String? gymId) async {
    setState(() => _saving = true);
    try {
      if (hasRealGym(gymId)) {
        // Google Place selection — resolve (server-side Details + upsert)
        // then persist. selectGymActionProvider writes `gymId` to
        // `users/{uid}` itself (UserRepository.update dual-writes gymName).
        // Mismo camino venga el `placeId` del buscador tipeado o de la
        // lista de cercanos (#814): el origen del tap no cambia cómo se
        // resuelve ni cómo se escribe, sólo CUÁNDO — acá, con el botón
        // mostrando su spinner (`_saving`) mientras el Details viaja.
        await ref
            .read(selectGymActionProvider.notifier)
            .select(uid: uid, placeId: gymId!);
        var actionState = ref.read(selectGymActionProvider);
        if (actionState.hasError) {
          throw actionState.error!;
        }
        if (actionState.valueOrNull?.needsName ?? false) {
          // Gym nuevo (o sin nombre de usuario): lo nombra quien lo vincula.
          if (!mounted) return;
          final typed = await showGymNameDialog(context);
          if (typed == null) return;
          await ref
              .read(selectGymActionProvider.notifier)
              .select(uid: uid, placeId: gymId!, name: typed);
          actionState = ref.read(selectGymActionProvider);
          if (actionState.hasError) {
            throw actionState.error!;
          }
        }
      } else {
        // "SIN GYM" se persiste como `null` (igual que el wizard): el
        // sentinel es un valor de borrador, no un gym que se guarde.
        await ref.read(userRepositoryProvider).update(uid, {'gymId': null});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppL10n.of(context).profileGymSaveSuccess,
              style: GoogleFonts.barlow(fontSize: 14),
            ),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ModerationBlockedException
                  ? AppL10n.of(context).moderationBlockedMessage
                  : AppL10n.of(context).profileGymSaveError,
              style: GoogleFonts.barlow(fontSize: 14),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
    final rawGymId = ref.watch(userProfileProvider).valueOrNull?.gymId;
    // El `'no-gym'` que dejaron versiones viejas es "sin gym", igual que null.
    final currentGymId = hasRealGym(rawGymId) ? rawGymId : null;
    final pendingGymId = _touched ? _draftGymId : currentGymId;

    // Con el centinela legacy guardado, "sin gym" ya es el estado visible pero
    // el valor persistido es otro: tocar OTRO tiene que poder GUARDAR para
    // migrarlo a `null`, aunque borrador y vigente normalizados coincidan.
    final legacySentinelStored = rawGymId != null && currentGymId == null;
    final saveEnabled = _touched &&
        !_saving &&
        (pendingGymId != currentGymId ||
            (legacySentinelStored && pendingGymId == null));

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: TreinoTappable(
            onTap: () => context.pop(),
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  'GIMNASIO', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Pinned current gym + search box + suggestions
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.paddingOf(context).bottom),
            child: TreinoFadeSlideIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // gym-selection-v2 AD-11: pinned above the search box,
                  // hidden by construction when currentGymId is null/kNoGymId.
                  PinnedCurrentGym(currentGymId: currentGymId),
                  GymSearchBox(
                    // `null` en el perfil == SIN GYM (así lo guarda esta pantalla y el
                    // wizard), así que se resalta aunque el borrador sea null.
                    selectedGymId: pendingGymId ?? kNoGymId,
                    onGymIdSelected: _onGymIdSelected,
                    // gym-selection-v2 AD-10: la lista de cercanos ocupa el
                    // estado de query vacía. Su tap es draft-only, igual que
                    // el del buscador de acá arriba (#814): sólo mueve
                    // el borrador. La resolución del Place y el write a
                    // `users/{uid}.gymId` los hace `_save()` al tocar
                    // GUARDAR, que es el ÚNICO punto de persistencia de esta
                    // pantalla. `selectedGymId` le devuelve el borrador para
                    // que la fila tocada se resalte.
                    emptyQueryContent: NearbyGymsList(
                      currentGymId: currentGymId,
                      selectedGymId: pendingGymId,
                      onGymSelected: _onGymIdSelected,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Save bar
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    saveEnabled ? () => _save(myUid, pendingGymId) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: TreinoButtonTokens.foreground(context),
                  disabledBackgroundColor: palette.border,
                  disabledForegroundColor: palette.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TreinoButtonTokens.foreground(context),
                        ),
                      )
                    : Text(
                        'GUARDAR', // i18n: Fase 6 Etapa 3
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
