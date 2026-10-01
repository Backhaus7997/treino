import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/data/mail_verification_service.dart';

// El parseo es la frontera con el backend
// (`functions/src/auth/codigo-de-verificacion.ts`): un valor que este binario
// no conoce no puede tirar, porque la pantalla es OBLIGATORIA y un backend más
// nuevo que la app dejaría a la gente trabada en una pantalla que explota.

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock implements HttpsCallableResult<Object?> {}

void main() {
  group('parsearSolicitud', () {
    test('mapea cada estado del backend', () {
      const casos = {
        'enviado': SolicitudDeCodigo.enviado,
        'vigente': SolicitudDeCodigo.vigente,
        'ya-verificado': SolicitudDeCodigo.yaVerificado,
        'enfriando': SolicitudDeCodigo.enfriando,
        'sin-perfil': SolicitudDeCodigo.noSalio,
        'sin-email': SolicitudDeCodigo.noSalio,
      };
      for (final MapEntry(:key, :value) in casos.entries) {
        expect(parsearSolicitud({'estado': key}).estado, value, reason: key);
      }
    });

    test('un estado desconocido o una respuesta rara no tiran', () {
      expect(parsearSolicitud({'estado': 'algo-nuevo'}).estado,
          SolicitudDeCodigo.noSalio);
      expect(parsearSolicitud(null).estado, SolicitudDeCodigo.noSalio);
      expect(parsearSolicitud('texto').estado, SolicitudDeCodigo.noSalio);
    });

    test('reintentarEn solo viene con enfriando', () {
      expect(
        parsearSolicitud({'estado': 'enfriando', 'reintentarEnMs': 30000})
            .reintentarEn,
        const Duration(seconds: 30),
      );
      expect(
        parsearSolicitud({'estado': 'enviado', 'reintentarEnMs': 30000})
            .reintentarEn,
        isNull,
      );
    });
  });

  group('parsearVerificacion', () {
    test('mapea cada estado del backend', () {
      const casos = {
        'verificado': VerificacionDeCodigo.verificado,
        'incorrecto': VerificacionDeCodigo.incorrecto,
        'vencido': VerificacionDeCodigo.vencido,
        'bloqueado': VerificacionDeCodigo.bloqueado,
        'sin-codigo': VerificacionDeCodigo.sinCodigo,
        'formato-invalido': VerificacionDeCodigo.formatoInvalido,
      };
      for (final MapEntry(:key, :value) in casos.entries) {
        expect(parsearVerificacion({'estado': key}).estado, value, reason: key);
      }
    });

    test('un estado desconocido no tira', () {
      expect(parsearVerificacion({'estado': 'nuevo'}).estado,
          VerificacionDeCodigo.desconocido);
      expect(
          parsearVerificacion(null).estado, VerificacionDeCodigo.desconocido);
    });

    test('intentosRestantes solo viene con incorrecto', () {
      expect(
        parsearVerificacion({'estado': 'incorrecto', 'intentosRestantes': 3})
            .intentosRestantes,
        3,
      );
      expect(
        parsearVerificacion({'estado': 'vencido', 'intentosRestantes': 3})
            .intentosRestantes,
        isNull,
      );
    });
  });

  group('MailVerificationService', () {
    late _MockFunctions functions;
    late _MockCallable callable;
    late _MockResult result;

    setUp(() {
      functions = _MockFunctions();
      callable = _MockCallable();
      result = _MockResult();
      when(() => functions.httpsCallable(any())).thenReturn(callable);
      when(() => callable.call<Object?>(any())).thenAnswer((_) async => result);
    });

    test('el pedido automático no manda «reenviar»', () async {
      // Sin «reenviar», un código vigente no se pisa: es lo que deja que el que
      // está en la bandeja siga sirviendo cuando la pantalla se vuelve a abrir.
      when(() => result.data).thenReturn({'estado': 'vigente'});

      final r = await MailVerificationService(functions: functions).solicitar();

      expect(r.estado, SolicitudDeCodigo.vigente);
      verify(() => functions.httpsCallable('solicitarCodigoDeVerificacion'))
          .called(1);
      verify(() => callable.call<Object?>(null)).called(1);
    });

    test('el botón «Reenviar» manda reenviar: true', () async {
      when(() => result.data).thenReturn({'estado': 'enviado'});

      await MailVerificationService(functions: functions)
          .solicitar(reenviar: true);

      verify(() => callable.call<Object?>({'reenviar': true})).called(1);
    });

    test('verificar manda el código', () async {
      when(() => result.data).thenReturn({'estado': 'verificado'});

      final r = await MailVerificationService(functions: functions)
          .verificar('048213');

      expect(r.estado, VerificacionDeCodigo.verificado);
      verify(() => functions.httpsCallable('verificarCodigoDeMail')).called(1);
      verify(() => callable.call<Object?>({'codigo': '048213'})).called(1);
    });
  });
}
