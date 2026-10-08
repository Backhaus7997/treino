import 'package:flutter/foundation.dart';

/// Un reporte sin resolver, tal como lo devuelve `listPendingReports`.
///
/// DTO plano y no freezed a proposito: nace de un `Map` que devuelve una Cloud
/// Function, no se persiste, no se compara por valor en ningun lado, y sumar
/// una clase generada obliga a correr `build_runner` a quien toque esto.
@immutable
class PendingReport {
  const PendingReport({
    required this.id,
    required this.targetKind,
    required this.targetId,
    required this.targetOwnerUid,
    required this.reason,
    required this.reporterUid,
    required this.detail,
    required this.createdAt,
    required this.firstViewedAt,
    required this.contentPath,
    required this.derivedOwnerUid,
    required this.derivedOwnerName,
    required this.attemptedAction,
    required this.attemptedAt,
  });

  /// Lee un item de la respuesta del callable.
  ///
  /// Tolerante por diseño: si el servidor agrega un campo, esto sigue
  /// funcionando; si saca uno, cae a un valor vacio en vez de explotar. Una
  /// cola de moderacion que no abre porque el servidor cambio una clave deja
  /// al equipo sin la herramienta justo cuando corre el reloj de las 24 horas.
  factory PendingReport.fromMap(Map<Object?, Object?> raw) {
    String texto(String clave) =>
        raw[clave] is String ? raw[clave]! as String : '';
    DateTime? fecha(String clave) {
      final v = raw[clave];
      return v is String ? DateTime.tryParse(v) : null;
    }

    return PendingReport(
      id: texto('id'),
      targetKind: texto('targetKind'),
      targetId: texto('targetId'),
      targetOwnerUid: texto('targetOwnerUid'),
      reason: texto('reason'),
      reporterUid: texto('reporterUid'),
      detail: raw['detail'] is String ? raw['detail']! as String : null,
      createdAt: fecha('createdAt'),
      firstViewedAt: fecha('firstViewedAt'),
      contentPath:
          raw['contentPath'] is String ? raw['contentPath']! as String : null,
      derivedOwnerUid: raw['derivedOwnerUid'] is String
          ? raw['derivedOwnerUid']! as String
          : null,
      derivedOwnerName: raw['derivedOwnerName'] is String
          ? raw['derivedOwnerName']! as String
          : null,
      attemptedAction: raw['attemptedAction'] is String
          ? raw['attemptedAction']! as String
          : null,
      attemptedAt: fecha('attemptedAt'),
    );
  }

  final String id;
  final String targetKind;
  final String targetId;
  final String targetOwnerUid;
  final String reason;
  final String reporterUid;

  /// Lo que escribio quien denuncio. Texto libre, puede citar lo que le
  /// dijeron — o sea datos de un tercero. No se loguea ni se manda por mail.
  final String? detail;

  final DateTime? createdAt;

  /// Cuando se MIRO por primera vez. Es la medida de la promesa publicada:
  /// las 24 horas son para revisar, no para resolver.
  final DateTime? firstViewedAt;

  /// Ruta del documento reportado, o `null` si no se pudo derivar.
  final String? contentPath;

  /// El autor REAL del contenido, derivado del documento por el servidor.
  ///
  /// `null` cuando el contenido ya no existe o no se pudo derivar. NO cae de
  /// vuelta a [targetOwnerUid]: ese lo declara quien denuncia y nada lo ata
  /// al autor real, así que mostrarlo como si lo fuera sería peor que no
  /// mostrar nada — es sobre este uid que se ejecuta «Dar de baja».
  final String? derivedOwnerUid;

  /// `displayName` de ese autor, si lo tiene.
  ///
  /// Un uid no se reconoce de un vistazo; el nombre sí. Van los dos: el
  /// nombre para reconocer, el uid para no confundir a dos parecidos.
  final String? derivedOwnerName;

  /// La acción que YA se ejecutó —o pudo haberse ejecutado— sobre este
  /// reporte sin que la resolución llegara a cerrarse. `null` en el caso
  /// normal.
  ///
  /// Auth y el mail queue no entran en una transacción de Firestore, así que
  /// un `userSuspended` que deshabilita la cuenta y después no llega a
  /// marcar el reporte devuelve el reporte a la cola. Antes volvía mudo, y
  /// el siguiente moderador lo descartaba: `dismissed`/`none` escrito sobre
  /// una cuenta dada de baja.
  final String? attemptedAction;

  /// Cuándo se anotó ese intento. `null` si no hay ninguno.
  final DateTime? attemptedAt;

  /// `true` cuando el uid que declaró quien denuncia NO es el autor real.
  ///
  /// Es señal de un intento de abuso: alguien denuncia contenido de Juan
  /// escribiendo el uid de Pedro. El servidor ya no ejecuta nada sobre el
  /// declarado, pero quien aprieta el botón tiene que verlo — hasta ahora
  /// sólo iba a un `logger.warn` de Cloud Logging, invisible desde acá.
  bool get uidDeclaradoNoCoincide {
    final derivado = derivedOwnerUid;
    return derivado != null && derivado != targetOwnerUid;
  }

  /// Horas desde que entro el reporte. `null` si no tiene fecha.
  int? get horasDesdeQueEntro {
    final creado = createdAt;
    if (creado == null) return null;
    return DateTime.now().toUtc().difference(creado.toUtc()).inHours;
  }

  /// `true` si ya paso el plazo prometido sin que nadie lo mirara.
  ///
  /// Mismo criterio que `moderationStats` del servidor: lo que se promete es
  /// REVISAR dentro de las 24 horas. Un reporte mirado en tiempo y todavia
  /// abierto no incumple nada — resolverlo puede requerir una decision.
  bool get rompioElPlazo {
    final creado = createdAt;
    if (creado == null) return false;
    final vencimiento = creado.toUtc().add(const Duration(hours: 24));
    final visto = firstViewedAt;
    if (visto == null) return DateTime.now().toUtc().isAfter(vencimiento);
    return visto.toUtc().isAfter(vencimiento);
  }
}
