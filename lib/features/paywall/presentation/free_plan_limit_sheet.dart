import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/athlete_checkout.dart';
import '../domain/athlete_entitlement.dart';
import 'athlete_paywall_screen.dart';

/// Qué eje del plan free se tocó. Cambia sólo el cuerpo del mensaje: el título
/// y la acción son los mismos.
enum FreePlanLimit {
  /// Tope de días de la rutina PROPIA del alumno.
  days,

  /// Tope de semanas (o sea, periodización) de la rutina propia.
  weeks,

  /// Plantilla del catálogo marcada `isPremium`. Eje distinto: acá el límite
  /// no es la forma de lo que armó, es el contenido curado al que accede.
  premiumTemplate,

  /// Quiso COPIAR una plantilla del catálogo para editarla.
  ///
  /// Distinto de [premiumTemplate], y la diferencia importa: acá la plantilla
  /// puede ser una de las gratis. Lo que es del plan pago es *personalizarla*
  /// —la spec le da fila propia (`docs/paywall-alumno-suelto.md` §4, "Editar /
  /// personalizar una plantilla del catálogo")—, mientras seguirla tal cual
  /// sigue siendo gratis y sin tope de días.
  ///
  /// Si se reusara [premiumTemplate] acá, el alumno leería "esta plantilla es
  /// del plan pago" sobre una plantilla que la pantalla anterior le mostró SIN
  /// candado. Dos mensajes contradictorios sobre el mismo objeto.
  customizeTemplate,

  /// Llegó al tope de rutinas propias del plan free. A diferencia de los otros
  /// tres, este límite se toca al GUARDAR: la cuenta sólo se conoce contra la
  /// lista existente.
  routineCount,

  /// Tocó un período de gráfico que es del plan pago. Es el único límite que
  /// no restringe lo que el alumno PUEDE HACER, sino hasta dónde puede MIRAR
  /// lo que ya hizo.
  chartHistory,

  /// La rutina propia que está editando YA tiene más días que el tope, y por
  /// eso el guardado entero rebota.
  ///
  /// **Es un límite de naturaleza distinta a [days], y por eso no lo reusa.**
  /// [days] frena un "+" que todavía no ocurrió: nada se perdió, el tope se
  /// explica en futuro. Éste habla de un documento que YA existe con esa
  /// forma — típicamente uno que el alumno armó antes de que el paywall se
  /// encendiera, o mientras estaba vinculado a un PF que después dejó de
  /// pagar por él. Decirle "armás rutinas de hasta N días" a alguien que está
  /// mirando la suya de N+1 no explica nada: la pregunta que tiene es qué
  /// hace AHORA con ésta.
  ///
  /// Y tiene respuesta, que es lo que hace que valga la pena el valor
  /// separado: `firestore.rules` mide el documento RESULTANTE, así que
  /// recortarla al tope guarda bien. El cuerpo de este caso es el único de la
  /// hoja que pide una acción concreta en vez de nombrar un límite.
  shapeDays,

  /// El hermano de [shapeDays] para el eje SEMANAS.
  ///
  /// Existe porque `withinFreeRoutineShape` mide las DOS dimensiones en la
  /// misma cláusula: cubrir sólo los días dejaría la rutina periodizada
  /// cayendo en el `permission-denied` crudo que este caso vino a sacar.
  shapeWeeks,
}

/// Hoja que explica por qué no se pudo agregar un día (o una semana) más.
///
/// Se abre desde el editor de rutinas cuando el alumno está en `free` y toca
/// el "+" que cruzaría el tope. La abre el TAP, no el guardado, a propósito:
/// es el instante exacto en que el tope muerde, y frenar recién al guardar
/// —después de que cargó ejercicios y series— haría que pierda el trabajo.
///
/// **El botón de pago lo decide la hoja, no el que la abre.**
///
/// Antes habia un parametro `onUpgrade` que cada call site tenia que pasar.
/// Se saco a proposito: son 8 call sites, y 8 lugares donde alguien podia
/// pasar una closure DISTINTA —una que abriera la web, por ejemplo— sin que
/// el tipo sellado se enterara. Una sola decision, en un solo lugar, es la
/// version segura.
///
/// La hoja mira [athleteCheckoutProvider]: dibuja el boton solo cuando hay una
/// superficie que de verdad puede cobrar. Si no la hay —web, o un binario sin
/// la clave del SDK— no lo dibuja, porque un CTA que no lleva a ningun lado es
/// peor que no tenerlo: promete una salida que no esta.
///
/// [actual] es cuántos días (o semanas) tiene HOY la rutina, y sólo lo usan
/// [FreePlanLimit.shapeDays] y [FreePlanLimit.shapeWeeks] — los dos casos que
/// hablan de un documento que ya existe fuera de forma. El tope contra el que
/// se compara NO se pasa: la hoja lo lee de [kFreeMaxRoutineDays] /
/// [kFreeMaxRoutineWeeks]. Es deliberado. El número ya vivía escrito a mano
/// dentro de las cadenas del `.arb` y quedó mintiendo el día que el tope
/// cambió; que la única fuente sea la constante es lo que hace que no pueda
/// volver a pasar.
Future<void> showFreePlanLimitSheet(
  BuildContext context, {
  required FreePlanLimit limit,
  int? actual,
}) {
  assert(
    (limit != FreePlanLimit.shapeDays && limit != FreePlanLimit.shapeWeeks) ||
        actual != null,
    'shapeDays/shapeWeeks describen una rutina concreta: sin `actual` el '
    'cuerpo no puede decir cuántos días tiene ni cuántos sobran, que es todo '
    'lo que los distingue de days/weeks.',
  );
  final palette = AppPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) => _FreePlanLimitBody(limit: limit, actual: actual),
  );
}

class _FreePlanLimitBody extends ConsumerWidget {
  const _FreePlanLimitBody({required this.limit, this.actual});

  final FreePlanLimit limit;
  final int? actual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La UNICA decision sobre si se puede comprar. No la toma el call site.
    final puedeComprar =
        ref.watch(athleteCheckoutProvider) is AthleteCheckoutOnStore;
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s18,
          AppSpacing.s12,
          AppSpacing.s18,
          AppSpacing.s18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                key: const Key('free_plan_limit_grabber'),
                width: 40,
                height: AppSpacing.hairline,
                decoration: BoxDecoration(
                  color: palette.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s18),
            Row(
              children: [
                Icon(TreinoIcon.lock, size: 18, color: palette.textMuted),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    l10n.paywallFreePlanLimitTitle,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              switch (limit) {
                FreePlanLimit.days =>
                  l10n.paywallFreePlanLimitDaysBody(kFreeMaxRoutineDays),
                FreePlanLimit.weeks => l10n.paywallFreePlanLimitWeeksBody,
                FreePlanLimit.premiumTemplate =>
                  l10n.paywallFreePlanLimitTemplateBody,
                FreePlanLimit.customizeTemplate =>
                  l10n.paywallFreePlanLimitCustomizeTemplateBody(
                    kFreeMaxRoutineDays,
                  ),
                FreePlanLimit.routineCount =>
                  l10n.paywallFreePlanLimitRoutineCountBody,
                FreePlanLimit.chartHistory =>
                  l10n.paywallFreePlanLimitChartHistoryBody,
                // El `?? 0` no se alcanza: el assert de
                // `showFreePlanLimitSheet` exige `actual` para estos dos. Está
                // para que la falta en release degrade a un cuerpo raro y no a
                // un crash sobre una pantalla que el alumno abrió para
                // entender por qué no puede guardar.
                FreePlanLimit.shapeDays =>
                  l10n.paywallFreePlanLimitShapeDaysBody(
                    actual ?? 0,
                    kFreeMaxRoutineDays,
                  ),
                FreePlanLimit.shapeWeeks =>
                  l10n.paywallFreePlanLimitShapeWeeksBody(
                    actual ?? 0,
                    kFreeMaxRoutineWeeks,
                  ),
              },
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.s18),
            if (puedeComprar) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('free_plan_limit_upgrade'),
                  onPressed: () => _abrirPaywall(context),
                  child: Text(l10n.paywallFreePlanLimitUpgrade),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('free_plan_limit_dismiss'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.paywallFreePlanLimitDismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Abre el paywall y, si el alumno compro, cierra tambien esta hoja.
  ///
  /// Se navega en vez de mostrar la compra adentro de la hoja porque la
  /// guideline 3.1.2 pide describir claramente que se lleva por ese precio, y
  /// eso no entra en un bottom sheet arriba del cuerpo del limite.
  Future<void> _abrirPaywall(BuildContext context) async {
    final compro = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AthletePaywallScreen(),
      ),
    );
    if (compro == true && context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
