import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../profile_setup/application/profile_setup_providers.dart';
import '../../profile_setup/domain/gym.dart';
import '../../profile_setup/presentation/widgets/gym_card.dart';
import '../application/user_providers.dart';

/// Allows the authenticated athlete to search and select a gym from the
/// existing catalog, then persist the selection to their profile.
///
/// REQ-PSR-019: search + selection + UserRepository.update({'gymId': ...}).
/// Reuses [filteredGymsProvider], [gymSearchQueryProvider], and [GymCard]
/// from profile_setup per ADR-PSR-011. // i18n: Fase 6 Etapa 3
class ProfileGymScreen extends ConsumerStatefulWidget {
  const ProfileGymScreen({super.key});

  @override
  ConsumerState<ProfileGymScreen> createState() => _ProfileGymScreenState();
}

class _ProfileGymScreenState extends ConsumerState<ProfileGymScreen> {
  String? _pendingGymId;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _save(String uid, String? gymId) async {
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).update(uid, {'gymId': gymId});
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
    final currentGymId =
        ref.watch(userProfileProvider).valueOrNull?.gymId;

    // Lazy-initialize _pendingGymId to currentGymId on first build.
    if (!_initialized) {
      _pendingGymId = currentGymId;
      _initialized = true;
    }

    final gyms = ref.watch(filteredGymsProvider);
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

        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (v) =>
                ref.read(gymSearchQueryProvider.notifier).state = v,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar gym', // i18n: Fase 6 Etapa 3
              prefixIcon: Icon(
                TreinoIcon.search,
                color: palette.textMuted,
                size: 20,
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Gym list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: gyms.length + 1, // +1 for "OTRO GYM / SIN GYM"
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              if (i < gyms.length) {
                final gym = gyms[i];
                return GymCard(
                  name: gym.name,
                  address: gym.address,
                  selected: _pendingGymId == gym.id,
                  onTap: () => setState(() => _pendingGymId = gym.id),
                );
              }
              // Last item: "OTRO GYM / SIN GYM"
              return GymCard(
                name: 'OTRO GYM / SIN GYM', // i18n: Fase 6 Etapa 3
                address: 'No registramos tu gimnasio', // i18n: Fase 6 Etapa 3
                selected: _pendingGymId == kNoGymId,
                onTap: () => setState(() => _pendingGymId = kNoGymId),
              );
            },
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
                onPressed: saveEnabled ? () => _save(myUid, _pendingGymId) : null,
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
