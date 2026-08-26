import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../data/wear_workout_service.dart';
import '../../domain/watch_effort.dart';
import 'wear_fitted_text.dart';
import 'wear_round_scaffold.dart';
import 'wear_widgets.dart';

/// La pantalla de un ejercicio POR TIEMPO mientras corre.
///
/// ## Por qué es una pantalla y no una fila más
///
/// Un ejercicio por tiempo no se "marca": se AGUANTA. Durante esos segundos el
/// atleta no tiene nada que tocar, y lo único que necesita ver —de reojo, con
/// la muñeca en una plancha o un hollow— es cuánto falta. Meter eso en la lista
/// de series lo dejaría chiquito y compitiendo con círculos que en ese momento
/// no sirven para nada.
///
/// ## Lo que NO vive acá
///
/// La cuenta regresiva no la lleva esta pantalla: llega ya resuelta desde el
/// deadline persistido en el nativo. Por eso sobrevive a que se apague la
/// pantalla y a que se destruya la Activity, y por eso el aviso al vencer
/// —la vibración— funciona aunque esto no se esté dibujando. Acá sólo se
/// pinta lo que el temporizador dice.
class WearExerciseTimerScreen extends StatelessWidget {
  const WearExerciseTimerScreen({
    super.key,
    required this.exerciseName,
    required this.timer,
    required this.effort,
    required this.onOcultar,
    required this.onCancelar,
    this.puedeCancelar = true,
  });

  final String exerciseName;
  final WearExerciseTimer timer;
  final WatchEffortDisplay effort;

  /// Esconde la pantalla sin tocar el temporizador, que sigue corriendo.
  final VoidCallback onOcultar;

  /// Abandona el ejercicio por tiempo SIN marcar la serie.
  ///
  /// Distinto de ocultar, y hace falta: si el atleta no aguanta la plancha, no
  /// tiene por qué esperar a que el reloj llegue a cero para poder salir.
  final VoidCallback onCancelar;

  /// Si esta cuenta es de este reloj.
  ///
  /// Cuando la arrancó el TELÉFONO, acá no se cancela: este reloj la está
  /// espejando, y el botón borraría el espejo mientras el dueño sigue contando
  /// y termina marcando la serie igual. Es la misma decisión que toma la fila
  /// del teléfono cuando la cuenta corre en el reloj — el dueño de la serie es
  /// el lado que la arrancó, y es el único que la maneja.
  ///
  /// «Ocultar» sí queda: esconder el espejo no le hace nada a la cuenta.
  final bool puedeCancelar;

  /// Diámetro del anillo, en dp.
  ///
  /// ## De dónde sale el número
  ///
  /// De una resta, no de un gusto. En el SM-L500 el viewport son 206,1 dp y la
  /// pantalla gasta, de arriba a abajo: 34,3 de margen superior (el 16,64 % que
  /// pide Horologist para una lista que arranca con texto), 14,3 de nombre, 8,
  /// el anillo, 8, 16 de la fila de esfuerzo, 8, y 48 de botones —el mínimo
  /// táctil de Wear OS, que no se toca—. Todo lo que no es el anillo suma 136,6.
  ///
  /// Con el anillo en 84 esa cuenta da 220,6 contra un viewport de 206,1: los
  /// botones no entran ni con la etiqueta clavada en un renglón. Medido sobre el
  /// código anterior era todavía peor —la fila terminaba en `y=267`— porque la
  /// etiqueta además envolvía; ese pedazo lo arregla el `maxLines: 1` de
  /// [WearButton]. Se llegaba con la corona, pero de entrada se veía media
  /// píldora cortada contra el borde.
  ///
  /// En 60 entra: el widget test a 206 dp mide la fila de botones en
  /// `y=147,5 → 195,5`, con 10,6 dp de sobra para el bisel físico — que es lo
  /// que un screenshot por adb NO muestra y la muñeca sí.
  ///
  /// ## Por qué el anillo y no otra cosa
  ///
  /// Porque es lo único con holgura. El margen superior es la constante de
  /// Horologist y bajarlo devuelve el nombre cortado arriba; los separadores ya
  /// están en 8, el mínimo de la escala; y 48 dp de botón es el piso táctil.
  ///
  /// ## Lo que este número NO puede arreglar
  ///
  /// Que la píldora entre ENTERA en el círculo. Con dos botones a lo ancho, las
  /// esquinas inferiores externas caen fuera de la circunferencia a cualquier
  /// altura que deje lugar para el anillo — es geometría, no ajuste. Lo que sí
  /// se garantiza, y lo que el test clava, es que las ETIQUETAS queden dentro:
  /// el corte pasa por el borde de la píldora y no por la mitad de una palabra.
  static const double _anilloLado = 60;

  /// Trazo del anillo, en dp.
  ///
  /// 4 y no 5, y no es un achique proporcional: sobre 60 dp un trazo de 4 pesa
  /// 6,7 % del diámetro, un poco MÁS que el 6,0 % que pesaban 5 sobre 84. El
  /// arco no se afina a la vista al achicarse el anillo, que era el riesgo.
  ///
  /// Y deja 52 dp de diámetro interno, contra los 46,3 que mide `00:24` en
  /// Barlow Condensed 700 a 22 — el tiempo entra con aire a cada lado.
  static const double _anilloTrazo = 4;

  /// Fracción ya transcurrida, de 0 a 1.
  double get _progreso {
    if (timer.totalMs <= 0) return 0;
    final hecho = (timer.totalMs - timer.remainingMs) / timer.totalMs;
    return hecho.clamp(0.0, 1.0);
  }

  /// `MM:SS`, igual que el temporizador del teléfono.
  ///
  /// Mismo formato en los dos aparatos a propósito: el atleta mira uno y otro
  /// durante la misma serie, y dos formatos distintos para el mismo número
  /// obligan a traducir mentalmente.
  ///
  /// Se redondea hacia ARRIBA: mostrar 0 durante el último segundo haría
  /// pensar que terminó cuando todavía falta.
  String get _tiempo {
    final total = (timer.remainingMs / 1000).ceil().clamp(0, 359999);
    final min = total ~/ 60;
    final seg = total % 60;
    return '${min.toString().padLeft(2, '0')}:${seg.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final termino = timer.finished;

    // `list` y no `centered`: el andamio centrado NO scrollea, así que cuando
    // el contenido no entra lo RECORTA — se vio en la muñeca con el título
    // cortado arriba y «Cancelar» pegado al borde de abajo. Con la lista, si no
    // entra se scrollea con la corona, que además ya está enganchada acá.
    //
    // El andamio también aporta el `Scaffold` —o sea el `Material`— y el inset
    // circular: sin él Flutter dibuja los textos con el subrayado amarillo de
    // "falta Material".
    // `list` y no `centered`, y hubo que ir y volver para entenderlo.
    //
    // `centered` NO scrollea: cuando el contenido no entra lo recorta, y en un
    // reloj con BISEL FÍSICO —como el SM-L500— el aro se come todavía más
    // borde. Resultado medido en la muñeca: el nombre cortado arriba y
    // «Cancelar» directamente inalcanzable.
    //
    // El intento anterior con lista había salido peor porque el `ListView`
    // impone ancho COMPLETO en el eje cruzado: el `SizedBox` del anillo se
    // ignoraba y el indicador salía ELÍPTICO. Eso lo resuelve el `Center`
    // explícito de abajo, que es lo que permite volver acá y tener scroll sin
    // deformar nada.
    //
    // Orden por prioridad de lectura: el tiempo y el nombre primero, después el
    // esfuerzo, y los botones al final — son lo único que puede quedar fuera de
    // vista, porque para eso está la corona.
    return WearRoundScaffold.list(
      // `text` porque el primer ítem ES texto: el 16,64 % que pide Horologist
      // para ese caso. Se probó bajarlo para ganar alto y volvió el nombre
      // cortado arriba contra el bisel — el aire de arriba no es desperdicio,
      // es la curva. El alto se recuperó del anillo, ver `_anilloLado`.
      firstItem: WearItemType.text,
      // `multiButton` deja abajo lugar para los DOS: ocultar y cancelar.
      lastItem: WearItemType.multiButton,
      children: [
        WearFittedText(
          exerciseName,
          maxLines: 1,
          maxSize: 13,
          minSize: 10,
          widthFactor: 0.85,
          styleFor: (size) => GoogleFonts.barlowCondensed(
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        // El `Center` NO es decorativo: sin él, cualquier padre que imponga
        // ancho completo vuelve a deformar el anillo.
        Center(
          child: SizedBox(
            width: _anilloLado,
            height: _anilloLado,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: _progreso,
                    strokeWidth: _anilloTrazo,
                    // Track visible: sobre el fondo negro del reloj, un track
                    // oscuro no se distingue y el anillo parece descentrado.
                    backgroundColor: palette.border,
                    // VERDE, igual que el temporizador del teléfono cuando
                    // corre. Es el color de "esto está en marcha" en toda la app.
                    valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                  ),
                ),
                // Acotado al DIÁMETRO INTERNO y con `scaleDown`. El `Stack`
                // clipea por defecto, así que un tiempo más ancho que el anillo
                // no se ve mal: directamente se corta. Sin el tope pasaba con la
                // letra agrandada del sistema, que en Wear OS llega a 1,24×.
                SizedBox(
                  width: _anilloLado - _anilloTrazo * 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _tiempo,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: termino ? palette.accent : palette.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // `FittedBox`: la fila con las dos métricas se pasaba por décimas de
        // píxel en la pantalla más angosta. Encogerla es preferible a que
        // Flutter la recorte.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: WearEffortRow(effort: effort, mostrarSinDatos: true),
        ),
        const SizedBox(height: 8),
        // No hay botón de «marcar»: al vencer, la serie se marca SOLA y esta
        // pantalla se va. Pedirle al atleta que confirme algo que el reloj ya
        // sabe es trabajo de más justo cuando está sin aire.
        //
        // Los dos van en UNA FILA y no apilados. Apilados sumaban ~30 dp de
        // alto y empujaban «Cancelar» fuera del viewport: como el `ListView` no
        // construye lo que no se ve, el botón directamente no existía y no
        // había forma de llegar a él ni girando la corona. Medido con un widget
        // test a 206 dp, que es como se encontró.
        //
        // Que la fila ENTRE en la primera vista no lo decide este `Row`: lo
        // decide lo que hay arriba. Ver `_anilloLado` para la resta completa, y
        // `wear_exercise_timer_screen_test.dart` para los dos tests que la
        // clavan — uno contra el rectángulo del viewport y otro contra el
        // círculo de la pantalla, que es el que caza el corte de «Cancela».
        Row(
          children: [
            Expanded(
              child: WearButton(
                // Ocultar NO cancela: el temporizador sigue corriendo y vibra
                // al vencer igual. Es para mirar las series sin perder la
                // cuenta.
                label: 'Ocultar',
                onTap: onOcultar,
                tint: palette.textMuted,
              ),
            ),
            if (puedeCancelar) ...[
              const SizedBox(width: 8),
              Expanded(
                child: WearButton(
                  label: 'Cancelar',
                  onTap: onCancelar,
                  tint: palette.danger,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
