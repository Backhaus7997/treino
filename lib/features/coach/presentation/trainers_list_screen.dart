import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/haversine.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/trainer_discovery_providers.dart';
import '../domain/trainer_public_profile.dart';
import 'coach_strings.dart';
import 'widgets/location_permission_rationale_sheet.dart';
import 'widgets/trainer_list_tile.dart';
import 'widgets/trainer_specialty_chips.dart';
import 'widgets/trainers_map_view.dart';

/// Pantalla principal de discovery de entrenadores (rol athlete).
///
/// Contiene dos vistas alternables via toggle MAPA/Lista:
/// - LISTA: scroll vertical de tiles ordenados por distancia
/// - MAPA: vista geográfica con pill markers + ubicación del athlete
///
/// IndexedStack mantiene el estado de ambas vistas para que el zoom/pan
/// del mapa no se pierda al toggle a lista y vuelta.
///
/// Per design D22 — ConsumerStatefulWidget para initState del rationale.
class TrainersListScreen extends ConsumerStatefulWidget {
  const TrainersListScreen({super.key});

  @override
  ConsumerState<TrainersListScreen> createState() => _TrainersListScreenState();
}

class _TrainersListScreenState extends ConsumerState<TrainersListScreen> {
  bool _rationaleShown = false;
  bool _showMap = false;

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
    final selected = ref.watch(selectedSpecialtyProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: _TitleStack(palette: palette),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ListMapToggle(
              showMap: _showMap,
              onChanged: (v) => setState(() => _showMap = v),
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
            child: IndexedStack(
              index: _showMap ? 1 : 0,
              children: const [
                _ListContent(),
                TrainersMapView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Title stack — magenta "ENCONTRÁ TU" + white "COACH" ──────────────────────

class _TitleStack extends StatelessWidget {
  const _TitleStack({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ENCONTRÁ TU',
          style: GoogleFonts.barlowCondensed(
            color: palette.highlight,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'COACH',
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            height: 1,
          ),
        ),
      ],
    );
  }
}

// ── Toggle pills MAPA / Lista — segmented control ────────────────────────────

class _ListMapToggle extends StatelessWidget {
  const _ListMapToggle({required this.showMap, required this.onChanged});
  final bool showMap;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TogglePill(
            label: 'MAPA',
            icon: TreinoIcon.mapPin,
            active: showMap,
            palette: palette,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 4),
          _TogglePill(
            label: 'LISTA',
            icon: TreinoIcon.users,
            active: !showMap,
            palette: palette,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.label,
    required this.icon,
    required this.active,
    required this.palette,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? palette.highlight : Colors.transparent;
    final fg = active ? palette.bg : palette.textMuted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── List content — extraído del build original para uso en IndexedStack ──────

class _ListContent extends ConsumerWidget {
  const _ListContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final discoveryAsync = ref.watch(trainerDiscoveryProvider);
    final position = ref.watch(athleteLocationProvider).valueOrNull;

    return discoveryAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
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
