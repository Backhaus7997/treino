/**
 * test/deep_links.test.js
 *
 * Coherencia de los App Links / Universal Links de `app.gettreino.com/abrir`.
 *
 *   node --test scripts/test/
 *
 * Por qué existen: un deep link mal configurado **no falla, no avisa y no
 * loguea**. El sistema operativo simplemente no verifica el dominio y abre el
 * navegador, que es exactamente lo que hacía antes. O sea que el sintoma de
 * estar roto es idéntico al de no haberlo hecho nunca, y no hay ninguna señal
 * que distinga las dos cosas.
 *
 * Cada aserción de acá cubre una forma concreta de romperlo en silencio:
 *
 *   - el SHA-256 sin reemplazar (el más probable de todos)
 *   - la huella de la UPLOAD key en vez de la de Play App Signing — Play
 *     re-firma el artefacto, asi que la huella que ve el celular es la de
 *     Google, no la tuya (solo se puede chequear el FORMATO, no cuál es)
 *   - el appID de iOS desincronizado del bundle o del team del proyecto
 *   - el host del intent-filter distinto del dominio que sirve los archivos
 *   - `autoVerify` faltante, sin el cual Android nunca busca el assetlinks
 *   - los `.well-known` tapados por el rewrite catch-all del SPA
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..', '..');
const leer = (p) => fs.readFileSync(path.join(RAIZ, p), 'utf8');
const leerJson = (p) => JSON.parse(leer(p));

/** El dominio que sirve los archivos de verificación. */
const HOST = 'app.gettreino.com';
/** El prefijo que abre la app. Todo lo demás del host es el Coach Hub web. */
const PREFIJO = '/abrir';

// ── Android ───────────────────────────────────────────────────────────────

test('assetlinks: el SHA-256 fue reemplazado de verdad', () => {
  const [entrada] = leerJson('web/well-known/assetlinks.json');
  const [huella] = entrada.target.sha256_cert_fingerprints;

  assert.ok(
    !/PEGAR|REEMPLAZAR|TODO|XXXX/i.test(huella),
    'El assetlinks.json todavía tiene el placeholder. Sacá la huella de\n' +
    'Play Console → Setup → App integrity → App signing key certificate.\n' +
    'TIENE que ser la de Play App Signing, NO la de tu upload key: Play\n' +
    're-firma el AAB, así que la huella que el celular verifica es la de Google.',
  );
});

test('assetlinks: la huella tiene forma de SHA-256', () => {
  const [entrada] = leerJson('web/well-known/assetlinks.json');
  const [huella] = entrada.target.sha256_cert_fingerprints;

  // 32 bytes en hex, separados por dos puntos, como los muestra Play Console.
  assert.match(
    huella,
    /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/,
    `La huella no tiene el formato de un SHA-256: ${huella}`,
  );
});

test('assetlinks: el package coincide con el applicationId de Gradle', () => {
  const [entrada] = leerJson('web/well-known/assetlinks.json');
  const gradle = leer('android/app/build.gradle.kts');
  const m = gradle.match(/applicationId\s*=\s*"([^"]+)"/);

  assert.ok(m, 'No se encontró el applicationId en build.gradle.kts');
  assert.strictEqual(entrada.target.package_name, m[1]);
});

test('manifest: hay un intent-filter con autoVerify para el host', () => {
  const manifest = leer('android/app/src/main/AndroidManifest.xml');

  // `includes` y no `match`: interpolar el host en un RegExp deja los puntos
  // como comodines, asi que `app.gettreino.com` matchearia tambien
  // `appXgettreinoYcom`. En una guarda cuyo unico trabajo es cazar un host
  // equivocado, eso es justo lo que no puede pasar. Lo marco CodeQL
  // (js/incomplete-hostname-regexp) y tenia razon.
  assert.ok(manifest.includes('android:autoVerify="true"'));
  assert.ok(manifest.includes(`android:host="${HOST}"`));
  assert.ok(manifest.includes(`android:pathPrefix="${PREFIJO}"`));
});

test('manifest: el intent-filter acota por path, no se come todo el host', () => {
  const manifest = leer('android/app/src/main/AndroidManifest.xml');

  // Sin pathPrefix, CUALQUIER link a app.gettreino.com abriría la app — y ese
  // host es el Coach Hub web, que tiene que seguir abriendo en el navegador.
  const filtros = manifest.split('<intent-filter');
  const conVerify = filtros.filter((f) => f.includes('autoVerify="true"'));

  assert.strictEqual(conVerify.length, 1, 'Se esperaba UN intent-filter verificado');
  assert.ok(
    conVerify[0].includes('android:pathPrefix='),
    'El intent-filter verificado no acota por path: se comería todo el host',
  );
});

// ── iOS ───────────────────────────────────────────────────────────────────

test('AASA: el appID coincide con el team y el bundle del proyecto', () => {
  const aasa = leerJson('web/well-known/apple-app-site-association');
  const pbx = leer('ios/Runner.xcodeproj/project.pbxproj');

  const team = pbx.match(/DEVELOPMENT_TEAM = ([A-Z0-9]+);/)[1];
  // El bundle del Runner, no el del target del reloj.
  const bundles = [...pbx.matchAll(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g)]
    .map((m) => m[1].trim())
    .filter((b) => !/watch|Tests|RunnerTests/i.test(b));

  const esperado = `${team}.${bundles[0]}`;
  const detalle = aasa.applinks.details[0];

  assert.strictEqual(detalle.appID, esperado);
  assert.deepStrictEqual(detalle.appIDs, [esperado]);
});

test('AASA: acota a /abrir/*, igual que Android', () => {
  const aasa = leerJson('web/well-known/apple-app-site-association');
  const d = aasa.applinks.details[0];

  assert.deepStrictEqual(d.paths, [`${PREFIJO}/*`]);
  assert.strictEqual(d.components[0]['/'], `${PREFIJO}/*`);
});

test('entitlements: el associated domain apunta al mismo host', () => {
  const ent = leer('ios/Runner/Runner.entitlements');

  assert.ok(ent.includes('com.apple.developer.associated-domains'));
  assert.ok(ent.includes(`applinks:${HOST}`));
});

// ── Las paginas de fallback ───────────────────────────────────────────────

test('la pagina del PROFE redirige sola al Coach Hub', () => {
  const html = leer('web/abrir/profe.html');

  // Si esta pagina se ve, el App Link no intercepto: no hay app, o el mail se
  // abrio en una computadora. El profe SI tiene a donde ir, asi que un segundo
  // click es peaje.
  assert.match(html, /http-equiv="refresh"[^>]*app\.gettreino\.com/);
});

test('la pagina del ALUMNO no redirige a ningun lado', () => {
  const html = leer('web/abrir/alumno.html');

  // El atleta no tiene equivalente web: el Coach Hub lo rebota contra el gate
  // de rol de `coach_hub_router.dart`. Mandarlo ahi seria cambiar una pantalla
  // que explica por una que lo expulsa. Esta asimetria es deliberada y es la
  // razon de que sean dos paginas y no una.
  assert.ok(!html.includes('http-equiv="refresh"'));
});

test('el redirect del profe no apunta adentro de /abrir', () => {
  const html = leer('web/abrir/profe.html');
  const m = html.match(/http-equiv="refresh" content="0;url=([^"]+)"/);

  assert.ok(m, 'No se encontro el meta-refresh');
  // Apuntar a /abrir/* haria que el App Link lo re-interceptara: un bucle
  // entre el navegador y la app.
  assert.ok(!m[1].includes(PREFIJO), `El redirect entra en ${PREFIJO}: ${m[1]}`);
});

// ── El servidor ───────────────────────────────────────────────────────────

test('vercel: los .well-known se sirven antes del catch-all del SPA', () => {
  const vercel = leerJson('vercel.json');
  const rutas = vercel.rewrites.map((r) => r.source);

  const catchAll = rutas.indexOf('/(.*)');
  const assetlinks = rutas.indexOf('/.well-known/assetlinks.json');
  const aasa = rutas.indexOf('/.well-known/apple-app-site-association');

  assert.ok(assetlinks !== -1, 'Falta el rewrite de assetlinks.json');
  assert.ok(aasa !== -1, 'Falta el rewrite de apple-app-site-association');
  // Vercel evalúa en orden y gana el primero: abajo del catch-all, los dos
  // archivos devolverían el index.html de Flutter y la verificación fallaría.
  assert.ok(assetlinks < catchAll, 'assetlinks.json queda debajo del catch-all');
  assert.ok(aasa < catchAll, 'apple-app-site-association queda debajo del catch-all');
});

test('vercel: el AASA se sirve como application/json', () => {
  const vercel = leerJson('vercel.json');

  // El archivo NO tiene extensión, así que Vercel lo mandaría como
  // octet-stream y iOS lo descarta sin decir nada.
  const regla = vercel.headers.find((h) =>
    h.source.includes('apple-app-site-association'));

  assert.ok(regla, 'Falta la regla de Content-Type para el AASA');
  assert.ok(
    regla.headers.some((h) =>
      h.key.toLowerCase() === 'content-type' && h.value.includes('application/json')),
    'El AASA no se sirve como application/json',
  );
});

test('vercel: las paginas de /abrir se sirven antes del catch-all', () => {
  const vercel = leerJson('vercel.json');
  const rutas = vercel.rewrites.map((r) => r.source);
  const catchAll = rutas.indexOf('/(.*)');

  for (const rol of ['alumno', 'profe']) {
    const i = rutas.indexOf(`${PREFIJO}/${rol}`);
    assert.ok(i !== -1, `Falta el rewrite de ${PREFIJO}/${rol}`);
    assert.ok(i < catchAll, `${PREFIJO}/${rol} queda debajo del catch-all`);
  }
});
