import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/moderation/domain/content_report.dart';
import 'package:treino/features/moderation/domain/report_reason.dart';
import 'package:treino/features/moderation/domain/report_target_kind.dart';

ContentReport _report({
  ReportTargetKind targetKind = ReportTargetKind.post,
  String targetId = 'post-1',
  String reporterUid = 'u1',
  String targetOwnerUid = 'u2',
  ReportReason reason = ReportReason.harassment,
  String? detail,
}) =>
    ContentReport(
      id: ContentReport.idFor(targetKind, targetId, reporterUid),
      reporterUid: reporterUid,
      targetKind: targetKind,
      targetId: targetId,
      targetOwnerUid: targetOwnerUid,
      reason: reason,
      detail: detail,
      createdAt: DateTime.utc(2026, 9, 1),
    );

void main() {
  group('ContentReport.idFor', () {
    test('es {targetKind}_{targetId}_{reporterUid}', () {
      expect(
        ContentReport.idFor(ReportTargetKind.post, 'p1', 'u1'),
        'post_p1_u1',
      );
    });

    // El uid de quien reporta es PARTE del id — el mismo reporter no puede
    // generar dos ids distintos para el mismo target, así que reportar dos
    // veces pisa el mismo doc (idempotente, sin contador). Y nadie puede
    // construir el id con el reporterUid de otra persona sin que
    // `reporterUid == request.auth.uid` (firestore.rules) lo rechace.
    test('reportar dos veces el mismo target da el MISMO id', () {
      final first = ContentReport.idFor(ReportTargetKind.review, 'r1', 'u1');
      final second = ContentReport.idFor(ReportTargetKind.review, 'r1', 'u1');
      expect(first, second);
    });

    test('reporters distintos sobre el mismo target dan ids distintos', () {
      final a = ContentReport.idFor(ReportTargetKind.review, 'r1', 'u1');
      final b = ContentReport.idFor(ReportTargetKind.review, 'r1', 'u2');
      expect(a, isNot(b));
    });
  });

  group('ContentReport — forma del documento', () {
    // REGRESIÓN: firestore.rules valida `create` de `reports` con
    // hasOnly(['reporterUid', 'targetKind', 'targetId', 'targetOwnerUid',
    // 'reason', 'detail', 'createdAt']) — SIN `id`. Si `toJson()` incluyera
    // `id`, ReportRepository.report() escribiría una key de más y el write
    // se rechazaría siempre con PERMISSION_DENIED.
    test('toJson() NO incluye "id" (firestore.rules: hasOnly sin id)', () {
      final json = _report().toJson();
      expect(json.containsKey('id'), isFalse);
      expect(
        json.keys.toSet(),
        {
          'reporterUid',
          'targetKind',
          'targetId',
          'targetOwnerUid',
          'reason',
          'detail',
          'createdAt',
        },
      );
    });

    // Los literales de wire tienen que coincidir EXACTO con las listas
    // permitidas de firestore.rules (`targetKind in [...]` / `reason in
    // [...]`) — un typo acá pasa el analyzer y el build_runner y sólo se ve
    // como PERMISSION_DENIED en producción.
    test('targetKind serializa con los literales que aceptan las reglas', () {
      const expected = {
        ReportTargetKind.post: 'post',
        ReportTargetKind.message: 'message',
        ReportTargetKind.review: 'review',
        ReportTargetKind.profile: 'profile',
      };
      for (final entry in expected.entries) {
        final json = _report(targetKind: entry.key).toJson();
        expect(json['targetKind'], entry.value);
      }
    });

    test('reason serializa con los literales que aceptan las reglas', () {
      const expected = {
        ReportReason.harassment: 'harassment',
        ReportReason.sexualContent: 'sexualContent',
        ReportReason.violenceOrSelfHarm: 'violenceOrSelfHarm',
        ReportReason.dangerousHealthAdvice: 'dangerousHealthAdvice',
        ReportReason.impersonation: 'impersonation',
        ReportReason.spam: 'spam',
        ReportReason.thirdPartyData: 'thirdPartyData',
        ReportReason.intellectualProperty: 'intellectualProperty',
        ReportReason.other: 'other',
      };
      for (final entry in expected.entries) {
        final json = _report(reason: entry.key).toJson();
        expect(json['reason'], entry.value);
      }
    });

    test('round-trip JSON preserva target, reason y detail', () {
      final original = _report(detail: 'contenido explícito en el chat');
      final vuelta = ContentReport.fromJson({
        ...original.toJson(),
        'id': original.id,
      });

      expect(vuelta, original);
      expect(vuelta.detail, 'contenido explícito en el chat');
    });

    test('detail null se preserva como null', () {
      final original = _report();
      final vuelta = ContentReport.fromJson({
        ...original.toJson(),
        'id': original.id,
      });

      expect(vuelta.detail, isNull);
    });
  });
}
