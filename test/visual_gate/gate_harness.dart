/// Harness del gate visual del Coach Hub (#761): monta el Coach Hub REAL.
///
/// ## Qué monta, y por qué importa que sea el real
///
/// El corpus de evidencia que este gate reemplaza (borrado en #723 / PR #759)
/// construía su propio `ThemeData` copiado a mano de `AppTheme`, porque creía
/// que `google_fonts` no podía resolver las tipografías dentro de
/// `flutter test`. Hoy sí puede: las Barlow están bundleadas bajo `assets:` en
/// el pubspec, aparecen en el `AssetManifest` del bundle de test y
/// `google_fonts` las lee del disco sin tocar la red. Medido: "ENTRENAR HOY" en
/// Barlow Condensed 700 @40px mide 216,4 px con la fuente real contra 480,0 px
/// con el fallback de test.
///
/// Eso cambia el diseño de raíz. Un golden que fotografía una RÉPLICA del tema
/// no detecta una regresión DEL tema: podés romper `AppTheme.light()` y los
/// catorce goldens siguen verdes. Este harness monta
/// `AppTheme.dark()` / `AppTheme.light()`, el `buildCoachHubRouter` real y el
/// `CoachHubScaffold` real. Lo único falso son los datos.
///
/// ## Qué se stubea y a qué altura
///
/// La regla es **stubear en el borde de I/O, no en el borde del layout**:
///
/// - `trainerPaymentsProvider` (pagos crudos) — el `pagosBucketsProvider` real
///   los clasifica contra el reloj congelado. Stubear los buckets ya hechos
///   saltearía la lógica que el golden quiere ver rendida.
/// - `aggregateAdherenceProvider` / `inactivosProvider` — acá sí se stubea el
///   valor: derivan de las sesiones de cada alumno, y sembrar seis historiales
///   de entrenamiento para mover un número del hero es un costo de
///   mantenimiento que el gate no puede pagar.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/coach_hub_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart'
    show chatsForCurrentUserProvider, totalUnreadCountProvider;
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/payments/application/payment_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'gate_seed.dart';

/// Los dos temas de la paleta Mint Magenta.
///
/// **Los dos se fotografían siempre.** No es simetría por prolijidad: el mint
/// del acento es idéntico en ambos, pero `bg` no — `palette.bg` sobre `accent`
/// da 12.10:1 en dark y 1.57:1 en light. Un gate de un solo tema deja el tema
/// donde el contraste se cae sin ninguna cobertura visual.
enum GateTheme {
  dark('dark'),
  light('light');

  const GateTheme(this.slug);

  /// Fragmento del nombre de archivo del golden.
  final String slug;

  /// El tema REAL de la app, no una réplica.
  ThemeData get theme =>
      this == GateTheme.dark ? AppTheme.dark() : AppTheme.light();

  AppPalette get palette => this == GateTheme.dark
      ? AppPalette.mintMagenta
      : AppPalette.mintMagentaLight;

  /// Valor que `ThemeModeNotifier` persiste en `SharedPreferences`.
  ///
  /// Se siembra igual al tema capturado para que el toggle del top bar se vea
  /// coherente con lo que la captura muestra. Sin esto el golden dark
  /// mostraría el toggle en "sistema" — determinístico, pero mintiendo sobre
  /// el estado de la app.
  String get prefValue => slug;
}

/// Los tres viewports del shell, uno por rama de `viewportFor()`.
///
/// Las anchuras no son redondas por gusto: 1440 y 1024 son los dos anchos de
/// monitor más comunes y caen a cada lado del breakpoint de 1280; 420 entra
/// holgado abajo de 768, donde el `MobileBanner` reemplaza al scaffold entero.
enum GateViewport {
  desktop(1440, 900, 'desktop'),
  compact(1024, 900, 'compact'),
  mobile(420, 900, 'mobile');

  const GateViewport(this.width, this.height, this.slug);

  final double width;
  final double height;
  final String slug;

  Size get size => Size(width, height);
}

/// Nombre de archivo del golden. Un solo lugar arma la convención, así que
/// renombrarlos es un cambio de una línea y no un find-and-replace.
String gateGoldenName({
  required String screen,
  required GateTheme theme,
  required GateViewport viewport,
}) =>
    'goldens/${screen}__${theme.slug}__${viewport.slug}.png';

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._state);
  final AsyncValue<User?> _state;

  @override
  Future<User?> build() async {
    state = _state;
    return _state.valueOrNull;
  }
}

/// Monta el Coach Hub en [route] con el seed fijo y lo deja listo para la foto.
///
/// Devuelve el [ProviderContainer] para que el test pueda afirmar sobre el
/// estado que produjo la captura, no sólo sobre sus píxeles.
Future<ProviderContainer> pumpGate(
  WidgetTester tester, {
  required GateTheme theme,
  required GateViewport viewport,
  String route = '/dashboard',
}) async {
  tester.view.physicalSize = viewport.size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({'app.theme_mode': theme.prefValue});
  final prefs = await SharedPreferences.getInstance();

  final user = _MockUser();
  when(() => user.uid).thenReturn(kGateTrainerId);

  final athletesById = {for (final a in kGateAthletes) a.id: a};
  final appointments = gateAppointments();

  final container = ProviderContainer(overrides: [
    // ── Sesión ────────────────────────────────────────────────────────────
    authNotifierProvider.overrideWith(() => _StubAuthNotifier(AsyncData(user))),
    authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(user)),
    userProfileProvider.overrideWith(
      (ref) => Stream<UserProfile?>.value(gateTrainerProfile()),
    ),
    sharedPreferencesProvider.overrideWith((ref) => Future.value(prefs)),

    // ── Datos del PF ──────────────────────────────────────────────────────
    trainerLinksStreamProvider.overrideWith(
      (ref) => Stream.value(gateTrainerLinks()),
    ),
    userPublicProfileProvider.overrideWith((ref, uid) {
      final athlete = athletesById[uid];
      return Stream<UserPublicProfile?>.value(
        athlete == null ? null : gateAthleteProfile(athlete),
      );
    }),
    // La versión batch NO deriva de la de arriba: son dos providers distintos
    // sobre el mismo repositorio, y Pagos usa esta. Sin overridearla, la tabla
    // cae al fallback `'Alumno'` en TODAS las filas — la captura sale
    // determinística igual, y por eso hay que mirarla: un baseline con seis
    // "Alumno" no detecta que se rompió la resolución de nombres, la consagra.
    userPublicProfilesBatchProvider.overrideWith((ref, key) async {
      final uids = key.isEmpty ? const <String>[] : key.split(',');
      return {
        for (final uid in uids)
          if (athletesById[uid] case final athlete?)
            uid: gateAthleteProfile(athlete),
      };
    }),
    // La ventana de la key la aplica la pantalla; devolver la agenda entera
    // mantiene el override en una línea y deja el filtrado —que es lo que el
    // reloj congelado vuelve testeable— en el código real.
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream<List<Appointment>>.value(appointments),
    ),
    trainerPaymentsProvider.overrideWith((ref) => Stream.value(gatePayments())),
    // Sin esto la sección Chat rinde "No pudimos cargar tus chats." — un
    // estado de error, tan determinístico como el bueno y por eso capaz de
    // colarse como baseline si nadie mira la imagen.
    chatsForCurrentUserProvider.overrideWith(
      (ref) => Stream<List<Chat>>.value(gateChats()),
    ),

    // La ficha de alumno trata un error en mediciones o rutinas como error del
    // resumen entero ("No se pudo cargar el resumen."). Sin estos tres
    // overrides el golden de la pantalla más data-bound del Hub sería una
    // captura de un mensaje de error — determinística, y completamente inútil
    // como baseline.
    measurementsForAthleteProvider.overrideWith(
      (ref, athleteId) => Stream.value(gateMeasurements(athleteId)),
    ),
    assignedRoutinesProvider.overrideWith((ref, athleteId) async {
      return const <Routine>[];
    }),
    // Las sesiones quedan vacías a propósito, no por olvido: la propia pantalla
    // documenta que un permission-denied acá NO es un error del resumen (el CF
    // borra `session_shares` cuando el link no está activo), así que degrada a
    // "sin sesiones" y los widgets dependientes muestran su estado vacío. Es un
    // camino de render legítimo y barato; sembrar seis historiales de
    // entrenamiento para mover un número no lo es.
    sessionsByUidProvider.overrideWith((ref, uid) async {
      return const <Session>[];
    }),

    // ── Derivados caros de sembrar (ver dartdoc de la librería) ───────────
    aggregateAdherenceProvider.overrideWith((ref) async => kGateAdherencePct),
    inactivosProvider.overrideWith(
      (ref) async => InactivosResult(
        inactiveAthleteIds: gateInactiveAthleteIds(),
      ),
    ),
    totalUnreadCountProvider.overrideWithValue(kGateUnreadChats),
  ]);
  addTearDown(container.dispose);

  // El redirect del router lee auth + perfil de forma síncrona. Sin calentarlos
  // primero, la primera evaluación los ve en `loading` y rebota a /login — la
  // captura sale de la pantalla equivocada.
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError((_) => null);
    await container.read(userProfileProvider.future).catchError((_) => null);
    await container.read(sharedPreferencesProvider.future);
  });

  final refresh = ValueNotifier<int>(0);
  addTearDown(refresh.dispose);
  final router =
      buildCoachHubRouter(refreshListenable: refresh, read: container.read);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme.theme,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  await _settle(tester);

  if (route != '/dashboard') {
    router.go(route);
    await _settle(tester);
  }

  _expectLandedOn(tester, router, route);
  return container;
}

/// La captura salió de la ruta que se pidió, y no de otra.
///
/// Existe porque el modo de falla sin esto es ilegible. El redirect del Coach
/// Hub manda a `/login` o `/not-allowed` ante auth o perfil sin resolver, y lo
/// único que ve el que lee el log es *"Found 0 widgets with type
/// CoachHubScaffold"* — cero pistas sobre qué se rindió en su lugar.
///
/// Pasó de verdad: el gate rompió en CI con ese mensaje y hubo que bajar el
/// log de tres jobs para descartar hipótesis. Este chequeo convierte eso en
/// una línea que dice a dónde fue a parar la captura.
void _expectLandedOn(WidgetTester tester, GoRouter router, String route) {
  final landed = router.routerDelegate.currentConfiguration.uri.toString();
  final onScreen = tester.widgetList<Scaffold>(find.byType(Scaffold)).length;

  expect(
    landed,
    route,
    reason: 'la captura tenía que salir de $route y el router quedó en '
        '$landed ($onScreen Scaffold en el árbol). Si es /login o '
        '/not-allowed, el redirect corrió antes de que auth o el perfil '
        'estuvieran resueltos — mirá el warm-up de pumpGate.',
  );
}

/// El árbol resolvió la paleta que el test pidió.
///
/// **Ojo con el contexto que se le pasa a `AppPalette.of`.** El elemento del
/// `MaterialApp` está ARRIBA del `Theme` que el propio `MaterialApp` instala,
/// así que ahí `Theme.of()` devuelve el tema por defecto de Flutter — sin la
/// `ThemeExtension`. Y `AppPalette.of` cae a `mintMagenta` (dark) cuando la
/// extensión falta (`app_palette.dart:133`), en silencio: la aserción pasaba
/// en dark por casualidad y fallaba en light sin decir por qué.
///
/// Por eso se lee desde el `Navigator`, que sí está debajo del `Theme`.
///
/// Sin este chequeo, un bug que sirviera la paleta dark en el tema light
/// produciría dos goldens idénticos y nadie lo notaría hasta verlos uno al
/// lado del otro.
void expectGatePalette(WidgetTester tester, GateTheme theme) {
  final context = tester.element(find.byType(Navigator).first);
  expect(
    AppPalette.of(context).bg,
    theme.palette.bg,
    reason: 'el tema ${theme.slug} tiene que resolver a su propia paleta',
  );
}

/// Ningún `RenderFlex overflowed` quedó dando vueltas.
///
/// Un overflow pinta la barra amarilla y negra, que ENTRA al golden: sin este
/// chequeo, regenerar la haría baseline y el defecto pasaría a ser la
/// referencia contra la que se compara todo lo que venga.
void expectGateNoOverflow(WidgetTester tester) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'la captura no puede llevarse puesto un overflow al golden',
  );
}

/// `pumpAndSettle` con techo corto (30 s en vez de los 10 min por defecto).
///
/// Un `TreinoShimmer` es un `controller.repeat()`: si algún provider del seed
/// quedó en `loading`, su esqueleto gira para siempre y `pumpAndSettle` no
/// vuelve nunca. Con el techo por defecto eso son diez minutos de runner
/// quemados antes del error. Con 30 s el gate falla rápido y el mensaje —un
/// timeout de settle— apunta derecho al provider que falta en el seed.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
