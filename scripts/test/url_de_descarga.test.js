/**
 * test/url_de_descarga.test.js
 *
 * El módulo puro: qué host lleva la URL de descarga según el plan de Storage.
 * Que los cuatro scripts lo USEN lo prueba `storage_scripts_url.test.js`,
 * cargándolos de verdad — borrando el cableado, éstos siguen en verde.
 *
 *   node --test scripts/test/url_de_descarga.test.js
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const {
  HOST_DE_LA_NUBE,
  armadorDeUrlDeDescarga,
  hostDeDescarga,
  origenDelEmulador,
} = require('../lib/url_de_descarga');
const { planDeStorage } = require('../lib/storage_target');

const RC = path.join(__dirname, '..', '..', '.firebaserc');
const DESTINO = 'exercises/thumbs/pullup-pesocorporal.jpg';
// Falso a propósito: un UUID real acá lo marca gitleaks (generic-api-key).
const TOKEN = 'token-de-prueba';

/** Lo que los cuatro scripts escribían a mano hasta este cambio. */
const urlDeAntes = (bucket) =>
  `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(DESTINO)}?alt=media&token=${TOKEN}`;

const EMULADOR = { FIRESTORE_EMULATOR_HOST: 'localhost:8080', FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199' };

test('en la nube la URL es BYTE A BYTE la de antes', () => {
  // Lo que este cambio no puede tocar: el camino de producción no se puede
  // probar sin escribir en producción, así que tiene que quedar idéntico.
  const plan = planDeStorage({ argv: ['--project=treino-otro-dev', '--bucket=bucket-de-prueba'], env: {}, rutaFirebaserc: RC });
  assert.strictEqual(plan.contraEmulador, false);

  const url = armadorDeUrlDeDescarga(plan, {})({ destino: DESTINO, token: TOKEN });
  assert.strictEqual(url, urlDeAntes('bucket-de-prueba'));
});

test('contra el emulador la URL nombra al EMULADOR, no a Google', () => {
  // EL TEST DEL BUG. Medido: con el host real, `CachedNetworkImage` recibe 404
  // (bucket demo) o 403 de PRODUCCIÓN (bucket treino-dev) y la app cae en
  // silencio al asset local; con el del emulador, 200.
  const plan = planDeStorage({ argv: [], env: EMULADOR, rutaFirebaserc: RC });
  assert.strictEqual(plan.contraEmulador, true, 'precondición: el plan tiene que decir emulador');

  const url = armadorDeUrlDeDescarga(plan, EMULADOR)({ destino: DESTINO, token: TOKEN });
  assert.strictEqual(
    url,
    `http://localhost:9199/v0/b/${plan.bucket}/o/exercises%2Fthumbs%2Fpullup-pesocorporal.jpg?alt=media&token=${TOKEN}`,
  );
  assert.ok(!url.includes('googleapis'), `quedó el host de la nube en una corrida de emulador: ${url}`);
});

test('el host sale del ambiente, no de un 9199 fijo', () => {
  const env = { FIRESTORE_EMULATOR_HOST: 'localhost:18080', FIREBASE_STORAGE_EMULATOR_HOST: '127.0.0.1:19199' };
  const plan = planDeStorage({ argv: [], env, rutaFirebaserc: RC });
  assert.strictEqual(hostDeDescarga(plan, env), 'http://127.0.0.1:19199');
});

test('STORAGE_EMULATOR_HOST le gana a FIREBASE_STORAGE_EMULATOR_HOST, como en el SDK', () => {
  // firebase-admin sólo deriva STORAGE_EMULATOR_HOST de la otra si no está
  // puesta: la URL tiene que nombrar el host al que el SDK subió de verdad.
  assert.strictEqual(
    origenDelEmulador({ STORAGE_EMULATOR_HOST: 'http://127.0.0.1:9300', FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199' }),
    'http://127.0.0.1:9300',
  );
  assert.strictEqual(origenDelEmulador({ FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199' }), 'http://localhost:9199');
});

test('contra el emulador sin un host legible, TIRA — nunca cae al de la nube', () => {
  // El plan toma estos ambientes como emulador, pero ninguno trae un host que
  // se pueda leer. Si el armador "se arreglara" con el host de la nube, sería
  // el bug de vuelta con otra cara. Tiene que cortar, y antes de la primera
  // subida.
  //
  // Acá había una fila con `FIREBASE_STORAGE_EMULATOR_HOST=' '`, que el plan
  // contaba como emulador con su `Boolean()`. Desde el #1445 el plan ya no lo
  // hace: una variable en blanco aborta antes (ver el test de abajo), así que
  // esa fila dejó de llegar al armador.
  for (const env of [
    // Sin esquema en STORAGE_EMULATOR_HOST, `new URL` lee `localhost:` como
    // protocolo. No se adivina.
    { FIRESTORE_EMULATOR_HOST: 'localhost:8080', STORAGE_EMULATOR_HOST: 'localhost:9199' },
    // CON esquema en FIREBASE_STORAGE_EMULATOR_HOST, que el SDK rechaza:
    // con el `http://` de adelante el origen saldría `http://http`.
    { FIRESTORE_EMULATOR_HOST: 'localhost:8080', FIREBASE_STORAGE_EMULATOR_HOST: 'http://localhost:9199' },
  ]) {
    const plan = planDeStorage({ argv: [], env, rutaFirebaserc: RC });
    assert.strictEqual(plan.contraEmulador, true, `precondición: ${JSON.stringify(env)} es emulador para el plan`);
    assert.throws(() => armadorDeUrlDeDescarga(plan, env), /EMULADOR/);
  }
});

test('con una variable en blanco el plan aborta antes, y el armador tampoco arma', () => {
  // La fila que salió del test de arriba: el corte se movió al plan (#1445),
  // pero el armador sigue sin estampar nada sobre ese plan.
  const env = { FIRESTORE_EMULATOR_HOST: 'localhost:8080', FIREBASE_STORAGE_EMULATOR_HOST: ' ' };
  const plan = planDeStorage({ argv: [], env, rutaFirebaserc: RC });
  assert.strictEqual(plan.coherente, false, 'precondición: el plan aborta');
  assert.strictEqual(plan.contraEmulador, false);
  assert.throws(() => armadorDeUrlDeDescarga(plan, env), /no es coherente/);
});

test('con un plan incoherente no arma nada', () => {
  const plan = planDeStorage({ argv: [], env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080' }, rutaFirebaserc: RC });
  assert.strictEqual(plan.coherente, false, 'precondición');
  assert.throws(() => armadorDeUrlDeDescarga(plan, {}), /no es coherente/);
});

test('host y formato son los del getDownloadURL del firebase-admin instalado', () => {
  // La URL se arma a mano porque `getDownloadURL` falla contra el emulador
  // (ver lib/url_de_descarga.js). Lo que se copia es su host y su formato, y
  // esto lee el fuente del SDK REAL —no una constante contra sí misma— para
  // que una major que los cambie se note acá y no en 793 URLs estampadas.
  const fs = require('node:fs');
  const fuente = fs.readFileSync(require.resolve('firebase-admin/storage'), 'utf8');

  assert.ok(fuente.includes(`'${HOST_DE_LA_NUBE}'`), `el SDK ya no usa ${HOST_DE_LA_NUBE}`);
  assert.ok(
    fuente.includes('`${endpoint}/b/${file.bucket.name}/o/${encodeURIComponent(file.name)}?alt=media&token=${token}`'),
    'cambió el formato de la URL de getDownloadURL en el SDK',
  );
});
