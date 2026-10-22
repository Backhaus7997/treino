import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/locale_resolver.dart';
import '../../../l10n/app_l10n.dart';
import '../../notifications/application/notification_providers.dart';
import '../../notifications/data/local_notifications_service.dart';

/// Título y cuerpo de la notificación de fin de descanso.
typedef TextosDelAviso = ({String titulo, String cuerpo});

/// Avisa con una notificación del sistema que terminó el descanso, SI la app
/// está en segundo plano (#1617).
///
/// ## El enganche: [update]
///
/// Es la única puerta de entrada. Se le dice cuándo termina el descanso en
/// curso —o `null` si no hay— y cada vez que ese instante CAMBIA: arranque,
/// «+15 s», SALTAR, fin de la sesión, cierre de la pantalla. El resto lo
/// resuelve esta clase:
///
/// - con la app en primer plano no agenda nada: ya avisa la barra del descanso
///   (`RestTimerBar`, que vibra al llegar a cero), y una notificación encima
///   sería el mismo aviso dos veces;
/// - al pasar a segundo plano (`paused`/`hidden`/`detached`) agenda el aviso
///   para [update]`.endsAt`;
/// - al volver (`resumed`) lo cancela, y con él saca de la bandeja el que ya
///   haya salido;
/// - si el instante cambia mientras está agendado, reagenda.
///
/// Mirar el ciclo de vida acá adentro, y no en cada pantalla, es lo que permite
/// que cualquier otro origen de descanso (el que arranca el reloj, #1616) use
/// el MISMO enganche sin duplicar la regla.
///
/// ## Qué NO hace
///
/// No decide si el descanso «cuenta»: el que llama le pasa `null` cuando no hay
/// nada que esperar (p. ej. la sesión ya está completa).
class RestEndAlerts with WidgetsBindingObserver {
  RestEndAlerts({
    required LocalNotificationsService notificaciones,
    required TextosDelAviso Function() textos,
  })  : _notificaciones = notificaciones,
        _textos = textos {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _enSegundoPlano = _esSegundoPlano(binding.lifecycleState);
  }

  final LocalNotificationsService _notificaciones;

  /// Se resuelven al AGENDAR y no al construir: la clase vive todo el proceso.
  final TextosDelAviso Function() _textos;

  /// Cuándo termina el descanso que nos dijeron, o null.
  DateTime? _fin;

  bool _enSegundoPlano = false;

  /// El instante para el que creemos tener algo agendado en el sistema.
  ///
  /// No se anula cuando la alarma ya sonó: sigue siendo lo que el sistema
  /// tiene, y se limpia recién cuando cambia el estado (al volver o al cambiar
  /// el descanso), que es cuando también hay que sacar la notificación de la
  /// bandeja.
  DateTime? _agendado;

  /// Las llamadas al plugin son asíncronas y NO pueden cruzarse: si el usuario
  /// vuelve a la app mientras el agendado todavía consulta el permiso de
  /// alarmas exactas, un `cancel` que lo adelante dejaría la notificación
  /// agendada con la app en primer plano, o sea el aviso doble que esta clase
  /// existe para evitar. Un solo pase a la vez; lo que llega mientras corre se
  /// resuelve en otra vuelta contra el estado más reciente.
  bool _aplicando = false;
  bool _otraVuelta = false;

  /// El descanso en curso termina en [endsAt]; `null` = no hay descanso.
  ///
  /// Idempotente: repetir el mismo valor no toca el plugin.
  void update(DateTime? endsAt) {
    _fin = endsAt;
    _conciliar();
  }

  /// Deja de mirar el ciclo de vida y retira lo que haya agendado.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    update(null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final aSegundoPlano = _esSegundoPlano(state);
    if (aSegundoPlano == _enSegundoPlano) return;
    _enSegundoPlano = aSegundoPlano;
    _conciliar();
  }

  /// `inactive` NO cuenta: es el estado de pasada (el centro de notificaciones,
  /// una llamada entrante) y la app sigue a la vista. Para irse de verdad pasa
  /// por `hidden` y `paused`.
  static bool _esSegundoPlano(AppLifecycleState? estado) =>
      estado == AppLifecycleState.paused ||
      estado == AppLifecycleState.hidden ||
      estado == AppLifecycleState.detached;

  void _conciliar() {
    if (_aplicando) {
      _otraVuelta = true;
      return;
    }
    _aplicando = true;
    unawaited(_correr());
  }

  Future<void> _correr() async {
    try {
      do {
        _otraVuelta = false;
        await _aplicar();
      } while (_otraVuelta);
    } finally {
      _aplicando = false;
    }
  }

  /// Lleva lo agendado a lo que corresponde AHORA: algo para [_fin] si la app
  /// está en segundo plano y el descanso sigue por venir, nada en otro caso.
  Future<void> _aplicar() async {
    final fin = _enSegundoPlano ? _fin : null;
    if (fin == _agendado) return;

    if (fin == null || !fin.isAfter(clock.now())) {
      final habiaAlgo = _agendado != null;
      _agendado = null;
      if (habiaAlgo) await _notificaciones.cancelar(kIdFinDeDescanso);
      return;
    }

    final textos = _textos();
    final agendada = await _notificaciones.agendar(
      id: kIdFinDeDescanso,
      cuando: fin,
      title: textos.titulo,
      body: textos.cuerpo,
    );
    if (agendada) {
      _agendado = fin;
      return;
    }
    // No se pudo agendar el instante nuevo. Si había uno anterior, seguiría
    // vivo y sonaría a una hora que ya no es la del descanso: se lo retira.
    _agendado = null;
    await _notificaciones.cancelar(kIdFinDeDescanso);
  }
}

/// La instancia de la app. Vive todo el proceso porque el ciclo de vida es del
/// proceso, no de una pantalla.
final restEndAlertsProvider = Provider<RestEndAlerts>((ref) {
  final alertas = RestEndAlerts(
    notificaciones: ref.watch(localNotificationsServiceProvider),
    textos: _textosDelSistema,
  );
  ref.onDispose(alertas.dispose);
  return alertas;
});

/// Los textos en el idioma que resuelve la app (`resolveLocale`), sin
/// `BuildContext`: se piden cuando la app pasa a segundo plano, y ahí no hay
/// widget del que colgarse.
TextosDelAviso _textosDelSistema() {
  final l10n = lookupAppL10n(
    resolveLocale(PlatformDispatcher.instance.locale, AppL10n.supportedLocales),
  );
  return (
    titulo: l10n.sessionRestEndedTitle,
    cuerpo: l10n.sessionRestEndedBody,
  );
}
