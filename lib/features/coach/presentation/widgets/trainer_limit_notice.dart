import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Los topes del plan del PF que este aviso sabe mostrar
/// (docs/limite-ejercicios-pf.md y docs/limite-plantillas-pf.md, PR3).
///
/// Un solo widget para los dos avisos, generalizado por `kind`: son el mismo
/// layout diciendo lo mismo con otra palabra, y dos copias divergen
/// (docs/limite-plantillas-pf.md PR3, "El aviso"). Si se suma un tercer tope
/// de plan, entra acá con su propio caso — no con un tercer archivo.
enum TrainerLimitKind { customExercises, templates }

/// El aviso que el embudo de cada tope muestra cuando el PF lo choca
/// (docs/limite-ejercicios-pf.md PR3 y docs/limite-plantillas-pf.md PR3,
/// "Los avisos").
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
enum TrainerLimitNoticeForm { sheet, dialog }

/// Fuerza la forma del aviso. SÓLO para tests — mismo seam que
/// `debugPlanLimitPaywallForm` en `plan_limit_paywall.dart`, y por el mismo
/// motivo: `kIsWeb` es una constante de compilación que bajo `flutter test`
/// vale `false` siempre, así que sin este seam la rama [dialog] quedaría sin
/// cobertura.
@visibleForTesting
TrainerLimitNoticeForm? debugTrainerLimitNoticeForm;

TrainerLimitNoticeForm _resolveForm() =>
    debugTrainerLimitNoticeForm ??
    (kIsWeb ? TrainerLimitNoticeForm.dialog : TrainerLimitNoticeForm.sheet);

/// Muestra el aviso de [kind]. [limit] y [count] son los que ya resolvió el
/// provider de cuota de ese tope (`customExerciseQuotaProvider` /
/// `templateQuotaProvider`) — acá no se vuelve a mirar la cuota, sólo se
/// decide qué texto mostrar.
///
/// Dos estados, igual en las dos superficies:
/// - **En el tope** (`count == limit`): "llegaste al tope, podés editar,
///   asignar o [borrar/archivar]".
/// - **Por encima** (`count > limit`, bajaste de plan): "conservás todos,
///   para crear uno nuevo [borrá/archivá] N", con `N = count - limit + 1`.
Future<void> showTrainerLimitNotice(
  BuildContext context, {
  required TrainerLimitKind kind,
  required int limit,
  required int count,
}) {
  final overLimit = count > limit;
  final toFree = count - limit + 1;

  if (_resolveForm() == TrainerLimitNoticeForm.dialog) {
    return showDialog<void>(
      context: context,
      builder: (_) => _TrainerLimitDialog(
        kind: kind,
        overLimit: overLimit,
        limit: limit,
        count: count,
        toFree: toFree,
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
    builder: (_) => _TrainerLimitSheet(
      kind: kind,
      overLimit: overLimit,
      limit: limit,
      count: count,
      toFree: toFree,
    ),
  );
}

/// Móvil — sheet de sólo estado. Strings vía [AppL10n]: es la convención del
/// móvil (docs/limite-ejercicios-pf.md PR3, "Convenciones").
class _TrainerLimitSheet extends StatelessWidget {
  const _TrainerLimitSheet({
    required this.kind,
    required this.overLimit,
    required this.limit,
    required this.count,
    required this.toFree,
  });

  final TrainerLimitKind kind;
  final bool overLimit;
  final int limit;
  final int count;
  final int toFree;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    final title = switch (kind) {
      TrainerLimitKind.customExercises => l10n.customExerciseLimitNoticeTitle,
      TrainerLimitKind.templates => l10n.templateLimitNoticeTitle,
    };
    final body = overLimit
        ? switch (kind) {
            TrainerLimitKind.customExercises =>
              l10n.customExerciseLimitOverBody(count, limit, toFree),
            TrainerLimitKind.templates =>
              l10n.templateLimitOverBody(count, limit, toFree),
          }
        : switch (kind) {
            TrainerLimitKind.customExercises =>
              l10n.customExerciseLimitReachedBody(limit),
            TrainerLimitKind.templates => l10n.templateLimitReachedBody(limit),
          };

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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s12,
              AppSpacing.s20,
              AppSpacing.s18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),
                Flexible(
                  child: SingleChildScrollView(
                    child: _NoticeContent(
                      palette: palette,
                      title: title.toUpperCase(),
                      body: body,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const Key('trainer_limit_dismiss'),
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
class _TrainerLimitDialog extends StatelessWidget {
  const _TrainerLimitDialog({
    required this.kind,
    required this.overLimit,
    required this.limit,
    required this.count,
    required this.toFree,
  });

  final TrainerLimitKind kind;
  final bool overLimit;
  final int limit;
  final int count;
  final int toFree;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final noun = switch (kind) {
      TrainerLimitKind.customExercises => 'ejercicios propios',
      TrainerLimitKind.templates => 'plantillas',
    };
    // "Uno nuevo/todos" (ejercicios, masculino) vs. "una nueva/todas"
    // (plantillas, femenino) — el género del sustantivo cambia con el kind.
    final unoNuevo = switch (kind) {
      TrainerLimitKind.customExercises => 'uno nuevo',
      TrainerLimitKind.templates => 'una nueva',
    };
    final todos = switch (kind) {
      TrainerLimitKind.customExercises => 'todos',
      TrainerLimitKind.templates => 'todas',
    };
    final verb = switch (kind) {
      TrainerLimitKind.customExercises => 'borrá',
      TrainerLimitKind.templates => 'archivá',
    };
    final title = switch (kind) {
      TrainerLimitKind.customExercises => 'TOPE DE EJERCICIOS PROPIOS',
      TrainerLimitKind.templates => 'TOPE DE PLANTILLAS',
    };
    // El mismo texto de conservación que en el móvil cuando está PASADO de
    // tope (docs/limite-ejercicios-pf.md PR3, "Los avisos": "Pasado de tope:
    // el mismo texto de conservación que en el móvil, más el botón").
    final body = overLimit
        ? 'Tenés $count $noun y tu plan incluye $limit. '
            'Conservás $todos; para crear $unoNuevo, $verb $toFree.' // i18n: Fase W3
        : 'Tu plan incluye $limit $noun y ya tenés '
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
          padding: const EdgeInsets.all(AppSpacing.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NoticeContent(
                palette: palette,
                title: title,
                body: body,
              ),
              const SizedBox(height: AppSpacing.s20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('trainer_limit_ver_planes'),
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

/// Ícono + título + cuerpo. EL MISMO layout en las dos superficies y en los
/// dos `kind` — sólo cambia el texto, mismo criterio que
/// `_PlanLimitPaywallContent` en `plan_limit_paywall.dart`: un solo lugar que
/// decide QUÉ dice.
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
              borderRadius: BorderRadius.circular(AppRadius.md),
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
