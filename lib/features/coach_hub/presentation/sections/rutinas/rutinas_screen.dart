// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/widgets/section_header/section_header.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';

/// Sección «Rutinas» del Coach Hub web.
///
/// Una rutina se asigna a UN alumno, así que el flujo necesita un destino.
/// El sidebar es global (no está parado sobre ningún alumno), por eso esta
/// pantalla es el punto de entrada: lista los alumnos vinculados y, al tocar
/// uno, abre sus rutinas (`/rutinas/:athleteId`) donde el PF ve las que ya le
/// cargó y puede crear o editar. Mismo espíritu que mobile, expuesto desde el
/// menú lateral.
class RutinasScreen extends ConsumerWidget {
  const RutinasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TreinoSectionHeader(title: 'Rutinas'), // i18n
          const SizedBox(height: 6),
          Text(
            'Elegí un alumno para armarle una rutina.', // i18n
            style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 20),
          linksAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) =>
                _muted(palette, 'No pudimos cargar los alumnos.'), // i18n
            data: (links) {
              // Una fila por alumno: colapsamos al link más reciente (el stream
              // viene requestedAt DESC) y excluimos `pending` (esas son
              // solicitudes, todavía no son alumnos).
              final seen = <String>{};
              final athletes = <TrainerLink>[];
              for (final l in links) {
                if (l.status == TrainerLinkStatus.pending) continue;
                if (seen.add(l.athleteId)) athletes.add(l);
              }
              if (athletes.isEmpty) {
                return _muted(
                    palette, 'Todavía no tenés alumnos vinculados.'); // i18n
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final link in athletes)
                    _AthleteRow(athleteId: link.athleteId),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Widget _muted(AppPalette palette, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text,
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14)),
    );

/// Fila de un alumno — tap abre el editor de rutinas para ese alumno.
class _AthleteRow extends ConsumerStatefulWidget {
  const _AthleteRow({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_AthleteRow> createState() => _AthleteRowState();
}

class _AthleteRowState extends ConsumerState<_AthleteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(widget.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final name = rawName.isEmpty ? 'Alumno' : rawName; // i18n
    final initial = name.substring(0, 1).toUpperCase();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/rutinas/${widget.athleteId}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _hovered ? palette.borderHover : palette.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: palette.bg,
                child: Text(
                  initial,
                  style: TextStyle(
                      color: palette.accent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Icon(TreinoIcon.chevronRight, size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
