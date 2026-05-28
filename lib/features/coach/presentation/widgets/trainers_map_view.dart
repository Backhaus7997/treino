import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../application/trainer_discovery_providers.dart';
import '../../domain/trainer_public_profile.dart';
import 'trainers_map_bottom_sheet.dart';

/// Map view de Discovery — embeddable dentro de `TrainersListScreen`
/// como uno de los dos contenidos del IndexedStack (el otro es la lista).
///
/// NO incluye Scaffold ni AppBar — esos los provee la pantalla parent.
/// Tiles oscuros (CartoDB Dark Matter), pill markers con precio +
/// inicial del PF, dot de ubicación del athlete, attribution OSM + CARTO.
///
/// Es `ConsumerStatefulWidget` para mantener un `MapController` persistente
/// entre rebuilds — necesario para el FAB "centrar en mi ubicación" que
/// llama `mapController.move()` programáticamente.
class TrainersMapView extends ConsumerStatefulWidget {
  const TrainersMapView({super.key});

  /// Centro inicial del mapa — Córdoba Capital, zona Centro-Norte.
  static const _initialCenter = LatLng(-31.40, -64.18);
  static const _initialZoom = 13.0;

  /// Tiles dark de CartoDB (free + open data). Coincide visualmente con
  /// la paleta dark mode del resto de la app. Atribución requerida —
  /// renderizada como overlay en la esquina inferior derecha.
  static const _tileUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  static const _tileSubdomains = ['a', 'b', 'c', 'd'];

  @override
  ConsumerState<TrainersMapView> createState() => _TrainersMapViewState();
}

class _TrainersMapViewState extends ConsumerState<TrainersMapView> {
  final _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Centra el mapa en la ubicación actual del atleta, manteniendo el zoom.
  /// No-op si el atleta no tiene ubicación.
  void _recenterToAthlete(Position pos) {
    _mapController.move(
      LatLng(pos.latitude, pos.longitude),
      _mapController.camera.zoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final discoveryAsync = ref.watch(trainerDiscoveryProvider);
    // Scoped: solo rebuild cuando el Position cambia, no en cada
    // transición de AsyncValue (loading → data).
    final athletePosition =
        ref.watch(athleteLocationProvider.select((s) => s.valueOrNull));

    return discoveryAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No pudimos cargar el mapa.',
            style: TextStyle(color: palette.textMuted),
          ),
        ),
      ),
      data: (trainers) {
        // UX decisión: cuando el filtro "Online" está ON, el mapa queda
        // "neutralizado" — el atleta quiso ver virtuales y eso es info de
        // lista, no de mapa. No renderamos markers de trainers; el banner
        // CTA lo redirige a modo lista. (El dot del atleta se mantiene como
        // referencia visual de "estás acá".)
        //
        // Cuando "Online" está OFF (default), markers normales: uno por
        // cada `TrainerLocation` (gym o custom) de cada PF. Un híbrido con
        // 2 gyms tiene 2 pines — tap en cualquiera abre el mismo perfil.
        final virtualOnly = ref.watch(virtualOnlyFilterProvider);
        final markers = <Marker>[
          if (!virtualOnly)
            for (final t in trainers)
              for (final loc in effectiveLocationsOf(t))
                _buildTrainerMarker(
                  context,
                  t,
                  palette,
                  LatLng(loc.lat, loc.lng),
                ),
          if (athletePosition != null)
            _buildAthleteMarker(athletePosition, palette),
        ];

        // Banner CTA: aparece siempre que el filtro "Online" esté ON. Lo
        // que el atleta quiere ver no es geográfico — el mapa no aplica.
        final showVirtualBanner = virtualOnly;

        return Stack(
          children: [
            // Mapa de fondo
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: TrainersMapView._initialCenter,
                initialZoom: TrainersMapView._initialZoom,
                minZoom: 3,
                maxZoom: 18,
                // Pinta el canvas del mapa con el bg del theme dark mientras
                // las tiles del CDN cargan. Sin esto, scrollear rápido muestra
                // "cuadrados blancos" donde aún no llegó la tile — flicker
                // feo que contrasta con el theme oscuro.
                backgroundColor: palette.bg,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: TrainersMapView._tileUrl,
                  subdomains: TrainersMapView._tileSubdomains,
                  userAgentPackageName: 'com.treino.app',
                  retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
                  maxZoom: 19,
                  // Pre-carga tiles vecinas (1 buffer ring) — reduce el flash
                  // cuando se hace pan rápido a una zona no cacheada.
                  panBuffer: 1,
                ),
                MarkerLayer(markers: markers),
              ],
            ),
            // Atribución OSM + CARTO (legal compliance) — top-right del map,
            // arriba del bottom sheet para no quedar tapada.
            Positioned(
              top: 8,
              right: 8,
              child: _AttributionChip(palette: palette),
            ),
            // Banner CTA: aparece sobre el mapa cuando el atleta activa
            // "Online" — el mapa no aplica para virtuales, el banner ofrece
            // switch a modo lista donde sí se ven todos los que ofrecen online.
            if (showVirtualBanner)
              Positioned(
                top: 8,
                left: 16,
                right: 80, // deja espacio para el _AttributionChip top-right
                child: _VirtualOnlyBanner(
                  palette: palette,
                  onTapList: () =>
                      ref.read(mapModeProvider.notifier).state = false,
                ),
              ),
            // FAB "Centrar en mi ubicación" — solo aparece si el atleta tiene
            // location concedida. Ubicado a la derecha, con offset de ~220px
            // desde el bottom para quedar arriba del bottom sheet collapsed
            // (drag handle ~28 + header ~24 + carousel 110 + paddings ~40 ≈
            // 200px) + 20px de aire. Si el sheet se expande, el FAB queda
            // detrás — aceptable UX, el user quiso ver detalles.
            if (athletePosition != null)
              Positioned(
                right: 16,
                bottom: 220,
                child: _RecenterFab(
                  palette: palette,
                  onTap: () => _recenterToAthlete(athletePosition),
                ),
              ),
            // Bottom sheet con carousel de cards.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TrainersMapBottomSheet(),
            ),
          ],
        );
      },
    );
  }

  // ── Markers ────────────────────────────────────────────────────────────────

  Marker _buildTrainerMarker(
    BuildContext context,
    TrainerPublicProfile t,
    AppPalette palette,
    LatLng point,
  ) {
    final initial = (t.displayName?.trim().isNotEmpty == true
            ? t.displayName!.trim()[0]
            : '?')
        .toUpperCase();
    final priceLabel = t.trainerMonthlyRate != null
        ? '\$${(t.trainerMonthlyRate! / 1000).toStringAsFixed(0)}k/mes'
        : 'Consultar';

    return Marker(
      point: point,
      width: 110,
      height: 48,
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onTap: () => context.go('/coach/trainer/${t.uid}'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
              decoration: BoxDecoration(
                color: palette.highlight,
                borderRadius: BorderRadius.circular(9999),
                boxShadow: [
                  BoxShadow(
                    color: palette.bg.withValues(alpha: 0.6),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: palette.bg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: GoogleFonts.barlowCondensed(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    priceLabel,
                    style: GoogleFonts.barlowCondensed(
                      color: palette.bg,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            CustomPaint(
              size: const Size(10, 8),
              painter: _DownArrowPainter(color: palette.highlight),
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildAthleteMarker(Position pos, AppPalette palette) {
    return Marker(
      point: LatLng(pos.latitude, pos.longitude),
      width: 28,
      height: 28,
      child: _AthleteLocationDot(palette: palette),
    );
  }
}

// ── Athlete location dot — mint con anillo concéntrico ────────────────────────

class _AthleteLocationDot extends StatelessWidget {
  const _AthleteLocationDot({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.accent.withValues(alpha: 0.25),
            ),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.accent,
              border: Border.all(color: palette.bg, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Attribution chip — OSM + CARTO legal compliance ──────────────────────────

class _AttributionChip extends StatelessWidget {
  const _AttributionChip({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '© OpenStreetMap · CARTO',
        style: GoogleFonts.barlow(
          fontSize: 9,
          color: palette.textPrimary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

// ── Down arrow painter — la "cola" del pill marker que apunta al lat/lng ──────

class _DownArrowPainter extends CustomPainter {
  _DownArrowPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DownArrowPainter old) => old.color != color;
}

// ── Recenter FAB ──────────────────────────────────────────────────────────────

/// Botón flotante "Centrar en mi ubicación". Pattern estándar de apps de
/// mapas (Google Maps, Waze, Uber). Recentra el viewport en la `Position`
/// actual del atleta sin cambiar el zoom — útil cuando el user paneó lejos
/// y se "perdió". Solo se renderea cuando `athleteLocationProvider` tiene
/// `Position` válida (sino el botón no tiene a dónde ir).
class _RecenterFab extends StatelessWidget {
  const _RecenterFab({required this.palette, required this.onTap});
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.bgCard,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.border),
          ),
          child: Icon(
            TreinoIcon.mapPin,
            color: palette.accent,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ── Virtual-only banner ──────────────────────────────────────────────────────

/// Banner que aparece en modo mapa cuando el filtro "Online" está ON y hay
/// PFs virtuales puros (sin ubicación física) que el mapa no puede mostrar.
/// Tap → cambia a modo lista para que el atleta los vea.
class _VirtualOnlyBanner extends StatelessWidget {
  const _VirtualOnlyBanner({
    required this.palette,
    required this.onTapList,
  });
  final AppPalette palette;
  final VoidCallback onTapList;

  @override
  Widget build(BuildContext context) {
    const label = 'Entrenadores online no se ven en el mapa';
    return Material(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      child: InkWell(
        onTap: onTapList,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(TreinoIcon.infoCircle, size: 18, color: palette.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tocá para verlos en lista',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(TreinoIcon.forward, size: 18, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}
