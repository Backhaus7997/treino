import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../application/trainer_discovery_providers.dart';
import '../../domain/trainer_location.dart';
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

  /// Tiles CartoDB "Voyager" — estilo colorido tipo Google Maps con
  /// agua azul, parques verdes, calles beige/blanco. Reemplazó al
  /// `dark_all` (calles imperceptibles sobre negro) y al intento de
  /// Stadia Alidade Smooth Dark (requiere API key, devolvía tiles
  /// negras en anonymous). Voyager es free, sin API key, y prioriza
  /// identificación de zonas a primera vista.
  ///
  /// Trade-off: rompe la coherencia "dark mode" de la app, pero el
  /// user explícitamente lo pidió porque el dark dificultaba reconocer
  /// barrios y calles. Los markers mint/magenta de los PFs igual
  /// destacan sobre el fondo claro.
  ///
  /// Atribución requerida (OSM + CARTO).
  static const _tileUrl =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
  static const _tileSubdomains = ['a', 'b', 'c', 'd'];

  @override
  ConsumerState<TrainersMapView> createState() => _TrainersMapViewState();
}

class _TrainersMapViewState extends ConsumerState<TrainersMapView> {
  final _mapController = MapController();

  /// Estado del bottom sheet "entrenadores cerca" — lifted del child para
  /// que el FAB de centrar pueda adaptar su offset según si el sheet está
  /// colapsado o expandido (sino el FAB queda tapado o flotando suelto).
  bool _sheetCollapsed = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Centra el mapa en la ubicación actual del atleta, manteniendo el zoom
  /// pero **reseteando la rotación al norte** (0°) — el user puede haber
  /// rotado el mapa accidentalmente con dos dedos, dejando los textos de
  /// las calles inclinados. Al tocar "centrar" esperás recuperar el estado
  /// "default": tu ubicación al centro + mapa derecho con norte arriba.
  ///
  /// No-op si el atleta no tiene ubicación.
  void _recenterToAthlete(Position pos) {
    _mapController.moveAndRotate(
      LatLng(pos.latitude, pos.longitude),
      _mapController.camera.zoom,
      0, // norte arriba — textos rectos
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
        // Markers: uno por cada `TrainerLocation` (gym o custom) de cada
        // PF. Un híbrido con 2 gyms tiene 2 pines — tap en cualquiera abre
        // el mismo perfil.
        //
        // El modo "Online" no se chequea acá: cuando el atleta lo activa,
        // el screen padre hace auto-switch a LISTA y el toggle MAPA queda
        // disabled, así que esta vista nunca se rendera con virtualOnly ON
        // bajo flujos normales. El conditional `if (!virtualOnly)` se
        // mantenía como guardia defensiva — removido ahora que el flow es
        // determinístico.
        final trainerMarkers = <Marker>[
          for (final t in trainers)
            for (final loc in effectiveLocationsOf(t))
              _buildLocationMarker(
                context,
                t,
                palette,
                LatLng(loc.lat, loc.lng),
                loc.type,
              ),
        ];
        final athleteMarker = athletePosition != null
            ? _buildAthleteMarker(athletePosition, palette)
            : null;

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
                  // Todos los gestos EXCEPTO rotación. El user la disparaba
                  // sin querer con pinch-zoom y los textos de las calles
                  // quedaban inclinados — Google Maps mantiene el norte
                  // arriba por default y es la convención más esperable.
                  // `~InteractiveFlag.rotate` aplica máscara de exclusión.
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: TrainersMapView._tileUrl,
                  subdomains: TrainersMapView._tileSubdomains,
                  userAgentPackageName: 'com.treino.app',
                  // CartoDB Voyager NO tiene tiles @2x retina disponibles
                  // — solicitar `.../{z}/{x}/{y}@2x.png` devuelve 400.
                  // Forzamos `retinaMode: false` para usar siempre tiles @1x.
                  // Trade-off: leve blur en pantallas high-DPI, pero el mapa
                  // se ve correctamente en lugar de quedar todo negro.
                  // Para retina real en producción habría que cambiar a un
                  // tile provider con @2x (Stamen Terrain, Stadia, Mapbox).
                  retinaMode: false,
                  maxZoom: 19,
                  // Pre-carga tiles vecinas (1 buffer ring) — reduce el flash
                  // cuando se hace pan rápido a una zona no cacheada.
                  panBuffer: 1,
                ),
                // Cluster layer: agrupa pines cercanos cuando el mapa está
                // alejado. Mientras el zoom < 14, markers con overlap (~50px)
                // se colapsan en un círculo numerado. Zoom >= 14 (barrio
                // nivel) → cada pin se renderea individual. Tap en cluster
                // → zoom in al área.
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 50,
                    disableClusteringAtZoom: 14,
                    size: const Size(44, 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(50),
                    markers: trainerMarkers,
                    // Default era `zoomToBoundsOnClick: true` que calcula
                    // bounds y zoomea de golpe — muy agresivo, dejaba al
                    // atleta perdido con un solo pin sin contexto. Lo
                    // override: zoom progresivo +2 niveles por tap, capeado
                    // a 14 (que es donde el cluster naturalmente se separa).
                    zoomToBoundsOnClick: false,
                    onClusterTap: (cluster) {
                      final current = _mapController.camera.zoom;
                      final next = (current + 2).clamp(3.0, 14.0);
                      _mapController.move(cluster.bounds.center, next);
                    },
                    builder: (context, markers) => _ClusterBubble(
                      count: markers.length,
                      palette: palette,
                    ),
                  ),
                ),
                // El dot del atleta queda FUERA del cluster — siempre visible
                // como referencia "estás acá", incluso cuando los PFs cerca
                // se colapsaron en cluster.
                if (athleteMarker != null)
                  MarkerLayer(markers: [athleteMarker]),
              ],
            ),
            // Atribución OSM + CARTO (legal compliance) — top-right del map,
            // arriba del bottom sheet para no quedar tapada.
            Positioned(
              top: 8,
              right: 8,
              child: _AttributionChip(palette: palette),
            ),
            // FAB "Centrar en mi ubicación" — solo aparece si el atleta tiene
            // location concedida. AnimatedPositioned para que el offset
            // bottom se adapte suavemente cuando el sheet expande/colapsa:
            //   - sheet colapsado (~64px) → FAB en bottom 80
            //   - sheet expandido (~174px) → FAB en bottom 190
            // Misma duración + curve que el AnimatedSize del carousel para
            // que ambas transiciones se sientan sincronizadas.
            if (athletePosition != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                right: 16,
                bottom: _sheetCollapsed ? 80 : 190,
                child: _RecenterFab(
                  palette: palette,
                  onTap: () => _recenterToAthlete(athletePosition),
                ),
              ),
            // Bottom sheet con carousel de cards. State `collapsed` lifted
            // arriba para que el FAB lo pueda leer.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TrainersMapBottomSheet(
                collapsed: _sheetCollapsed,
                onCollapsedChanged: (next) =>
                    setState(() => _sheetCollapsed = next),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Markers ────────────────────────────────────────────────────────────────

  /// Pill marker para una ubicación del PF. Color + ícono cambian según el
  /// `type` de la ubicación:
  ///   - `gym`    → pill **mint** (accent) + ícono de mancuernas.
  ///   - `custom` → pill **magenta** (highlight) + ícono de pin.
  ///
  /// Esto resuelve la confusión visual del PR#2 donde todos los markers se
  /// veían iguales — ahora el atleta distingue gym (catálogo) de lugar
  /// propio del PF a primera vista.
  Marker _buildLocationMarker(
    BuildContext context,
    TrainerPublicProfile t,
    AppPalette palette,
    LatLng point,
    TrainerLocationType type,
  ) {
    final isGym = type == TrainerLocationType.gym;
    // Custom locations: magenta darkeneado (lerp 35% hacia bg). El
    // magenta puro de `palette.highlight` se sentía neón sobre tiles
    // claros tipo Voyager — bajamos saturación manteniendo el tono.
    final pillColor = isGym
        ? palette.accent
        : Color.lerp(palette.highlight, palette.bg, 0.2)!;
    final icon = isGym ? TreinoIcon.dumbbell : TreinoIcon.mapPin;
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
                color: pillColor,
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
                    child: Icon(icon, color: pillColor, size: 15),
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
              painter: _DownArrowPainter(color: pillColor),
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

// ── Cluster bubble ──────────────────────────────────────────────────────────

/// Burbuja que reemplaza visualmente a múltiples markers cuando se solapan
/// (zoom < 14). Círculo magenta (highlight) con el count adentro — consistente
/// con el color dominante de los pines. Tap → zoom incremental +2 niveles
/// hasta que naturalmente se separe (override del default que hacía zoom muy
/// agresivo).
class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({required this.count, required this.palette});
  final int count;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Mismo darkened-magenta que el pill marker custom, así cluster +
        // markers se sienten cohesivos cuando coexisten en pantalla.
        color: Color.lerp(palette.highlight, palette.bg, 0.2)!,
        border: Border.all(color: palette.bg, width: 2),
        boxShadow: [
          BoxShadow(
            color: palette.bg.withValues(alpha: 0.6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: GoogleFonts.barlowCondensed(
          color: palette.bg,
          fontWeight: FontWeight.w700,
          fontSize: 17,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
