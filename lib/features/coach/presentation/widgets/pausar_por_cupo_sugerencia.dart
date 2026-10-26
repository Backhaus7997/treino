import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/core/widgets/treino_toast.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart'
    show AppRadius, AppSpacing, AppTextSize;
import '../../../../l10n/app_l10n.dart';
import '../../../profile/application/user_providers.dart';

/// ¿Hay que sugerirle al PF que pause su perfil?
///
/// Sólo con un tope que exista ([tope] `null` = sin tope), la carga ponderada
/// que lo alcanzó —el igual cuenta, como en el medidor: con `carga == tope` ya
/// no entra nadie— y el PF todavía abierto a alumnos nuevos.
bool sugerirPausaPorCupo({
  required double carga,
  required int? tope,
  required bool tomandoAlumnos,
}) =>
    tomandoAlumnos && tope != null && carga >= tope;

/// Sugerencia de pausar el perfil cuando el cupo del plan está lleno.
///
/// Es una SUGERENCIA y nada más: el PF decide. Pausar solo tenía un costo que
/// no se ve en el momento — el día que se libera un lugar nadie lo vuelve a
/// abrir, y un PF invisible con cupo libre pierde alumnos sin enterarse.
///
/// Sin esto, con el cupo lleno las solicitudes seguían entrando como
/// `pending` y recién rebotaban al aceptarlas: el alumno esperaba y el PF
/// rechazaba algo que nunca pudo aceptar.
///
/// "Ahora no" la esconde mientras el widget esté montado; vuelve la próxima
/// vez que el PF entre a la pantalla si sigue al tope.
class PausarPorCupoSugerencia extends ConsumerStatefulWidget {
  const PausarPorCupoSugerencia({
    super.key,
    required this.carga,
    required this.tope,
    this.margin = EdgeInsets.zero,
  });

  /// Separación con lo de afuera. Va ACÁ y no en el llamador porque el widget
  /// decide si se dibuja: un gap afuera dejaría un hueco vacío fuera del tope.
  final EdgeInsetsGeometry margin;

  /// Carga ponderada actual (activo 1.0, pausado 0.5).
  final double carga;

  /// Tope del plan en unidades de peso; `null` = sin tope.
  final int? tope;

  @override
  ConsumerState<PausarPorCupoSugerencia> createState() =>
      _PausarPorCupoSugerenciaState();
}

class _PausarPorCupoSugerenciaState
    extends ConsumerState<PausarPorCupoSugerencia> {
  bool _descartada = false;
  bool _guardando = false;

  Future<void> _pausar(String uid) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      // Al confirmar, el stream del perfil trae `acceptingAthletes: false` y
      // la sugerencia se va sola: no hay estado local que mantener.
      await ref
          .read(userRepositoryProvider)
          .update(uid, {'acceptingAthletes': false});
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
    if (_descartada ||
        profile == null ||
        !sugerirPausaPorCupo(
          carga: widget.carga,
          tope: widget.tope,
          tomandoAlumnos: profile.acceptingAthletes,
        )) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Container(
      key: const Key('pausar_por_cupo_sugerencia'),
      margin: widget.margin,
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.highlight),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.trainerPlanLimitPauseTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: AppTextSize.body,
              letterSpacing: 0.8,
              color: palette.highlight,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.trainerPlanLimitPauseBody,
            style: GoogleFonts.barlow(
              fontSize: AppTextSize.bodyDense,
              height: 1.4,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('pausar_por_cupo_ahora_no'),
                onPressed: () => setState(() => _descartada = true),
                child: const Text('Ahora no'), // i18n
              ),
              const SizedBox(width: AppSpacing.s8),
              OutlinedButton(
                key: const Key('pausar_por_cupo_pausar'),
                onPressed: _guardando ? null : () => _pausar(profile.uid),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.accentText,
                  side: BorderSide(color: palette.accent),
                  shape: const StadiumBorder(),
                ),
                child: Text(l10n.trainerPlanLimitPauseAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
