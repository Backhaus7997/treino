import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// El aviso que [intentarCrearEjercicioPropio] muestra cuando el PF choca el
/// tope de ejercicios propios de su plan
/// (docs/limite-ejercicios-pf.md PR3, "Los avisos").
///
/// **Móvil: SOLO estado.** Sin botón de acción, sin nombrar "web", "mail" ni
/// "pasá a un plan" — bajo la Guideline 3.1.3(f) cualquiera de esas cosas es
/// un llamado a comprar afuera, y lo que se arriesga es la exención del
/// ENTRENADOR (mismo criterio que `free_plan_limit_sheet.dart`). Lo cuidan
/// `anti_steering_movil_test.dart` y `superficie_de_cobro_alumno_test.dart` —
/// si alguno se pone rojo por este archivo, se cambia el TEXTO acá, nunca el
/// guard.
///
/// **Web: con botón VER PLANES** a `/facturacion/planes`. La web sí vende
/// (E8 — 3.1.3(f) sólo ampara al binario móvil).
enum CustomExerciseLimitNoticeForm { sheet, dialog }

/// Fuerza la forma del aviso. SÓLO para tests — mismo seam que
/// `debugPlanLimitPaywallForm` en `plan_limit_paywall.dart`, y por el mismo
/// motivo: `kIsWeb` es una constante de compilación que bajo `flutter test`
/// vale `false` siempre, así que sin este seam la rama [dialog] quedaría sin
/// cobertura.
@visibleForTesting
CustomExerciseLimitNoticeForm? debugCustomExerciseLimitNoticeForm;

CustomExerciseLimitNoticeForm _resolveForm() =>
    debugCustomExerciseLimitNoticeForm ??
    (kIsWeb
        ? CustomExerciseLimitNoticeForm.dialog
        : CustomExerciseLimitNoticeForm.sheet);

/// Muestra el aviso. [limit] y [count] son los que ya resolvió
/// [customExerciseQuotaProvider] — acá no se vuelve a mirar la cuota, sólo se
/// decide qué texto mostrar.
///
/// Dos estados, igual en las dos superficies (docs/limite-ejercicios-pf.md
/// PR3):
/// - **En el tope** (`count == limit`): "llegaste al tope, podés editar o
///   borrar".
/// - **Por encima** (`count > limit`, E3 — bajó de plan): "conservás todos,
///   para crear uno nuevo borrá N", con `N = count - limit + 1`.
Future<void> showCustomExerciseLimitNotice(
  BuildContext context, {
  required int limit,
  required int count,
}) {
  final overLimit = count > limit;
  final toDelete = count - limit + 1;

  if (_resolveForm() == CustomExerciseLimitNoticeForm.dialog) {
    return showDialog<void>(
      context: context,
      builder: (_) => _CustomExerciseLimitDialog(
        overLimit: overLimit,
        limit: limit,
        count: count,
        toDelete: toDelete,
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    // Mismo motivo que `plan_limit_paywall.dart`: en la app móvil el shell
    // vive DENTRO del `Scaffold.body`, así que sin `useRootNavigator: true`
    // el sheet queda recortado y la bottom bar flota encima.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _CustomExerciseLimitSheet(
      overLimit: overLimit,
      limit: limit,
      count: count,
      toDelete: toDelete,
    ),
  );
}

/// Móvil — sheet de sólo estado. Strings vía [AppL10n]: es la convención del
/// móvil (docs/limite-ejercicios-pf.md PR3, "Convenciones").
class _CustomExerciseLimitSheet extends StatelessWidget {
  const _CustomExerciseLimitSheet({
    required this.overLimit,
    required this.limit,
    required this.count,
    required this.toDelete,
  });

  final bool overLimit;
  final int limit;
  final int count;
  final int toDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          border: Border(
            top: BorderSide(color: palette.accent.withValues(alpha: 0.33)),
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),
                Flexible(
                  child: SingleChildScrollView(
                    child: _NoticeContent(
                      palette: palette,
                      title: l10n.customExerciseLimitNoticeTitle.toUpperCase(),
                      body: overLimit
                          ? l10n.customExerciseLimitOverBody(
                              count,
                              limit,
                              toDelete,
                            )
                          : l10n.customExerciseLimitReachedBody(limit),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const Key('custom_exercise_limit_dismiss'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textPrimary,
                      side: BorderSide(color: palette.borderStrong),
                      shape: const StadiumBorder(),
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                    ),
                    child: Text(
                      l10n.customExerciseLimitDismiss.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: AppFonts.barlowCondensed,
                        fontSize: AppTextSize.body,
                        fontWeight: AppFonts.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Web (Coach Hub) — dialog con botón VER PLANES. Strings hardcodeadas
/// marcadas `// i18n: Fase W3`, como el resto del Coach Hub.
class _CustomExerciseLimitDialog extends StatelessWidget {
  const _CustomExerciseLimitDialog({
    required this.overLimit,
    required this.limit,
    required this.count,
    required this.toDelete,
  });

  final bool overLimit;
  final int limit;
  final int count;
  final int toDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // El mismo texto de conservación que en el móvil cuando está PASADO de
    // tope (docs/limite-ejercicios-pf.md PR3, "Los avisos": "Pasado de tope:
    // el mismo texto de conservación que en el móvil, más el botón").
    final body = overLimit
        ? 'Tenés $count ejercicios propios y tu plan incluye $limit. '
            'Conservás todos; para crear uno nuevo, borrá $toDelete.' // i18n: Fase W3
        : 'Tu plan incluye $limit ejercicios propios y ya tenés '
            '$limit.'; // i18n: Fase W3

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: palette.accent, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NoticeContent(
                palette: palette,
                title: 'TOPE DE EJERCICIOS PROPIOS', // i18n: Fase W3
                body: body,
              ),
              const SizedBox(height: AppSpacing.s20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('custom_exercise_limit_ver_planes'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/facturacion/planes');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: TreinoButtonTokens.foreground(context),
                    shape: const StadiumBorder(),
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                  ),
                  child: const Text(
                    'VER PLANES', // i18n: Fase W3
                    style: TextStyle(
                      fontFamily: AppFonts.barlowCondensed,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Ahora no', // i18n: Fase W3
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ícono + título + cuerpo. EL MISMO layout en las dos superficies — sólo
/// cambia el texto del cuerpo (móvil vía [AppL10n], web hardcodeado), mismo
/// criterio que `_PlanLimitPaywallContent` en `plan_limit_paywall.dart`: un
/// solo lugar que decide QUÉ dice.
class _NoticeContent extends StatelessWidget {
  const _NoticeContent({
    required this.palette,
    required this.title,
    required this.body,
  });

  final AppPalette palette;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.08),
              border: Border.all(color: palette.accent.withValues(alpha: 0.33)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(TreinoIcon.dumbbell, size: 28, color: palette.accent),
          ),
        ),
        const SizedBox(height: AppSpacing.s14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            color: palette.textPrimary,
            fontSize: AppTextSize.heading,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          body,
          textAlign: TextAlign.center,
          style:
              TextStyle(color: palette.textMuted, fontSize: AppTextSize.body),
        ),
      ],
    );
  }
}
