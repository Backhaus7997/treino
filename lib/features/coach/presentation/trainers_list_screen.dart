import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../gyms/application/gym_providers.dart';
import '../../gyms/domain/gym.dart';
import '../application/trainer_discovery_providers.dart';
import '../domain/trainer_location.dart';
import '../../../l10n/app_l10n.dart';
import 'widgets/location_permission_rationale_sheet.dart';
import 'widgets/trainer_advanced_filter_chips.dart';
import 'widgets/trainer_compact_filter_row.dart';
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
    // Estado del toggle MAPA/LISTA vive en `mapModeProvider` (top-level del
    // feature). Necesita ser shared con el banner del mapa (TrainersMapView)
    // que también lo setea cuando el atleta tap "Tocá para verlos en lista".
    final showMap = ref.watch(mapModeProvider);

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
              showMap: showMap,
              onChanged: (v) => ref.read(mapModeProvider.notifier).state = v,
              mapDisabled: ref.watch(virtualOnlyFilterProvider),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Modo: Presencial vs Online — decisión más importante.
          //    En modo MAPA, paddings más chicos para liberar pantalla.
          Padding(
            padding:
                EdgeInsets.fromLTRB(16, showMap ? 8 : 12, 16, showMap ? 4 : 8),
            child: const _ModeTabs(),
          ),
          // 2. Filtros — en MAPA, una sola row compacta combinando
          //    distancia + precio + specialty. En LISTA, layout original
          //    con section headers y filas separadas.
          if (showMap)
            const TrainerCompactFilterRow()
          else ...[
            _SectionHeader(palette: palette, text: 'ESPECIALIDAD'),
            const SizedBox(height: 6),
            TrainerSpecialtyChips(
              selected: selected,
              onChanged: (next) =>
                  ref.read(selectedSpecialtyProvider.notifier).state = next,
            ),
            // 3. Filtros avanzados — solo en modo Presencial. En Online no
            //    aplica distancia (sin ubicación física) y precio es info
            //    visible en el card del PF.
            if (!ref.watch(virtualOnlyFilterProvider)) ...[
              const SizedBox(height: 12),
              _SectionHeader(palette: palette, text: 'FILTROS'),
              const SizedBox(height: 6),
              const TrainerAdvancedFilterChips(),
            ],
          ],
          SizedBox(height: showMap ? 4 : 8),
          Expanded(
            child: IndexedStack(
              index: showMap ? 1 : 0,
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
  const _ListMapToggle({
    required this.showMap,
    required this.onChanged,
    this.mapDisabled = false,
  });
  final bool showMap;
  final ValueChanged<bool> onChanged;

  /// Cuando true, el pill MAPA se renderea muted + tap no hace nada.
  /// Lo setea el caller cuando el filtro Online está ON — el modo MAPA no
  /// aplica para virtuales (se ve solo en LISTA).
  final bool mapDisabled;

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
            active: showMap && !mapDisabled,
            disabled: mapDisabled,
            palette: palette,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 4),
          _TogglePill(
            label: 'LISTA',
            icon: TreinoIcon.users,
            active: !showMap || mapDisabled,
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
    this.disabled = false,
  });
  final String label;
  final IconData icon;
  final bool active;
  final AppPalette palette;
  final VoidCallback onTap;

  /// Cuando true: pill se muestra muted (opacidad reducida + colores
  /// neutros) y el tap no dispara onTap. Lo usa el pill MAPA cuando el
  /// modo Online está activo (mapa no aplica para virtuales).
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final bg = disabled
        ? Colors.transparent
        : (active ? palette.highlight : Colors.transparent);
    final fg = disabled
        ? palette.textMuted
        : (active ? palette.bg : palette.textMuted);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
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
    final virtualOnly = ref.watch(virtualOnlyFilterProvider);
    // Cargamos el catálogo completo una sola vez — el provider está cacheado
    // (FutureProvider sin autoDispose). Lookup por gymId es O(1) en el map.
    final gymsAsync = ref.watch(gymsProvider);
    final gymsById = <String, Gym>{
      for (final g in gymsAsync.valueOrNull ?? const <Gym>[]) g.id: g,
    };

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
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom),
          itemCount: trainers.length,
          itemBuilder: (context, i) {
            final t = trainers[i];
            final nearest =
                position == null ? null : nearestLocationOf(t, position);
            final label = _labelFor(nearest, gymsById);
            final isVirtual = virtualOnly ||
                (effectiveLocationsOf(t).isEmpty && t.trainerOffersOnline);
            return TrainerListTile(
              profile: t,
              distanceKm:
                  position == null ? null : nearestDistanceKm(t, position),
              onTap: () => context.go('/coach/trainer/${t.uid}'),
              locationLabel: label,
              isVirtualOnly: isVirtual,
            );
          },
        );
      },
    );
  }

  /// Devuelve un label corto para la ubicación más cercana del PF:
  ///   - Si es `gym` y el gym está en `gymsById` → el `name` del gym.
  ///   - Si es `gym` pero no encontramos el doc (cache miss) → 'Gimnasio'.
  ///   - Si es `custom` → el `customLabel`.
  ///   - Si `nearest` es null → null (sin label).
  String? _labelFor(TrainerLocation? nearest, Map<String, Gym> gymsById) {
    if (nearest == null) return null;
    if (nearest.type == TrainerLocationType.gym) {
      final gym = nearest.gymId == null ? null : gymsById[nearest.gymId];
      return gym?.name ?? 'Gimnasio';
    }
    return nearest.customLabel;
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
          AppL10n.of(context).coachEmptyLabel,
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
              AppL10n.of(context).coachErrorLabel,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(AppL10n.of(context).coachRetryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mode tabs (Presencial / Online) ─────────────────────────────────────────
//
// Segmented control binario. Controla `virtualOnlyFilterProvider`: ON cuando
// el atleta elige "Online", OFF cuando elige "Presencial". Esta decisión es
// la más importante de la pantalla — modalidad de servicio, no filtro. Por
// eso vive arriba de todo, con peso visual distinto a los chips de abajo.

class _ModeTabs extends ConsumerWidget {
  const _ModeTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final virtualOnly = ref.watch(virtualOnlyFilterProvider);

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _ModeTab(
            label: 'PRESENCIAL',
            active: !virtualOnly,
            onTap: () {
              final wasVirtualOnly = ref.read(virtualOnlyFilterProvider);
              ref.read(virtualOnlyFilterProvider.notifier).state = false;
              // Auto-switch a MAPA solo cuando venimos de ONLINE —
              // simétrico al tap ONLINE que auto-switchea a LISTA. Si ya
              // estabas en PRESENCIAL y elegiste LISTA, respetamos esa
              // elección (no forzamos MAPA en cada re-tap).
              if (wasVirtualOnly) {
                ref.read(mapModeProvider.notifier).state = true;
              }
            },
            palette: palette,
          ),
          _ModeTab(
            label: 'ONLINE',
            active: virtualOnly,
            onTap: () {
              // Auto-switch a LISTA: el mapa no aplica para virtuales,
              // así que el atleta cae directo en LISTA sin pasos extra.
              // El toggle MAPA queda visualmente disabled mientras Online ON.
              ref.read(virtualOnlyFilterProvider.notifier).state = true;
              ref.read(mapModeProvider.notifier).state = false;
            },
            palette: palette,
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.active,
    required this.onTap,
    required this.palette,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.2,
                color: active ? palette.bg : palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.palette, required this.text});
  final AppPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Text(
        text,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.4,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
