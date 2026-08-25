/// Entorno fijado del gate de regresión visual del Coach Hub (#761).
///
/// ## Por qué existe este archivo y no un `if` suelto en cada test
///
/// Lo que hunde a la mayoría de los gates de goldens en Flutter no es el
/// harness: es que **CI corre en ubuntu y los devs en macOS**. Distinta
/// rasterización de fuentes, distinto antialiasing, distinto hinting. El
/// síntoma es siempre el mismo — *"falla en CI, pasa local"* — y el desenlace
/// también: a la tercera vez alguien desactiva el job.
///
/// La respuesta acá es no pretender que los píxeles sean portables. **El gate
/// corre en un solo entorno**, declarado en [gateSkipReason]: Linux, `TZ=UTC`,
/// y la versión de Flutter que pinea `.github/workflows/ci.yml`. En cualquier
/// otro lado se **saltea con motivo**, nunca falla — un dev en su Mac corre
/// `flutter test` y no ve un rojo que no puede arreglar.
///
/// Regenerar goldens sigue el mismo principio: se regeneran **en el runner**,
/// no en tu máquina. Ver `docs/visual-gate.md`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/app_clock.dart';

import 'gate_fonts.dart';

/// Interruptor del gate. Lo prende el job *Visual Gate (Coach Hub)*; sin él la
/// suite se saltea, así `flutter test` a secas nunca la corre.
///
/// Es una variable de entorno y no un `--dart-define` a propósito: el
/// `--dart-define` invalida el kernel cache y obliga a recompilar toda la
/// suite. Con la variable, regenerar es una línea y no un rebuild.
const String kGateEnvVar = 'TREINO_VISUAL_GATE';

/// Instante congelado de TODOS los goldens del gate.
///
/// Martes 17/03/2026, 10:30. Elegido, no sorteado:
///
/// - **Martes**, día hábil del medio: la agenda tiene turnos pasados y futuros
///   en el mismo día, que es donde vive el filtro `startsAt.isAfter(now)`.
/// - **17**, lejos de los dos bordes del mes: los buckets de vencimiento y los
///   cortes de mes no quedan pegados a un límite donde un off-by-one pasa
///   desapercibido.
/// - **10:30**, en horario de trabajo: el Coach Hub es una superficie de
///   escritorio y así se ve cuando se usa.
/// - **2026**, sin DST: Argentina no observa horario de verano desde 2009, así
///   que el offset es constante y no hay una fecha del año que rinda distinto.
///
/// Es local-flagged (no UTC) porque reemplaza a `DateTime.now()`. Con `TZ=UTC`
/// —que [gateSkipReason] exige— local y UTC coinciden, así que el instante es
/// el mismo en todas las corridas del gate.
DateTime get kGateNow => DateTime(2026, 3, 17, 10, 30);

/// Motivo por el que este entorno NO puede correr el gate, o `null` si puede.
///
/// El texto va derecho al `skip:` del `group`, así que se lee en el output de
/// `flutter test` sin abrir este archivo.
String? gateSkipReason() {
  if (Platform.environment[kGateEnvVar] != '1') {
    return 'gate apagado: se prende con $kGateEnvVar=1 (lo hace el job '
        '"Visual Gate (Coach Hub)" de CI). Ver docs/visual-gate.md.';
  }

  if (!Platform.isLinux) {
    return 'el gate sólo corre en Linux (${Platform.operatingSystem} detectado). '
        'Los goldens están rasterizados por el runner de CI: fuera de ahí el '
        'antialiasing difiere y el resultado no significa nada. Para regenerar, '
        'ver docs/visual-gate.md.';
  }

  return null;
}

/// Todo lo que hace determinística a la suite: tipografías registradas, reloj
/// congelado, y el test con nombre que prueba que las dos cosas pasaron.
///
/// Llamalo una vez, dentro del `group` del gate y antes de los `testWidgets`.
void useGateEnvironment() {
  setUpAll(loadGateFonts);
  setUp(() => AppClock.freeze(kGateNow));
  tearDown(AppClock.unfreeze);
  testGateFontsAreRegistered();
}

/// Aserciones sobre el entorno mismo, para correr como un test más.
///
/// Van como test y no como `assert` escondido por una razón: si el runner
/// cambia de zona horaria o alguien mueve el pin de Flutter, quiero un test
/// rojo **con nombre** en el output de CI, no catorce diffs de píxeles que no
/// explican nada.
void testGateEnvironmentIsPinned() {
  test('el entorno del gate está pinneado (Linux + TZ=UTC + reloj congelado)',
      () {
    expect(
      Platform.isLinux,
      isTrue,
      reason: 'los goldens fueron rasterizados en el runner ubuntu de CI',
    );

    expect(
      DateTime(2026, 3, 17).timeZoneOffset,
      Duration.zero,
      reason:
          'el job declara TZ=UTC. Sin eso, argentinaNow() —que hace .toUtc() '
          'sobre el instante congelado— rinde una hora distinta según el '
          'huso del runner, y las pantallas que muestran horas cambian de '
          'píxeles sin que nadie haya tocado la UI.',
    );

    AppClock.freeze(kGateNow);
    addTearDown(AppClock.unfreeze);
    expect(
      AppClock.isFrozen,
      isTrue,
      reason: 'sin el seam congelado los goldens dependen de la hora de CI',
    );
    expect(AppClock.now(), kGateNow);
  });
}
