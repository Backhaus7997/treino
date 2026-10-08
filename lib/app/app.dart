import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/analytics/analytics_service.dart';
import '../core/analytics/route_analytics.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/notifications/application/cola_de_avisos.dart';
import '../features/notifications/application/notification_providers.dart';
import '../features/notifications/application/notification_router.dart';
import '../features/notifications/presentation/permission_gate.dart'
    show permissionPromptSettledProvider;
import '../features/watch/application/watch_credential_providers.dart';
import '../features/watch/application/watch_effort_notifier.dart';
import '../features/watch/application/watch_timer_control_notifier.dart';
import '../l10n/app_l10n.dart';
import 'locale_resolver.dart';
import 'root_scaffold_messenger.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_provider.dart';
import 'theme/theme_watcher.dart';

/// Whether [message] was sent by [currentUid] — used to suppress
/// self-notifications.
///
/// FCM routes by TOKEN, not by uid. If a device's token leaks into another
/// account's `fcmTokens` (e.g. two accounts tested on one phone), the device
/// would otherwise receive — and show — a push for a message IT sent. The
/// device always knows its own uid, so this guard is independent of token
/// registration hygiene and is the invariant: you are never notified of your
/// own message.
///
/// Reads `data['senderId']` (added by the Cloud Function) and falls back to
/// the `other` query param embedded in the deepLink, so it works even before
/// the function is redeployed. Fail-open: returns false when the sender can't
/// be determined (shows the notification, same as before).
bool isOwnChatMessage(RemoteMessage message, String? currentUid) {
  if (currentUid == null) return false;
  final data = message.data;
  var senderId = data['senderId'] as String?;
  if (senderId == null || senderId.isEmpty) {
    final deepLink = data['deepLink'] as String?;
    if (deepLink != null) {
      senderId = Uri.tryParse(deepLink)?.queryParameters['other'];
    }
  }
  return senderId != null && senderId.isNotEmpty && senderId == currentUid;
}

class TreinoApp extends ConsumerStatefulWidget {
  const TreinoApp({super.key});

  @override
  ConsumerState<TreinoApp> createState() => _TreinoAppState();
}

class _TreinoAppState extends ConsumerState<TreinoApp> {
  late final GoRouter _router;

  /// Loguea `screen_view` en cada navegación. Se detacha en [dispose].
  late final RouteAnalytics _routeAnalytics;

  /// Foreground message subscription — cancelled on dispose.
  StreamSubscription<RemoteMessage>? _fgSub;

  /// Background-tap subscription (onMessageOpenedApp) — cancelled on dispose.
  StreamSubscription<RemoteMessage>? _bgSub;

  /// Avisos que llegaron antes de que el permiso del sistema se resolviera.
  /// Las reglas de la cola (tope, orden, drenaje) viven en [ColaDeAvisos], que
  /// tiene sus propios tests — acá sólo se decide CUÁNDO encolar y drenar.
  final ColaDeAvisos _avisosEnEspera = ColaDeAvisos();

  /// Corta la espera si el permiso no resuelve nunca. Se cancela en [dispose]:
  /// un timer vivo después del desmontaje revienta tests ajenos con
  /// `!timersPending`, y el error no nombra a quién lo dejó colgado.
  Timer? _esperaDelPermiso;

  /// Escucha a [permissionPromptSettledProvider] para drenar la cola.
  ProviderSubscription<bool>? _permisoSub;

  @override
  void initState() {
    super.initState();
    final refresh = ref.read(routerRefreshNotifierProvider);
    _router = buildRouter(refreshListenable: refresh, read: ref.read);

    // Analytics de navegación (#666). Sin esto la app no emite UN solo evento
    // de qué pantalla se usa, y ese dato no es recuperable retroactivamente.
    _routeAnalytics = RouteAnalytics(
      router: _router,
      analytics: ref.read(analyticsServiceProvider),
    )..attach();

    // (c) Eagerly read fcmLifecycleProvider to register the auth-state listener
    //     for the app lifetime. Without this, all of PR#2a is dead code —
    //     no tokens are ever registered. ADR-PN-003, REQ-PN-CLIENT-004.
    ref.read(fcmLifecycleProvider);

    // (c2) Igual que arriba, para el companion de Apple Watch: sin este read
    //      el handoff de credencial es código muerto — el servicio existe pero
    //      nadie lo llama y el reloj se queda esperando para siempre.
    //      Corta solo si no hay reloj emparejado. Change watch-standalone-client.
    ref.read(watchCredentialLifecycleProvider);

    // (c3) Le avisa al reloj cuando cambia la rutina activa. El reloj habla
    //      Firestore por REST y no tiene listeners, así que sin este aviso un
    //      cambio hecho en el teléfono recién se veía al cambiar de página en
    //      la muñeca. Best-effort: si el reloj no está alcanzable el aviso se
    //      pierde y el reloj se pone al día solo, como antes.
    ref.read(watchActiveRoutineNudgeProvider);
    // El canal de escucha al reloj vive mientras vive la app, no solo mientras
    // esté abierta la pantalla del player.
    //
    // Antes solo lo miraban dos filas DENTRO del player, así que el teléfono
    // dejaba de escuchar al reloj apenas salías de ahí — y volvía a empezar de
    // cero al entrar. Un cronómetro arrancado en la muñeca con el teléfono en
    // Home no llegaba nunca.
    ref.read(watchEffortNotifierProvider);

    // Y el canal por el que el RELOJ pide cancelar el cronómetro del teléfono.
    // Vive acá por lo mismo: si naciera al abrir el player, una cancelación
    // hecha desde la muñeca con el teléfono en otra pantalla no llegaría nunca.
    ref.read(watchTimerControlNotifierProvider);

    // (a0) Notificaciones LOCALES: las que se dibujan con la app abierta.
    //
    // El tap de éstas NO pasa por `onMessageOpenedApp` —esa la dispara el SDK
    // nativo sólo para las de background—, así que la navegación del tap se
    // engancha acá, contra el MISMO `goDeepLink` que usan las otras dos
    // puertas. Si no, tocar un aviso con la app abierta no haría nada.
    //
    // `init` es async y no se espera: lo único que hace antes de estar listo es
    // que un `show()` muy temprano se descarte con un log. Bloquear el arranque
    // de la app por el canal de notificaciones sería un intercambio malo.
    final localNotifs = ref.read(localNotificationsServiceProvider);
    // El future se GUARDA (y además se deja sin esperar acá). El cold-start
    // gate de más abajo lo espera antes de preguntar por el aviso que abrió la
    // app: en iOS el launch notification lo registra `initialize`, así que
    // preguntar antes de que termine devuelve null y el deep link se pierde
    // justo en el caso que este gate existe para cubrir.
    final localNotifsInit = localNotifs.init(
      onTap: (deepLink) {
        final ctx = _router.routerDelegate.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        goDeepLink(ctx, deepLink);
      },
    );
    unawaited(localNotifsInit);

    // (a) Attach foreground handler. (REQ-PN-HANDLER-001)
    final fcm = ref.read(fcmServiceProvider);

    // En iOS quién se dibuja lo decide `PresentacionEnPrimerPlano`
    // (`AppDelegate.swift`); esto es sólo la red si ese delegate se cae.
    // Ver el dartdoc de `habilitarPresentacionEnPrimerPlano`.
    unawaited(fcm.habilitarPresentacionEnPrimerPlano());

    _fgSub = fcm.onForegroundMessage.listen(_onForeground);

    // (a1) Cuando el prompt del permiso termina, sale lo que quedó esperando.
    //      `fireImmediately` no hace falta: si ya está resuelto, `_onForeground`
    //      no encola nada y esto no tiene trabajo.
    _permisoSub = ref.listenManual<bool>(
      permissionPromptSettledProvider,
      (_, resuelto) {
        if (resuelto) unawaited(_drenarAvisosEnEspera());
      },
    );

    // (a2) Background tap: app resumed from background via notification tap →
    //      navigate to the deepLink. (ADR-PN-009, REQ-PN-HANDLER-002,
    //      SCENARIO-655, 656.)
    _bgSub = fcm.onMessageOpenedApp.listen((message) {
      if (isOwnChatMessage(
          message, ref.read(firebaseAuthProvider).currentUser?.uid)) {
        return;
      }
      final ctx = _router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      goDeepLink(ctx, message.data['deepLink'] as String?);
    });

    // (b) Cold-start gate: wait for router to be ready before navigating.
    //     addPostFrameCallback guarantees GoRouter is fully mounted.
    //     ADR-PN-011, REQ-PN-HANDLER-003, SCENARIO-657, 658.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final message = await fcm.getInitialMessage();
      if (message != null) {
        if (isOwnChatMessage(
            message, ref.read(firebaseAuthProvider).currentUser?.uid)) {
          return;
        }
        final ctx = _router.routerDelegate.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        goDeepLink(ctx, message.data['deepLink'] as String?);
        return;
      }

      // (b2) El mismo gate, para las notificaciones LOCALES.
      //
      // Hasta acá esto no existía y el tap se perdía entero: el callback de
      // `LocalNotificationsService.init` sólo corre con la app VIVA, así que
      // tocar un aviso local con la app cerrada la arrancaba en la pantalla de
      // inicio. `getInitialMessage` cubría únicamente el lado de FCM.
      //
      // Va en el `else` del de arriba porque la app la abre UNA notificación:
      // si FCM ya reclamó el arranque, preguntar por la local sólo puede
      // devolver un aviso viejo y pisar el destino correcto.
      await localNotifsInit;
      final deepLinkLocal = await localNotifs.deepLinkDeArranque();
      if (deepLinkLocal == null) return;
      final ctx = _router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      goDeepLink(ctx, deepLinkLocal);
    });
  }

  @override
  void dispose() {
    _routeAnalytics.detach();
    _fgSub?.cancel();
    _bgSub?.cancel();
    _esperaDelPermiso?.cancel();
    _permisoSub?.close();
    super.dispose();
  }

  /// Location actual del router, o `null` si todavía no resolvió ninguna.
  ///
  /// La guarda de `isEmpty` NO es decorativa, y es la misma que documenta
  /// `RouteAnalytics._currentRoute`: con la lista de matches vacía, `state`
  /// tira `StateError: No element`. Acá además devolver `null` es lo correcto
  /// semánticamente — "no sé dónde está" hace que la supresión falle abierta.
  ///
  /// Location concreta del router. La lógica vive en [locationActualDe] para
  /// que se pueda testear con un router de verdad — ver su dartdoc, que
  /// explica por qué las otras dos APIs obvias no sirven.
  String? _currentLocation() => locationActualDe(_router);

  /// Handler de mensajes con la app en PRIMER PLANO.
  ///
  /// FCM no dibuja nada en foreground: te entrega el mensaje y se desentiende.
  /// En el teléfono la notificación la dibuja la app
  /// ([LocalNotificationsService]); en web, donde no hay notificación del
  /// sistema, sigue el SnackBar de ADR-PN-010.
  ///
  /// Dos guardas antes de mostrar, y cubren cosas distintas: [isOwnChatMessage]
  /// ("lo mandaste vos desde otro dispositivo") y
  /// [shouldSuppressForegroundNotification] ("ya lo estás mirando").
  ///
  /// REQ-PN-HANDLER-001.
  void _onForeground(RemoteMessage message) {
    // Sin volcar `message.data`: ahí viajan uids y el deep link del chat, y
    // esto corre también en release.
    debugPrint('[fcm] onMessage recibido');

    // Never show the sender their own message (token may be cross-registered
    // on a shared device). See [isOwnChatMessage].
    if (isOwnChatMessage(
        message, ref.read(firebaseAuthProvider).currentUser?.uid)) {
      debugPrint('[fcm] suprimido: es tu propio mensaje');
      return;
    }

    final deepLink = message.data['deepLink'] as String?;

    // No avisar de algo que la persona ya está mirando.
    //
    // Es una guarda DISTINTA de `isOwnChatMessage`, no una versión más amplia:
    // aquélla tapa "este mensaje lo mandaste vos desde otro dispositivo" y
    // ésta tapa "ya lo estás viendo". Un mensaje ajeno que llega mientras
    // tenés el chat abierto sólo lo agarra ésta; tu propio mensaje llegando
    // desde Home sólo lo agarra aquélla. Las dos tienen que quedar.
    final location = _currentLocation();
    if (shouldSuppressForegroundNotification(
      currentLocation: location,
      deepLink: deepLink,
    )) {
      debugPrint('[fcm] suprimido: ya lo estás mirando ($location)');
      return;
    }
    debugPrint('[fcm] se muestra — location=$location deepLink=$deepLink');

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';

    // En WEB sigue el SnackBar, y no por vagancia: el Coach Hub es Flutter web
    // y ahí no hay notificación del sistema que mostrar. Sacarlo dejaría a esa
    // superficie SIN ningún aviso, que es peor que el cartel in-app que tenía.
    // En el teléfono, en cambio, el cartel era justo el problema del E2E.
    if (kIsWeb) {
      _mostrarSnackBar(title: title, body: body, deepLink: deepLink);
      return;
    }

    final aviso = Aviso(title: title, body: body, deepLink: deepLink);

    // La CARRERA DEL PERMISO: un aviso que llega antes de que el usuario haya
    // contestado el prompt del sistema se ENCOLA, no se degrada.
    //
    // `PermissionGate` no pide permiso hasta tener el perfil cargado y el
    // onboarding resuelto, así que en una instalación nueva esta ventana está
    // garantizada, no es un caso de borde. Y los dos sistemas fallan distinto
    // adentro de ella: en iOS `show()` tira (`Error 2003 — Source is not
    // authorized`) y devuelve false, así que al menos salía el cartel; en
    // Android, sin `POST_NOTIFICATIONS`, no tira nada —el sistema descarta la
    // notificación en silencio y `show()` devuelve true— así que el aviso
    // desaparecía ENTERO, sin cartel y sin log.
    //
    // Encolar lo arregla en las dos: el aviso espera a que el permiso resuelva
    // y recién ahí se intenta de verdad.
    if (!ref.read(permissionPromptSettledProvider)) {
      _encolarHastaQueElPermisoResuelva(aviso);
      return;
    }

    unawaited(_entregar(aviso));
  }

  /// Entrega un aviso: notificación del sistema y, si no salió, cartel in-app.
  ///
  /// Se ESPERA el resultado de `show`, y de ahí sale el fallback. Antes esto
  /// iba con `unawaited` y el bool se tiraba a la basura: si el plugin no había
  /// inicializado —cosa que pasa en silencio, porque su `init` también corre
  /// sin await— el aviso se perdía entero y el usuario no se enteraba de que le
  /// habían escrito. Un cartel in-app es un mal premio consuelo, pero es
  /// infinitamente mejor que nada.
  Future<void> _entregar(Aviso aviso, {bool soloCartel = false}) async {
    if (!soloCartel) {
      final mostrada = await ref.read(localNotificationsServiceProvider).show(
            title: aviso.title,
            body: aviso.body,
            deepLink: aviso.deepLink,
          );
      if (mostrada || !mounted) return;
      debugPrint('[fcm] la notificación del sistema no salió — cae al cartel');
    }
    if (!mounted) return;
    _mostrarSnackBar(
      title: aviso.title,
      body: aviso.body,
      deepLink: aviso.deepLink,
    );
  }

  /// Guarda el aviso hasta que el prompt del permiso termine.
  ///
  /// La cola tiene tope y tira los MÁS VIEJOS: si llegan quince avisos antes de
  /// que el usuario conteste, mostrarle quince notificaciones de golpe apenas
  /// acepta es su propia forma de ser ignorado.
  ///
  /// El timer es la red, y existe porque el permiso puede no resolverse NUNCA:
  /// el gate espera perfil completo y onboarding terminado, y un usuario que se
  /// queda en el tour deja la cola colgada para siempre. Al vencer, los avisos
  /// salen por el cartel — que es exactamente lo que pasaba antes de que esta
  /// cola existiera, así que el peor caso de este cambio empata con el mejor
  /// caso del anterior.
  void _encolarHastaQueElPermisoResuelva(Aviso aviso) {
    debugPrint('[fcm] permiso sin resolver — el aviso espera');
    _avisosEnEspera.encolar(aviso);
    _esperaDelPermiso ??= Timer(
      ColaDeAvisos.kEsperaMaxima,
      () => _drenarAvisosEnEspera(soloCartel: true),
    );
  }

  /// Saca todo lo encolado. Nunca descarta: o sale por el sistema, o por el
  /// cartel.
  Future<void> _drenarAvisosEnEspera({bool soloCartel = false}) async {
    _esperaDelPermiso?.cancel();
    _esperaDelPermiso = null;
    if (_avisosEnEspera.vacia) return;

    final pendientes = _avisosEnEspera.drenar();
    debugPrint('[fcm] drenando ${pendientes.length} aviso(s) en espera');

    for (final aviso in pendientes) {
      if (!mounted) return;
      await _entregar(aviso, soloCartel: soloCartel);
    }
  }

  /// Cartel in-app. Camino de WEB únicamente — ver [_onForeground].
  /// ADR-PN-010, SCENARIO-652, 653, 654.
  void _mostrarSnackBar({
    required String title,
    required String body,
    required String? deepLink,
  }) {
    final messenger = ref.read(rootScaffoldMessengerKeyProvider).currentState;
    if (messenger == null) return;

    // Capture context from the navigator so goDeepLink has GoRouter access.
    final ctx = _router.routerDelegate.navigatorKey.currentContext;

    messenger.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (body.isNotEmpty) Text(body),
          ],
        ),
        // `persist: false` A MANO. `SnackBar` hace
        // `persist = persist ?? action != null`: con acción es eterno por
        // default y el `duration` de acá abajo NO se mira. Sin esto el cartel
        // se queda hasta recargar la página.
        persist: false,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label:
              ctx != null ? AppL10n.of(ctx).appFcmSnackBarActionLabel : 'Ver',
          onPressed: () {
            if (ctx == null || !ctx.mounted) return;
            goDeepLink(ctx, deepLink);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'TREINO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
      // i18n — ADR-I18N-004, ADR-I18N-005
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      localeResolutionCallback: (locale, supported) =>
          resolveLocale(locale ?? const Locale('es', 'AR'), supported),
      // Root ScaffoldMessenger key — foreground push SnackBars (ADR-PN-010)
      // y avisos de la capa de providers (p.ej. adjuntos de chat, #435).
      // Vive en un provider para que ese código lo alcance sin BuildContext.
      scaffoldMessengerKey: ref.watch(rootScaffoldMessengerKeyProvider),
      // Global: tap anywhere outside an input dismisses the keyboard.
      // translucent so buttons/scroll still win the tap; only empty-area
      // taps reach this and unfocus the current field.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: ThemeWatcher(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
