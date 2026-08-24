import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../chat/application/chat_providers.dart'
    show chatRepositoryProvider;
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;

/// CTA "CONSULTAR" del perfil público de un PF — abre un chat de PRE-CONSULTA
/// sin vínculo formal (#637).
///
/// **Por qué existe.** El perfil tenía un solo CTA, "PEDIR VÍNCULO", y
/// [TrainerContactCtaStub] lo deshabilita si el atleta ya tiene un vínculo
/// `pending`/`active` con CUALQUIER PF. O sea que apenas le pedía vínculo al
/// primer coach los otros quedaban inalcanzables: el producto obligaba a
/// **elegir antes de poder preguntar**.
///
/// **Por qué NO mira el gate de vínculo.** Preguntarle a un entrenador no es
/// cambiarse de entrenador. Se muestra SIEMPRE, y por eso no watchea ningún
/// provider de links — cero rebuilds por un estado que no lo afecta.
///
/// **Qué chat abre.** `ChatRepository.getOrCreate` mira primero si hay un
/// `trainer_links` vigente: si lo hay abre el chat de Coach de siempre, y si no
/// marca el doc con `kind: 'inquiry'`. La regla que habilita esa marca exige
/// que el destinatario sea un PF real y publicado — se cumple por construcción
/// porque este widget sólo vive en el perfil público de un PF, pero el `catch`
/// cubre que lo haya despublicado mientras el atleta miraba la pantalla.
class TrainerInquiryCta extends ConsumerStatefulWidget {
  const TrainerInquiryCta({super.key, required this.trainerId});

  /// uid del PF a consultar.
  final String trainerId;

  @override
  ConsumerState<TrainerInquiryCta> createState() => _TrainerInquiryCtaState();
}

class _TrainerInquiryCtaState extends ConsumerState<TrainerInquiryCta> {
  bool _busy = false;

  Future<void> _onPressed() async {
    if (_busy) return;
    final selfId = ref.read(currentUidProvider);
    if (selfId == null) return;
    // Defensivo: nadie chatea con uno mismo.
    if (selfId == widget.trainerId) return;

    setState(() => _busy = true);
    // Router + messenger capturados ANTES del await (mismo protocolo que
    // `_MessageButton`): la ruta puede popear mid-write y desmontar `context`.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final errorText = AppL10n.of(context).coachInquiryCtaError;
    try {
      final chat = await ref.read(chatRepositoryProvider).getOrCreate(
            selfId: selfId,
            otherId: widget.trainerId,
            asInquiry: true,
          );
      router.push('/coach/chat/${chat.chatId}?other=${widget.trainerId}');
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorText)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          enabled: !_busy,
          label: l10n.coachInquiryCtaLabel,
          child: ExcludeSemantics(
            child: FilledButton(
              onPressed: _busy ? null : _onPressed,
              style: FilledButton.styleFrom(
                // AGENTS.md §2: sobre el acento va el ink invariante de
                // TreinoButtonTokens, NUNCA `palette.bg` — el mint es idéntico
                // en las dos paletas pero `bg` da 1.57:1 en light.
                backgroundColor: TreinoButtonTokens.background(context),
                foregroundColor: TreinoButtonTokens.foreground(context),
                disabledBackgroundColor: palette.border,
                disabledForegroundColor: palette.textMuted,
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              child: _busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TreinoButtonTokens.foreground(context),
                      ),
                    )
                  : Text(
                      l10n.coachInquiryCtaLabel,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 1.5,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          l10n.coachInquiryCtaHelp,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(
            fontSize: 13,
            color: palette.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
