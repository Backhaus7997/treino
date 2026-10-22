import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/rest_rules.dart';
import 'package:treino/features/workout/domain/rest_state.dart';

/// Corre los fixtures compartidos de `conformance/rest_timer.json` contra la
/// implementación Dart del descanso compartido (#1616): [RestRules] y el
/// formato con el que [SessionRepository] lo escribe y lo lee.
///
/// El Apple Watch reimplementa todo esto en Swift (`RestRules.swift`) y corre
/// los MISMOS casos desde `conformance/run_swift.sh`. Si divergen, la muñeca y
/// la mano vuelven a mostrar dos descansos distintos — que es exactamente lo
/// que #1616 vino a cerrar. Ver `conformance/README.md`.
void main() {
  group('conformance — rest_timer.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/rest_timer.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'No se encontró ${file.path}. Los fixtures de conformidad son '
            'el contrato con la implementación Swift: si el archivo no está, '
            'ese contrato no existe.',
      );
      fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('el fixture apunta a la implementación que este test ejercita', () {
      expect(fixture['rule'], 'rest-timer');
      expect(
        fixture['source_of_truth'],
        'lib/features/workout/domain/rest_rules.dart',
      );
    });

    test('el fixture tiene casos de TODAS las operaciones', () {
      final cases = (fixture['cases'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((c) => c['op'] as String)
          .toSet();
      // Un fixture sin casos de una operación la deja sin contrato y en verde.
      expect(
        cases,
        containsAll(
            <String>['remaining', 'start', 'extend', 'mirror', 'decode']),
      );
    });

    test('cada caso resuelve como dice el contrato', () {
      final cases =
          (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

      // Se acumulan TODAS las discrepancias antes de fallar: con un solo
      // `expect` por caso, la primera esconde las demás.
      final failures = <String>[];

      DateTime? fecha(Object? ms) => ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);

      for (final c in cases) {
        final name = c['name'] as String;
        final op = c['op'] as String;
        final given = c['given'] as Map<String, dynamic>;
        final expected = c['expect'] as Map<String, dynamic>;

        void falla(String esperado, String obtenido) => failures.add(
              '  · "$name" ($op)\n'
              '      esperado: $esperado\n'
              '      obtenido: $obtenido',
            );

        switch (op) {
          case 'remaining':
            final endsAt = fecha(given['endsAtMs'])!;
            final now = fecha(given['nowMs'])!;
            final restante = RestRules.remaining(endsAt: endsAt, now: now);
            final termino = RestRules.isFinished(endsAt: endsAt, now: now);
            if (restante != expected['remaining'] ||
                termino != expected['finished']) {
              falla(
                '${expected['remaining']} s, terminado: ${expected['finished']}',
                '$restante s, terminado: $termino',
              );
            }

          case 'start':
            final fin = RestRules.endsAt(
              start: fecha(given['startMs'])!,
              totalSeconds: given['totalSeconds'] as int,
            );
            if (fin.millisecondsSinceEpoch != expected['endsAtMs']) {
              falla('${expected['endsAtMs']}', '${fin.millisecondsSinceEpoch}');
            }

          case 'extend':
            final r = RestRules.extend(
              endsAt: fecha(given['endsAtMs'])!,
              totalSeconds: given['totalSeconds'] as int,
              seconds: given['seconds'] as int,
              now: fecha(given['nowMs'])!,
            );
            final obtenido = r == null
                ? 'nada'
                : '${r.endsAt.millisecondsSinceEpoch} / ${r.totalSeconds} s';
            final esperado = expected['none'] == true
                ? 'nada'
                : '${expected['endsAtMs']} / ${expected['totalSeconds']} s';
            if (obtenido != esperado) falla(esperado, obtenido);

          case 'mirror':
            final accion = RestRules.decide(
              local: fecha(given['localEndsAtMs']),
              remote: fecha(given['remoteEndsAtMs']),
              localPending: given['localPending'] as bool,
              now: fecha(given['nowMs'])!,
            );
            if (accion.name != expected['action']) {
              falla('${expected['action']}', accion.name);
            }

          case 'decode':
            final doc =
                (given['doc'] as Map<String, dynamic>).cast<String, Object?>();
            final leido = SessionRepository.restFromDoc(doc);
            final esperado = expected['rest'] as Map<String, dynamic>?;
            if (esperado == null) {
              if (leido != null) falla('nada', '$leido');
              break;
            }
            final debe = RestState(
              exerciseId: esperado['exerciseId'] as String,
              setNumber: esperado['setNumber'] as int,
              totalSeconds: esperado['totalSeconds'] as int,
              endsAt: fecha(esperado['endsAtMs'])!,
              owner: switch (esperado['owner']) {
                'phone' => RestOwner.telefono,
                'watch' => RestOwner.reloj,
                final otro => throw StateError('dueño $otro en el fixture'),
              },
            );
            if (leido != debe) {
              falla('$debe', '$leido');
              break;
            }
            // Y al revés: escribirlo tiene que dar EXACTAMENTE el documento.
            // Es lo que garantiza que el teléfono y el Wear escriban lo mismo
            // que el Apple Watch lee, y viceversa.
            final escrito = SessionRepository.restToDoc(leido!);
            final igual = escrito.length == doc.length &&
                escrito.entries.every((e) => doc[e.key] == e.value);
            if (!igual) {
              falla('al escribirlo: $doc', '$escrito');
            }

          default:
            failures.add('  · "$name": operación desconocida "$op"');
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'La implementación DART discrepa del contrato compartido en '
            '${failures.length} de ${cases.length} casos:\n'
            '${failures.join('\n')}\n\n'
            'Si el contrato es el correcto, arreglá la implementación. Si el '
            'contrato está mal, corregí el JSON de conformance/ PRIMERO y '
            'después las DOS implementaciones — nunca al revés.',
      );
    });

    test('los instantes del fixture NO entran en 32 bits', () {
      // La presión que el fixture existe para hacer: en watchOS `Int` es de 32
      // bits, y una implementación que lea los ms como `Int` se rompe en la
      // muñeca aunque pase en el host. Si alguien "simplificara" los casos a
      // offsets chicos, esa presión desaparecería sin que nada se pusiera rojo.
      const maxInt32 = 2147483647;
      for (final raw in fixture['cases'] as List<dynamic>) {
        final c = raw as Map<String, dynamic>;
        final given = c['given'] as Map<String, dynamic>;
        final instantes = [
          for (final k in ['endsAtMs', 'nowMs', 'startMs', 'remoteEndsAtMs'])
            if (given[k] != null) given[k] as int,
          if (given['doc'] case final Map<String, dynamic> doc
              when doc['restEndsAtMs'] != null)
            doc['restEndsAtMs'] as int,
        ];
        for (final ms in instantes) {
          expect(ms, greaterThan(maxInt32), reason: 'caso "${c['name']}"');
        }
      }
    });
  });
}
