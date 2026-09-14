import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — ratchet de deriva de reloj en el módulo Coach.
///
/// Tercera contraparte de `no_hex_scan_test.dart` y `no_raw_radius_scan_test.dart`,
/// esta vez para la convención de tiempo. Sale de #671, que encontró **23
/// call-sites** en `coach_hub/` que reimplementaban desde cero el bug de
/// timezone que #403 ya había arreglado. No fue una reversión: la regla vivía
/// únicamente en comentarios, y no había un solo test que la sostuviera.
///
/// ## Las dos convenciones, y cuándo va cada una
///
/// | Clase | Campos | "Ahora" correcto | Cómo mostrar |
/// |---|---|---|---|
/// | **Wall-clock ADR-7** | `Appointment.startsAt`, `AvailabilityOverride.date` | `nowWall()` | leer los campos **crudos** |
/// | **Instante real** | `createdAt`, `paidAt`, `updatedAt`, `finishedAt` | `AppClock.now()` | `.toLocal()` está bien |
/// | **Bucket de calendario** | "hoy", bordes de mes/semana, vencimientos | `argentinaNow()` | derivar en ART |
///
/// `lib/core/utils/argentina_time.dart` lo dice textual: *"CALENDAR concepts —
/// payment period keys, day buckets, month/week boundaries — MUST be derived in
/// ART, not UTC"*. Y `lib/features/coach/domain/wall_clock.dart` documenta por
/// qué `nowWall()` es distinto de `argentinaNow()` y no intercambiable.
///
/// ## Trampa: `difference` NO es una de estas clases
///
/// `DateTime.difference` compara instantes reales por `microsecondsSinceEpoch`,
/// **sin importar el flag UTC**. Mezclar un local y un UTC ahí NO es un bug —
/// `DateTime.now().difference(createdAt)` es correcto. En #671 dos call-sites
/// parecían defectuosos por eso y no lo eran; lo que fallaba era el `dd/mm` de
/// al lado, que leía los campos crudos de un instante. Mirá qué se hace con el
/// resultado antes de "arreglar" un `difference`.
///
/// ## Ambigüedad conocida, deliberadamente NO tocada acá
///
/// `trainer_dashboard_tab.dart:1090` y `:1310` comparan contra `startsAt`
/// usando `argentinaNow()`, cuando por la tabla de arriba correspondería
/// `nowWall()`. En Argentina los dos coinciden —`argentinaUtcOffset` es
/// constante y `resolveLocale` fija es-AR— así que hoy **no es un bug**. Se
/// deja anotado para que el próximo no tenga que redescubrirlo: cambiarlo es
/// modificar comportamiento de mobile sin beneficio visible, y no entra en un
/// PR de tooling.
///
/// ## CUATRO REGLAS
///
///   1. Ningún archivo FUERA de la allowlist puede usar `DateTime.now()` ni
///      `.toLocal()` dentro de `coach/` o `coach_hub/`.
///   2. La allowlist NUNCA crece — ratchet de archivos.
///   3. La deuda total NUNCA crece — ratchet de ocurrencias.
///   4. Un archivo que ya no los usa DEBE salir de la allowlist.
///
/// Igual que con los radios (#665), acá NO se puede exigir cero: hay usos
/// legítimos —escribir `createdAt`, medir un `difference` real— y por eso la
/// allowlist arranca grande. Estar en la lista significa **"revisado o
/// pendiente de revisar"**, no "exento". Lo que el ratchet impide es que la
/// próxima pantalla nazca con el mismo defecto sin que nadie lo vea.
///
/// ## DOS REGÍMENES, porque son dos realidades
///
/// Las cuatro reglas de arriba son el **ratchet** de Coach: deuda alta (80
/// ocurrencias), allowlist grande, y el único contrato posible es "no crece".
///
/// `core/` es al revés y por eso tiene su propio grupo, con **regla cero**:
///
/// | | Coach | `core/` |
/// |---|---|---|
/// | deuda al escribir esto | 80 ocurrencias, 37 archivos | **0 líneas de código** |
/// | contrato | ratchet (sólo baja) | **cero, sin allowlist** |
/// | qué se cuenta | texto crudo (prosa incluida) | **sólo código** (los `//` se saltean) |
/// | excepción | 37 archivos | **una**: `app_clock.dart`, el seam |
///
/// Que el segundo grupo cuente sólo código no es un detalle: en `core/` viven
/// los dartdocs que EXPLICAN por qué no usar el reloj crudo —`argentina_time`,
/// `appointment_window`, el propio `app_clock`— y son 12 de las 14 menciones.
/// Un scanner textual ahí castigaría justo a la documentación que enseña la
/// regla, y la salida sería borrarla. Con el strip de comentarios se puede
/// exigir CERO en código sin pagar ese precio.
///
/// ## Por qué `core/` y no todo `lib/` (medido, no estimado)
///
/// ```bash
/// rg -c 'DateTime\.now\(\)|\.toLocal\(\)' -g '*.dart' lib \
///   | awk -F: '{split($1,p,"/"); k=p[2]"/"p[3]; s[k]+=$2} \
///              END {for (i in s) printf "%6d  %s\n", s[i], i}' | sort -rn
/// ```
///
/// `features/coach` 46 · `features/coach_hub` 34 · `features/workout` 27 ·
/// **`core/utils` 14** · `features/profile` 8 · el resto, cola larga. Total
/// `lib/`: 178 en 91 archivos.
///
/// `core/` no entra por ser chico: entra porque es donde viven los seams
/// (`app_clock`, `argentina_time`, `wall_clock`) y una fuga ahí **se propaga a
/// toda la app**. Es exactamente lo que pasó: el default de
/// `computeWeeklyStreak` leía `DateTime.now()` crudo, ningún caller de
/// producción pasaba `now:`, y eso volvió indeterminista el camino de render
/// de Insights y de Perfil enteros. `main` quedó en rojo el 08/09/2026 con un
/// test que pasaba seis días de siete. Este guard escaneaba `coach/` y
/// `coach_hub/`; la fuga vivía en `core/utils/` y por eso nadie la vio.
///
/// `features/workout` y los demás quedan afuera **a propósito**: 27+ de deuda
/// real necesitarían allowlist y ratchet, que es otro PR y otra discusión. Lo
/// que no se puede es dejar `core/` sin cubrir por analogía con ellos.
///
/// ## El seam: `AppClock.now()` (#761)
///
/// `lib/core/utils/app_clock.dart` es el único lugar del repo que llama a
/// `DateTime.now()` de verdad. En producción es un passthrough — mismo valor,
/// misma zona horaria, mismo costo. Congelado por un test, devuelve siempre
/// el mismo instante.
///
/// Lo trajo el gate de regresión visual del Coach Hub: sin él, el filtro de
/// "próximas sesiones" del dashboard (`startsAt.isAfter(now)`) descarta turnos
/// según la hora a la que corra CI, y el golden pasa o falla según el reloj
/// del runner. Un golden que cambia porque cambió la fecha no es un gate, es
/// ruido.
///
/// `argentinaNow()` y `nowWall()` ya leen de ahí, así que **la mayoría del
/// código no cambia**: seguí usando el helper que corresponda por la tabla de
/// arriba. `AppClock.now()` directo es sólo para el tercer caso —instante
/// real— donde antes ibas a escribir `DateTime.now()`.
///
/// ALCANCE DEL SCANNER (deliberado):
///   ✓ DateTime.now()      — el reloj crudo
///   ✓ .toLocal()          — la conversión que corre un wall-clock
///   ✗ argentinaNow()      — el helper correcto para buckets
///   ✗ nowWall()           — el helper correcto para startsAt
///   ✗ AppClock.now()      — el seam congelable (core/utils/app_clock.dart)
void main() {
  group('no_raw_clock_scan — ratchet de deriva de reloj en Coach', () {
    /// `DateTime.now()` crudo y `.toLocal()`. Los helpers correctos
    /// (`argentinaNow`, `nowWall`) NO matchean: ese es el objetivo.
    final rawClockPattern = RegExp(r'DateTime\.now\(\)|\.toLocal\(\)');

    /// Sólo el módulo Coach: es el que tiene la deuda alta y el que necesita
    /// un ratchet. `core/` NO va acá — tiene deuda cero y lo cubre el grupo de
    /// abajo, con regla cero y contando sólo código. Ver los DOS REGÍMENES en
    /// el dartdoc de la librería.
    const scannedRoots = ['features/coach/', 'features/coach_hub/'];

    /// Techo de archivos permitidos, congelado al mergear este guard. NUNCA
    /// subirlo: cada migración lo baja.
    const allowlistCeiling = 37;

    /// Techo de ocurrencias totales. Mismo contrato: sólo baja.
    ///
    /// 86 → 80 con #761. Cinco son call-sites de código que quedaban en el
    /// camino de RENDER de las pantallas del gate visual y pasaron a
    /// `AppClock.now()`: dashboard right column, chat list pane, dos en la
    /// ficha de alumno, y el default de `nowWall()`. La sexta es prosa — el
    /// dartdoc de `wall_clock.dart` decía *"defaults to `DateTime.now()`"*,
    /// que este cambio vuelve falso. El scanner es textual y no distingue
    /// código de comentario, así que las cuenta igual.
    ///
    /// Bajar el techo es obligatorio al migrar: dejarlo arriba de la medición
    /// real regala cupo para regresiones nuevas, que es justo lo que el
    /// ratchet existe para impedir.
    const rawClockDebtCeiling = 80;

    /// Registro de deuda, rutas relativas a `lib/`.
    const allowlist = {
      'features/coach/application/dashboard_day_counts.dart',
      'features/coach/application/profile_share_providers.dart',
      'features/coach/athlete_coach_view.dart',
      'features/coach/data/appointment_repository.dart',
      'features/coach/data/athlete_file_repository.dart',
      'features/coach/data/follow_up_entry_repository.dart',
      'features/coach/data/nutrition_plan_repository.dart',
      'features/coach/data/trainer_link_repository.dart',
      'features/coach/domain/wall_clock.dart',
      'features/coach/presentation/agenda_formatters.dart',
      'features/coach/presentation/athlete_agenda_screen.dart',
      'features/coach/presentation/athlete_detail_screen.dart',
      'features/coach/presentation/availability_editor_screen.dart',
      'features/coach/presentation/trainer_agenda_tab.dart',
      'features/coach/presentation/trainer_dashboard_tab.dart',
      'features/coach/presentation/widgets/appointment_detail_sheet.dart',
      'features/coach/presentation/widgets/day_timeline.dart',
      'features/coach/presentation/widgets/new_session_sheet.dart',
      'features/coach/trainer_coach_view.dart',
      'features/coach_hub/application/aggregate_adherence_provider.dart',
      'features/coach_hub/presentation/sections/agenda/agenda_web_helpers.dart',
      'features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart',
      'features/coach_hub/presentation/sections/agenda/appointment_detail_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/batch_cobrar_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/new_session_dialog.dart',
      'features/coach_hub/presentation/sections/agenda/override_form_dialog.dart',
      'features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_list_pane.dart',
      'features/coach_hub/presentation/sections/chat/widgets/chat_message_bubble.dart',
      'features/coach_hub/presentation/sections/dashboard/widgets/dashboard_hero.dart',
      'features/coach_hub/presentation/sections/dashboard/widgets/dashboard_right_column.dart',
      'features/coach_hub/presentation/sections/invitaciones/widgets/solicitud_card.dart',
      'features/coach_hub/presentation/sections/nutricion/widgets/nutricion_plan_row.dart',
      'features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart',
      'features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart',
      'features/coach_hub/presentation/widgets/custom_exercise_video_web_uploader.dart',
    };

    late List<String> offenders;
    late List<String> staleEntries;
    var totalDebt = 0;

    setUpAll(() {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) {
        offenders = const [];
        staleEntries = allowlist.toList()..sort();
        return;
      }

      final found = <String>[];
      final seen = <String>{};

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final normalized = entity.path.replaceAll(r'\', '/');
        final libIndex = normalized.indexOf('lib/');
        if (libIndex == -1) continue;
        final relativePath = normalized.substring(libIndex + 4);

        if (!scannedRoots.any(relativePath.startsWith)) continue;

        final matches =
            rawClockPattern.allMatches(entity.readAsStringSync()).length;
        totalDebt += matches;

        if (matches == 0) continue;
        seen.add(relativePath);
        if (!allowlist.contains(relativePath)) found.add(relativePath);
      }

      found.sort();
      offenders = found;
      staleEntries = allowlist.where((p) => !seen.contains(p)).toList()..sort();
    });

    test('ningún archivo nuevo de Coach usa DateTime.now() ni .toLocal()', () {
      expect(
        offenders,
        isEmpty,
        reason: 'Reloj crudo fuera de la allowlist:\n'
            '${offenders.join('\n')}\n\n'
            'Elegí según QUÉ estás comparando:\n'
            '  • contra Appointment.startsAt  →  nowWall()  '
            '(coach/domain/wall_clock.dart)\n'
            '  • bucket de día/mes/semana     →  argentinaNow()  '
            '(core/utils/argentina_time.dart)\n'
            '  • instante real (createdAt…)   →  AppClock.now()  '
            '(core/utils/app_clock.dart) — es passthrough en prod y un test '
            'lo puede congelar\n\n'
            'Ojo: un `difference` entre instantes NO necesita arreglo — ver el '
            'dartdoc de este test.',
      );
    });

    test(
      'la allowlist no creció vs el estado congelado (ratchet de archivos)',
      () {
        expect(
          allowlist.length,
          lessThanOrEqualTo(allowlistCeiling),
          reason:
              'La allowlist tiene ${allowlist.length} entradas y el techo es '
              '$allowlistCeiling. SÓLO PUEDE ACHICARSE. Si migraste archivos, '
              'bajá también allowlistCeiling a ${allowlist.length}.',
        );
      },
    );

    test('la deuda total no creció (ratchet de ocurrencias)', () {
      expect(
        totalDebt,
        lessThanOrEqualTo(rawClockDebtCeiling),
        reason:
            'Hay $totalDebt usos de reloj crudo en coach/ + coach_hub/ y el '
            'techo es $rawClockDebtCeiling. Agregar uno a un archivo YA listado '
            'también rompe el ratchet: así se acumularon los 23 de #671 sin que '
            'nadie los viera.',
      );
    });

    test('la allowlist no tiene entradas muertas', () {
      expect(
        staleEntries,
        isEmpty,
        reason: 'Estos archivos ya no usan reloj crudo (o no existen) pero '
            'siguen en la allowlist:\n${staleEntries.join('\n')}\n\n'
            'Sacalos y bajá allowlistCeiling.',
      );
    });
  });

  group('no_raw_clock_scan — CERO reloj crudo en core/', () {
    /// Mismo patrón que el ratchet de Coach.
    final rawClockPattern = RegExp(r'DateTime\.now\(\)|\.toLocal\(\)');

    /// `core/` entero: ahí viven los seams, y una fuga ahí se propaga a toda
    /// la app. Ver "Por qué `core/` y no todo `lib/`" en el dartdoc.
    const scannedRoot = 'core/';

    /// LA ÚNICA excepción, y es estructural: `AppClock` ES el seam. Alguien
    /// tiene que llamar a `DateTime.now()` de verdad, y el diseño de #761 es
    /// que sea exactamente un lugar. Esto NO es una allowlist que pueda
    /// crecer: si aparece un segundo archivo acá, el diseño se rompió.
    ///
    /// Que el seam SIGA leyendo la hora real no se prueba acá y no se puede
    /// probar con un scanner: `app_clock.dart` menciona `DateTime.now()` tres
    /// veces —la llamada, el mensaje de un assert y el dartdoc— y ningún
    /// grep sabe cuál es cuál. Un test textual que lo intentara diría "el
    /// seam está sano" con el seam roto, que es la advertencia falsa de
    /// AGENTS.md §11.1. Lo prueba por COMPORTAMIENTO
    /// `test/core/utils/app_clock_test.dart` — *"sin congelar es un
    /// passthrough de `DateTime.now()`"*, con un sándwich temporal. Medido:
    /// cambiándole el cuerpo a `AppClock.now()`, ese test se pone rojo con un
    /// delta de 233.940 horas.
    ///
    /// PERO EL ARCHIVO NO VA EXENTO ENTERO, y ésta es la parte que importa.
    /// Saltearlo completo dejaba un agujero real: un método NUEVO acá que
    /// llamara al reloj sin pasar por `_frozen` —`static DateTime nowUtc() =>
    /// DateTime.now().toUtc()`, digamos— sería infreezable, y no lo cazaba
    /// nadie. Este guard no, porque el archivo estaba exento; y
    /// `app_clock_test.dart` tampoco, porque prueba `now()` y los helpers de
    /// hoy, no un método que todavía no existe. El seam se escanea como
    /// cualquier otro archivo y se permite **exactamente una** lectura: el
    /// passthrough. Lo levantó Codex en la review del PR de este guard.
    const seam = 'core/utils/app_clock.dart';

    /// Marca del passthrough legítimo dentro del seam: `_frozen ?? …`. Es lo
    /// que distingue "leer el reloj respetando el congelamiento" de "leer el
    /// reloj a secas", que es justo lo que este guard existe para impedir.
    const marcaDelPassthrough = '_frozen ??';

    /// Líneas de CÓDIGO con reloj crudo, por archivo.
    ///
    /// Se saltean las líneas que ARRANCAN con `//` o `///` y los bloques
    /// `/* … */`. En `core/` la prosa que explica por qué no usar el reloj
    /// crudo es 12 de las 14 menciones: contarla obligaría a borrarla para
    /// que el guard pase, que es el peor final posible para un guard.
    ///
    /// LIMITACIÓN, a propósito: un comentario al FINAL de una línea de código
    /// (`foo(); // ojo con DateTime.now()`) sí cuenta. Cortar desde `//` haría
    /// perder un hit real en cualquier línea que además tenga una URL
    /// (`'https://…'`), y este guard prefiere gritar de más a callarse de
    /// menos. Si te toca, movelo a su propia línea.
    /// Una línea que ARRANCA con comilla es la continuación de un string
    /// multilínea, no una lectura de reloj. Es el caso de `app_clock.dart:74`,
    /// que cita `DateTime.now()` dentro del mensaje de un assert.
    ///
    /// Se mira el arranque y no "¿el hit está dentro de comillas?" a propósito:
    /// lo segundo pide un parser, y equivocarlo silenciaría hits reales. Así,
    /// un `foo('… DateTime.now() …')` en UNA sola línea se cuenta igual —
    /// ruidoso, pero del lado seguro. Si te toca, partí el string.
    bool esContinuacionDeString(String linea) {
      final s = linea.trimLeft();
      return s.startsWith("'") || s.startsWith('"');
    }

    List<String> hitsDeCodigo(String contenido) {
      final hits = <String>[];
      var enBloque = false;
      var nro = 0;
      for (final linea in const LineSplitter().convert(contenido)) {
        nro++;
        final s = linea.trimLeft();
        if (enBloque) {
          if (s.contains('*/')) enBloque = false;
          continue;
        }
        if (s.startsWith('/*')) {
          if (!s.contains('*/')) enBloque = true;
          continue;
        }
        if (s.startsWith('//')) continue;
        if (esContinuacionDeString(linea)) continue;
        if (rawClockPattern.hasMatch(linea)) hits.add('$nro: ${linea.trim()}');
      }
      return hits;
    }

    late Map<String, List<String>> offenders;

    /// Líneas del seam que leen el reloj de verdad (ni comentario ni string).
    late List<String> lecturasDelSeam;

    setUpAll(() {
      final libDir = Directory('lib');
      offenders = {};
      lecturasDelSeam = const [];
      if (!libDir.existsSync()) return;

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final normalized = entity.path.replaceAll(r'\', '/');
        final libIndex = normalized.indexOf('lib/');
        if (libIndex == -1) continue;
        final relativePath = normalized.substring(libIndex + 4);

        if (!relativePath.startsWith(scannedRoot)) continue;

        final hits = hitsDeCodigo(entity.readAsStringSync());

        if (relativePath == seam) {
          // El seam NO va exento entero: se le permite exactamente el
          // passthrough, y cualquier otra lectura cae en `offenders`.
          lecturasDelSeam = hits;
          final ilegitimas =
              hits.where((h) => !h.contains(marcaDelPassthrough)).toList();
          if (ilegitimas.isNotEmpty) offenders[relativePath] = ilegitimas;
          continue;
        }

        if (hits.isNotEmpty) offenders[relativePath] = hits;
      }
    });

    test('ningún archivo de core/ usa DateTime.now() ni .toLocal()', () {
      expect(
        offenders,
        isEmpty,
        reason: 'Reloj crudo en core/ — acá NO hay allowlist, el contrato es '
            'CERO:\n'
            '${offenders.entries.map((e) => '  ${e.key}\n'
                '${e.value.map((h) => '      $h').join('\n')}').join('\n')}\n\n'
            'Elegí según QUÉ estás comparando:\n'
            '  • contra Appointment.startsAt  →  nowWall()\n'
            '  • bucket de día/mes/semana     →  argentinaNow()\n'
            '  • instante real (createdAt…)   →  AppClock.now()\n\n'
            'Los tres leen de AppClock, así que un test los puede congelar. '
            'Un `DateTime.now()` acá NO se congela, y en core/ eso se propaga '
            'a toda la app: es literalmente cómo `main` quedó en rojo el '
            '08/09/2026. Si de verdad necesitás el reloj real (medir un '
            '`difference`, un timeout), pasá por AppClock igual — en '
            'producción es el mismo valor.',
      );
    });

    test('el seam tiene UNA sola lectura de reloj: el passthrough', () {
      expect(
        lecturasDelSeam,
        hasLength(1),
        reason: 'El seam (`$seam`) debe leer el reloj real en exactamente UN '
            'lugar — `now() => _frozen ?? DateTime.now()`. Encontradas '
            '${lecturasDelSeam.length}:\n'
            '${lecturasDelSeam.map((h) => '      $h').join('\n')}\n\n'
            'Si son MÁS: un helper nuevo acá que no pase por `_frozen` es '
            'infreezable, y no lo caza nadie más — `app_clock_test.dart` '
            'prueba `now()` y los helpers de hoy, no uno que acabás de '
            'agregar. Hacelo derivar de `AppClock.now()`.\n'
            'Si son MENOS: o se movió el seam —actualizá `seam`— o alguien '
            'lo rompió y `AppClock.now()` dejó de leer la hora real. Eso '
            'último lo confirma `app_clock_test.dart`.',
      );
    });

    test('la exención del seam no está muerta', () {
      expect(
        File('lib/$seam').existsSync(),
        isTrue,
        reason: 'La única exención de este guard apunta a `$seam`, que ya no '
            'existe. Si el seam se movió, actualizá la constante: mientras '
            'apunte a un archivo fantasma, el lugar NUEVO se reporta como '
            'ofensor y nadie sabe por qué.\n\n'
            'Ojo: este test NO dice que el seam funcione — para eso está '
            '`test/core/utils/app_clock_test.dart`. Ver el dartdoc de `seam`.',
      );
    });
  });
}
