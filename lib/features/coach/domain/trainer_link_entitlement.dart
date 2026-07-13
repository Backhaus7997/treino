import 'package:json_annotation/json_annotation.dart';

/// Derecho de uso del vínculo PF ↔ atleta (paywall Fase 7, PR1).
///
/// Ortogonal a [TrainerLinkStatus] (ADR-1, design paywall-profes-fase7 §1.3):
/// `status` es el ciclo de vida del vínculo (accept/decline/terminate);
/// `entitlement` es el overlay de paywall. Un vínculo puede estar
/// `status: active` y `entitlement: blocked` simultáneamente (excedente
/// bloqueado por falta de pago del PF, ver design §6).
///
/// Un vínculo es plenamente operativo solo si `status == active &&
/// entitlement == entitled`.
///
/// Default-absent ⇒ `entitled`: sin backfill, todos los vínculos existentes
/// decodifican como entitled (design §7).
enum TrainerLinkEntitlement {
  @JsonValue('entitled')
  entitled,
  @JsonValue('blocked')
  blocked,
}

extension TrainerLinkEntitlementX on TrainerLinkEntitlement {
  String toJson() => switch (this) {
        TrainerLinkEntitlement.entitled => 'entitled',
        TrainerLinkEntitlement.blocked => 'blocked',
      };

  static TrainerLinkEntitlement fromJson(String? value) => switch (value) {
        'entitled' => TrainerLinkEntitlement.entitled,
        'blocked' => TrainerLinkEntitlement.blocked,
        // Default-absent / valor desconocido ⇒ entitled (sin backfill).
        _ => TrainerLinkEntitlement.entitled,
      };
}
