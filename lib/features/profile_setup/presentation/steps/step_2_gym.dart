import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../gyms/application/gym_providers.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../../gyms/domain/gym_brand.dart';
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../widgets/gym_card.dart';

/// Step 2: picker de dos niveles (marca → sucursal) + opción
/// "OTRO/SIN GYM". Mockup: `profile-setup-2.png`.
///
/// Step 1 lista marcas (`gymBrandsProvider`, agrupadas por `brandId`) con su
/// cantidad de sucursales. Marca de una sola sucursal (independiente) resuelve
/// directo, sin pasar por step 2. Marca con 2+ sucursales entra a step 2
/// (`branchesForBrandProvider`), donde se elige la sucursal exacta.
class Step2Gym extends ConsumerStatefulWidget {
  const Step2Gym({super.key});

  @override
  ConsumerState<Step2Gym> createState() => _Step2GymState();
}

class _Step2GymState extends ConsumerState<Step2Gym> {
  String? _selectedBrandId;

  void _onBrandTap(GymBrand brand) {
    if (brand.branchCount == 1 && brand.singleBranchGymId != null) {
      ref
          .read(profileSetupNotifierProvider.notifier)
          .updateGymId(brand.singleBranchGymId);
      return;
    }
    setState(() => _selectedBrandId = brand.brandId);
  }

  void _onBranchTap(String gymId) {
    ref.read(profileSetupNotifierProvider.notifier).updateGymId(gymId);
  }

  void _onBack() => setState(() => _selectedBrandId = null);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final selectedGymId = ref.watch(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.draft.gymId,
      ),
    );
    final selectedBrandId = _selectedBrandId;

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          TextField(
            onChanged: (v) =>
                ref.read(gymBrandSearchQueryProvider.notifier).state = v,
            style: GoogleFonts.barlow(color: palette.textPrimary, fontSize: 14),
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
          const SizedBox(height: 14),
          if (selectedBrandId == null) ...[
            _BrandList(
              selectedGymId: selectedGymId,
              onBrandTap: _onBrandTap,
            ),
            GymCard(
              name: 'OTRO GYM / SIN GYM',
              address: 'No registramos tu gimnasio',
              selected: selectedGymId == kNoGymId,
              onTap: () => ref
                  .read(profileSetupNotifierProvider.notifier)
                  .updateGymId(kNoGymId),
            ),
            const SizedBox(height: 12),
          ] else
            _BranchList(
              brandId: selectedBrandId,
              selectedGymId: selectedGymId,
              onBack: _onBack,
              onBranchTap: _onBranchTap,
            ),
        ],
      ),
    );
  }
}

/// Step 1: lista de marcas filtrada por [gymBrandSearchQueryProvider].
class _BrandList extends ConsumerWidget {
  const _BrandList({required this.selectedGymId, required this.onBrandTap});

  final String? selectedGymId;
  final void Function(GymBrand) onBrandTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandsAsync = ref.watch(gymBrandsProvider);
    final query = ref.watch(gymBrandSearchQueryProvider).trim().toLowerCase();

    return brandsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _ErrorRetry(
        onRetry: () => ref.invalidate(gymsProvider),
      ),
      data: (brands) {
        final filtered = query.isEmpty
            ? brands
            : brands
                .where((b) => b.brandName.toLowerCase().contains(query))
                .toList(growable: false);

        return Column(
          children: [
            for (final brand in filtered) ...[
              GymCard(
                name: brand.brandName,
                address: brand.branchCount == 1
                    ? '1 sucursal'
                    : '${brand.branchCount} sucursales',
                selected: brand.singleBranchGymId != null &&
                    selectedGymId == brand.singleBranchGymId,
                onTap: () => onBrandTap(brand),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

/// Step 2: sucursales de la marca elegida ([brandId]), filtradas por
/// [gymBrandSearchQueryProvider] (branchName o city).
class _BranchList extends ConsumerWidget {
  const _BranchList({
    required this.brandId,
    required this.selectedGymId,
    required this.onBack,
    required this.onBranchTap,
  });

  final String brandId;
  final String? selectedGymId;
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
        GestureDetector(
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
        const SizedBox(height: 12),
        branchesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => _ErrorRetry(
            onRetry: () => ref.invalidate(gymsProvider),
          ),
          data: (branches) {
            final filtered = query.isEmpty
                ? branches
                : branches
                    .where((g) =>
                        (g.branchName ?? '').toLowerCase().contains(query) ||
                        (g.city ?? '').toLowerCase().contains(query))
                    .toList(growable: false);

            return Column(
              children: [
                for (final gym in filtered) ...[
                  GymCard(
                    name: gym.branchName ?? gym.name,
                    address: gym.city ?? gym.address ?? '',
                    selected: selectedGymId == gym.id,
                    onTap: () => onBranchTap(gym.id),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
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
      ),
    );
  }
}
