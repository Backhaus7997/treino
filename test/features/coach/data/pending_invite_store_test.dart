import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/features/coach/data/pending_invite_store.dart';

Future<PendingInviteStore> _store([Map<String, Object> inicial = const {}]) async {
  SharedPreferences.setMockInitialValues(inicial);
  return PendingInviteStore(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la invitación sobrevive: se guarda y se lee', () async {
    final s = await _store();
    await s.guardar('pf-1');

    expect(await s.leer(), 'pf-1');
  });

  test('va a DISCO, no a memoria', () async {
    // Es el punto entero de esta clase: hace falta un uid para crear el
    // vínculo, y el uid llega DESPUÉS del login — que rearma todo lo que vive
    // en memoria. Una instancia nueva simula ese renacer.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await PendingInviteStore(prefs).guardar('pf-1');

    final despuesDelLogin = PendingInviteStore(
      await SharedPreferences.getInstance(),
    );
    expect(await despuesDelLogin.leer(), 'pf-1');
  });

  test('limpiar la borra', () async {
    final s = await _store();
    await s.guardar('pf-1');
    await s.limpiar();

    expect(await s.leer(), isNull);
  });

  test('una invitación vieja no reaparece', () async {
    final s = await _store();
    final hace40dias = DateTime(2026).subtract(const Duration(days: 40));
    await s.guardar('pf-1', ahora: hace40dias);

    // Sin caducidad, el alumno que abrió el link, no completó el registro y
    // volvió meses después se encontraba con un PF que ya no tiene nada que
    // ver.
    expect(await s.leer(ahora: DateTime(2026)), isNull);
  });

  test('dentro de la ventana sigue valiendo', () async {
    final s = await _store();
    final hace29dias = DateTime(2026).subtract(const Duration(days: 29));
    await s.guardar('pf-1', ahora: hace29dias);

    expect(await s.leer(ahora: DateTime(2026)), 'pf-1');
  });

  test('leer una caducada la limpia de paso', () async {
    final s = await _store();
    await s.guardar('pf-1', ahora: DateTime(2025));
    await s.leer(ahora: DateTime(2026));

    // Dejarla ocupando lugar hace que la PRÓXIMA invitación compita con ella.
    expect(await s.leer(ahora: DateTime(2025, 1, 2)), isNull);
  });

  test('una guardada sin fecha se descarta', () async {
    // Versión anterior del store. No hay forma de saber de cuándo es, así que
    // asumirla fresca sería inventar.
    final s = await _store({'pending_invite_trainer_id': 'pf-viejo'});

    expect(await s.leer(), isNull);
  });

  test('no guarda una invitación vacía', () async {
    final s = await _store();
    await s.guardar('   ');

    expect(await s.leer(), isNull);
  });
}
