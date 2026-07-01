import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../gyms/application/gym_providers.dart';
import '../../gyms/domain/gym.dart' show kNoGymId;
import '../../gyms/domain/gym_brand.dart';
import '../../profile_setup/presentation/widgets/gym_card.dart';
import '../application/user_providers.dart';

/// Allows the authenticated athlete to search and select a gym from the
/// existing catalog (two-step: marca → sucursal), then persist the selection
/// to their profile.
///
/// REQ-PSR-019: search + selection + UserRepository.update({'gymId': ...}).
/// Reuses [gymBrandsProvider], [branchesForBrandProvider],
/// [gymBrandSearchQueryProvider] and [GymCard] from gyms/profile_setup per
/// ADR-PSR-011 (onboarding/profile-edit parity). // i18n: Fase 6 Etapa 3
class ProfileGymScreen extends ConsumerStatefulWidget {
  const ProfileGymScreen({super.key});

  @override
  ConsumerState<ProfileGymScreen> createState() => _ProfileGymScreenState();
}

class _ProfileGymScreenState extends ConsumerState<ProfileGymScreen> {
  String? _pendingGymId;
  bool _initialized = false;
  bool _saving = false;
  String? _selectedBrandId;

  // No initState reset needed: gymBrandSearchQueryProvider is autoDispose, so
  // its state is destroyed when this screen unmounts and re-initializes empty
  // on the next entry.

  Future<void> _save(String uid, String? gymId) async {
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).update(uid, {'gymId': gymId});
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

  void _onBrandTap(GymBrand brand) {
    if (brand.branchCount == 1 && brand.singleBranchGymId != null) {
      setState(() => _pendingGymId = brand.singleBranchGymId);
      return;
    }
    setState(() => _selectedBrandId = brand.brandId);
  }

  void _onBranchTap(String gymId) => setState(() => _pendingGymId = gymId);

  void _onBackToBrands() => setState(() => _selectedBrandId = null);

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
    final selectedBrandId = _selectedBrandId;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: () =>
                selectedBrandId == null ? context.pop() : _onBackToBrands(),
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
                ref.read(gymBrandSearchQueryProvider.notifier).state = v,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: AppL10n.of(context).profileGymSearchHint,
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

        // Brand list (step 1) or branch list (step 2)
        Expanded(
          child: selectedBrandId == null
              ? _BrandListView(
                  pendingGymId: _pendingGymId,
                  onBrandTap: _onBrandTap,
                  onNoGymTap: () => setState(() => _pendingGymId = kNoGymId),
                )
              : _BranchListView(
                  brandId: selectedBrandId,
                  pendingGymId: _pendingGymId,
                  onBack: _onBackToBrands,
                  onBranchTap: _onBranchTap,
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

/// Step 1: lista de marcas, filtrada por [gymBrandSearchQueryProvider],
/// incluyendo la opción fija "OTRO GYM / SIN GYM" al final.
class _BrandListView extends ConsumerWidget {
  const _BrandListView({
    required this.pendingGymId,
    required this.onBrandTap,
    required this.onNoGymTap,
  });

  final String? pendingGymId;
  final void Function(GymBrand) onBrandTap;
  final VoidCallback onNoGymTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandsAsync = ref.watch(gymBrandsProvider);
    final query = ref.watch(gymBrandSearchQueryProvider).trim().toLowerCase();

    return brandsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _ErrorRetry(
        onRetry: () => ref.invalidate(gymsProvider),
      ),
      data: (brands) {
        final filtered = query.isEmpty
            ? brands
            : brands
                .where((b) => b.brandName.toLowerCase().contains(query))
                .toList(growable: false);

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.paddingOf(context).bottom),
          itemCount: filtered.length + 1, // +1 for "OTRO GYM / SIN GYM"
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            if (i < filtered.length) {
              final brand = filtered[i];
              return GymCard(
                name: brand.brandName,
                address: brand.branchCount == 1
                    ? '1 sucursal'
                    : '${brand.branchCount} sucursales',
                selected: brand.singleBranchGymId != null &&
                    pendingGymId == brand.singleBranchGymId,
                onTap: () => onBrandTap(brand),
              );
            }
            // Last item: "OTRO GYM / SIN GYM"
            return GymCard(
              name: 'OTRO GYM / SIN GYM', // i18n: Fase 6 Etapa 3
              address: 'No registramos tu gimnasio', // i18n: Fase 6 Etapa 3
              selected: pendingGymId == kNoGymId,
              onTap: onNoGymTap,
            );
          },
        );
      },
    );
  }
}

/// Step 2: sucursales de la marca elegida ([brandId]), filtradas por
/// [gymBrandSearchQueryProvider] (branchName o city).
class _BranchListView extends ConsumerWidget {
  const _BranchListView({
    required this.brandId,
    required this.pendingGymId,
    required this.onBack,
    required this.onBranchTap,
  });

  final String brandId;
  final String? pendingGymId;
  final VoidCallback onBack;
  final void Function(String) onBranchTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final branchesAsync = ref.watch(branchesForBrandProvider(brandId));
    final query = ref.watch(gymBrandSearchQueryProvider).trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 18, color: palette.textPrimary),
                const SizedBox(width: 8),
                Text(
                  'VOLVER A MARCAS',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1.0,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: branchesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ErrorRetry(
                onRetry: () => ref.invalidate(gymsProvider),
              ),
            ),
            data: (branches) {
              final filtered = query.isEmpty
                  ? branches
                  : branches
                      .where((g) =>
                          (g.branchName ?? '').toLowerCase().contains(query) ||
                          (g.city ?? '').toLowerCase().contains(query))
                      .toList(growable: false);

              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.paddingOf(context).bottom),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final gym = filtered[i];
                  return GymCard(
                    name: gym.branchName ?? gym.name,
                    address: gym.city ?? gym.address ?? '',
                    selected: pendingGymId == gym.id,
                    onTap: () => onBranchTap(gym.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppL10n.of(context).profileLoadError,
          style: TextStyle(color: palette.danger, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              AppL10n.of(context).coachRetryLabel,
              style: TextStyle(color: palette.accent),
            ),
          ),
        ),
      ],
    );
  }
}
