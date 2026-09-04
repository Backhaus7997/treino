import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/deep_link_destination.dart';
import 'package:treino/features/coach/domain/trainer_invite_link.dart';

void main() {
  test('el link que se arma es el que el parser entiende', () {
    // Las DOS mitades del contrato, clavadas sobre el mismo literal. Es el
    // test que evita el modo de falla más caro de un deep link: generar links
    // que del otro lado no resuelven, y enterarse por un alumno que no pudo
    // vincularse.
    final link = buildTrainerInviteLink('pf-123')!;
    final destino = DeepLinkDestination.fromQuery(Uri.parse(link).queryParameters);

    expect(destino, isNotNull);
    expect(destino!.to, DeepLinkTo.invitacion);
    expect(destino.trainerId, 'pf-123');
  });

  test('cuelga de /abrir, que es lo que las tiendas tienen registrado', () {
    // Si esto cambia hay que re-registrar universal links en Apple y Google:
    // `apple-app-site-association` y el `intent-filter` sólo reclaman
    // `/abrir/*`. Un path fuera de ahí abre el navegador, no la app.
    final uri = Uri.parse(buildTrainerInviteLink('pf-123')!);

    expect(uri.scheme, 'https');
    expect(uri.host, 'app.gettreino.com');
    expect(uri.path, startsWith('/abrir/'));
  });

  test('sin PF no hay link', () {
    // Mejor no ofrecer nada para copiar que ofrecer algo que no resuelve.
    expect(buildTrainerInviteLink(''), isNull);
    expect(buildTrainerInviteLink('   '), isNull);
  });

  test('el uid se escapa: no lo pega crudo en la query', () {
    final uri = Uri.parse(buildTrainerInviteLink('a b&to=facturacion')!);

    // Sin escapar, ese `&to=` inyectaba un segundo destino en el mismo link.
    expect(uri.queryParameters['pf'], 'a b&to=facturacion');
    expect(uri.queryParameters['to'], 'invitacion');
  });
}
