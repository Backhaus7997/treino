// AlumnosNuevosCard — card «ALUMNOS NUEVOS» de la columna izquierda de
// PerfilPublicoScreen, debajo de `ConsultasCard`.
//
// La pausa del PF (`acceptingAthletes`): apagada, deja de aparecer en Coach
// Discovery y no le llegan solicitudes ni consultas nuevas (las rules lo leen
// de `users/{uid}`). Va en Perfil público por lo mismo que Consultas: es una
// decisión sobre cómo te ven los alumnos potenciales.
//
// Persiste AL TOCAR y es optimista con vuelta atrás, igual que `ConsultasCard`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_toast.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

class AlumnosNuevosCard extends ConsumerStatefulWidget {
  const AlumnosNuevosCard({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<AlumnosNuevosCard> createState() => _AlumnosNuevosCardState();
}

class _AlumnosNuevosCardState extends ConsumerState<AlumnosNuevosCard> {
  late bool _valor;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _valor = widget.profile.acceptingAthletes;
  }

  @override
  void didUpdateWidget(covariant AlumnosNuevosCard old) {
    super.didUpdateWidget(old);
    // El stream del perfil manda: la app mobile o la sugerencia de cupo lleno
    // pueden cambiarlo afuera, y gana el que llegó.
    if (old.profile.acceptingAthletes != widget.profile.acceptingAthletes) {
      _valor = widget.profile.acceptingAthletes;
    }
  }

  Future<void> _cambiar(bool nuevo) async {
    if (_guardando) return;
    final anterior = _valor;
    setState(() {
      _valor = nuevo;
      _guardando = true;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .update(widget.profile.uid, {'acceptingAthletes': nuevo});
    } catch (_) {
      if (!mounted) return;
      setState(() => _valor = anterior);
      showTreinoToast(
        context,
        'No se pudo guardar. Probá de nuevo.',
        type: TreinoToastType.error,
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
        key: const Key('alumnos_nuevos_card'),
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
              'ALUMNOS NUEVOS', // i18n: Fase 11
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
                        l10n.trainerAcceptingAthletesTitle,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: AppFonts.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        l10n.trainerAcceptingAthletesSubtitle,
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
                  key: const Key('alumnos_nuevos_card_switch'),
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
