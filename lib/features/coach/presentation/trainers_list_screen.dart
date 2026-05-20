import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/haversine.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/trainer_discovery_providers.dart';
import '../domain/trainer_public_profile.dart';
import 'coach_strings.dart';
import 'widgets/location_permission_rationale_sheet.dart';
import 'widgets/trainer_list_tile.dart';
import 'widgets/trainer_specialty_chips.dart';

/// Pantalla principal de discovery de entrenadores (rol athlete).
///
/// Reemplaza el stub `AthleteCoachView`. ConsumerStatefulWidget per D22 —
/// necesita initState para el flow de permission rationale.
class TrainersListScreen extends ConsumerStatefulWidget {
  const TrainersListScreen({super.key});

  @override
  ConsumerState<TrainersListScreen> createState() => _TrainersListScreenState();
}

class _TrainersListScreenState extends ConsumerState<TrainersListScreen> {
  bool _rationaleShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowRationale();
    });
  }

  Future<void> _maybeShowRationale() async {
    if (_rationaleShown) return;
    final notifier = ref.read(athleteLocationProvider.notifier);
    if (!notifier.isInitial) return;
    _rationaleShown = true;
    final accepted = await LocationPermissionRationaleSheet.show(context);
    if (!mounted) return;
    if (accepted == true) {
      await notifier.requestPermission();
    } else {
      notifier.setDeniedForTest();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final discoveryAsync = ref.watch(trainerDiscoveryProvider);
    final selected = ref.watch(selectedSpecialtyProvider);
    final position = ref.watch(athleteLocationProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(CoachStrings.appBarTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(CoachStrings.mapProximamente)),
              );
            },
            icon: Icon(TreinoIcon.mapPin, color: palette.accent, size: 18),
            label: Text(
              CoachStrings.mapToggleLabel,
              style: TextStyle(color: palette.accent),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TrainerSpecialtyChips(
              selected: selected,
              onChanged: (s) =>
                  ref.read(selectedSpecialtyProvider.notifier).state = s,
            ),
          ),
          Expanded(
            child: discoveryAsync.when(
              loading: () => Center(
                  child: CircularProgressIndicator(color: palette.accent)),
              error: (_, __) => _ErrorState(
                onRetry: () => ref.invalidate(trainerDiscoveryProvider),
              ),
              data: (trainers) {
                if (trainers.isEmpty) {
                  return const _EmptyState();
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: trainers.length,
                  itemBuilder: (context, i) {
                    final t = trainers[i];
                    return TrainerListTile(
                      profile: t,
                      distanceKm: _distanceFor(t, position),
                      onTap: () => context.go('/coach/trainer/${t.uid}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double? _distanceFor(TrainerPublicProfile t, Position? pos) {
    if (pos == null ||
        t.trainerLatitude == null ||
        t.trainerLongitude == null) {
      return null;
    }
    return haversineKm(
      pos.latitude,
      pos.longitude,
      t.trainerLatitude!,
      t.trainerLongitude!,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          CoachStrings.emptyLabel,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textMuted),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              CoachStrings.errorLabel,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text(CoachStrings.retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
