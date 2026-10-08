import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../../workout/application/session_providers.dart';
import '../domain/athlete_entitlement.dart';
import 'treino_pro_showcase.dart';

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
/// **Lo que la hoja muestra lo decide ella, no el que la abre.**
///
/// Antes habia un parametro `onUpgrade` que cada call site tenia que pasar.
/// Se saco a proposito: son 8 call sites, y 8 lugares donde alguien podia
/// pasar una closure DISTINTA —una que abriera la web, por ejemplo—. Una sola
/// decision, en un solo lugar, es la version segura.
///
/// **No hay botón de pago.** La app no vende y tampoco puede decir dónde se
/// compra: bajo 3.1.3(f) eso ya es un llamado a comprar afuera (ver
/// `superficie_de_cobro_alumno_test.dart`). Lo que SÍ puede es contar qué
/// incluye el plan pago, y eso hace [TreinoProShowcase] debajo del tope: el
/// beneficio que responde a ESTE tope va primero y resaltado. Describe y nada
/// más — sin precio, sin CTA y sin anunciar el mail que el barrido le manda
/// después, que es justamente el canal que sí tiene permitido nombrar la
/// salida.
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
  // ── Se anota que este alumno chocó un tope ──
  //
  // Lo lee el barrido nocturno para mandarle un mail con la salida. La app no
  // puede decírsela: bajo 3.1.3(f) un cartel que diga dónde se paga YA es un
  // "call to action for purchase outside of the app", tappable o no.
  //
  // ⚠️ **LA HOJA NO CAMBIA NI UNA PALABRA POR ESTO**, y no es un detalle: lo
  // que Apple revisa es la interfaz. Una anotación invisible no es un llamado
  // a comprar; un «te mandamos un mail» impreso acá sí lo sería, porque
  // señalizaría el camino de compra desde adentro del binario.
  //
  // Va acá y no en el cuerpo de la hoja porque esta función corre UNA vez por
  // presentación, mientras que un `build` corre las que haga falta.
  //
  // Sin `await` a propósito: la hoja abre ya, no espera a una anotación.
  //
  // ⚠️ El `try` NO es redundante con el que tiene `registrarTopeTocado`
  // adentro, y lo encontró un test: ahí el catch cubre el fallo ASÍNCRONO de
  // Firestore, pero cualquier cosa que tire ANTES de entrar al método —o un
  // refactor futuro que le saque su propio catch— explota acá y se lleva
  // puesta la hoja. El usuario se quedaría sin el mensaje que le explica por
  // qué no puede hacer algo, por una anotación que no le importa.
  //
  // Dos redes, porque una sola falla en silencio y lo que se rompe es la
  // pantalla, no la anotación.
  try {
    final contenedor = ProviderScope.containerOf(context, listen: false);
    final uid = contenedor.read(currentUidProvider);
    if (uid != null) {
      unawaited(
        contenedor
            .read(userRepositoryProvider)
            .registrarTopeTocado(uid, limit.name)
            .catchError((_) {}),
      );
    }
  } catch (_) {
    // Ver arriba: la hoja abre igual.
  }

  final palette = AppPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    // Con la tarjeta de TREINO Pro la hoja ya no entra en los 9/16 de alto que
    // da el default. El cuerpo scrollea si igual no entra (teléfono chico,
    // texto agrandado), y `useSafeArea` la frena debajo de la barra de estado.
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: palette.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) => _FreePlanLimitBody(limit: limit, actual: actual),
  );
}

/// El beneficio de TREINO Pro que responde a cada tope.
///
/// `switch` exhaustivo a propósito: el día que se sume un `FreePlanLimit`
/// noveno, esto no compila hasta que alguien decida qué le responde la
/// tarjeta. Los dos `shape*` comparten beneficio con su eje: el alumno que
/// mira una rutina de 5 días fuera de tope quiere lo mismo que el que tocó el
/// "+" del cuarto.
TreinoProBenefit _beneficioDe(FreePlanLimit limit) => switch (limit) {
      FreePlanLimit.days || FreePlanLimit.shapeDays => TreinoProBenefit.days,
      FreePlanLimit.weeks || FreePlanLimit.shapeWeeks => TreinoProBenefit.weeks,
      FreePlanLimit.premiumTemplate => TreinoProBenefit.templates,
      FreePlanLimit.customizeTemplate => TreinoProBenefit.customize,
      FreePlanLimit.routineCount => TreinoProBenefit.routines,
      FreePlanLimit.chartHistory => TreinoProBenefit.charts,
    };

class _FreePlanLimitBody extends StatelessWidget {
  const _FreePlanLimitBody({required this.limit, this.actual});

  final FreePlanLimit limit;
  final int? actual;

  /// Lo que tarda la hoja en asomar antes de que arranque la coreografía de
  /// adentro: si arrancara junto con la subida, el primer tramo pasaría
  /// mientras la hoja todavía se mueve y nadie lo vería.
  static const Duration _asomo = AppMotion.fast;

  @override
  Widget build(BuildContext context) {
    // Ya no se decide nada sobre comprar: la app no vende, y tampoco puede
    // decir donde se compra. Ver el encabezado de la clase.
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Tres pisos: la manija y el botón quedan FIJOS, y sólo el medio scrollea.
    // Con la tarjeta la hoja mide unos 660 px, y en un teléfono chico —o con el
    // texto agrandado— un botón al final del scroll quedaría abajo del pliegue:
    // la única salida de un paywall, escondida. Fijo, se ve siempre.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.s12,
              bottom: AppSpacing.s18,
            ),
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
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s18),
              child: _contenido(palette, l10n),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s18,
              AppSpacing.s20,
              AppSpacing.s18,
              AppSpacing.s18,
            ),
            // Sin animación de entrada, a propósito: una salida que tarda en
            // aparecer es un patrón oscuro de paywall, por más que sean
            // milisegundos.
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('free_plan_limit_dismiss'),
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.textPrimary,
                  side: BorderSide(color: palette.borderStrong),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                ),
                child: Text(
                  l10n.paywallFreePlanLimitDismiss.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: AppFonts.barlowCondensed,
                    fontSize: AppTextSize.body,
                    fontWeight: AppFonts.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido(AppPalette palette, AppL10n l10n) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FreePlanLimitLockBadge(delay: _asomo),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: TreinoFadeSlideIn(
                  delay: _asomo + AppMotion.stagger(1),
                  distance: AppMotion.slideSm,
                  child: Text(
                    l10n.paywallFreePlanLimitTitle.toUpperCase(),
                    style: TextStyle(
                      fontFamily: AppFonts.barlowCondensed,
                      fontSize: AppTextSize.titleLarge,
                      fontWeight: AppFonts.w700,
                      letterSpacing: AppFonts.headingTracking,
                      height: 1.1,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          // Primero el tope y DESPUÉS el plan: quien lee esto quiso hacer
          // algo y no pudo. Arrancar por la oferta le pasaría por encima al
          // motivo por el que está mirando la hoja — mismo criterio que el
          // mail de `free-limit-reached`.
          TreinoFadeSlideIn(
            delay: _asomo + AppMotion.stagger(2),
            distance: AppMotion.slideSm,
            child: Text(
              _cuerpo(l10n),
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontSize: AppTextSize.body,
                height: 1.45,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          TreinoProShowcase(
            highlight: _beneficioDe(limit),
            delay: _asomo + AppMotion.stagger(3),
          ),
        ],
      );

  String _cuerpo(AppL10n l10n) => switch (limit) {
        FreePlanLimit.days =>
          l10n.paywallFreePlanLimitDaysBody(kFreeMaxRoutineDays),
        FreePlanLimit.weeks => l10n.paywallFreePlanLimitWeeksBody,
        FreePlanLimit.premiumTemplate => l10n.paywallFreePlanLimitTemplateBody,
        FreePlanLimit.customizeTemplate =>
          l10n.paywallFreePlanLimitCustomizeTemplateBody(
            kFreeMaxRoutineDays,
          ),
        FreePlanLimit.routineCount => l10n.paywallFreePlanLimitRoutineCountBody,
        FreePlanLimit.chartHistory => l10n.paywallFreePlanLimitChartHistoryBody,
        // El `?? 0` no se alcanza: el assert de
        // `showFreePlanLimitSheet` exige `actual` para estos dos. Está
        // para que la falta en release degrade a un cuerpo raro y no a
        // un crash sobre una pantalla que el alumno abrió para
        // entender por qué no puede guardar.
        FreePlanLimit.shapeDays => l10n.paywallFreePlanLimitShapeDaysBody(
            actual ?? 0,
            kFreeMaxRoutineDays,
          ),
        FreePlanLimit.shapeWeeks => l10n.paywallFreePlanLimitShapeWeeksBody(
            actual ?? 0,
            kFreeMaxRoutineWeeks,
          ),
      };
}
