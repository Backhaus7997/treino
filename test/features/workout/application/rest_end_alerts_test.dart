// #1617: avisar con una notificación del sistema cuando termina el descanso y
// la app está en segundo plano.
//
// `RestEndAlerts` es el único enganche: la pantalla (y mañana el reloj, #1616)
// sólo le dice cuándo termina el descanso. Estos tests lo ejercitan de punta a
// punta sobre un servicio REAL con un plugin de mentira, así que lo que se mira
// es lo que cruzaría el canal hacia el sistema.

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/notifications/data/local_notifications_service.dart';
import 'package:treino/features/workout/application/rest_end_alerts.dart';

import '../../notifications/data/plugin_falso.dart';
import 'ciclo_de_vida.dart';

/// Las DOS notificaciones del descanso: el aviso final y la cuenta regresiva.
const ambas = [kIdFinDeDescanso, kIdCuentaDeDescanso];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late PluginFalso falso;
  late RestEndAlerts alertas;

  void segundoPlano() => aSegundoPlano(binding);
  void primerPlano() => aPrimerPlano(binding);

  /// Deja correr las llamadas asíncronas al plugin.
  Future<void> reposo() => pumpEventQueue();

  Future<void> armar({
    bool alarmasExactas = true,
    bool esAndroid = true,
  }) async {
    // El binding es uno solo para todo el archivo: se arranca siempre en primer
    // plano y ANTES de crear el observador.
    primerPlano();
    falso = PluginFalso(alarmasExactas: alarmasExactas, esAndroid: esAndroid);
    alertas = RestEndAlerts(
      notificaciones: await falso.servicio(),
      textos: () => (
        titulo: 'Terminó el descanso',
        cuerpo: 'Volvé a la serie',
        cuentaTitulo: 'Descanso',
        cuentaCuerpo: 'Volvé a la serie cuando llegue a cero',
      ),
    );
  }

  tearDown(() {
    alertas.dispose();
    primerPlano();
  });

  DateTime en(int segundos) => clock.now().add(Duration(seconds: segundos));

  group('agenda', () {
    test('al pasar a segundo plano con un descanso en curso', () async {
      await armar();
      final fin = en(90);

      alertas.update(fin);
      segundoPlano();
      await reposo();

      expect(falso.agendados, hasLength(1));
      final a = falso.agendados.single;
      expect(a.id, kIdFinDeDescanso);
      expect(a.cuando.isAtSameMomentAs(fin), isTrue);
      expect(a.detalles.android!.channelId, kCanalDeAvisos);
      expect(a.titulo, 'Terminó el descanso');
      expect(a.cuerpo, 'Volvé a la serie');
    });

    test('con el modo según canScheduleExactNotifications', () async {
      await armar(alarmasExactas: true);
      alertas.update(en(90));
      segundoPlano();
      await reposo();
      expect(
          falso.agendados.single.modo, AndroidScheduleMode.exactAllowWhileIdle);
      alertas.dispose();

      await armar(alarmasExactas: false);
      alertas.update(en(90));
      segundoPlano();
      await reposo();
      expect(falso.agendados.single.modo,
          AndroidScheduleMode.inexactAllowWhileIdle);
    });

    test('si el descanso arranca con la app YA en segundo plano (reloj, #1616)',
        () async {
      await armar();
      segundoPlano();
      await reposo();
      expect(falso.agendados, isEmpty);

      alertas.update(en(60));
      await reposo();

      expect(falso.agendados, hasLength(1));
    });

    test('«hidden» y después «paused» agenda UNA vez', () async {
      await armar();
      alertas.update(en(90));

      irA(binding, AppLifecycleState.hidden);
      irA(binding, AppLifecycleState.paused);
      await reposo();

      expect(falso.agendados, hasLength(1));
    });
  });

  group('NO agenda', () {
    // Es el aviso doble que el issue pide evitar: en primer plano ya avisa la
    // barra (vibra al llegar a cero).
    test('con la app en primer plano', () async {
      await armar();

      alertas.update(en(90));
      await reposo();

      expect(falso.eventos, isEmpty);
    });

    test('«inactive» no cuenta como segundo plano', () async {
      // El centro de notificaciones o una llamada entrante: la app sigue a la
      // vista y la barra sigue avisando.
      await armar();
      alertas.update(en(90));

      irA(binding, AppLifecycleState.inactive);
      await reposo();

      expect(falso.agendados, isEmpty);
    });

    test('sin descanso en curso', () async {
      await armar();

      segundoPlano();
      await reposo();
      alertas.update(null);
      await reposo();

      expect(falso.agendados, isEmpty);
    });

    test('un descanso que ya terminó', () async {
      await armar();

      alertas.update(clock.now().subtract(const Duration(seconds: 1)));
      segundoPlano();
      await reposo();

      // Ni agenda ni cancela: no hay nada que tocar. (Mirar `eventos` y no sólo
      // `agendados` es lo que distingue esta regla de la guarda del servicio,
      // que también rechaza una fecha pasada.)
      expect(falso.eventos, isEmpty);
    });

    test('lo mismo dos veces (update idempotente)', () async {
      await armar();
      final fin = en(90);
      segundoPlano();

      alertas.update(fin);
      await reposo();
      alertas.update(fin);
      alertas.update(fin);
      await reposo();

      expect(falso.agendados, hasLength(1));
    });
  });

  group('cancela', () {
    test('al volver a primer plano', () async {
      await armar();
      alertas.update(en(90));
      segundoPlano();
      await reposo();
      expect(falso.agendados, hasLength(1));

      primerPlano();
      await reposo();

      expect(falso.cancelados, ambas);
    });

    test('con SALTAR (el descanso pasa a null)', () async {
      await armar();
      alertas.update(en(90));
      segundoPlano();
      await reposo();

      alertas.update(null);
      await reposo();

      expect(falso.cancelados, ambas);
    });

    test('al terminar la sesión (dispose)', () async {
      await armar();
      alertas.update(en(90));
      segundoPlano();
      await reposo();

      alertas.dispose();
      await reposo();

      expect(falso.cancelados, ambas);
    });

    test('y después de dispose deja de mirar el ciclo de vida', () async {
      await armar();
      alertas.dispose();
      await reposo();

      // Un llamador rezagado le habla después de dispose: si siguiera
      // observando, irse a segundo plano agendaría.
      alertas.update(en(90));
      segundoPlano();
      await reposo();

      expect(falso.eventos, isEmpty);
    });

    // La carrera que justifica el pase único: el agendado consulta el permiso
    // de alarmas ANTES de agendar. Si el usuario vuelve en ese hueco y el
    // cancel adelanta al agendado, la notificación queda agendada con la app en
    // primer plano: el aviso doble, y además a destiempo.
    test('si el usuario vuelve ANTES de que termine de agendar, gana volver',
        () async {
      await armar();
      alertas.update(en(90));
      await reposo();

      segundoPlano();
      primerPlano(); // sin esperar entre medio
      await reposo();

      expect(
          falso.eventos,
          [
            'mostrar:$kIdCuentaDeDescanso',
            'agendar:$kIdFinDeDescanso',
            'cancelar:$kIdFinDeDescanso',
            'cancelar:$kIdCuentaDeDescanso'
          ],
          reason: 'la última palabra la tiene el regreso');
    });

    test('lo que dejó un agendado viejo si el reagendado falla', () async {
      await armar();
      alertas.update(en(90));
      segundoPlano();
      await reposo();
      expect(falso.agendados, hasLength(1));

      // El próximo agendado falla: el anterior seguiría vivo y sonaría a una
      // hora que ya no es la del descanso.
      falso.falloAlAgendar = (_) => Exception('canal');
      alertas.update(en(105));
      await reposo();

      expect(falso.eventos.last, 'cancelar:$kIdFinDeDescanso');
    });
  });

  // Medido en un emulador (Android 17): la notificación NO se llegaba a mostrar
  // nunca. El cero de la cuenta lo ve la barra —a la misma hora que la alarma, o
  // antes si es inexacta, o apenas descongela el proceso— y llama a
  // `update(null)`. Si eso cancelaba, mataba el aviso justo cuando el sistema lo
  // iba a publicar («Cannot find enqueued record for key»).
  group('el fin NATURAL del descanso no cancela el aviso', () {
    /// Corre [cuerpo] con un reloj que el test mueve a mano.
    Future<void> conReloj(
      Future<void> Function(
              DateTime Function() ahora, void Function(DateTime) ir)
          cuerpo,
    ) async {
      var ahora = DateTime(2026, 10, 22, 10, 40);
      await withClock(
        Clock(() => ahora),
        () => cuerpo(() => ahora, (t) => ahora = t),
      );
    }

    test('update(null) con el instante vencido no toca lo agendado; volver sí',
        () async {
      await conReloj((ahora, ir) async {
        await armar();
        final fin = ahora().add(const Duration(seconds: 199));
        alertas.update(fin);
        segundoPlano();
        await reposo();
        expect(falso.eventos,
            ['mostrar:$kIdCuentaDeDescanso', 'agendar:$kIdFinDeDescanso']);

        // El reloj llega al cero: el tick de la barra (o el proceso al
        // descongelarse) avisa que el descanso terminó.
        ir(fin);
        alertas.update(null);
        await reposo();
        expect(falso.cancelados, isEmpty,
            reason: 'cancelar acá mata la notificación antes de publicarse');

        // Y recién al volver se retira, junto con la que ya haya salido.
        primerPlano();
        await reposo();
        expect(falso.cancelados, ambas);
      });
    });

    // Control negativo del de arriba: SALTAR un segundo ANTES del cero sigue
    // cancelando. Sin esto, una regla que ignorara TODO `update(null)` pasaría
    // el test anterior y dejaría un aviso de un descanso saltado.
    test('update(null) ANTES del instante (SALTAR) sigue cancelando', () async {
      await conReloj((ahora, ir) async {
        await armar();
        final fin = ahora().add(const Duration(seconds: 199));
        alertas.update(fin);
        segundoPlano();
        await reposo();

        ir(fin.subtract(const Duration(seconds: 1)));
        alertas.update(null);
        await reposo();

        expect(falso.cancelados, ambas);
      });
    });

    test('un segundo update(null) tras el fin natural tampoco cancela',
        () async {
      // El cero de la barra y el listener de la sesión completa pueden llegar
      // los dos con `null`.
      await conReloj((ahora, ir) async {
        await armar();
        final fin = ahora().add(const Duration(seconds: 90));
        alertas.update(fin);
        segundoPlano();
        await reposo();

        ir(fin);
        alertas.update(null);
        alertas.update(null);
        await reposo();

        expect(falso.cancelados, isEmpty);
      });
    });

    test('un descanso nuevo después del fin natural se agenda', () async {
      await conReloj((ahora, ir) async {
        await armar();
        final fin = ahora().add(const Duration(seconds: 90));
        alertas.update(fin);
        segundoPlano();
        await reposo();
        ir(fin);
        alertas.update(null);
        await reposo();

        // El reloj arranca otro descanso con la app todavía en segundo plano.
        final otro = ahora().add(const Duration(seconds: 60));
        alertas.update(otro);
        await reposo();

        expect(falso.eventos, [
          'mostrar:$kIdCuentaDeDescanso',
          'agendar:$kIdFinDeDescanso',
          'mostrar:$kIdCuentaDeDescanso',
          'agendar:$kIdFinDeDescanso'
        ]);
        expect(falso.agendados.last.cuando.isAtSameMomentAs(otro), isTrue);
      });
    });

    test('cancel() retira todo aunque el descanso haya terminado solo',
        () async {
      // Terminar o abandonar la sesión: no hay nada que avisar.
      await conReloj((ahora, ir) async {
        await armar();
        final fin = ahora().add(const Duration(seconds: 90));
        alertas.update(fin);
        segundoPlano();
        await reposo();
        ir(fin);
        alertas.update(null);
        await reposo();
        expect(falso.cancelados, isEmpty);

        alertas.cancel();
        await reposo();

        expect(falso.cancelados, ambas);
      });
    });

    test('con la app en primer plano el fin natural no hace nada', () async {
      await conReloj((ahora, ir) async {
        await armar();
        final fin = ahora().add(const Duration(seconds: 90));
        alertas.update(fin);
        ir(fin);
        alertas.update(null);
        await reposo();

        expect(falso.eventos, isEmpty);
      });
    });
  });

  // La cuenta regresiva en vivo (#1617). Desde Android 14 la alarma exacta
  // viene denegada por defecto y la inexacta se demora (medido: hasta el 75 % de
  // lo que faltaba): el cronómetro del sistema da el número exacto mientras el
  // «ding» final llega cuando llega.
  group('cuenta regresiva', () {
    Future<T> conReloj<T>(DateTime ahora, Future<T> Function() cuerpo) =>
        withClock(Clock.fixed(ahora), cuerpo);
    final t0 = DateTime(2026, 10, 22, 10, 40);

    test('al pasar a segundo plano se publica YA, además del aviso final',
        () async {
      await conReloj(t0, () async {
        await armar();
        final fin = t0.add(const Duration(seconds: 199));
        alertas.update(fin);
        segundoPlano();
        await reposo();

        expect(falso.eventos, [
          'mostrar:$kIdCuentaDeDescanso',
          'agendar:$kIdFinDeDescanso',
        ]);
        final p = falso.publicadas.single;
        expect(p.titulo, 'Descanso');
        expect(p.cuerpo, 'Volvé a la serie cuando llegue a cero');
        final a = p.detalles.android!;
        expect(a.when, fin.millisecondsSinceEpoch);
        expect(a.timeoutAfter, 199000);
        expect(a.usesChronometer && a.chronometerCountDown, isTrue);
        expect(a.ongoing && a.silent && a.onlyAlertOnce, isTrue);
        // El aviso final conserva sus textos, y NO es la cuenta.
        final agendada = falso.agendados.single;
        expect(agendada.titulo, 'Terminó el descanso');
        expect(agendada.cuerpo, 'Volvé a la serie');
        expect(agendada.detalles.android!.usesChronometer, isFalse);
        expect(agendada.detalles.android!.silent, isFalse);
      });
    });

    test('con la app en primer plano no se publica', () async {
      await conReloj(t0, () async {
        await armar();
        alertas.update(t0.add(const Duration(seconds: 90)));
        await reposo();

        expect(falso.publicadas, isEmpty);
      });
    });

    test('volver las cancela a las DOS: nunca queda una colgada', () async {
      await conReloj(t0, () async {
        await armar();
        alertas.update(t0.add(const Duration(seconds: 90)));
        segundoPlano();
        await reposo();

        primerPlano();
        await reposo();

        expect(falso.cancelados, unorderedEquals(ambas));
      });
    });

    test('se republica con el `when` nuevo y se reagenda (+15 s)', () async {
      await conReloj(t0, () async {
        await armar();
        final fin = t0.add(const Duration(seconds: 90));
        alertas.update(fin);
        segundoPlano();
        await reposo();

        final masQuince = fin.add(const Duration(seconds: 15));
        alertas.update(masQuince);
        await reposo();

        expect(falso.publicadas, hasLength(2));
        expect(falso.publicadas.last.id, kIdCuentaDeDescanso);
        final a = falso.publicadas.last.detalles.android!;
        expect(a.when, masQuince.millisecondsSinceEpoch);
        expect(a.timeoutAfter, 105000);
        expect(falso.agendados, hasLength(2));
        expect(falso.agendados.last.cuando.isAtSameMomentAs(masQuince), isTrue);
        expect(falso.cancelados, isEmpty,
            reason: 'republicar con el mismo id reemplaza, no se cancela');
      });
    });

    test('un descanso nuevo desde otro origen (reloj, #1616) también',
        () async {
      await conReloj(t0, () async {
        await armar();
        segundoPlano();
        await reposo();
        expect(falso.publicadas, isEmpty);

        alertas.update(t0.add(const Duration(seconds: 60)));
        await reposo();

        expect(falso.publicadas, hasLength(1));
        expect(falso.agendados, hasLength(1));
      });
    });

    test('el fin natural NO la cancela: la saca sola el timeout', () async {
      await conReloj(t0, () async {
        await armar();
        final fin = t0.add(const Duration(seconds: 90));
        alertas.update(fin);
        segundoPlano();
        await reposo();

        await withClock(Clock.fixed(fin), () async {
          alertas.update(null);
          await reposo();
        });

        expect(falso.cancelados, isEmpty);
      });
    });

    test('en iOS sólo sale el aviso agendado', () async {
      await conReloj(t0, () async {
        await armar(esAndroid: false);
        alertas.update(t0.add(const Duration(seconds: 90)));
        segundoPlano();
        await reposo();

        expect(falso.publicadas, isEmpty);
        expect(falso.eventos, ['agendar:$kIdFinDeDescanso']);
      });
    });

    test(
        'si la cuenta salió pero el aviso final no se pudo agendar, volver '
        'igual la limpia', () async {
      await conReloj(t0, () async {
        await armar();
        falso.falloAlAgendar = (_) => Exception('canal');
        alertas.update(t0.add(const Duration(seconds: 90)));
        segundoPlano();
        await reposo();
        expect(falso.publicadas, hasLength(1));
        falso.cancelados.clear();

        primerPlano();
        await reposo();

        expect(falso.cancelados, contains(kIdCuentaDeDescanso));
      });
    });

    test('si no se puede publicar la cuenta, el aviso final sale igual',
        () async {
      await conReloj(t0, () async {
        await armar();
        falso.falloAlMostrar = Exception('canal');
        alertas.update(t0.add(const Duration(seconds: 90)));
        segundoPlano();
        await reposo();

        expect(falso.publicadas, isEmpty);
        expect(falso.agendados, hasLength(1));
      });
    });
  });

  group('reagenda', () {
    test('con +15 s: el MISMO id con el instante nuevo', () async {
      await armar();
      final fin = en(90);
      alertas.update(fin);
      segundoPlano();
      await reposo();

      final masQuince = fin.add(const Duration(seconds: 15));
      alertas.update(masQuince);
      await reposo();

      expect(falso.agendados, hasLength(2));
      expect(falso.agendados.map((a) => a.id).toSet(), {kIdFinDeDescanso},
          reason: 'mismo id = reemplaza, no apila');
      expect(falso.agendados.last.cuando.isAtSameMomentAs(masQuince), isTrue);
      expect(falso.cancelados, isEmpty);
    });

    test('al volver y volver a irse, agenda de nuevo', () async {
      await armar();
      alertas.update(en(90));
      segundoPlano();
      await reposo();
      primerPlano();
      await reposo();

      segundoPlano();
      await reposo();

      expect(falso.agendados, hasLength(2));
    });
  });
}
