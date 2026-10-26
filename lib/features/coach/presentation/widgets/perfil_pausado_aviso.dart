import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/core/widgets/treino_toast.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart' show AppRadius, AppSpacing;
import '../../../../l10n/app_l10n.dart';
import '../../../profile/application/user_providers.dart';

/// Aviso fijo mientras el PF tiene pausados los alumnos nuevos
/// (`acceptingAthletes == false`), con un botón para reanudar.
///
/// Existe porque la pausa es invisible para el que la puso: lo saca del
/// discovery, pero en SU app todo se ve igual, y el switch para revertirla
/// vive adentro del editor de perfil. Un PF que se olvida de reanudar queda
/// oculto con lugares libres — el mismo costo por el que la pausa por cupo
/// lleno es una sugerencia y no automática. Este aviso es la otra mitad de esa
/// decisión: si nada pausa solo, nada puede quedar pausado sin que se vea.
///
/// No se descarta: dura lo que dura la pausa. Con el perfil abierto no dibuja
/// nada, ni el margen (por eso lo trae él y no el llamador).
class PerfilPausadoAviso extends ConsumerStatefulWidget {
  const PerfilPausadoAviso({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  ConsumerState<PerfilPausadoAviso> createState() => _PerfilPausadoAvisoState();
}

class _PerfilPausadoAvisoState extends ConsumerState<PerfilPausadoAviso> {
  bool _guardando = false;

  Future<void> _reanudar(String uid) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      // Al confirmar, el stream del perfil trae `acceptingAthletes: true` y el
      // aviso se va solo.
      await ref
          .read(userRepositoryProvider)
          .update(uid, {'acceptingAthletes': true});
    } catch (_) {
      if (mounted) {
        showTreinoToast(
          context,
          'No se pudo guardar. Probá de nuevo.', // i18n
          type: TreinoToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    if (profile == null || profile.acceptingAthletes) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Container(
      key: const Key('perfil_pausado_aviso'),
      margin: widget.margin,
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.highlight),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.trainerPausedNoticeTitle,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.8,
                    color: palette.highlight,
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l10n.trainerPausedNoticeBody,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          OutlinedButton(
            key: const Key('perfil_pausado_reanudar'),
            onPressed: _guardando ? null : () => _reanudar(profile.uid),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.accentText,
              side: BorderSide(color: palette.accent),
              shape: const StadiumBorder(),
            ),
            child: Text(l10n.trainerPausedNoticeAction),
          ),
        ],
      ),
    );
  }
}
