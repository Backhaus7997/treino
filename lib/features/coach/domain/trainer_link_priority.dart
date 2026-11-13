import 'trainer_link.dart';
import 'trainer_link_status.dart';

/// Cuál de varios vínculos NO terminados es "EL vínculo" del alumno (#1735).
///
/// Orden: `active` > `paused` > `pending` > el resto. Dentro del mismo estado
/// gana el más reciente (`requestedAt`).
///
/// Existe porque la lista llega ordenada por `requestedAt DESC` y tomar
/// `.first` da el vínculo más NUEVO, no el más importante. Con dos solicitudes
/// `pending` al mismo PF (dos dispositivos) y la VIEJA aceptada, la lista es
/// `[pending nueva, active vieja]`: `.first` esconde el vínculo activo y la
/// tab Coach dibuja «SOLICITUD ENVIADA» a un alumno que ya entrena.
///
/// Pura y sin orden implícito: no depende de cómo venga la lista.
TrainerLink? vinculoPrioritario(Iterable<TrainerLink> links) {
  TrainerLink? mejor;
  for (final link in links) {
    if (mejor == null || _gana(link, mejor)) mejor = link;
  }
  return mejor;
}

bool _gana(TrainerLink candidato, TrainerLink actual) {
  final a = _rango(candidato.status);
  final b = _rango(actual.status);
  if (a != b) return a < b;
  return candidato.requestedAt.isAfter(actual.requestedAt);
}

/// Menor = más importante.
int _rango(TrainerLinkStatus status) => switch (status) {
      TrainerLinkStatus.active => 0,
      TrainerLinkStatus.paused => 1,
      TrainerLinkStatus.pending => 2,
      TrainerLinkStatus.terminated => 3,
    };
