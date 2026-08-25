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

    /// Sólo el módulo Coach. El resto de `lib/` tiene su propia realidad y
    /// meterlo acá haría la allowlist inmanejable de entrada.
    const scannedRoots = ['features/coach/', 'features/coach_hub/'];

    /// Techo de archivos permitidos, congelado al mergear este guard. NUNCA
    /// subirlo: cada migración lo baja.
    const allowlistCeiling = 37;

    /// Techo de ocurrencias totales. Mismo contrato: sólo baja.
    ///
    /// 86 → 81 con #761: los cinco call-sites de reloj crudo que quedaban en
    /// el camino de RENDER de las cinco pantallas del gate visual pasaron a
    /// `AppClock.now()` (dashboard right column, chat list pane, y dos en la
    /// ficha de alumno; el quinto es el default de `nowWall()`). Bajar el
    /// techo es obligatorio al migrar: dejarlo en 86 regalaría cupo para
    /// cinco regresiones nuevas.
    const rawClockDebtCeiling = 81;

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

        final matches = rawClockPattern
            .allMatches(entity.readAsStringSync())
            .length;
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
        reason:
            'Reloj crudo fuera de la allowlist:\n'
            '${offenders.join('\n')}\n\n'
            'Elegí según QUÉ estás comparando:\n'
            '  • contra Appointment.startsAt  →  nowWall()  '
            '(coach/domain/wall_clock.dart)\n'
            '  • bucket de día/mes/semana     →  argentinaNow()  '
            '(core/utils/argentina_time.dart)\n'
            '  • instante real (createdAt…)   →  DateTime.now() está BIEN, '
            'pero el archivo va a la allowlist con un comentario que lo diga\n\n'
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
        reason:
            'Estos archivos ya no usan reloj crudo (o no existen) pero '
            'siguen en la allowlist:\n${staleEntries.join('\n')}\n\n'
            'Sacalos y bajá allowlistCeiling.',
      );
    });
  });
}
