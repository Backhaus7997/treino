// ConsultasCard — card «CONSULTAS» de la columna izquierda de
// PerfilPublicoScreen (#637).
//
// El kill switch del PF: si lo apaga, un alumno sin vínculo deja de poder
// escribirle antes de pedírselo. Vive en Perfil público y no en Ajustes porque
// esta pantalla es la que se presenta como "así te ven los alumnos potenciales
// en Coach Discovery" — y esto es exactamente una decisión sobre eso.
//
// Persiste AL TOCAR, sin botón Guardar, igual que la matriz de notificaciones
// (`notificaciones_tab.dart`) y a diferencia de `IdentidadCard`, cuyo patrón
// dirty/save existe porque edita texto libre. Un switch no tiene borrador.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

class ConsultasCard extends ConsumerStatefulWidget {
  const ConsultasCard({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<ConsultasCard> createState() => _ConsultasCardState();
}

class _ConsultasCardState extends ConsumerState<ConsultasCard> {
  late bool _valor;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _valor = widget.profile.acceptsInquiries;
  }

  @override
  void didUpdateWidget(covariant ConsultasCard old) {
    super.didUpdateWidget(old);
    // El stream del perfil manda. Si el valor cambió afuera —la app mobile, u
    // otra pestaña— gana el que llegó, no el optimista que teníamos puesto.
    if (old.profile.acceptsInquiries != widget.profile.acceptsInquiries) {
      _valor = widget.profile.acceptsInquiries;
    }
  }

  Future<void> _cambiar(bool nuevo) async {
    if (_guardando) return;
    final anterior = _valor;
    // Optimista: el switch se mueve solo, y vuelve si el servidor rebota.
    setState(() {
      _valor = nuevo;
      _guardando = true;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .update(widget.profile.uid, {'acceptsInquiries': nuevo});
    } catch (_) {
      if (!mounted) return;
      setState(() => _valor = anterior);
      ScaffoldMessenger.of(context).showSnackBar(
        // Mismo copy que el resto del Coach Hub cuando falla un guardado.
        const SnackBar(content: Text('No se pudo guardar. Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return TreinoFadeSlideIn(
      delay: AppMotion.stagger(2),
      child: Container(
        key: const Key('consultas_card'),
        padding: const EdgeInsets.all(AppSpacing.s18),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CONSULTAS', // i18n: Fase 11
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: AppFonts.w700,
                fontSize: AppTextSize.body,
                letterSpacing: AppFonts.headingTracking,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.trainerAcceptsInquiriesTitle,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: AppFonts.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        l10n.trainerAcceptsInquiriesSubtitle,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: AppTextSize.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s14),
                Switch(
                  key: const Key('consultas_card_switch'),
                  value: _valor,
                  onChanged: _guardando ? null : _cambiar,
                  activeThumbColor: palette.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
