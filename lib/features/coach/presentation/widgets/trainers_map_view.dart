import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/trainer_discovery_providers.dart';
import '../../domain/trainer_public_profile.dart';
import 'trainers_map_bottom_sheet.dart';

/// Map view de Discovery — embeddable dentro de `TrainersListScreen`
/// como uno de los dos contenidos del IndexedStack (el otro es la lista).
///
/// NO incluye Scaffold ni AppBar — esos los provee la pantalla parent.
/// Tiles oscuros (CartoDB Dark Matter), pill markers con precio +
/// inicial del PF, dot de ubicación del athlete, attribution OSM + CARTO.
class TrainersMapView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final discoveryAsync = ref.watch(trainerDiscoveryProvider);
    final athletePosition = ref.watch(athleteLocationProvider).valueOrNull;

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
        final markers = <Marker>[
          ...trainers
              .where((t) =>
                  t.trainerLatitude != null && t.trainerLongitude != null)
              .map((t) => _buildTrainerMarker(context, t, palette)),
          if (athletePosition != null)
            _buildAthleteMarker(athletePosition, palette),
        ];

        return Stack(
          children: [
            // Mapa de fondo
            FlutterMap(
              options: const MapOptions(
                initialCenter: _initialCenter,
                initialZoom: _initialZoom,
                minZoom: 3,
                maxZoom: 18,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  subdomains: _tileSubdomains,
                  userAgentPackageName: 'com.treino.app',
                  retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
                  maxZoom: 19,
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
  ) {
    final initial = (t.displayName?.trim().isNotEmpty == true
            ? t.displayName!.trim()[0]
            : '?')
        .toUpperCase();
    final priceLabel = t.trainerMonthlyRate != null
        ? '\$${(t.trainerMonthlyRate! / 1000).toStringAsFixed(0)}k/mes'
        : 'Consultar';

    return Marker(
      point: LatLng(t.trainerLatitude!, t.trainerLongitude!),
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
