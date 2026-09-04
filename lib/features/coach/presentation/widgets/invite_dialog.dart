import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../application/trainer_link_providers.dart';
import '../../domain/invite_outcome.dart';

/// Muestra el resultado de una invitación y, si corresponde, la aplica.
Future<void> showInviteDialog(BuildContext context, InviteOutcome outcome) =>
    showDialog<void>(
      context: context,
      // No se cierra tocando afuera: el caso E cambia de entrenador, y una
      // decisión así no se toma con un toque distraído en el fondo oscuro.
      barrierDismissible: outcome is! InviteRequiereDesvincular,
      builder: (_) => _InviteDialog(outcome: outcome),
    );

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.outcome});

  final InviteOutcome outcome;

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  bool _trabajando = false;
  String? _error;

  /// El PF que la invitación propone, sea cual sea el caso.
  String get _trainerId => switch (widget.outcome) {
        InvitePuedeVincular(:final trainerId) => trainerId,
        InviteYaSolicitado(:final trainerId) => trainerId,
        InviteYaVinculado(:final trainerId) => trainerId,
        InviteRequiereDesvincular(:final nuevoTrainerId) => nuevoTrainerId,
        InviteNoAplica() => '',
      };

  Future<void> _vincular({String? terminarPrimero}) async {
    if (_trabajando) return;
    final athleteId = ref.read(currentUidProvider);
    if (athleteId == null) return;

    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final repo = ref.read(trainerLinkRepositoryProvider);
      // El orden importa y no es intercambiable: primero se libera el cupo,
      // después se pide el nuevo. Al revés, el `request` chocaría con el
      // vínculo que todavía está vivo.
      if (terminarPrimero != null) {
        await repo.terminate(terminarPrimero, reason: 'switched_trainer');
      }
      await repo.request(trainerId: _trainerId, athleteId: athleteId);
      ref.invalidate(currentAthleteLinkProvider);
      ref.invalidate(currentAthleteLinkAnyStatusProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Nunca dar por buena una vinculación que el backend rechazó: el alumno
      // se quedaría esperando a un PF que no lo tiene.
      if (mounted) {
        setState(() => _error = 'No pudimos completar la vinculación: $e');
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // El nombre es decorativo: si no llega, el diálogo funciona igual. Una
    // vinculación no puede depender de que cargue un perfil público.
    final nombre = ref
        .watch(userPublicProfileProvider(_trainerId))
        .valueOrNull
        ?.displayName;
    final quien = (nombre == null || nombre.isEmpty) ? 'este entrenador' : nombre;

    final (titulo, cuerpo, acciones) = switch (widget.outcome) {
      InvitePuedeVincular() => (
          'TE INVITARON A ENTRENAR', // i18n
          '$quien te invitó a vincularte. Va a poder armarte rutinas y '
              'seguir tu progreso.', // i18n
          [
            _secundario('Ahora no'), // i18n
            _primario('Vincularme', () => _vincular()), // i18n
          ],
        ),
      InviteYaSolicitado() => (
          'YA LE ESCRIBISTE', // i18n
          'Ya le enviaste una solicitud a $quien. Te avisamos cuando '
              'responda.', // i18n
          [_primario('Entendido', _cerrar)], // i18n
        ),
      InviteYaVinculado() => (
          'YA ESTÁN VINCULADOS', // i18n
          'Ya entrenás con $quien. No hace falta que hagas nada.', // i18n
          [_primario('Entendido', _cerrar)], // i18n
        ),
      InviteRequiereDesvincular(:final vinculoActual) => (
          'YA TENÉS ENTRENADOR', // i18n
          'Para vincularte con $quien primero tenés que desvincularte del '
              'entrenador que tenés ahora. Podés volver a vincularte cuando '
              'quieras.', // i18n
          [
            _secundario('Cancelar'), // i18n
            _primario(
              'Desvincular y continuar', // i18n
              () => _vincular(terminarPrimero: vinculoActual.id),
            ),
          ],
        ),
      InviteNoAplica() => ('', '', <Widget>[]),
    };

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
      ),
      title: Text(
        titulo,
        style: GoogleFonts.barlowCondensed(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          height: 1.0,
          color: palette.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cuerpo,
            style: GoogleFonts.barlow(
              fontSize: 14,
              height: 1.4,
              color: palette.textMuted,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              _error!,
              key: const Key('invite_dialog_error'),
              style: GoogleFonts.barlow(
                fontSize: 13,
                height: 1.3,
                color: palette.danger,
              ),
            ),
          ],
        ],
      ),
      actions: acciones,
    );
  }

  void _cerrar() => Navigator.of(context).pop();

  Widget _secundario(String label) => TextButton(
        key: const Key('invite_dialog_cancel'),
        // Cancelar NO modifica ninguna asociación: sólo cierra.
        onPressed: _trabajando ? null : _cerrar,
        child: Text(label),
      );

  Widget _primario(String label, VoidCallback onTap) => FilledButton(
        key: const Key('invite_dialog_confirm'),
        onPressed: _trabajando ? null : onTap,
        child: _trabajando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      );
}
