import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../gyms/application/places_providers.dart';
import '../../gyms/domain/gym.dart' show kNoGymId;
import '../../profile_setup/presentation/widgets/gym_search_box.dart';
import '../application/user_providers.dart';

/// Allows the authenticated athlete to search and select a gym via Google
/// Places Autocomplete, then persist the selection to their profile.
///
/// REQ-PSR-019: search + selection + `UserRepository.update({'gymId': ...})`.
/// Reuses [GymSearchBox] — shared with `step_2_gym.dart` per spec gym-catalog
/// "Onboarding and profile-edit pickers share behavior" (single-search-box
/// contract, ADR-PSR-011).
///
/// A Google Places tap only stages `_pendingGymId` locally — the resolve
/// (`resolveGymPlace` Cloud Function call, billable) happens on explicit
/// "GUARDAR" tap, not on every suggestion tap, to avoid unnecessary Places
/// billing on accidental selections. `kNoGymId` needs no resolution.
class ProfileGymScreen extends ConsumerStatefulWidget {
  const ProfileGymScreen({super.key});

  @override
  ConsumerState<ProfileGymScreen> createState() => _ProfileGymScreenState();
}

class _ProfileGymScreenState extends ConsumerState<ProfileGymScreen> {
  String? _pendingGymId;
  bool _initialized = false;
  bool _saving = false;

  Future<void> _save(String uid, String? gymId) async {
    setState(() => _saving = true);
    try {
      if (gymId != null && gymId != kNoGymId) {
        // Google Place selection — resolve (server-side Details + upsert)
        // then persist. selectGymActionProvider writes `gymId` to
        // `users/{uid}` itself (UserRepository.update dual-writes gymName).
        await ref
            .read(selectGymActionProvider.notifier)
            .select(uid: uid, placeId: gymId);
        final actionState = ref.read(selectGymActionProvider);
        if (actionState.hasError) {
          throw actionState.error!;
        }
      } else {
        await ref.read(userRepositoryProvider).update(uid, {'gymId': gymId});
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppL10n.of(context).profileGymSaveError,
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
    final currentGymId = ref.watch(userProfileProvider).valueOrNull?.gymId;

    // Lazy-initialize _pendingGymId to currentGymId on first build.
    if (!_initialized) {
      _pendingGymId = currentGymId;
      _initialized = true;
    }

    final saveEnabled = _pendingGymId != currentGymId && !_saving;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
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

        // Search box + suggestions
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.paddingOf(context).bottom),
            child: GymSearchBox(
              selectedGymId: _pendingGymId,
              onGymIdSelected: (gymId) =>
                  setState(() => _pendingGymId = gymId ?? kNoGymId),
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
                    saveEnabled ? () => _save(myUid, _pendingGymId) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
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
                          color: palette.bg,
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
