// Diálogo de "+ Nuevo alumno" — genera y comparte el link de invitación.
//
// Antes ese botón hacía `context.go('/alumnos')`: te llevaba a la lista de
// alumnos, que es justo donde NO está el alumno que todavía no tenés. El
// alta real —el alumno se instala la app y pide vincularse— no tenía ninguna
// superficie en el Coach Hub.
//
// Sigue el contrato de sección: sin Scaffold/SafeArea, AppPalette, TreinoIcon
// (ADR-CHW-005).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/domain/trainer_invite_link.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

/// Abre el diálogo de invitación. Devuelve cuando el PF lo cierra.
Future<void> showInviteAthleteDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const InviteAthleteDialog(),
    );

class InviteAthleteDialog extends ConsumerStatefulWidget {
  const InviteAthleteDialog({super.key});

  @override
  ConsumerState<InviteAthleteDialog> createState() =>
      _InviteAthleteDialogState();
}

class _InviteAthleteDialogState extends ConsumerState<InviteAthleteDialog> {
  /// Se apaga solo. No es estado de negocio: es el acuse de recibo del copiado,
  /// que sin él deja al PF sin saber si el click hizo algo.
  bool _copiado = false;

  /// El que apaga el acuse, guardado para poder cancelarlo.
  ///
  /// Con un `Future.delayed` suelto y un chequeo de `mounted`, cerrar el
  /// diálogo justo después de copiar dejaba el timer corriendo dos segundos
  /// sosteniendo este State. No crasheaba —el `mounted` lo tapaba— pero era
  /// una fuga igual, y en tests es un fallo duro: «A Timer is still pending
  /// even after the widget tree was disposed». Lo encontró el test, no la
  /// vista.
  Timer? _apagarAcuse;

  @override
  void dispose() {
    _apagarAcuse?.cancel();
    super.dispose();
  }

  Future<void> _copiar(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    setState(() => _copiado = true);
    // Reiniciado en cada copiado: dos clicks seguidos no dejan que el primer
    // timer apague el acuse del segundo.
    _apagarAcuse?.cancel();
    _apagarAcuse = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiado = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider);
    final link = uid == null ? null : buildTrainerInviteLink(uid);

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
      ),
      child: ConstrainedBox(
        // Un link entra cómodo en 480; más ancho sólo agranda el aire.
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INVITÁ A UN ALUMNO', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  height: 1.0,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                link == null
                    // Único estado de error posible: el link se arma con el uid
                    // de la sesión, sin red de por medio. Si no hay uid, no hay
                    // sesión — y eso lo resuelve volver a entrar, no reintentar.
                    ? 'No pudimos leer tu sesión. Cerrá y volvé a entrar.' // i18n
                    : 'Compartile este link. Cuando lo abra va a poder '
                        'vincularse con vos desde la app.', // i18n
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  height: 1.4,
                  color: palette.textMuted,
                ),
              ),
              if (link != null) ...[
                const SizedBox(height: AppSpacing.s18),
                _CajaDelLink(link: link, palette: palette),
                const SizedBox(height: AppSpacing.s14),
                Row(
                  children: [
                    Expanded(
                      child: _BotonCopiar(
                        copiado: _copiado,
                        onTap: () => _copiar(link),
                        palette: palette,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    TextButton(
                      key: const Key('invite_dialog_close'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Listo', // i18n
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.s18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('invite_dialog_close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cerrar', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// El link, seleccionable y completo.
///
/// `SelectableText` y no `Text`: si el copiado al portapapeles falla —permisos
/// del navegador, contexto no seguro— seleccionar a mano es la única salida que
/// le queda al PF. Un `Text` plano lo dejaría sin ninguna.
class _CajaDelLink extends StatelessWidget {
  const _CajaDelLink({required this.link, required this.palette});

  final String link;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('invite_dialog_link'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: palette.textPrimary.withValues(alpha: 0.05),
        border: Border.all(color: palette.textPrimary.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: SelectableText(
        link,
        maxLines: 2,
        style: GoogleFonts.barlow(
          fontSize: 12,
          height: 1.3,
          color: palette.textPrimary,
        ),
      ),
    );
  }
}

/// Copiar, con acuse de recibo.
///
/// El swap ícono→tilde dura [AppMotion.micro] y pasa por [AppMotion.resolve],
/// así que con reduce-motion activo el cambio es instantáneo en vez de
/// animado. Se anima opacidad, no layout: el botón no cambia de tamaño al
/// confirmar, que es lo que provocaría un salto justo debajo del cursor.
class _BotonCopiar extends StatelessWidget {
  const _BotonCopiar({
    required this.copiado,
    required this.onTap,
    required this.palette,
  });

  final bool copiado;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: const Key('invite_dialog_copy'),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: TreinoButtonTokens.foreground(context),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
      ),
      icon: AnimatedSwitcher(
        duration: AppMotion.resolve(context, AppMotion.micro),
        child: Icon(
          copiado ? TreinoIcon.check : TreinoIcon.copy,
          key: ValueKey(copiado),
          size: 15,
        ),
      ),
      label: Text(
        copiado ? '¡Copiado!' : 'Copiar link', // i18n
        style: GoogleFonts.barlowCondensed(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
