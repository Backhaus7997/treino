import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/moderacion/moderacion_screen.dart';
import 'package:treino/features/moderation/application/moderation_queue_providers.dart';
import 'package:treino/features/moderation/data/moderation_queue_service.dart';
import 'package:treino/features/moderation/domain/moderation_stats.dart';
import 'package:treino/features/moderation/domain/pending_report.dart';

/// Doble del servicio. Registra lo que se le pidio resolver.
///
/// `implements` y no `extends`: el constructor real pide un
/// `FirebaseFunctions`, y tocar `FirebaseFunctions.instance` en un test sin
/// Firebase inicializado tira `FirebaseException` antes de llegar a medir
/// nada. Implementando el contrato no hay super al que llamar.
class _ServicioFalso implements ModerationQueueService {
  _ServicioFalso({required this.reportes, this.explota = false});

  final List<PendingReport> reportes;
  final bool explota;
  final List<({String id, String status, String action})> resueltos = [];

  @override
  Future<List<PendingReport>> listPending({int limit = 50}) async {
    if (explota) throw Exception('sin red');
    return reportes;
  }

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

PendingReport _reporte({required String id, int horas = 2}) =>
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
    });

void main() {
  Future<_ServicioFalso> montar(
    WidgetTester tester, {
    required bool esModerador,
    List<PendingReport> reportes = const [],
    bool explota = false,
  }) async {
    final servicio = _ServicioFalso(reportes: reportes, explota: explota);
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
}
