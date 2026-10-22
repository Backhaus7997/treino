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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late PluginFalso falso;
  late RestEndAlerts alertas;

  void segundoPlano() => aSegundoPlano(binding);
  void primerPlano() => aPrimerPlano(binding);

  /// Deja correr las llamadas asíncronas al plugin.
  Future<void> reposo() => pumpEventQueue();

  Future<void> armar({bool alarmasExactas = true}) async {
    // El binding es uno solo para todo el archivo: se arranca siempre en primer
    // plano y ANTES de crear el observador.
    primerPlano();
    falso = PluginFalso(alarmasExactas: alarmasExactas);
    alertas = RestEndAlerts(
      notificaciones: await falso.servicio(),
      textos: () => (titulo: 'Terminó el descanso', cuerpo: 'Volvé a la serie'),
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

      expect(falso.cancelados, [kIdFinDeDescanso]);
    });

    test('con SALTAR (el descanso pasa a null)', () async {
      await armar();
      alertas.update(en(90));
      segundoPlano();
      await reposo();

      alertas.update(null);
      await reposo();

      expect(falso.cancelados, [kIdFinDeDescanso]);
    });

    test('al terminar la sesión (dispose)', () async {
      await armar();
      alertas.update(en(90));
      segundoPlano();
      await reposo();

      alertas.dispose();
      await reposo();

      expect(falso.cancelados, [kIdFinDeDescanso]);
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

      expect(falso.eventos,
          ['agendar:$kIdFinDeDescanso', 'cancelar:$kIdFinDeDescanso'],
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
