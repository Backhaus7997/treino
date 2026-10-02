// Las claves `planLimit*` — los textos de la forma MÓVIL de los TRES avisos de
// tope del PF (alumnos, ejercicios propios, plantillas).
//
// Los widget tests de `plan_limit_paywall_test.dart`,
// `trainer_limit_notice_test.dart` y
// `avisos_de_tope_movil_sin_llamado_a_comprar_test.dart` ejercitan estas
// claves DESDE la pantalla, pero no llegan a todas: hay ramas que las tablas
// de hoy no dejan alcanzar (el beneficio «Hasta N plantillas», el `=1` de un
// plural que la UI nunca dispara). Este archivo las mira directo, en las dos
// lenguas.
//
// Historia (hallazgo Codex, PR #1266): la unificación de los tres avisos había
// hardcodeado en castellano los textos móviles de ejercicios propios y
// plantillas y borrado sus claves de `intl_en.arb`. Lo que se pinea acá es lo
// que hubiera atajado eso: que CADA clave exista en inglés, con texto propio
// (no vacío, no el castellano copiado), y que los plurales anden.
//
// Ojo: `resolveLocale` (ADR-I18N-005) fuerza es_AR en producción, así que el
// inglés hoy sólo se ve con un Locale explícito. Estos tests son lo que
// garantiza que esté cuando se levante esa traba.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Cada clave `planLimit*`, con argumentos de muestra. Si se suma una clave al
/// ARB y no entra acá, el test de completitud se pone rojo.
final Map<String, String Function(AppL10n l)> _claves = {
  'planLimitVerPlanesMovil': (l) => l.planLimitVerPlanesMovil,
  'planLimitEntendido': (l) => l.planLimitEntendido,
  'planLimitPorMes': (l) => l.planLimitPorMes,
  'planLimitPlanAMedidaTitulo': (l) => l.planLimitPlanAMedidaTitulo,
  'planLimitContactanos': (l) => l.planLimitContactanos,
  'planLimitAlumnosTituloTope': (l) => l.planLimitAlumnosTituloTope,
  'planLimitAlumnosTituloInactiva': (l) => l.planLimitAlumnosTituloInactiva,
  'planLimitAlumnosTituloBaja': (l) => l.planLimitAlumnosTituloBaja,
  'planLimitAlumnosCuerpoInactivaExplicacion': (l) =>
      l.planLimitAlumnosCuerpoInactivaExplicacion,
  'planLimitAlumnosCuerpoTopeMovilLimitado': (l) =>
      l.planLimitAlumnosCuerpoTopeMovilLimitado('Plan 1', 3),
  'planLimitAlumnosCuerpoTopeMovilIlimitado': (l) =>
      l.planLimitAlumnosCuerpoTopeMovilIlimitado('Plan 1'),
  'planLimitAlumnosPlanAMedidaCuerpo': (l) =>
      l.planLimitAlumnosPlanAMedidaCuerpo,
  'planLimitAlumnosPlanAMedidaSnack': (l) => l.planLimitAlumnosPlanAMedidaSnack,
  'planLimitReactivateTituloMovil': (l) =>
      l.planLimitReactivateTituloMovil('Plan 1'),
  'planLimitReactivateCuerpoMovil': (l) => l.planLimitReactivateCuerpoMovil(5),
  'planLimitVerEstadoMovil': (l) => l.planLimitVerEstadoMovil,
  'planLimitReactivateEstadoMovil': (l) =>
      l.planLimitReactivateEstadoMovil('paused'),
  'planLimitEstadoActiva': (l) => l.planLimitEstadoActiva,
  'planLimitEstadoPendiente': (l) => l.planLimitEstadoPendiente,
  'planLimitEstadoGracia': (l) => l.planLimitEstadoGracia,
  'planLimitEstadoPausada': (l) => l.planLimitEstadoPausada,
  'planLimitEstadoCancelada': (l) => l.planLimitEstadoCancelada,
  'planLimitAlumnosBeneficioLimitado': (l) =>
      l.planLimitAlumnosBeneficioLimitado(3),
  'planLimitAlumnosBeneficioIlimitado': (l) =>
      l.planLimitAlumnosBeneficioIlimitado,
  'planLimitSuscripcionPausadaMovil': (l) => l.planLimitSuscripcionPausadaMovil,
  'planLimitSuscripcionBajaMovil': (l) => l.planLimitSuscripcionBajaMovil,
  'planLimitTrainerTituloEjercicios': (l) => l.planLimitTrainerTituloEjercicios,
  'planLimitTrainerTituloPlantillas': (l) => l.planLimitTrainerTituloPlantillas,
  'planLimitTrainerPasadoTopeEjercicios': (l) =>
      l.planLimitTrainerPasadoTopeEjercicios(5, 3, 2),
  'planLimitTrainerPasadoTopePlantillas': (l) =>
      l.planLimitTrainerPasadoTopePlantillas(5, 3, 2),
  'planLimitTrainerInactivaEjercicios': (l) =>
      l.planLimitTrainerInactivaEjercicios('Plan 1', 'Free', 3),
  'planLimitTrainerInactivaPlantillas': (l) =>
      l.planLimitTrainerInactivaPlantillas('Plan 1', 'Free', 3),
  'planLimitTrainerTopeEjerciciosConTier': (l) =>
      l.planLimitTrainerTopeEjerciciosConTier('Plan 1', 3),
  'planLimitTrainerTopeEjerciciosGenerico': (l) =>
      l.planLimitTrainerTopeEjerciciosGenerico(3),
  'planLimitTrainerTopePlantillasConTier': (l) =>
      l.planLimitTrainerTopePlantillasConTier('Plan 1', 3),
  'planLimitTrainerTopePlantillasGenerico': (l) =>
      l.planLimitTrainerTopePlantillasGenerico(3),
  'planLimitTrainerBeneficioEjerciciosLimitado': (l) =>
      l.planLimitTrainerBeneficioEjerciciosLimitado(3),
  'planLimitTrainerBeneficioEjerciciosIlimitado': (l) =>
      l.planLimitTrainerBeneficioEjerciciosIlimitado,
  'planLimitTrainerBeneficioPlantillasLimitado': (l) =>
      l.planLimitTrainerBeneficioPlantillasLimitado(3),
  'planLimitTrainerBeneficioPlantillasIlimitado': (l) =>
      l.planLimitTrainerBeneficioPlantillasIlimitado,
  'planLimitTrainerPlanAMedidaCuerpo': (l) =>
      l.planLimitTrainerPlanAMedidaCuerpo,
};

/// Una llamada, y lo que tiene que salir en cada lengua.
typedef _Caso = ({
  String nombre,
  String Function(AppL10n l) llamar,
  String es,
  String en,
});

/// Los dos lados de cada plural (`=1` y `other`) de las claves que lo tienen,
/// más el borde `0` donde importa. El castellano es el que aprobó el dueño y
/// NO cambia; el inglés es su traducción.
final List<_Caso> _plurales = [
  // ── Alumnos ──
  (
    nombre: 'alumnos, cuerpo del tope: 1',
    llamar: (l) => l.planLimitAlumnosCuerpoTopeMovilLimitado('Free', 1),
    es: 'Tu plan Free incluye 1 alumno.',
    en: 'Your Free plan includes 1 student.',
  ),
  (
    nombre: 'alumnos, cuerpo del tope: 7',
    llamar: (l) => l.planLimitAlumnosCuerpoTopeMovilLimitado('Plan 1', 7),
    es: 'Tu plan Plan 1 incluye 7 alumnos.',
    en: 'Your Plan 1 plan includes 7 students.',
  ),
  (
    nombre: 'alumnos, caja de estado: 1',
    llamar: (l) => l.planLimitReactivateCuerpoMovil(1),
    es: 'No está activa. Mientras tanto, tu cuenta tiene el límite del plan '
        'Free: 1 alumno.',
    en: "It isn't active. Meanwhile, your account has the Free plan limit: "
        '1 student.',
  ),
  (
    nombre: 'alumnos, caja de estado: 2',
    llamar: (l) => l.planLimitReactivateCuerpoMovil(2),
    es: 'No está activa. Mientras tanto, tu cuenta tiene el límite del plan '
        'Free: 2 alumnos.',
    en: "It isn't active. Meanwhile, your account has the Free plan limit: "
        '2 students.',
  ),
  (
    nombre: 'alumnos, beneficio: 1',
    llamar: (l) => l.planLimitAlumnosBeneficioLimitado(1),
    es: 'Hasta 1 alumno',
    en: 'Up to 1 student',
  ),
  (
    nombre: 'alumnos, beneficio: 15',
    llamar: (l) => l.planLimitAlumnosBeneficioLimitado(15),
    es: 'Hasta 15 alumnos',
    en: 'Up to 15 students',
  ),
  // ── Ejercicios propios ──
  (
    nombre: 'ejercicios, pasado de tope: count 1 (límite 0)',
    llamar: (l) => l.planLimitTrainerPasadoTopeEjercicios(1, 0, 2),
    es: 'Tenés 1 ejercicio propio y tu plan incluye 0. Conservás todos; para '
        'crear uno nuevo, borrá 2.',
    en: 'You have 1 custom exercise and your plan includes 0. You keep them '
        'all; to create a new one, delete 2.',
  ),
  (
    nombre: 'ejercicios, pasado de tope: count 80',
    llamar: (l) => l.planLimitTrainerPasadoTopeEjercicios(80, 60, 21),
    es: 'Tenés 80 ejercicios propios y tu plan incluye 60. Conservás todos; '
        'para crear uno nuevo, borrá 21.',
    en: 'You have 80 custom exercises and your plan includes 60. You keep '
        'them all; to create a new one, delete 21.',
  ),
  (
    nombre: 'ejercicios, inactiva: límite 1',
    llamar: (l) => l.planLimitTrainerInactivaEjercicios('Plan 1', 'Free', 1),
    es: 'Tu suscripción a Plan 1 no está activa. Mientras tanto, tu plan Free '
        'incluye 1 ejercicio propio.',
    en: "Your Plan 1 subscription isn't active. Meanwhile, your Free plan "
        'includes 1 custom exercise.',
  ),
  (
    nombre: 'ejercicios, inactiva: límite 20',
    llamar: (l) => l.planLimitTrainerInactivaEjercicios('Plan 1', 'Free', 20),
    es: 'Tu suscripción a Plan 1 no está activa. Mientras tanto, tu plan Free '
        'incluye 20 ejercicios propios.',
    en: "Your Plan 1 subscription isn't active. Meanwhile, your Free plan "
        'includes 20 custom exercises.',
  ),
  (
    nombre: 'ejercicios, en el tope con tier: límite 1',
    llamar: (l) => l.planLimitTrainerTopeEjerciciosConTier('Free', 1),
    es: 'Tu plan Free incluye 1 ejercicio propio. Podés editar o borrar los '
        'que ya tenés.',
    en: 'Your Free plan includes 1 custom exercise. You can edit or delete '
        'the ones you already have.',
  ),
  (
    nombre: 'ejercicios, en el tope con tier: límite 20',
    llamar: (l) => l.planLimitTrainerTopeEjerciciosConTier('Free', 20),
    es: 'Tu plan Free incluye 20 ejercicios propios. Podés editar o borrar '
        'los que ya tenés.',
    en: 'Your Free plan includes 20 custom exercises. You can edit or delete '
        'the ones you already have.',
  ),
  (
    nombre: 'ejercicios, en el tope genérico: límite 1',
    llamar: (l) => l.planLimitTrainerTopeEjerciciosGenerico(1),
    es: 'Tu plan incluye 1 ejercicio propio. Podés editar o borrar los que ya '
        'tenés.',
    en: 'Your plan includes 1 custom exercise. You can edit or delete the '
        'ones you already have.',
  ),
  (
    nombre: 'ejercicios, en el tope genérico: límite 0',
    llamar: (l) => l.planLimitTrainerTopeEjerciciosGenerico(0),
    es: 'Tu plan incluye 0 ejercicios propios. Podés editar o borrar los que '
        'ya tenés.',
    en: 'Your plan includes 0 custom exercises. You can edit or delete the '
        'ones you already have.',
  ),
  (
    nombre: 'ejercicios, beneficio: 1',
    llamar: (l) => l.planLimitTrainerBeneficioEjerciciosLimitado(1),
    es: 'Hasta 1 ejercicio propio',
    en: 'Up to 1 custom exercise',
  ),
  (
    nombre: 'ejercicios, beneficio: 60',
    llamar: (l) => l.planLimitTrainerBeneficioEjerciciosLimitado(60),
    es: 'Hasta 60 ejercicios propios',
    en: 'Up to 60 custom exercises',
  ),
  // ── Plantillas ──
  (
    nombre: 'plantillas, pasado de tope: count 1 (límite 0)',
    llamar: (l) => l.planLimitTrainerPasadoTopePlantillas(1, 0, 2),
    es: 'Tenés 1 plantilla y tu plan incluye 0. Conservás todas; para crear '
        'una nueva, archivá 2.',
    en: 'You have 1 template and your plan includes 0. You keep them all; to '
        'create a new one, archive 2.',
  ),
  (
    nombre: 'plantillas, pasado de tope: count 5',
    llamar: (l) => l.planLimitTrainerPasadoTopePlantillas(5, 3, 3),
    es: 'Tenés 5 plantillas y tu plan incluye 3. Conservás todas; para crear '
        'una nueva, archivá 3.',
    en: 'You have 5 templates and your plan includes 3. You keep them all; to '
        'create a new one, archive 3.',
  ),
  (
    nombre: 'plantillas, inactiva: límite 1',
    llamar: (l) => l.planLimitTrainerInactivaPlantillas('Plan 1', 'Free', 1),
    es: 'Tu suscripción a Plan 1 no está activa. Mientras tanto, tu plan Free '
        'incluye 1 plantilla.',
    en: "Your Plan 1 subscription isn't active. Meanwhile, your Free plan "
        'includes 1 template.',
  ),
  (
    nombre: 'plantillas, inactiva: límite 3',
    llamar: (l) => l.planLimitTrainerInactivaPlantillas('Plan 1', 'Free', 3),
    es: 'Tu suscripción a Plan 1 no está activa. Mientras tanto, tu plan Free '
        'incluye 3 plantillas.',
    en: "Your Plan 1 subscription isn't active. Meanwhile, your Free plan "
        'includes 3 templates.',
  ),
  (
    nombre: 'plantillas, en el tope con tier: límite 1',
    llamar: (l) => l.planLimitTrainerTopePlantillasConTier('Free', 1),
    es: 'Tu plan Free incluye 1 plantilla. Podés editar o archivar las que ya '
        'tenés.',
    en: 'Your Free plan includes 1 template. You can edit or archive the ones '
        'you already have.',
  ),
  (
    nombre: 'plantillas, en el tope con tier: límite 3',
    llamar: (l) => l.planLimitTrainerTopePlantillasConTier('Free', 3),
    es: 'Tu plan Free incluye 3 plantillas. Podés editar o archivar las que '
        'ya tenés.',
    en: 'Your Free plan includes 3 templates. You can edit or archive the '
        'ones you already have.',
  ),
  (
    nombre: 'plantillas, en el tope genérico: límite 1',
    llamar: (l) => l.planLimitTrainerTopePlantillasGenerico(1),
    es: 'Tu plan incluye 1 plantilla. Podés editar o archivar las que ya '
        'tenés.',
    en: 'Your plan includes 1 template. You can edit or archive the ones you '
        'already have.',
  ),
  (
    nombre: 'plantillas, en el tope genérico: límite 10',
    llamar: (l) => l.planLimitTrainerTopePlantillasGenerico(10),
    es: 'Tu plan incluye 10 plantillas. Podés editar o archivar las que ya '
        'tenés.',
    en: 'Your plan includes 10 templates. You can edit or archive the ones '
        'you already have.',
  ),
  // Esta rama no se alcanza desde la UI con las tablas de hoy (sólo Free tiene
  // tope de plantillas y Free nunca es «el siguiente»): por eso se mira acá.
  (
    nombre: 'plantillas, beneficio: 1',
    llamar: (l) => l.planLimitTrainerBeneficioPlantillasLimitado(1),
    es: 'Hasta 1 plantilla',
    en: 'Up to 1 template',
  ),
  (
    nombre: 'plantillas, beneficio: 3',
    llamar: (l) => l.planLimitTrainerBeneficioPlantillasLimitado(3),
    es: 'Hasta 3 plantillas',
    en: 'Up to 3 templates',
  ),
];

void main() {
  late AppL10n es;
  late AppL10n en;

  setUpAll(() async {
    es = await AppL10n.delegate.load(const Locale('es', 'AR'));
    en = await AppL10n.delegate.load(const Locale('en'));
  });

  group('completitud', () {
    test('la tabla de este archivo tiene TODAS las claves planLimit* del ARB',
        () {
      // Se lee el `.arb` plantilla, no el código generado: una clave nueva sin
      // fila acá tiene que avisar, en vez de quedar sin mirar.
      final arb = jsonDecode(File('lib/l10n/intl_es_AR.arb').readAsStringSync())
          as Map<String, dynamic>;
      final delArb = {
        for (final k in arb.keys)
          if (k.startsWith('planLimit')) k,
      };
      expect(delArb, isNotEmpty, reason: 'el ARB no tiene claves planLimit*');
      expect(_claves.keys.toSet(), delArb);
    });
  });

  group('cada clave existe en inglés, con texto propio', () {
    for (final entry in _claves.entries) {
      test(entry.key, () {
        final textoEs = entry.value(es);
        final textoEn = entry.value(en);

        expect(textoEs, isNotEmpty);
        // `intl_en.arb` tiene claves con "" de andamiaje (ADR-I18N-005): un
        // inglés vacío renderiza un aviso en blanco.
        expect(textoEn, isNotEmpty,
            reason: '${entry.key} está vacía en inglés');
        // Y el castellano copiado tampoco es una traducción.
        expect(textoEn, isNot(textoEs),
            reason: '${entry.key} en inglés es idéntica al castellano');
        // Un placeholder mal escrito se cuela como llaves literales.
        for (final texto in [textoEs, textoEn]) {
          for (final residuo in ['{', '}', 'plural']) {
            expect(texto, isNot(contains(residuo)),
                reason: '${entry.key}: «$residuo» sin resolver en «$texto»');
          }
        }
      });
    }
  });

  group('plurales: singular y plural, en las dos lenguas', () {
    for (final caso in _plurales) {
      test('${caso.nombre} — es_AR (el castellano NO cambia)', () {
        expect(caso.llamar(es), caso.es);
      });
      test('${caso.nombre} — en', () {
        expect(caso.llamar(en), caso.en);
      });
    }
  });

  group('sin plural: textos fijos', () {
    test('es_AR — el castellano NO cambia', () {
      expect(es.planLimitVerPlanesMovil, 'VER PLANES');
      expect(es.planLimitEntendido, 'Entendido');
      expect(es.planLimitPorMes, '/mes');
      expect(es.planLimitPlanAMedidaTitulo, 'PLAN A MEDIDA');
      expect(es.planLimitContactanos, 'CONTACTANOS');
      expect(es.planLimitVerEstadoMovil, 'VER ESTADO');
      expect(
          es.planLimitSuscripcionPausadaMovil, 'Tu suscripción está pausada.');
      expect(es.planLimitAlumnosTituloBaja, 'TU SUSCRIPCIÓN ESTÁ DADA DE BAJA');
      expect(es.planLimitSuscripcionBajaMovil,
          'Tu suscripción está dada de baja.');
      expect(es.planLimitTrainerTituloEjercicios, 'TOPE DE EJERCICIOS PROPIOS');
      expect(es.planLimitTrainerTituloPlantillas, 'TOPE DE PLANTILLAS');
      expect(es.planLimitTrainerBeneficioEjerciciosIlimitado,
          'Ejercicios propios sin límite');
      expect(es.planLimitTrainerBeneficioPlantillasIlimitado,
          'Plantillas sin límite');
      expect(
        es.planLimitTrainerPlanAMedidaCuerpo,
        'Estás en el plan más grande. Estamos preparando un plan a tu medida.',
      );
      expect(
        es.planLimitAlumnosPlanAMedidaCuerpo,
        'Estás en el plan más grande. Para más de 15 alumnos estamos '
        'preparando un plan a tu medida.',
      );
      expect(
        es.planLimitAlumnosPlanAMedidaSnack,
        'Muy pronto vas a poder tener más de 15 alumnos.',
      );
    });

    test('en — neutro: nada de upgrade / subscribe / buy / purchase', () {
      expect(en.planLimitVerPlanesMovil, 'VIEW PLANS');
      expect(en.planLimitEntendido, 'Got it');
      expect(en.planLimitPorMes, '/month');
      expect(en.planLimitPlanAMedidaTitulo, 'CUSTOM PLAN');
      expect(en.planLimitContactanos, 'CONTACT US');
      expect(en.planLimitVerEstadoMovil, 'VIEW STATUS');
      expect(en.planLimitAlumnosTituloBaja, 'YOUR SUBSCRIPTION IS CANCELLED');
      expect(
          en.planLimitSuscripcionBajaMovil, 'Your subscription is cancelled.');
      expect(en.planLimitTrainerTituloEjercicios, 'CUSTOM EXERCISE LIMIT');
      expect(en.planLimitTrainerTituloPlantillas, 'TEMPLATE LIMIT');
      expect(en.planLimitTrainerBeneficioEjerciciosIlimitado,
          'Unlimited custom exercises');
      expect(en.planLimitTrainerBeneficioPlantillasIlimitado,
          'Unlimited templates');
    });
  });
}
