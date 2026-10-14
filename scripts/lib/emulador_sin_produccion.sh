# shellcheck shell=bash
#
# emulador_sin_produccion.sh — que el emulador de Functions no alcance
# producción por lo que NO está emulado.
#
# Lo sourcean `scripts/emulator.sh` (que levanta con `--project treino-dev`) y
# el canario de CI `scripts/check_emulator_sin_produccion.js`, que lo prueba
# contra una firebase-tools real. Que los dos corran ESTE archivo es el punto:
# el canario no mide una copia de la lógica, mide la que usa el emulador.
#
#   source scripts/lib/emulador_sin_produccion.sh
#   cerrar_produccion functions || exit 1      # el directorio de las Functions
#
# Exporta dos variables, CLOUD_SECRET_MANAGER_URL y
# GOOGLE_APPLICATION_CREDENTIALS, y devuelve 1 sin exportar la segunda si la
# credencial falsa no sirve o si algún archivo de env de las Functions la pisa.
#
# --------------------------------------------------------------------------
# Secretos: el emulador de Functions los leía de Secret Manager de PRODUCCIÓN
# --------------------------------------------------------------------------
# Medido el 2026-10-14 contra firebase-tools 15.19.0, con un proyecto
# `demo-sonda-secretos`, una función con un `defineSecret` falso y Secret
# Manager apuntado a un servidor local que registraba cada pedido:
#
#   - Al arrancar el emulador no pide nada. Al INVOCAR la función, el CLI hace
#     `GET /v1/projects/<--project>/secrets/<nombre>/versions/latest:access`, y
#     el valor que devuelve llega al proceso de la función.
#     (`resolveSecretEnvs`, `lib/emulator/functionsEmulator.js`.)
#   - El cartel de proyecto `demo-` ("attempts to access non-emulated services
#     for this project will fail") no aplica: con el proyecto demo el pedido
#     salió igual. Lo hace el CLI, no el runtime de la función.
#   - `functions/.secret.local` lo evita sólo para las claves que tienen valor
#     NO vacío: `SECRETO=` sin valor sale a Secret Manager igual.
#
# Leído, no medido —con treino-dev no se invocó nada—: `<--project>` es
# `getProjectId()`, o sea el `--project` de emulator.sh, o sea producción. Un
# trigger como `sendQueuedMail` sobre datos sembrados recibiría la
# RESEND_API_KEY real y podría mandar mails de verdad; las funciones de Mercado
# Pago, lo mismo con MP_ACCESS_TOKEN. Los secretos de hoy:
# `rg -n 'defineSecret\(' functions/src -g '!__tests__'`.
#
# Por eso Secret Manager se redirige a un puerto local donde no escucha nadie:
# todo secreto que no tenga valor en `.secret.local` falla en vez de traer el
# de producción, se declare como se declare —no depende de barrer los
# `defineSecret` y acertarles a todos—. Y como el origin es `http:`, el CLI ni
# siquiera carga una credencial: manda el token literal "owner"
# (`isLocalInsecureRequest`, `lib/apiv2.js`). Medido: la función recibe "" y
# el emulador loguea "Unable to access secret environment variables from
# Google Cloud Secret Manager", que acá es lo ESPERADO, no algo para arreglar
# con credenciales.
#
# Para probar un flujo que necesita un secreto: un valor DE PRUEBA en
# `functions/.secret.local` (gitignoreado). Nunca el de producción.
#
# ⚠ CLOUD_SECRET_MANAGER_URL no está documentada: la lee `secretManagerOrigin()`
# de `lib/api.js`. Si una versión de firebase-tools la deja de leer, este
# cierre desaparece en silencio. Lo vigila el canario de CI.
#
# --------------------------------------------------------------------------
# Credenciales: el runtime de Functions usaba las del dev contra producción
# --------------------------------------------------------------------------
# Los servicios emulados no necesitan credencial. Los que NO tienen emulador
# —FCM: `getMessaging()` en `notifications/send-fcm.ts` y
# `notifications/notify-wear-workout.ts`— salen a Google con la que encuentre
# `firebase-admin`, por el proyecto del `--project`. Y encontraba una real.
# Medido el 2026-10-14 (firebase-tools 15.19.0, proyecto `demo-`, los cuatro
# emuladores): sin nada exportado, el runtime arranca con las ADC de gcloud del
# dev (`RefreshTokenCredential`, client_id del cliente público de gcloud).
#
# Cómo se elige (`getCredentialsEnvironment`, `lib/emulator/env.js`): si el CLI
# encuentra ADC, el runtime las hereda; si NO las encuentra y hay `firebase
# login`, el CLI le INYECTA al runtime el login como
# GOOGLE_APPLICATION_CREDENTIALS. Medido con HOME aislado y un login falso,
# con un proyecto no-`demo-` inexistente y con uno `demo-` (la cuenta sale de
# `getProjectDefaultAccount`, sin guarda para `demo-`): el runtime recibió
# `~/.config/firebase/<email>_application_default_credentials.json`, client_id
# del cliente OAuth de firebase-tools, y SIN ningún aviso en el log. O sea que
# "no tengo ADC" no protegía nada.
#
# Por eso se exporta una credencial FALSA (`credencial_falsa_del_emulador.json`,
# al lado de este archivo, tipo `authorized_user`, valores inventados). Medido:
#   - El runtime la usa a ella, aunque las ADC reales sigan en el $HOME:
#     GOOGLE_APPLICATION_CREDENTIALS le gana al archivo bien conocido.
#   - El CLI la cuenta como ADC (`hasDefaultCredentials()` da true; sin ella,
#     con HOME vacío, da false), así que ya no inyecta el login. Con el login
#     falso de arriba y esta credencial, el runtime recibió ÉSTA.
#   - Firestore, Storage y Auth emulados siguen andando.
#   - FCM falla con `app/invalid-credential` / `invalid_client`. Ojo: el canje
#     del token SÍ sale a la red (oauth2 de Google), con datos falsos, y Google
#     lo rechaza. Nada real sale de esta máquina por ahí.
#
# Pisa cualquier GOOGLE_APPLICATION_CREDENTIALS heredado del shell, incluida la
# clave de servicio de producción (`$TREINO_SA_KEY`, AGENTS.md § Entornos).
#
# El CLI con `firebase login` NO cambia (leído; con treino-dev no se levantó
# nada): para un proyecto real se autentica con el login antes que con las ADC
# (`requireAuth`), y con eso sigue leyendo la config del proyecto, que es de
# donde sale el bucket de Storage del runtime. Sin login lee la copia en caché
# (`adminsdkconfig` del configstore), y si tampoco la hay cae a
# `constructDefaultAdminSdkConfig`: bucket `<proyecto>.appspot.com`, que NO es
# el de treino-dev. Medido (proyecto inexistente, sin login): el runtime
# arrancó con `<proyecto>.appspot.com` y un WARN "Unable to fetch project
# Admin SDK configuration". Los triggers de Storage sin `bucket` explícito se
# atan a ese bucket y no disparan con las subidas de la app. Antes, sin login
# pero con ADC, el CLI leía la config real con ellas; ahora no puede. Por eso
# `emulator.sh` exporta STORAGE_BUCKET_URL, lo único que lee ese fallback
# (medido: con ella, el bucket fue el que se le pasó).
#
# ⚠ Una GOOGLE_APPLICATION_CREDENTIALS escrita en un archivo de env de las
# Functions le GANA a ésta: firebase-tools no la tiene como clave reservada, y
# el runtime se arma con `process.env` primero y esos archivos después. Medido:
# con la variable en `functions/.env.local`, el runtime corrió con la de ahí.
# Y `.secret.local` también cuenta: el emulador mete en el runtime TODAS sus
# claves, no sólo las de los `defineSecret`. Por eso, si alguno de esos
# archivos la define, no se arranca.
#
# ⚠ El emulador va a seguir diciendo "Application Default Credentials
# detected. Non-emulated services will access production using these
# credentials." Las que detecta son éstas, las falsas.
#
# Si el archivo falta, no es `authorized_user` o le falta alguno de
# `client_id`, `client_secret` y `refresh_token`, NO se exporta y la función
# devuelve 1: con GOOGLE_APPLICATION_CREDENTIALS apuntando a algo que no sirve,
# el CLI vuelve a inyectar el login (ver arriba) y el runtime termina con la
# credencial real. Sin `refresh_token`, `hasDefaultCredentials()` ya da false.
#
# ⚠ Que el CLI no inyecte el login cuando hay una credencial también es
# comportamiento no documentado de firebase-tools. Lo vigila el mismo canario.
#
# Lo fija `scripts/test/emulator_secretos_locales.test.js`.

cerrar_produccion() {
  local dir_functions="${1:?cerrar_produccion: falta el directorio de las Functions}"

  export CLOUD_SECRET_MANAGER_URL="http://127.0.0.1:1"
  echo "Secret Manager -> $CLOUD_SECRET_MANAGER_URL (nadie escucha, a propósito):"
  echo "  un defineSecret sin valor en functions/.secret.local llega VACÍO a la función."

  local credencial
  credencial="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/credencial_falsa_del_emulador.json"
  # shellcheck disable=SC2016  # el $ es de JS, no de bash
  if ! node -e '
    const c = require(process.argv[1]);
    const ok = (v) => typeof v === "string" && v.length > 0;
    process.exit(c.type === "authorized_user" && ok(c.client_id) && ok(c.client_secret) && ok(c.refresh_token) ? 0 : 1);
  ' "$credencial" 2>/dev/null; then
    {
      echo ""
      echo "ERROR: falta o está rota $credencial; el emulador NO se levanta."
      echo "Sin ella, el runtime de Functions usaría tus credenciales reales contra producción."
    } >&2
    return 1
  fi

  # Los archivos de env que el emulador mete en el runtime DESPUÉS de
  # process.env: `.env`, `.env.<proyecto o alias>`, `.env.local` y
  # `.secret.local`. Se miran TODOS los `.env*`, de más: frenar por un
  # `.env.example` cuesta menos que dejar pasar el del proyecto.
  #
  # La clave se busca con el mismo criterio que el parser de firebase-tools
  # (`LINE_RE`, `lib/functions/env.js`): `export` opcional y pegado o no, y
  # espacios en cualquier lado. Con `export\s+` se escapaba
  # `exportGOOGLE_APPLICATION_CREDENTIALS=…`, que firebase-tools sí lee (medido
  # con su `parseStrict`; lo encontró el review del PR).
  #
  # Un archivo que no se puede leer también frena: no hay forma de saber qué
  # define.
  local pisan
  # shellcheck disable=SC2016  # el $ es de JS, no de bash
  pisan="$(node -e '
    const fs = require("fs"), path = require("path");
    const dir = process.argv[1];
    // Si el directorio no está, no hay nada que mirar y el chequeo daría OK sin
    // haber revisado los archivos que el emulador sí va a cargar de otro lado.
    if (!fs.existsSync(dir)) { console.log(`${dir} (no existe: no se pudo revisar)`); process.exit(0); }
    for (const f of fs.readdirSync(dir).sort()) {
      if (!/^\.env(\..+)?$/.test(f) && f !== ".secret.local") continue;
      const ruta = path.join(dir, f);
      let texto;
      try {
        if (!fs.statSync(ruta).isFile()) continue;
        texto = fs.readFileSync(ruta, "utf8");
      } catch (e) {
        console.log(`${ruta} (no se pudo leer: ${e.code})`);
        continue;
      }
      if (/^\s*(?:export)?\s*GOOGLE_APPLICATION_CREDENTIALS\s*=/m.test(texto)) console.log(ruta);
    }
  ' "$dir_functions")" || return 1
  if [ -n "$pisan" ]; then
    {
      echo ""
      echo "ERROR: estos archivos de env de Functions definen GOOGLE_APPLICATION_CREDENTIALS"
      echo "(o no se pueden leer); el emulador NO se levanta:"
      while IFS= read -r archivo; do echo "  $archivo"; done <<<"$pisan"
      echo "El emulador carga .env, .env.<proyecto o alias>, .env.local y .secret.local DESPUÉS"
      echo "de esta credencial falsa: una GOOGLE_APPLICATION_CREDENTIALS ahí le gana, y el runtime"
      echo "correría con ésa. Por las dudas se frena con cualquier .env*. Sacala de esos archivos."
    } >&2
    return 1
  fi
  export GOOGLE_APPLICATION_CREDENTIALS="$credencial"
  echo "Credenciales -> $GOOGLE_APPLICATION_CREDENTIALS (FALSA, a propósito):"
  echo "  FCM y las demás APIs de Google sin emulador fallan; el aviso 'Application Default Credentials detected' es por ésta."
}
