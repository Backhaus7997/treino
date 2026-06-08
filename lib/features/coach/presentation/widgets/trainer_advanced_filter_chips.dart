import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/trainer_discovery_providers.dart';
import '../../domain/discovery_filters.dart';
import '../../domain/trainer_specialty.dart';
import 'trainer_specialty_chips.dart' show SpecialtyLabels;

/// Row de chips para filtros avanzados (distance + price) — Fase 2b.
///
/// Cada chip:
/// - Renderiza el label corto del filtro actual (ej: "< 5 km" o "Distancia")
/// - Tap → abre `showModalBottomSheet` con la lista de opciones
/// - Visual: cuando el filtro NO es `any`, el chip se pinta como activo
///   (mismo color que specialty chip seleccionado)
///
/// Diseño Fase 2b: chips inline en una row scrollable horizontal,
/// renderizada DEBAJO del row de specialty chips. La row queda compacta
/// (2 chips) — si en el futuro agregamos más filtros, sigue scrolleando.
class TrainerAdvancedFilterChips extends ConsumerWidget {
  const TrainerAdvancedFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final distance = ref.watch(selectedDistanceFilterProvider);
    final price = ref.watch(selectedPriceFilterProvider);
    // Filter de distancia depende del estado del athleteLocationProvider:
    // - `valueOrNull != null`: location lista → chip enabled
    // - `isLoading`: GPS fix en curso (2-3 seg) → chip en "buscando..." con
    //   spinner (NO disabled — sino visualmente el user ve un flash feo
    //   de "deshabilitado" cuando recién tocó Activar)
    // - otherwise (denied / initial sin permiso): chip disabled muted con
    //   ícono location_off; tap abre modal explicativo
    final locationAsync = ref.watch(athleteLocationProvider);
    final hasLocation = locationAsync.valueOrNull != null;
    final isLoadingLocation = locationAsync.isLoading;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          TrainerFilterChip(
            label: isLoadingLocation && !hasLocation
                ? 'Buscando ubicación...'
                : distance.chipLabel,
            isActive: distance != DistanceFilter.any && hasLocation,
            disabled: !hasLocation && !isLoadingLocation,
            isLoading: isLoadingLocation && !hasLocation,
            palette: palette,
            onTap: () {
              if (isLoadingLocation && !hasLocation) {
                return; // no-op mientras carga
              }
              if (hasLocation) {
                showDistanceFilterSheet(context, ref, distance);
              } else {
                showLocationRequiredFilterSheet(context, ref);
              }
            },
          ),
          const SizedBox(width: 8),
          TrainerFilterChip(
            label: price.chipLabel,
            isActive: price != PriceFilter.any,
            disabled: false,
            isLoading: false,
            palette: palette,
            onTap: () => showPriceFilterSheet(context, ref, price),
          ),
          // "Online" se promocionó a tabs Presencial/Online en el header
          // (Fase 6 Etapa 0 PR#3). Ya no vive como chip en esta row.
        ],
      ),
    );
  }
}

// ── Top-level sheet helpers ──────────────────────────────────────────────────
// Promovidos de métodos privados de la clase a funciones top-level para que
// `TrainerCompactFilterRow` (vista MAPA) pueda reusar exactamente el mismo
// flow sin duplicar código.

Future<void> showDistanceFilterSheet(
  BuildContext context,
  WidgetRef ref,
  DistanceFilter current,
) async {
  final selected = await _showFilterSheet<DistanceFilter>(
    context: context,
    title: 'Distancia',
    options: DistanceFilter.values,
    current: current,
    labelOf: (v) => v.label,
  );
  if (selected != null) {
    ref.read(selectedDistanceFilterProvider.notifier).state = selected;
  }
}

Future<void> showPriceFilterSheet(
  BuildContext context,
  WidgetRef ref,
  PriceFilter current,
) async {
  final selected = await _showFilterSheet<PriceFilter>(
    context: context,
    title: 'Precio',
    options: PriceFilter.values,
    current: current,
    labelOf: (v) => v.label,
  );
  if (selected != null) {
    ref.read(selectedPriceFilterProvider.notifier).state = selected;
  }
}

/// Modal de selección de especialidad — **multi-select**.
///
/// "Todos" limpia el set (sin filtro). Tap en cualquier especialidad
/// toggle in/out del set. Closure del sheet = aplicar (los cambios son
/// live, no hay botón Aplicar — la próxima rebuild del provider ya
/// refleja el filtro).
///
/// Diferente de `_showFilterSheet<T>` porque (a) el caso "Todos" mapea
/// a Set vacío en el provider, y (b) cada tap NO cierra el sheet —
/// queda abierto para tap múltiples antes de cerrar.
Future<void> showSpecialtyFilterSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final palette = AppPalette.of(context);
  final maxSheetHeight = MediaQuery.of(context).size.height * 0.55;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.bgCard,
    isScrollControlled: true,
    // Cap a 55% del alto de pantalla. Con 11 opciones (Todos + 10
    // specialties) el contenido sin cap ocupaba casi full screen. Ahora
    // el sheet queda ~la mitad y el ListView interno scrollea para
    // mostrar las opciones que no entran.
    constraints: BoxConstraints(maxHeight: maxSheetHeight),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'ESPECIALIDAD',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 1.4,
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Consumer re-builds este bloque cada vez que el set cambia,
            // sin cerrar el sheet — multi-select live.
            Flexible(
              child: Consumer(builder: (ctx, sheetRef, _) {
                final selected = sheetRef.watch(selectedSpecialtyProvider);
                return ListView(
                  shrinkWrap: true,
                  children: [
                    _FilterOptionTile(
                      label: 'Todos',
                      isSelected: selected.isEmpty,
                      palette: palette,
                      onTap: () => sheetRef
                          .read(selectedSpecialtyProvider.notifier)
                          .state = const <TrainerSpecialty>{},
                    ),
                    for (final s in TrainerSpecialty.values)
                      _FilterOptionTile(
                        label: SpecialtyLabels.of(s),
                        isSelected: selected.contains(s),
                        palette: palette,
                        onTap: () {
                          final next = Set<TrainerSpecialty>.from(selected);
                          if (next.contains(s)) {
                            next.remove(s);
                          } else {
                            next.add(s);
                          }
                          sheetRef
                              .read(selectedSpecialtyProvider.notifier)
                              .state = next;
                        },
                      ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Modal explicativo cuando el athlete denegó (o no otorgó) location y
/// tocó el chip de distancia. Le explica por qué y le ofrece reintentar
/// el permission flow.
Future<void> showLocationRequiredFilterSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final palette = AppPalette.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ACTIVÁ TU UBICACIÓN',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 1.4,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Para filtrar entrenadores por distancia necesitamos saber dónde estás. La ubicación se usa solo en tu dispositivo, no la subimos a ningún servidor.',
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: palette.border),
                      foregroundColor: palette.textPrimary,
                      minimumSize: const Size.fromHeight(44),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'Ahora no',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleActivatePressed(sheetContext, ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      minimumSize: const Size.fromHeight(44),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'Activar',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Handler del botón "Activar" del modal de location-required.
///
/// Branch según current permission state — necesario para evitar el crash
/// del geolocator cuando se llama `requestPermission()` sobre estado
/// `deniedForever` (la app se cierra en algunos Android). Solución:
/// chequear primero, y si está deniedForever, abrir app settings directo
/// (el user puede otorgar manualmente desde ahí).
Future<void> _handleActivatePressed(
  BuildContext sheetContext,
  WidgetRef ref,
) async {
  Navigator.of(sheetContext).pop();
  try {
    final current = await Geolocator.checkPermission();
    if (current == LocationPermission.deniedForever) {
      // Sistema ya no nos deja pedir de nuevo — abrir app settings.
      // NO llamamos `requestPermission()` después porque genera doble
      // recarga (app background → foreground → otra request). El user
      // vuelve, toca "Distancia" de nuevo, y ahí refresca via el flow
      // normal (este mismo handler con checkPermission ya devolviendo
      // `denied` o `whileInUse`).
      await Geolocator.openAppSettings();
    } else if (current == LocationPermission.whileInUse ||
        current == LocationPermission.always) {
      // Ya estaba otorgado (caso típico cuando el user volvió de app
      // settings después de activar manualmente). Solo refrescamos
      // posición — no re-disparamos diálogo del sistema.
      await ref.read(athleteLocationProvider.notifier).requestPermission();
    } else {
      // Estado `denied` (preguntado y rechazado pero no permanente) o
      // `unableToDetermine` — pedir permission normalmente. Sistema
      // muestra diálogo y el user puede aceptar.
      await ref.read(athleteLocationProvider.notifier).requestPermission();
    }
  } catch (_) {
    // Errores del plugin se tragan silenciosamente — el provider state
    // ya refleja el estado real y la UI se actualiza acorde.
  }
}

Future<T?> _showFilterSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T current,
  required String Function(T) labelOf,
}) {
  final palette = AppPalette.of(context);
  final maxSheetHeight = MediaQuery.of(context).size.height * 0.55;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: palette.bgCard,
    // isScrollControlled: true permite que el sheet ocupe más de la mitad
    // de pantalla si hace falta — sin esto la lista de opciones overflowea
    // en phones chicos cuando hay muchas opciones.
    isScrollControlled: true,
    // Mismo cap que el sheet de especialidad — cuando un filtro tenga
    // muchas opciones futuras, no se come la pantalla entera.
    constraints: BoxConstraints(maxHeight: maxSheetHeight),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                title.toUpperCase(),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 1.4,
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Flexible + ListView para que la lista scrollee si hay más
            // opciones de las que entran. shrinkWrap: true para que tome
            // solo la altura necesaria cuando entra todo.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final opt in options)
                    _FilterOptionTile(
                      label: labelOf(opt),
                      isSelected: opt == current,
                      palette: palette,
                      onTap: () => Navigator.of(sheetContext).pop(opt),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Chip (público para reuso desde TrainerCompactFilterRow) ─────────────────

class TrainerFilterChip extends StatelessWidget {
  const TrainerFilterChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.disabled,
    required this.isLoading,
    required this.palette,
    required this.onTap,
  });
  final String label;
  final bool isActive;
  final bool disabled;
  final bool isLoading;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color borderColor;
    final double opacity;

    if (isLoading) {
      // Loading: chip se ve "activo en proceso" — fondo neutral, texto en
      // color primario, sin opacidad reducida. El user ve que estamos
      // trabajando, no que falló.
      bg = palette.bgCard;
      fg = palette.textPrimary;
      borderColor = palette.border;
      opacity = 1.0;
    } else if (disabled) {
      // Soft-disabled: background neutral, texto e ícono muted. Tap sigue
      // funcionando (abre el modal explicativo "activar ubicación").
      bg = palette.bgCard;
      fg = palette.textMuted;
      borderColor = palette.border;
      opacity = 0.6;
    } else if (isActive) {
      bg = palette.accent;
      fg = palette.bg;
      borderColor = palette.accent;
      opacity = 1.0;
    } else {
      bg = palette.bgCard;
      fg = palette.textPrimary;
      borderColor = palette.border;
      opacity = 1.0;
    }

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            // Border-radius 10 (era 9999/pill). Look menos "filter pill"
            // y más "system UI" — el user lo prefirió en feedback de Fase 6.
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (disabled) ...[
                Icon(Icons.location_off, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 0.3,
                  color: fg,
                ),
              ),
              if (!isLoading) ...[
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, size: 16, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Option tile ───────────────────────────────────────────────────────────────

class _FilterOptionTile extends StatelessWidget {
  const _FilterOptionTile({
    required this.label,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.barlow(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? palette.accent : palette.textPrimary,
                ),
              ),
            ),
            if (isSelected) Icon(Icons.check, color: palette.accent, size: 20),
          ],
        ),
      ),
    );
  }
}
