import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lo que contesta `solicitarCodigoDeVerificacion`
/// (`functions/src/auth/codigo-de-verificacion.ts`).
enum SolicitudDeCodigo {
  /// Salió un código nuevo.
  enviado,

  /// Ya había uno sin vencer: no se mandó otro, para no invalidar el que el
  /// usuario puede tener en la bandeja.
  vigente,

  /// El mail ya estaba confirmado.
  yaVerificado,

  /// Hubo un envío hace menos de 60 s. Ver [ResultadoDeSolicitud.reintentarEn].
  enfriando,

  /// La cuenta no tiene rol o no tiene mail, o el servidor contestó algo que
  /// este binario no conoce. Para la pantalla es lo mismo: no salió.
  noSalio,
}

/// Lo que contesta `verificarCodigoDeMail`.
enum VerificacionDeCodigo {
  verificado,
  incorrecto,
  vencido,

  /// Se gastaron los intentos de ese código: hay que pedir otro.
  bloqueado,

  /// No hay código pendiente: nunca se pidió, o ya se usó.
  sinCodigo,

  /// No son 6 dígitos. No gasta intentos.
  formatoInvalido,

  /// El servidor contestó algo que este binario no conoce.
  desconocido,
}

class ResultadoDeSolicitud {
  const ResultadoDeSolicitud(this.estado, {this.reintentarEn});

  final SolicitudDeCodigo estado;

  /// Solo con [SolicitudDeCodigo.enfriando]: cuánto falta para poder pedir otro.
  final Duration? reintentarEn;
}

class ResultadoDeVerificacion {
  const ResultadoDeVerificacion(this.estado, {this.intentosRestantes});

  final VerificacionDeCodigo estado;

  /// Solo con [VerificacionDeCodigo.incorrecto].
  final int? intentosRestantes;
}

/// Traduce la respuesta del callable. Un valor que no conoce cae en
/// [SolicitudDeCodigo.noSalio] y no tira: un backend más nuevo que la app no
/// puede dejar al usuario trabado en una pantalla que explota.
@visibleForTesting
ResultadoDeSolicitud parsearSolicitud(Object? data) {
  final mapa = data is Map ? data : const <Object?, Object?>{};
  final estado = switch (mapa['estado']) {
    'enviado' => SolicitudDeCodigo.enviado,
    'vigente' => SolicitudDeCodigo.vigente,
    'ya-verificado' => SolicitudDeCodigo.yaVerificado,
    'enfriando' => SolicitudDeCodigo.enfriando,
    _ => SolicitudDeCodigo.noSalio,
  };
  final ms = mapa['reintentarEnMs'];
  return ResultadoDeSolicitud(
    estado,
    reintentarEn: estado == SolicitudDeCodigo.enfriando && ms is num
        ? Duration(milliseconds: ms.toInt())
        : null,
  );
}

/// Ídem para la verificación.
@visibleForTesting
ResultadoDeVerificacion parsearVerificacion(Object? data) {
  final mapa = data is Map ? data : const <Object?, Object?>{};
  final estado = switch (mapa['estado']) {
    'verificado' => VerificacionDeCodigo.verificado,
    'incorrecto' => VerificacionDeCodigo.incorrecto,
    'vencido' => VerificacionDeCodigo.vencido,
    'bloqueado' => VerificacionDeCodigo.bloqueado,
    'sin-codigo' => VerificacionDeCodigo.sinCodigo,
    'formato-invalido' => VerificacionDeCodigo.formatoInvalido,
    _ => VerificacionDeCodigo.desconocido,
  };
  final restantes = mapa['intentosRestantes'];
  return ResultadoDeVerificacion(
    estado,
    intentosRestantes:
        estado == VerificacionDeCodigo.incorrecto && restantes is num
            ? restantes.toInt()
            : null,
  );
}

/// Las dos llamadas de la pantalla del código. Solo las llamadas: el estado
/// vive en la pantalla, igual que en `BirthDateGateScreen`.
///
/// Los errores de red o del servidor (`FirebaseFunctionsException`) suben tal
/// cual: la pantalla los muestra como «probá de nuevo».
class MailVerificationService {
  MailVerificationService({required FirebaseFunctions functions})
      : _functions = functions;

  final FirebaseFunctions _functions;

  /// [reenviar] solo desde el botón «Reenviar código»: sin eso, si ya hay un
  /// código vigente el servidor no manda otro (ver [SolicitudDeCodigo.vigente]).
  Future<ResultadoDeSolicitud> solicitar({bool reenviar = false}) async {
    final result = await _functions
        .httpsCallable('solicitarCodigoDeVerificacion')
        .call<Object?>(reenviar ? {'reenviar': true} : null);
    return parsearSolicitud(result.data);
  }

  Future<ResultadoDeVerificacion> verificar(String codigo) async {
    final result = await _functions
        .httpsCallable('verificarCodigoDeMail')
        .call<Object?>({'codigo': codigo});
    return parsearVerificacion(result.data);
  }
}

/// Región explícita: el cliente de Firebase usa `us-central1` por defecto y
/// las funciones viven en `southamerica-east1`.
final mailVerificationServiceProvider = Provider<MailVerificationService>(
  (ref) => MailVerificationService(
    functions: FirebaseFunctions.instanceFor(region: 'southamerica-east1'),
  ),
);
