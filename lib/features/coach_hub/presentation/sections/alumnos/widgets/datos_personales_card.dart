import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/coach/application/profile_share_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/gender.dart';

/// Entero si es redondo, un decimal si no (61 → "61", 60.5 → "60.5"). Copia
/// local de `_trimNum` (`alumno_detail_screen.dart`) — ver nota en
/// `resumen_kpi_strip.dart`.
String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Tarjeta de datos personales del alumno en el tab Resumen — Fase 3 WU-05
/// (extraído de `_DatosPersonalesCard`, `alumno_detail_screen.dart`,
/// ADR-A3-04).
///
/// Lee [profileShareProvider] (athlete-shared-profile, Slice 1). Mientras el
/// alumno no opte in (doc ausente → null), muestra un estado vacío claro.
/// Los campos nil dentro del doc se omiten silenciosamente.
///
/// Web read-only — no escribe `profile_shares` en esta slice.
class DatosPersonalesCard extends ConsumerWidget {
  const DatosPersonalesCard({
    super.key,
    required this.palette,
    required this.athleteId,
  });

  final AppPalette palette;
  final String athleteId;

  String _fmtBornAt(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    return '$d/$m/$y';
  }

  String _updatedAt(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    final days = diff.inDays;
    if (days == 0) return 'actualizado hoy'; // i18n
    if (days == 1) return 'actualizado hace 1 día'; // i18n
    return 'actualizado hace $days días'; // i18n
  }

  String _genderLabel(Gender g) => switch (g) {
        Gender.male => 'Masculino', // i18n
        Gender.female => 'Femenino', // i18n
        Gender.nonBinary => 'No binario', // i18n
        Gender.undisclosed => 'Prefiero no decir', // i18n
      };

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: child,
      );

  Widget _skeleton() => _box(
        TreinoShimmer(
          child: Column(
            key: const Key('datos_personales_skeleton'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 4; i++) ...[
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                if (i < 3) const SizedBox(height: AppSpacing.s8),
              ],
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileShareProvider(athleteId));
    final String stateKey;
    final Widget content;

    if (async.isLoading && !async.hasValue) {
      stateKey = 'loading';
      content = _skeleton();
    } else if (async.hasError) {
      stateKey = 'error';
      content = _box(Text(
        'No se pudieron cargar los datos personales.', // i18n
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      ));
    } else {
      final share = async.valueOrNull;
      stateKey = share == null ? 'empty' : 'data';
      content = _box(
        share == null
            ? Text(
                'El alumno no compartió sus datos personales.', // i18n
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (share.phone != null) ...[
                    _DatoRow(
                      palette: palette,
                      label: 'Teléfono', // i18n
                      value: share.phone!,
                    ),
                  ],
                  if (share.bornAt != null) ...[
                    _DatoRow(
                      palette: palette,
                      label: 'Fecha de nacimiento', // i18n
                      value: _fmtBornAt(share.bornAt!),
                    ),
                  ],
                  if (share.heightCm != null) ...[
                    _DatoRow(
                      palette: palette,
                      label: 'Altura', // i18n
                      value: '${share.heightCm} cm',
                    ),
                  ],
                  if (share.bodyWeightKg != null) ...[
                    _DatoRow(
                      palette: palette,
                      label: 'Peso', // i18n
                      value: '${_trimNum(share.bodyWeightKg!)} kg',
                    ),
                  ],
                  if (share.gender != null) ...[
                    _DatoRow(
                      palette: palette,
                      label: 'Género', // i18n
                      value: _genderLabel(share.gender!),
                    ),
                  ],
                  if (share.experienceLevel != null) ...[
                    _DatoRow(
                      palette: palette,
                      label: 'Nivel', // i18n
                      value: share.experienceLevel!.displayNameEs,
                    ),
                  ],
                  if (share.updatedAt != null) ...[
                    const SizedBox(height: AppSpacing.s8 - 2),
                    Text(
                      _updatedAt(share.updatedAt!),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
      );
    }

    return TreinoStateSwitcher(
      childKey: ValueKey('datos_personales_$stateKey'),
      child: content,
    );
  }
}

class _DatoRow extends StatelessWidget {
  const _DatoRow({
    required this.palette,
    required this.label,
    required this.value,
  });

  final AppPalette palette;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8 - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(color: palette.textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
