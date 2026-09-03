import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/weekly_streak_calculator.dart';
import '../../home/application/todays_routine_provider.dart';

/// Objetivo de sesiones por semana del atleta logueado — el umbral que una
/// semana tiene que alcanzar para que la racha semanal la cuente.
///
/// Sale de la rutina ACTIVA, resuelta por [todaysRoutineProvider]: ahí vive la
/// cadena de prioridad completa (marcador explícito → plan del PF → única
/// auto-creada), compartida con el cliente watchOS vía
/// `resolveActiveRoutineId` y fijada por los fixtures de
/// `conformance/routine_selection.json`. Reimplementar la resolución acá sería
/// una segunda fuente de verdad de la misma pregunta — y la primera vez que
/// divergieran, el atleta vería un objetivo en Entrenar y otro distinto en su
/// racha.
///
/// Devuelve [weeklyStreakFallbackTarget] mientras la rutina carga, si el
/// atleta no tiene ninguna activa, o si la que tiene es toda días de descanso.
/// Es un `Provider<int>` sincrónico a propósito: durante el loading la racha
/// se calcula contra el fallback en vez de dejar la pantalla en spinner. El
/// número se corrige solo cuando la rutina emite.
///
/// `select` sobre `valueOrNull` mantiene la suscripción acotada al objetivo:
/// que el atleta avance de día dentro de la misma rutina NO recalcula la racha.
final weeklyStreakTargetProvider = Provider.autoDispose<int>((ref) {
  final target = ref.watch(
    todaysRoutineProvider.select(
      (async) => weeklyTargetFromRoutine(async.valueOrNull?.routine),
    ),
  );
  return target;
});
