// Borrar los filtros de EXPLORAR = borrar las respuestas guardadas del
// cuestionario (`users/{uid}.templatePreferences`), y poder restaurarlas.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/template_preferences_providers.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';

const _uid = 'athlete-1';
const _prefs = TemplatePreferences(
  daysPerWeek: 3,
  minutesPerSession: 30,
  goals: [RoutineGoal.health],
  priorityMuscleGroups: ['glutes'],
);

UserProfile _perfil(TemplatePreferences? p) => UserProfile(
      uid: _uid,
      email: 'a@t.com',
      displayName: 'A',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      templatePreferences: p,
    );

void main() {
  late FakeFirebaseFirestore db;
  late ProviderContainer c;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(_uid).set({
      'templatePreferences': _prefs.toJson(),
    });
    c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      userProfileProvider.overrideWith((ref) => Stream.value(_perfil(_prefs))),
    ]);
    c.listen(userProfileProvider, (_, __) {});
    await c.read(userProfileProvider.future);
  });
  tearDown(() => c.dispose());

  Future<Object?> guardado() async =>
      (await db.collection('users').doc(_uid).get())
          .data()?['templatePreferences'];

  test('clear() borra las respuestas guardadas', () async {
    final ok = await c.read(templatePreferencesControllerProvider).clear();
    expect(ok, isTrue);
    expect(await guardado(), isNull);
  });

  test('save() las restaura (el DESHACER del aviso)', () async {
    final ctrl = c.read(templatePreferencesControllerProvider);
    await ctrl.clear();
    await ctrl.save(_prefs);
    expect(
      TemplatePreferences.fromJson(
        Map<String, Object?>.from((await guardado())! as Map),
      ),
      _prefs,
    );
  });

  test('clear() sin perfil cargado no escribe y devuelve false', () async {
    final vacio = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      userProfileProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(vacio.dispose);
    expect(await vacio.read(templatePreferencesControllerProvider).clear(),
        isFalse);
    expect(await guardado(), isNotNull);
  });

  test('el campo se borra del documento, no queda en null', () async {
    await c.read(templatePreferencesControllerProvider).clear();
    final doc = await db.collection('users').doc(_uid).get();
    expect(doc.data()!.containsKey('templatePreferences'), isFalse);
  });
}
