import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/moderacion/moderacion_screen.dart';
import 'package:treino/features/moderation/application/moderation_queue_providers.dart';
import 'package:treino/features/moderation/data/moderation_queue_service.dart';
import 'package:treino/features/moderation/domain/moderation_stats.dart';
import 'package:treino/features/moderation/domain/pending_queue.dart';
import 'package:treino/features/moderation/domain/pending_report.dart';

/// Doble del servicio. Registra lo que se le pidio resolver.
///
/// `implements` y no `extends`: el constructor real pide un
/// `FirebaseFunctions`, y tocar `FirebaseFunctions.instance` en un test sin
/// Firebase inicializado tira `FirebaseException` antes de llegar a medir
/// nada. Implementando el contrato no hay super al que llamar.
class _ServicioFalso implements ModerationQueueService {
  _ServicioFalso({
    required this.reportes,
    this.explota = false,
    this.incompleta = false,
  });

  final List<PendingReport> reportes;
  final bool explota;
  final bool incompleta;
  final List<({String id, String status, String action})> resueltos = [];
  final List<String> marcados = [];

  @override
  Future<PendingQueue> listPending({int limit = 50}) async {
    if (explota) throw Exception('sin red');
    return PendingQueue(reportes: reportes, incompleta: incompleta);
  }

  @override
  Future<void> markViewed(String reportId) async => marcados.add(reportId);

  @override
  Future<ModerationStats> stats() async => const ModerationStats(
        pending: 2,
        oldestPendingHours: 40,
        breachingSla: 1,
      );

  @override
  Future<void> resolve({
    required String reportId,
    required String status,
    required String action,
    String? note,
  }) async {
    resueltos.add((id: reportId, status: status, action: action));
  }
}

PendingReport _reporte({
  required String id,
  int horas = 2,
  String? derivedOwnerUid = 'o1',
  String? derivedOwnerName,
  String? attemptedAction,
}) =>
    PendingReport.fromMap({
      'id': id,
      'targetKind': 'post',
      'targetId': 'p1',
      'targetOwnerUid': 'o1',
      'reason': 'harassment',
      'reporterUid': 'r1',
      'detail': 'me dijeron cosas',
      'createdAt': DateTime.now()
          .toUtc()
          .subtract(Duration(hours: horas))
          .toIso8601String(),
      'contentPath': 'posts/p1',
      if (derivedOwnerUid != null) 'derivedOwnerUid': derivedOwnerUid,
      if (derivedOwnerName != null) 'derivedOwnerName': derivedOwnerName,
      if (attemptedAction != null) 'attemptedAction': attemptedAction,
    });

void main() {
  Future<_ServicioFalso> montar(
    WidgetTester tester, {
    required bool esModerador,
    List<PendingReport> reportes = const [],
    bool explota = false,
    bool incompleta = false,
  }) async {
    final servicio = _ServicioFalso(
      reportes: reportes,
      explota: explota,
      incompleta: incompleta,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isModeratorProvider.overrideWith((ref) => esModerador),
          moderationQueueServiceProvider.overrideWithValue(servicio),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: ModeracionScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return servicio;
  }

  testWidgets('sin el claim no muestra nada de la cola', (tester) async {
    // La ruta se puede escribir a mano en la barra del navegador, asi que la
    // pantalla tiene que sostenerse sola — esconder el item del sidebar no es
    // el control de acceso.
    await montar(tester, esModerador: false, reportes: [_reporte(id: 'r1')]);

    expect(find.textContaining('equipo de TREINO'), findsOneWidget);
    expect(find.textContaining('posts/p1'), findsNothing);
    expect(find.textContaining('me dijeron cosas'), findsNothing);
  });

  testWidgets('con el claim lista los pendientes', (tester) async {
    await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    expect(find.textContaining('HARASSMENT'), findsOneWidget);
    expect(find.textContaining('posts/p1'), findsOneWidget);
  });

  testWidgets('muestra la RUTA del contenido, no el contenido', (tester) async {
    // Traer el post acá seria una copia mas de datos de terceros. Quien modera
    // abre el documento en la consola, autenticado.
    await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    expect(find.textContaining('posts/p1'), findsOneWidget);
  });

  testWidgets('resolver manda el estado y la accion', (tester) async {
    final servicio =
        await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(servicio.resueltos, hasLength(1));
    expect(servicio.resueltos.first.id, 'r1');
    expect(servicio.resueltos.first.status, 'dismissed');
    expect(servicio.resueltos.first.action, 'none');
  });

  testWidgets('dar de baja pide confirmacion antes de resolver nada',
      (tester) async {
    // Es la accion mas grave de las cuatro e irreversible desde la UI: tocar
    // el boton no puede disparar la baja directo, tiene que haber un paso
    // en el medio.
    final servicio =
        await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    await tester.tap(find.text('Dar de baja'));
    await tester.pumpAndSettle();

    expect(find.text('¿Dar de baja esta cuenta?'), findsOneWidget);
    expect(servicio.resueltos, isEmpty);
  });

  testWidgets('confirmar la baja resuelve con userSuspended', (tester) async {
    final servicio =
        await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    await tester.tap(find.text('Dar de baja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, dar de baja'));
    await tester.pumpAndSettle();

    expect(servicio.resueltos, hasLength(1));
    expect(servicio.resueltos.first.id, 'r1');
    expect(servicio.resueltos.first.status, 'actioned');
    expect(servicio.resueltos.first.action, 'userSuspended');
  });

  testWidgets('cancelar la confirmacion no resuelve nada', (tester) async {
    final servicio =
        await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    await tester.tap(find.text('Dar de baja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(servicio.resueltos, isEmpty);
  });

  testWidgets('la fila marca el reporte como MIRADO al renderizarse',
      (tester) async {
    // Listar no es mirar. El servidor dejó de estampar `firstViewedAt` al
    // traer la página: marcarlos todos ahí —incluidos los que el ListView
    // perezoso ni renderiza— dejaba a `moderationStats` contándolos dentro del
    // plazo PARA SIEMPRE, y el tablero podía declarar cumplimiento sin que
    // nadie hubiera leído nada.
    final servicio =
        await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    expect(servicio.marcados, ['r1']);
  });

  testWidgets('no vuelve a marcar uno que ya fue mirado', (tester) async {
    final yaVisto = PendingReport.fromMap({
      'id': 'r1',
      'targetKind': 'post',
      'reason': 'harassment',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'firstViewedAt': DateTime.now().toUtc().toIso8601String(),
    });
    final servicio =
        await montar(tester, esModerador: true, reportes: [yaVisto]);

    expect(servicio.marcados, isEmpty);
  });

  testWidgets('una cola INCOMPLETA no se dice igual que una vacía',
      (tester) async {
    // El servidor escanea hasta un tope y avisa cuando lo alcanza. Decir «no
    // hay reportes esperando» sobre una lista cortada es afirmar que no hay
    // nada cuando lo que pasó es que dejamos de buscar — y esos reportes
    // quedarían invisibles en cada refresco.
    await montar(tester, esModerador: true, incompleta: true);

    expect(find.textContaining('No hay reportes esperando'), findsNothing);
    expect(find.textContaining('No pudimos terminar'), findsOneWidget);
  });

  testWidgets('con resultados incompletos lo avisa al pie', (tester) async {
    await montar(
      tester,
      esModerador: true,
      reportes: [_reporte(id: 'r1')],
      incompleta: true,
    );

    expect(find.textContaining('La lista está incompleta'), findsOneWidget);
  });

  testWidgets('la cola vacia lo dice, no queda en blanco', (tester) async {
    await montar(tester, esModerador: true);

    expect(find.textContaining('No hay reportes esperando'), findsOneWidget);
  });

  testWidgets('si la cola no abre, ofrece reintentar', (tester) async {
    // Un error de red que deja la pantalla en blanco es indistinguible de
    // "no hay nada", y esa confusion es justo la que la cola existe para no
    // tener.
    await montar(tester, esModerador: true, explota: true);

    expect(find.textContaining('No pudimos abrir la cola'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('la tarjeta dice quién escribió el contenido', (tester) async {
    // Mostraba la ruta, el motivo, el tipo y el detalle — nunca a quién se le
    // da de baja, que es la única de las cuatro acciones irreversible desde
    // acá. Van el nombre y el uid: el nombre para reconocer, el uid porque
    // dos cuentas pueden llamarse igual y es lo que se pega en la consola.
    await montar(tester, esModerador: true, reportes: [
      _reporte(id: 'r1', derivedOwnerUid: 'uid-real', derivedOwnerName: 'Juan'),
    ]);

    expect(find.textContaining('Juan'), findsOneWidget);
    expect(find.textContaining('uid-real'), findsOneWidget);
  });

  testWidgets('sin autor derivado lo dice, y NO cae al uid declarado',
      (tester) async {
    // `targetOwnerUid` lo escribe quien denuncia y nada lo ata al autor real.
    // Mostrarlo bajo la etiqueta "Autor" en la pantalla donde alguien aprieta
    // "Dar de baja" sería peor que no mostrar nada.
    await montar(tester, esModerador: true, reportes: [
      _reporte(id: 'r1', derivedOwnerUid: null),
    ]);

    expect(find.textContaining('No pudimos derivar el autor'), findsOneWidget);
    expect(find.textContaining('Autor: o1'), findsNothing);
  });

  testWidgets('el uid declarado que no coincide se ve en la tarjeta',
      (tester) async {
    // Es señal de intento de abuso: se denuncia contenido de uno escribiendo
    // el uid de otro. Hasta ahora eso sólo iba a un `logger.warn` de Cloud
    // Logging — invisible para quien aprieta el botón irreversible.
    await montar(tester, esModerador: true, reportes: [
      _reporte(id: 'r1', derivedOwnerUid: 'otro-uid'),
    ]);

    expect(find.textContaining('declaró otro uid'), findsOneWidget);
    expect(find.textContaining('(o1)'), findsOneWidget);
  });

  testWidgets(
      'sin mismatch no hay aviso: una alarma que grita siempre se ignora',
      (tester) async {
    await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    expect(find.textContaining('declaró otro uid'), findsNothing);
  });

  testWidgets('una acción ya ejecutada se avisa, en castellano',
      (tester) async {
    // El reporte vuelve a la cola cuando la mutación entró y el cierre no.
    // Antes volvía mudo y el siguiente moderador lo descartaba: dismissed/none
    // escrito sobre una cuenta dada de baja.
    await montar(tester, esModerador: true, reportes: [
      _reporte(id: 'r1', attemptedAction: 'userSuspended'),
    ]);

    expect(find.textContaining('dar de baja la cuenta'), findsOneWidget);
    // El identificador del contrato no se le muestra a quien decide.
    expect(find.textContaining('userSuspended'), findsNothing);
  });

  testWidgets('sin intento previo, la tarjeta no avisa nada', (tester) async {
    await montar(tester, esModerador: true, reportes: [_reporte(id: 'r1')]);

    expect(find.textContaining('no llegó a cerrarse'), findsNothing);
  });

  testWidgets('la confirmación de baja dice a QUIÉN se da de baja',
      (tester) async {
    // Preguntar "¿dar de baja esta cuenta?" sin decir cuál convierte la
    // confirmación en un trámite: el paso existe para que alguien pueda
    // frenar, y no se puede frenar lo que no se ve.
    await montar(tester, esModerador: true, reportes: [
      _reporte(id: 'r1', derivedOwnerUid: 'uid-real', derivedOwnerName: 'Juan'),
    ]);

    await tester.tap(find.text('Dar de baja'));
    await tester.pumpAndSettle();

    expect(find.text('¿Dar de baja esta cuenta?'), findsOneWidget);
    // Dos: el de la tarjeta de atrás y el del sheet.
    expect(find.textContaining('uid-real'), findsNWidgets(2));
  });

  testWidgets(
      'la confirmación también muestra el uid declarado que no coincide',
      (tester) async {
    await montar(tester, esModerador: true, reportes: [
      _reporte(id: 'r1', derivedOwnerUid: 'otro-uid'),
    ]);

    await tester.tap(find.text('Dar de baja'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('La baja se ejecuta sobre el autor real'),
      findsOneWidget,
    );
  });
}
