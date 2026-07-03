import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/geohash.dart';
import '../../../../core/utils/haversine.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../coach/presentation/widgets/location_permission_rationale_sheet.dart';
import '../../../gyms/application/places_providers.dart';
import '../../../profile_setup/presentation/widgets/gym_card.dart';

/// Distance-ranked nearby-gyms section — the `emptyQueryContent` widget
/// passed to [GymSearchBox] by `ProfileGymScreen` (design AD-10). Renders
/// every state from the design's state table: location opt-in affordance,
/// fetch loading/error/empty, and EVERY fetched row (up to the provider's
/// `maxResultCount: 20` request cap) with "a X km" labels.
///
/// Per design gym-selection-v2 AD-13 (Phase 3 addendum): renders ALL
/// fetched results, not a smaller fixed visible subset — the retired
/// 8-row cap + "Ver más" affordance actively hid the user's real gym
/// (ranked #14 in a dense area) behind an extra tap during device testing.
/// The 20 results are already fetched and already billed for; rendering
/// them all costs zero additional API calls.
///
/// Calls [NearbyLocationNotifier.checkSilently] exactly once per
/// screen-open (on first build) — the silent half of the AD-1 hybrid
/// location pattern. Never calls `requestPermission()` except after the
/// user taps the inline affordance AND accepts the rationale sheet.
///
/// A tap on a row resolves and persists the selection immediately via
/// `selectGymActionProvider.select(uid, placeId)` — spec gym-places-search
/// "Selecting a nearby gym uses the same selection path as Autocomplete"
/// (no session token, unlike a staged Autocomplete tap). [onGymSelected] is
/// then notified so the host screen can update its highlighted/pinned
/// state.
class NearbyGymsList extends ConsumerStatefulWidget {
  const NearbyGymsList({
    super.key,
    required this.uid,
    required this.currentGymId,
    this.onGymSelected,
  });

  /// Athlete uid — passed straight through to
  /// `selectGymActionProvider.select(uid: uid, placeId: ...)`.
  final String uid;

  /// Suppressed from the rendered rows per design AD-5 (the pinned card is
  /// the single source of truth for the current gym).
  final String? currentGymId;

  /// Called with the resolved `gymId` after a successful nearby selection.
  final void Function(String gymId)? onGymSelected;

  @override
  ConsumerState<NearbyGymsList> createState() => _NearbyGymsListState();
}

class _NearbyGymsListState extends ConsumerState<NearbyGymsList> {
  bool _checkedSilently = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Silent check-once-per-open (AD-1) — fired from didChangeDependencies
    // (not initState) so `ref` is safe to read; guarded by _checkedSilently
    // so rebuilds never re-trigger it.
    if (!_checkedSilently) {
      _checkedSilently = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(nearbyLocationProvider.notifier).checkSilently();
        }
      });
    }
  }

  Future<void> _onActivateLocationTap() async {
    final accepted = await showLocationPermissionRationaleSheet(context);
    if (!mounted || !accepted) return;
    await ref.read(nearbyLocationProvider.notifier).requestPermission();
  }

  Future<void> _onGymTap(String placeId) async {
    await ref.read(selectGymActionProvider.notifier).select(
          uid: widget.uid,
          placeId: placeId,
          useSessionToken: false,
        );
    if (!mounted) return;
    final actionState = ref.read(selectGymActionProvider);
    if (!actionState.hasError) {
      widget.onGymSelected?.call(placeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final locationState = ref.watch(nearbyLocationProvider);
    final position = locationState.valueOrNull;

    if (locationState.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (position == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _onActivateLocationTap,
            icon: Icon(TreinoIcon.mapPin, color: palette.accent, size: 18),
            label: Text(
              l10n.gymNearbyLocationAffordance,
              style: GoogleFonts.barlow(color: palette.accent, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final bucket = geohash5(position.latitude, position.longitude);
    final nearbyAsync = ref.watch(nearbyGymsProvider(bucket));

    return nearbyAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.gymNearbyLoadError,
              style: TextStyle(color: palette.danger, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => ref.invalidate(nearbyGymsProvider(bucket)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l10n.coachRetryLabel,
                  style: TextStyle(color: palette.accent),
                ),
              ),
            ),
          ],
        ),
      ),
      data: (gyms) {
        final deduped = gyms
            .where((g) => g.placeId != widget.currentGymId)
            .toList(growable: false);
        if (deduped.isEmpty) return const SizedBox.shrink();

        // AD-13: render every fetched (deduped) row — no visible-count cap,
        // no "Ver más" expand step. The list already scrolls inside
        // ProfileGymScreen's SingleChildScrollView.
        return Column(
          children: [
            for (final gym in deduped) ...[
              GymCard(
                name: gym.name,
                address: _addressWithDistance(
                  gym.address,
                  haversineKm(
                    position.latitude,
                    position.longitude,
                    gym.lat,
                    gym.lng,
                  ),
                ),
                selected: false,
                onTap: () => _onGymTap(gym.placeId),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  String _addressWithDistance(String? address, double km) {
    final distanceLabel = 'a ${km.toStringAsFixed(1)} km';
    if (address == null || address.isEmpty) return distanceLabel;
    return '$address · $distanceLabel';
  }
}
