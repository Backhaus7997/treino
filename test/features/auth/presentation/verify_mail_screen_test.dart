import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/mail_verification_service.dart';
import 'package:treino/features/auth/presentation/verify_mail_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/verified_email.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Doble del notifier de auth: anota `cancelOnboarding` y puede fallar.
class _AuthFalso extends AuthNotifier {
  int cancelaciones = 0;
  Object? falla;
  Completer<void>? espera;

  @override
  Future<User?> build() async => null;

  @override
  Future<void> cancelOnboarding() async {
    cancelaciones++;
    await espera?.future;
    if (falla != null) throw falla!;
  }
}

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockMetadata extends Mock implements UserMetadata {}

/// Perfil de un alta: alumno, sin ningún mail confirmado.
UserProfile _perfil({
  UserRole role = UserRole.athlete,
  Map<String, VerifiedEmail> emailVerification = const {},
}) {
  final creado = DateTime.utc(2026, 10, 1);
  return UserProfile(
    uid: 'u1',
    email: 'ana@test.com',
    displayName: 'Ana',
    role: role,
    createdAt: creado,
    updatedAt: creado,
    emailVerification: emailVerification,
  );
}

class _MockFunctions extends Mock implements FirebaseFunctions {}

/// Doble del servicio: anota cada pedido y contesta lo que el test le diga.
class _Servicio extends MailVerificationService {
  _Servicio() : super(functions: _MockFunctions());

  /// `true` = pedido con «reenviar».
  final pedidos = <bool>[];
  final codigos = <String>[];
  ResultadoDeSolicitud solicitud =
      const ResultadoDeSolicitud(SolicitudDeCodigo.enviado);
  ResultadoDeVerificacion verificacion =
      const ResultadoDeVerificacion(VerificacionDeCodigo.verificado);
  Object? fallaAlPedir;

  @override
  Future<ResultadoDeSolicitud> solicitar({bool reenviar = false}) async {
    pedidos.add(reenviar);
    if (fallaAlPedir != null) throw fallaAlPedir!;
    return solicitud;
  }

  @override
  Future<ResultadoDeVerificacion> verificar(String codigo) async {
    codigos.add(codigo);
    return verificacion;
  }
}

/// Cuenta cualquier cambio de navegación: la pantalla no navega nunca por su
/// cuenta (la saca el router con el snapshot del perfil).
class _Navegacion extends NavigatorObserver {
  int cambios = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      cambios++;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => cambios++;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      cambios++;

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      cambios++;
}

/// Reloj de la pantalla en los tests. Sigue al tiempo falso de `pump` (que no
/// mueve `DateTime.now`), así los timers y la espera dicen lo mismo. [salto]
/// suma tiempo que pasó SIN que corra ningún timer, como con la app en segundo
/// plano. [lecturas] cuenta cuántas veces la pantalla miró la hora: cada tick
/// la mira, así que es lo que mide cuántos ticks hubo.
class _Reloj {
  Duration salto = Duration.zero;
  int lecturas = 0;

  DateTime lee() {
    lecturas++;
    return TestWidgetsFlutterBinding.instance.clock.now().add(salto);
  }
}

Future<void> _montar(
  WidgetTester tester,
  _Servicio servicio, {
  _Navegacion? navegacion,
  _Reloj? reloj,
  _AuthFalso? authFalso,
  Stream<UserProfile?>? perfil,
  Duration? antiguedad = const Duration(hours: 1),
}) async {
  final auth = _MockAuth();
  final user = _MockUser();
  final metadata = _MockMetadata();
  when(() => user.uid).thenReturn('u1');
  when(() => user.email).thenReturn('ana@test.com');
  // Por defecto, un alta de hace una hora: la cuenta a la que se le ofrece
  // «Me equivoqué de mail». `antiguedad: null` = Auth no sabe cuándo se creó.
  when(() => metadata.creationTime).thenReturn(
    antiguedad == null ? null : DateTime.now().subtract(antiguedad),
  );
  when(() => user.metadata).thenReturn(metadata);
  when(() => auth.currentUser).thenReturn(user);

  final container = ProviderContainer(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      mailVerificationServiceProvider.overrideWithValue(servicio),
      userProfileProvider
          .overrideWith((_) => perfil ?? Stream.value(_perfil())),
      if (authFalso != null) authNotifierProvider.overrideWith(() => authFalso),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: VerifyMailScreen(ahora: reloj?.lee),
        navigatorObservers: [if (navegacion != null) navegacion],
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  // El pedido automático sale en el primer frame.
  await tester.pump();
  await tester.pump();
}

/// La cuenta regresiva del «Reenviar» es un Timer periódico: se desmonta la
/// pantalla al final para que no quede corriendo entre tests.
Future<void> _desmontar(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

AuthPillButton _confirmar(WidgetTester tester) =>
    tester.widget<AuthPillButton>(find.byKey(const Key('verify_mail_confirm')));

TextButton _reenviar(WidgetTester tester) =>
    tester.widget<TextButton>(find.byKey(const Key('verify_mail_resend')));

void main() {
  testWidgets('al abrir pide el código SIN reenviar y dice a qué mail',
      (tester) async {
    final servicio = _Servicio();
    await _montar(tester, servicio);

    expect(servicio.pedidos, [false]);
    expect(
      find.text('Te mandamos un código de 6 dígitos a ana@test.com.'),
      findsOneWidget,
    );
    await _desmontar(tester);
  });

  testWidgets('con un código vigente no pide otro y lo avisa', (tester) async {
    final servicio = _Servicio()
      ..solicitud = const ResultadoDeSolicitud(SolicitudDeCodigo.vigente);
    await _montar(tester, servicio);

    expect(servicio.pedidos, [false]);
    expect(find.textContaining('Ya te mandamos un código'), findsOneWidget);
    await _desmontar(tester);
  });

  testWidgets('CONFIRMAR se habilita recién con los 6 dígitos', (tester) async {
    await _montar(tester, _Servicio());

    expect(_confirmar(tester).onPressed, isNull);
    await tester.enterText(
        find.byKey(const Key('verify_mail_code_field')), '1234');
    await tester.pump();
    expect(_confirmar(tester).onPressed, isNull);

    await tester.enterText(
        find.byKey(const Key('verify_mail_code_field')), '123456');
    await tester.pump();
    expect(_confirmar(tester).onPressed, isNotNull);
    await _desmontar(tester);
  });

  testWidgets('un código incorrecto dice cuántos intentos quedan',
      (tester) async {
    final servicio = _Servicio()
      ..verificacion = const ResultadoDeVerificacion(
        VerificacionDeCodigo.incorrecto,
        intentosRestantes: 3,
      );
    await _montar(tester, servicio);

    await tester.enterText(
        find.byKey(const Key('verify_mail_code_field')), '000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify_mail_confirm')));
    await tester.pump();
    await tester.pump();

    expect(servicio.codigos, ['000000']);
    expect(find.text('El código no coincide. Te quedan 3 intentos.'),
        findsOneWidget);
    await _desmontar(tester);
  });

  testWidgets('verificado: lo avisa y NO navega a mano', (tester) async {
    // La salida la decide el router con el snapshot del perfil; navegar antes
    // correría una carrera con el stream.
    final navegacion = _Navegacion();
    await _montar(tester, _Servicio(), navegacion: navegacion);
    final antes = navegacion.cambios;

    await tester.enterText(
        find.byKey(const Key('verify_mail_code_field')), '048213');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify_mail_confirm')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Listo, mail confirmado.'), findsOneWidget);
    // Ni push ni pop: un pop deja la pantalla en el árbol mientras anima, así
    // que buscarla no alcanzaba para ver que se fue.
    expect(navegacion.cambios, antes);
    await _desmontar(tester);
  });

  testWidgets('«Reenviar» arranca bloqueado 60 s y después pide con reenviar',
      (tester) async {
    final servicio = _Servicio();
    final reloj = _Reloj();
    await _montar(tester, servicio, reloj: reloj);

    // Mismo cooldown que el backend: si el botón se habilitara antes, diría
    // «enviado» y el servidor no mandaría nada.
    expect(_reenviar(tester).onPressed, isNull);
    expect(find.text('Reenviar código en 60 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 61));
    expect(_reenviar(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('verify_mail_resend')));
    await tester.pump();
    await tester.pump();

    expect(servicio.pedidos, [false, true]);
    expect(find.text('Te mandamos un código nuevo a ana@test.com.'),
        findsOneWidget);
    await _desmontar(tester);
  });

  testWidgets('con el tope de envíos: dice los minutos y no deja reenviar',
      (tester) async {
    // 44 min 10 s: se redondea PARA ARRIBA, el botón no se habilita antes de
    // lo que dijo el servidor.
    final servicio = _Servicio()
      ..solicitud = const ResultadoDeSolicitud(
        SolicitudDeCodigo.limitado,
        reintentarEn: Duration(minutes: 44, seconds: 10),
      );
    final reloj = _Reloj();
    await _montar(tester, servicio, reloj: reloj);

    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 45 min.'),
      findsOneWidget,
    );
    expect(_reenviar(tester).onPressed, isNull);
    // Una espera de 45 min no se muestra como «en 2650 s».
    expect(find.textContaining('Reenviar código en'), findsNothing);
    expect(find.text('Reenviar código'), findsOneWidget);

    // Pasados los 60 s del cooldown común sigue bloqueado: la espera es la del
    // servidor, no la del botón.
    await tester.pump(const Duration(seconds: 61));
    expect(_reenviar(tester).onPressed, isNull);
    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 44 min.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(minutes: 45));
    expect(_reenviar(tester).onPressed, isNotNull);
    expect(find.text('Ya podés pedir otro código.'), findsOneWidget);
    await _desmontar(tester);
  });

  testWidgets('con el tope de envíos y 90 min o más: lo dice en horas',
      (tester) async {
    // 4 h 20 min: «en 260 min» no se lee. Se redondea hacia arriba, a 5 h.
    final servicio = _Servicio()
      ..solicitud = const ResultadoDeSolicitud(
        SolicitudDeCodigo.limitado,
        reintentarEn: Duration(hours: 4, minutes: 20),
      );
    await _montar(tester, servicio, reloj: _Reloj());

    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 5 h.'),
      findsOneWidget,
    );
    expect(_reenviar(tester).onPressed, isNull);
    await _desmontar(tester);
  });

  testWidgets(
      'la espera sale del reloj, no de contar ticks (app en segundo '
      'plano)', (tester) async {
    // Con la app en segundo plano los timers no reponen el tiempo que pasó:
    // restando de a uno por tick, la espera de 45 min seguiría diciendo 45 min.
    final servicio = _Servicio()
      ..solicitud = const ResultadoDeSolicitud(
        SolicitudDeCodigo.limitado,
        reintentarEn: Duration(minutes: 45),
      );
    final reloj = _Reloj();
    await _montar(tester, servicio, reloj: reloj);
    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 45 min.'),
      findsOneWidget,
    );

    // Pasan 40 min de reloj sin que corra ningún timer, y después dispara UN
    // solo tick (el próximo de la cuenta cae a los 60 s).
    reloj.salto += const Duration(minutes: 40);
    await tester.pump(const Duration(seconds: 61));

    // 45 min - 40 min - 61 s = 3 min 59 s → 4 min, hacia arriba.
    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 4 min.'),
      findsOneWidget,
    );
    expect(_reenviar(tester).onPressed, isNull);
    await _desmontar(tester);
  });

  testWidgets('con una espera de horas NO se reconstruye cada segundo',
      (tester) async {
    // Reconstruir la pantalla cada segundo para mostrar «4 h» gasta batería.
    // Cada tick mira el reloj, así que las lecturas cuentan los ticks.
    final servicio = _Servicio()
      ..solicitud = const ResultadoDeSolicitud(
        SolicitudDeCodigo.limitado,
        reintentarEn: Duration(hours: 4),
      );
    final reloj = _Reloj();
    await _montar(tester, servicio, reloj: reloj);
    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 4 h.'),
      findsOneWidget,
    );

    // 10 min: lo que se ve no cambia hasta que baje a 3 h, así que ni un tick.
    final alMontar = reloj.lecturas;
    await tester.pump(const Duration(minutes: 10));
    expect(reloj.lecturas, alMontar);
    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 4 h.'),
      findsOneWidget,
    );

    // A la hora de reloj (t = 70 min) ya bajó a 3 h.
    await tester.pump(const Duration(hours: 1));
    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 3 h.'),
      findsOneWidget,
    );

    // Un segundo ANTES del vencimiento sigue bloqueado, y no hay botón
    // habilitado antes de tiempo ni un «0 min».
    await tester.pump(const Duration(hours: 4) -
        const Duration(minutes: 70) -
        const Duration(seconds: 1));
    expect(
      find.text('Pediste muchos códigos. Probá de nuevo en 1 min.'),
      findsOneWidget,
    );
    expect(_reenviar(tester).onPressed, isNull);

    // Y en el vencimiento, se habilita.
    await tester.pump(const Duration(seconds: 1));
    expect(_reenviar(tester).onPressed, isNotNull);
    expect(find.text('Ya podés pedir otro código.'), findsOneWidget);
    await _desmontar(tester);
  });

  group('al volver de segundo plano', () {
    // El timer no avanza con el dispositivo dormido: con el tick a una hora de
    // distancia, sin recalcular al volver se vería la espera de antes de
    // bloquear el teléfono.
    Future<_Reloj> montarConEspera(WidgetTester tester) async {
      final servicio = _Servicio()
        ..solicitud = const ResultadoDeSolicitud(
          SolicitudDeCodigo.limitado,
          reintentarEn: Duration(hours: 4),
        );
      final reloj = _Reloj();
      await _montar(tester, servicio, reloj: reloj);
      return reloj;
    }

    Future<void> dormirYVolver(WidgetTester tester, _Reloj reloj, Duration d) {
      // Las transiciones válidas de la plataforma, una por una.
      for (final e in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(e);
      }
      // Pasa el tiempo de reloj, pero ningún pump llega al tick programado.
      reloj.salto += d;
      for (final e in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(e);
      }
      return tester.pump();
    }

    testWidgets('recalcula contra el reloj sin esperar al timer',
        (tester) async {
      final reloj = await montarConEspera(tester);
      expect(
        find.text('Pediste muchos códigos. Probá de nuevo en 4 h.'),
        findsOneWidget,
      );

      await dormirYVolver(tester, reloj, const Duration(hours: 2));

      expect(
        find.text('Pediste muchos códigos. Probá de nuevo en 2 h.'),
        findsOneWidget,
      );
      expect(_reenviar(tester).onPressed, isNull);

      // Y el tick quedó re-armado: sigue la cuenta (a los 90 min pasa a minutos).
      await tester.pump(const Duration(seconds: 1801));
      expect(
        find.text('Pediste muchos códigos. Probá de nuevo en 90 min.'),
        findsOneWidget,
      );
      await _desmontar(tester);
    });

    testWidgets('si venció mientras dormía, el botón se habilita',
        (tester) async {
      final reloj = await montarConEspera(tester);

      await dormirYVolver(tester, reloj, const Duration(hours: 5));

      expect(_reenviar(tester).onPressed, isNotNull);
      expect(find.text('Ya podés pedir otro código.'), findsOneWidget);
      await _desmontar(tester);
    });
  });

  testWidgets('verificado después de «limitado»: el éxito no queda tapado',
      (tester) async {
    final servicio = _Servicio()
      ..solicitud = const ResultadoDeSolicitud(
        SolicitudDeCodigo.limitado,
        reintentarEn: Duration(minutes: 45),
      );
    await _montar(tester, servicio, reloj: _Reloj());

    await tester.enterText(
        find.byKey(const Key('verify_mail_code_field')), '048213');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify_mail_confirm')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Listo, mail confirmado.'), findsOneWidget);
    expect(find.textContaining('Pediste muchos códigos'), findsNothing);
    expect(find.textContaining('Reenviar código en'), findsNothing);
    await _desmontar(tester);
  });

  testWidgets('si se cae la red al pedir, lo dice', (tester) async {
    final servicio = _Servicio()..fallaAlPedir = Exception('sin red');
    await _montar(tester, servicio);

    expect(find.byKey(const Key('verify_mail_error')), findsOneWidget);
    expect(find.textContaining('Revisá tu conexión'), findsOneWidget);
    await _desmontar(tester);
  });

  testWidgets('siempre hay una salida: cerrar sesión', (tester) async {
    await _montar(tester, _Servicio());

    expect(find.byKey(const Key('verify_mail_sign_out')), findsOneWidget);
    await _desmontar(tester);
  });

  group('«Me equivoqué de mail»', () {
    Future<void> abrirDialogo(WidgetTester tester) async {
      await tester
          .ensureVisible(find.byKey(const Key('verify_mail_wrong_email')));
      await tester.tap(find.byKey(const Key('verify_mail_wrong_email')));
      await tester.pumpAndSettle();
    }

    testWidgets('el botón está a la vista y no borra nada por sí solo',
        (tester) async {
      final auth = _AuthFalso();
      await _montar(tester, _Servicio(), authFalso: auth);

      expect(find.byKey(const Key('verify_mail_wrong_email')), findsOneWidget);
      expect(find.text('Me equivoqué de mail'), findsOneWidget);
      expect(find.byKey(const Key('verify_mail_wrong_email_confirm')),
          findsNothing);
      expect(auth.cancelaciones, 0);
      await _desmontar(tester);
    });

    testWidgets('al tocarlo pide confirmación explicando que se borra',
        (tester) async {
      final auth = _AuthFalso();
      await _montar(tester, _Servicio(), authFalso: auth);

      await abrirDialogo(tester);

      expect(find.byKey(const Key('verify_mail_wrong_email_confirm')),
          findsOneWidget);
      expect(find.textContaining('borrar esta cuenta'), findsOneWidget);
      expect(find.textContaining('mismo nombre'), findsOneWidget);
      expect(auth.cancelaciones, 0);
      await _desmontar(tester);
    });

    testWidgets('«Volver» en el diálogo no llama a nada', (tester) async {
      final auth = _AuthFalso();
      await _montar(tester, _Servicio(), authFalso: auth);

      await abrirDialogo(tester);
      await tester.tap(find.byKey(const Key('verify_mail_wrong_email_back')));
      await tester.pumpAndSettle();

      expect(auth.cancelaciones, 0);
      expect(find.byKey(const Key('verify_mail_wrong_email_confirm')),
          findsNothing);
      await _desmontar(tester);
    });

    testWidgets('confirmar llama a cancelOnboarding UNA vez y no navega',
        (tester) async {
      final auth = _AuthFalso();
      final navegacion = _Navegacion();
      await _montar(tester, _Servicio(),
          authFalso: auth, navegacion: navegacion);

      await abrirDialogo(tester);
      final antes = navegacion.cambios;
      await tester
          .tap(find.byKey(const Key('verify_mail_wrong_email_confirm')));
      await tester.pump(const Duration(seconds: 1));

      expect(auth.cancelaciones, 1);
      // Solo se cerró el diálogo (1 pop): la salida la decide el router.
      expect(navegacion.cambios, antes + 1);
      await _desmontar(tester);
    });

    testWidgets('mientras borra, bloquea los demás botones', (tester) async {
      final auth = _AuthFalso()..espera = Completer<void>();
      await _montar(tester, _Servicio(), authFalso: auth);

      await abrirDialogo(tester);
      await tester
          .tap(find.byKey(const Key('verify_mail_wrong_email_confirm')));
      await tester.pump();
      await tester.pump();

      expect(auth.cancelaciones, 1);
      expect(
        tester
            .widget<TextButton>(
                find.byKey(const Key('verify_mail_wrong_email')))
            .onPressed,
        isNull,
      );
      expect(_reenviar(tester).onPressed, isNull);
      expect(
        tester
            .widget<ButtonStyleButton>(
                find.byKey(const Key('verify_mail_sign_out')))
            .onPressed,
        isNull,
      );

      auth.espera!.complete();
      await tester.pump();
      await _desmontar(tester);
    });

    testWidgets('si falla: avisa y los botones vuelven a andar',
        (tester) async {
      final auth = _AuthFalso()..falla = Exception('boom');
      await _montar(tester, _Servicio(), authFalso: auth);

      await abrirDialogo(tester);
      await tester
          .tap(find.byKey(const Key('verify_mail_wrong_email_confirm')));
      await tester.pumpAndSettle();

      expect(auth.cancelaciones, 1);
      expect(find.text('No pudimos borrar la cuenta. Probá de nuevo.'),
          findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
                find.byKey(const Key('verify_mail_wrong_email')))
            .onPressed,
        isNotNull,
      );

      // Se puede reintentar.
      await abrirDialogo(tester);
      await tester
          .tap(find.byKey(const Key('verify_mail_wrong_email_confirm')));
      await tester.pumpAndSettle();
      expect(auth.cancelaciones, 2);
      await _desmontar(tester);
    });
  });
  // A esta pantalla no llegan solo las altas: el router también manda a
  // cuentas con historia (promoción a entrenador, cambio de mail en Auth, y
  // TODAS las viejas sin verificar el día que se prende `app_config/email_gate`).
  // «Me equivoqué de mail» borra sin reautenticar, así que a esas no se les
  // muestra. Les queda «Cerrar sesión».
  group('«Me equivoqué de mail» solo en un alta recién creada', () {
    Future<void> sinElBoton(WidgetTester tester) async {
      expect(find.byKey(const Key('verify_mail_wrong_email')), findsNothing);
      expect(find.byKey(const Key('verify_mail_sign_out')), findsOneWidget);
      await _desmontar(tester);
    }

    testWidgets('alta de hace una hora, alumno sin mail confirmado: está',
        (tester) async {
      await _montar(tester, _Servicio());

      expect(find.byKey(const Key('verify_mail_wrong_email')), findsOneWidget);
      await _desmontar(tester);
    });

    testWidgets('cuenta creada hace más de 24 h (interruptor recién prendido)',
        (tester) async {
      await _montar(tester, _Servicio(),
          antiguedad: const Duration(hours: 24, minutes: 1));
      await sinElBoton(tester);
    });

    testWidgets('cuenta de hace meses', (tester) async {
      await _montar(tester, _Servicio(), antiguedad: const Duration(days: 200));
      await sinElBoton(tester);
    });

    testWidgets('entrenador (promovido), aunque la cuenta sea nueva',
        (tester) async {
      await _montar(tester, _Servicio(),
          perfil: Stream.value(_perfil(role: UserRole.trainer)));
      await sinElBoton(tester);
    });

    testWidgets('promovido con la entrada de alumno ya confirmada',
        (tester) async {
      await _montar(
        tester,
        _Servicio(),
        perfil: Stream.value(_perfil(
          role: UserRole.trainer,
          emailVerification: const {
            'athlete': VerifiedEmail(email: 'ana@test.com'),
          },
        )),
      );
      await sinElBoton(tester);
    });

    testWidgets('mail cambiado en Auth: ya había confirmado otro',
        (tester) async {
      await _montar(
        tester,
        _Servicio(),
        perfil: Stream.value(_perfil(
          emailVerification: const {
            'athlete': VerifiedEmail(email: 'viejo@test.com'),
          },
        )),
      );
      await sinElBoton(tester);
    });

    testWidgets('perfil cargando: falla cerrado', (tester) async {
      final perfil = StreamController<UserProfile?>();
      addTearDown(perfil.close);
      await _montar(tester, _Servicio(), perfil: perfil.stream);
      await sinElBoton(tester);
    });

    testWidgets('sin perfil (null): falla cerrado', (tester) async {
      await _montar(tester, _Servicio(), perfil: Stream.value(null));
      await sinElBoton(tester);
    });

    testWidgets('Auth no sabe cuándo se creó: falla cerrado', (tester) async {
      await _montar(tester, _Servicio(), antiguedad: null);
      await sinElBoton(tester);
    });

    testWidgets('el perfil llega después: recién ahí aparece', (tester) async {
      final perfil = StreamController<UserProfile?>();
      addTearDown(perfil.close);
      await _montar(tester, _Servicio(), perfil: perfil.stream);
      expect(find.byKey(const Key('verify_mail_wrong_email')), findsNothing);

      perfil.add(_perfil());
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('verify_mail_wrong_email')), findsOneWidget);
      await _desmontar(tester);
    });
  });
}
