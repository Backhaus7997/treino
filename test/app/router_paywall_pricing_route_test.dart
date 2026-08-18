// El modal del paywall (`showPlanLimitPaywall`) se dispara TAMBIEN desde la app
// movil: `TrainerDashboardTab` (home del PF) y `trainer_coach_view` viven en
// lib/features/coach/, no en el Coach Hub web. Su CTA "VER PLANES" hace
// context.push('/facturacion/planes').
//
// Esa ruta existia SOLO en el router del Coach Hub. En movil el push caia en el
// errorBuilder (NotFoundScreen): el modal decia lo correcto y el boton no
// llevaba a ningun lado. Este test pinea que la ruta este registrada en el
// router movil, para que un refactor no la vuelva a dejar afuera.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/router.dart';

Iterable<String> _paths(List<RouteBase> routes) sync* {
  for (final r in routes) {
    if (r is GoRoute) yield r.path;
    yield* _paths(r.routes);
  }
}

void main() {
  test('el router movil registra /facturacion/planes (CTA del paywall)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );

    expect(
      _paths(router.configuration.routes),
      contains('/facturacion/planes'),
      reason: 'sin esta ruta, "VER PLANES" del paywall muere en NotFoundScreen '
          'en toda la app movil',
    );
  });
}
