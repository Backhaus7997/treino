/// La clave de `users/{uid}.notificationPrefs` que gobierna los correos
/// comerciales: `notificationPrefs.novedades_plan.email === false` los frena.
///
/// Vive en TRES lugares y los tres tienen que decir lo mismo:
///
///  - el backend, que la lee para decidir si manda
///    (`ATHLETE_PROSPECT_PREF_KEY` en
///    `functions/src/subscriptions/athlete-prospect-mail.ts`, que importa
///    `free-limit-mail.ts`; `trainer-limit-mail.ts` repite el literal en
///    `TRAINER_LIMIT_PREF_KEY`);
///  - esta constante, con la que la app la escribe;
///  - la landing de baja, que la escribe por el link del pie del correo.
///
/// Si dos de las tres divergen, el interruptor de la app escribe un campo que
/// nadie lee: el usuario apaga los correos y siguen llegando, que es peor que
/// no tener interruptor. Por eso hay un test que lee el `.ts` y compara
/// (`test/features/profile/notification_pref_keys_drift_test.dart`).
///
/// El nombre es del backend y no se toca acá: renombrarla es migrar los
/// documentos de todos los usuarios que ya tengan la preferencia guardada.
const String kPrefCorreosPromocionales = 'novedades_plan';

/// La clave de `users/{uid}.notificationPrefs` que gobierna los recordatorios
/// diarios de entrenamiento (racha en riesgo / volvé a entrenar), que le llegan
/// al ATLETA como push:
/// `notificationPrefs.recordatorios_entrenamiento.push === false` los frena, y
/// una preferencia ausente los deja pasar (mismo criterio que el resto de las
/// filas: sólo un `false` EXPLÍCITO apaga).
///
/// Vive en DOS lugares y los dos tienen que decir lo mismo:
///
///  - el backend, que la lee para decidir si manda
///    (`functions/src/notifications/notify-daily-reminders.ts`);
///  - esta constante, con la que la app la escribe desde Perfil › Privacidad.
///
/// Si divergen, el atleta apaga el interruptor y el push sigue llegando: un
/// control que no controla nada. Por eso el mismo test de deriva que cuida
/// [kPrefCorreosPromocionales] lee ese `.ts` y compara
/// (`test/features/profile/notification_pref_keys_drift_test.dart`).
///
/// A diferencia de [kPrefCorreosPromocionales], el canal acá es `push` y no
/// `email`: es un aviso del sistema operativo, no un correo.
const String kPrefRecordatoriosEntrenamiento = 'recordatorios_entrenamiento';
