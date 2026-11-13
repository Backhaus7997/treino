// `followedTemplateProvider`: ¿el atleta sigue una plantilla del catálogo sin
// haberla copiado? (#1698)
//
// Seguir una plantilla sólo escribe `users/{uid}.activeRoutineId`; no crea
// ningún doc del atleta. Home usa esta mirada para no darle la bienvenida de
// «no tenés rutina» a quien ya está entrenando una.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/home/application/followed_template_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routinesProvider;
import 'package:treino/features/workout/domain/routine.dart';

UserProfile _profile({String? activeRoutineId}) => UserProfile(
      uid: 'u1',
      email: 'u1@test.com',
      displayName: 'Martín',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
      activeRoutineId: activeRoutineId,
    );

Routine _plantilla(String id) => Routine(
      id: id,
      name: 'Plantilla $id',
      level: ExperienceLevel.beginner,
      days: const [],
    );

ProviderContainer _container({
  String? activeRoutineId,
  required Future<List<Routine>> Function() catalog,
  void Function()? onCatalogRead,
}) {
  final c = ProviderContainer(
    overrides: [
      userProfileProvider.overrideWith(
        (ref) => Stream.value(_profile(activeRoutineId: activeRoutineId)),
      ),
      routinesProvider.overrideWith((ref) {
        onCatalogRead?.call();
        return catalog();
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Mantiene vivo el provider (es autoDispose) y deja que el perfil emita.
Future<AsyncValue<Routine?>> _resolver(ProviderContainer c) async {
  c.listen(followedTemplateProvider, (_, __) {});
  await c.read(userProfileProvider.future);
  // El catálogo (si se lee) es un Future: un par de turnos del event loop
  // alcanzan para que resuelva.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return c.read(followedTemplateProvider);
}

void main() {
  test('sin marcador → AsyncData(null) y NO lee el catálogo', () async {
    var lecturas = 0;
    final c = _container(
      catalog: () async => [_plantilla('tpl-1')],
      onCatalogRead: () => lecturas++,
    );

    final r = await _resolver(c);

    expect(r.hasValue, isTrue);
    expect(r.value, isNull);
    expect(lecturas, 0, reason: 'el atleta nuevo no paga la lectura');
  });

  test('marcador vacío se trata igual que ausente', () async {
    var lecturas = 0;
    final c = _container(
      activeRoutineId: '',
      catalog: () async => [_plantilla('tpl-1')],
      onCatalogRead: () => lecturas++,
    );

    final r = await _resolver(c);

    expect(r.value, isNull);
    expect(lecturas, 0);
  });

  test('marcador = plantilla del catálogo → esa plantilla', () async {
    final c = _container(
      activeRoutineId: 'tpl-2',
      catalog: () async => [_plantilla('tpl-1'), _plantilla('tpl-2')],
    );

    final r = await _resolver(c);

    expect(r.value?.id, 'tpl-2');
  });

  test('marcador que NO es del catálogo (propia, del PF u obsoleto) → null',
      () async {
    final c = _container(
      activeRoutineId: 'mia-1',
      catalog: () async => [_plantilla('tpl-1')],
    );

    final r = await _resolver(c);

    expect(r.hasValue, isTrue);
    expect(r.value, isNull);
  });

  test('catálogo cargando → loading, no «no sigue ninguna»', () async {
    final pendiente = Completer<List<Routine>>();
    final c = _container(
      activeRoutineId: 'tpl-1',
      catalog: () => pendiente.future,
    );

    final r = await _resolver(c);

    expect(r.isLoading, isTrue);
  });

  test('catálogo con error → error, no «no sigue ninguna»', () async {
    final c = _container(
      activeRoutineId: 'tpl-1',
      catalog: () async => throw StateError('sin red'),
    );

    final r = await _resolver(c);

    expect(r.hasError, isTrue);
  });
}
