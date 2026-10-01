import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/mail_verification_service.dart';
import 'package:treino/features/auth/presentation/verify_mail_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

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

Future<void> _montar(
  WidgetTester tester,
  _Servicio servicio, {
  _Navegacion? navegacion,
}) async {
  final auth = _MockAuth();
  final user = _MockUser();
  when(() => user.uid).thenReturn('u1');
  when(() => user.email).thenReturn('ana@test.com');
  when(() => auth.currentUser).thenReturn(user);

  final container = ProviderContainer(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      mailVerificationServiceProvider.overrideWithValue(servicio),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const VerifyMailScreen(),
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
    await _montar(tester, servicio);

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
}
