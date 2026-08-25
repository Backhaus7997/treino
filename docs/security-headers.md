# Security headers del Coach Hub web

Slice B/D parcial de [#680](https://github.com/Backhaus7997/treino/issues/680).
Documenta **por qué** cada header del bloque `headers` de `firebase.json`
(target `coach-hub-dev`) está como está. `firebase.json` es JSON estricto y no
admite comentarios — la justificación vive acá.

> Este archivo cubre **sólo los headers de hosting**. El threat model completo,
> la matriz de cobertura de reglas y el inventario de PII son otros slices de
> #680 y van a `docs/security.md`.

---

## Estado verificado (2026-08-24)

Todo lo de abajo se comprobó contra el build real (`flutter build web -t
lib/main_coach_hub.dart`) servido por el **emulador de Firebase Hosting**, no
razonando sobre el papel.

| Header | Política | Verificado |
|---|---|---|
| `X-Content-Type-Options: nosniff` | enforcing | ✅ servido |
| `X-Frame-Options: DENY` | enforcing | ✅ servido |
| `Referrer-Policy: strict-origin-when-cross-origin` | enforcing | ✅ servido |
| `Strict-Transport-Security` | enforcing | ✅ servido |
| `Permissions-Policy` | enforcing | ✅ servido |
| `Content-Security-Policy-Report-Only` | **report-only** | ✅ servido, app bootea sin violaciones |

---

## Por qué la CSP va en Report-Only

Porque la CSP "linda" **rompe la app**, y eso se midió, no se supuso.

Primer intento, la CSP que uno escribiría de memoria para Flutter web
(`script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com`): la app **no
arranca**. Muere con `Uncaught TypeError` y la consola tira ocho violaciones.
El motivo es que **cada plugin de FlutterFire inyecta un script inline** en el
arranque — `firebase_core`, `firestore`, `auth`, `storage`, `functions`,
`analytics`, `app_check` y `messaging`, uno por cabeza:

```
Executing inline script violates the following Content Security Policy directive
'script-src ...'. Either the 'unsafe-inline' keyword, a hash
('sha256-lxybZtu/9pEo9t2cXF8OdVCueZV6paBpNEQpBgqbYWA='), or a nonce is required.
```

De ahí salen las tres decisiones incómodas de la policy actual:

1. **`script-src` necesita `'unsafe-inline'`.** La alternativa son los ocho
   hashes `sha256-` de arriba, pero cambian con **cada bump de un plugin de
   FlutterFire**, y el síntoma de que quedaron viejos es la app en blanco en
   producción — nada en CI lo detecta. Un header que se rompe solo en cada
   `flutter pub upgrade` no es una defensa, es una trampa.

   Con `'unsafe-inline'` la CSP pierde buena parte de su valor anti-XSS. Sigue
   sirviendo para acotar de **dónde** se puede cargar script externo, pero no
   para frenar un `<script>` inyectado. **Por eso sola no justifica pasar a
   enforcing.**

2. **`accounts.google.com` está en la policy aunque no debería hacer falta.**
   `lib/main_coach_hub.dart` dice explícitamente que el Coach Hub NO usa Google
   Sign-In (decisión #2 del propose), pero el plugin `google_sign_in` se
   registra igual en web y carga `https://accounts.google.com/gsi/client` en
   cada visita. Está en la lista porque el navegador lo pide, no porque lo
   queramos. → seguimiento abajo.

3. **`fonts.gstatic.com` en `font-src`/`connect-src`.** Las tipografías del
   producto están bundleadas y `GoogleFonts.config.allowRuntimeFetching = false`
   (ver `lib/main.dart`), pero el **engine de Flutter** baja Roboto por su
   cuenta como fallback, por fuera de `google_fonts`.

### Lo que NO se pudo verificar

El shell **sin autenticar** (pantalla de login) bootea con cero violaciones.
Todo lo que hay **después del login** quedó sin probar: subida de archivos a
Storage, recorte de avatar con croppie, callables de Cloud Functions, media de
chat. Es justamente la superficie que maneja datos de alumnos.

Pasar la CSP a enforcing sin haber ejercitado esos flujos sería apostar la app
del PF a una lista de dominios incompleta. Un header honesto en report-only vale
más que uno estricto que tira la producción abajo.

### Cómo pasarla a enforcing (checklist)

1. Deploy con report-only y recolectar violaciones reales durante ≥ 1 semana de
   uso (agregar `report-uri`/`report-to` a un endpoint, hoy no hay).
2. Ejercitar a mano, logueado: subir avatar, adjuntar imagen y video en chat,
   subir archivo de alumno, abrir un video de YouTube.
3. Recién ahí renombrar la key `Content-Security-Policy-Report-Only` →
   `Content-Security-Policy` en `firebase.json`.
4. Ojo: `frame-ancestors` se **ignora** en modo report-only (está en la spec).
   Hoy el anti-clickjacking lo da `X-Frame-Options: DENY`, que sí es enforcing.
   No borres el `X-Frame-Options` "porque ya está en la CSP" hasta que la CSP
   sea enforcing de verdad.

---

## HSTS: lo que el issue daba por faltante ya estaba

`#680` lista HSTS entre los headers ausentes. **No es así.** Firebase Hosting
ya lo sirve solo en los dominios `*.web.app`:

```
$ curl -sI https://coach-treino-dev.web.app/
strict-transport-security: max-age=31556926; includeSubDomains; preload
```

Se declara igual en `firebase.json` por una razón concreta: ese header lo pone
Firebase **por ser un dominio `.web.app`**. El día que el Coach Hub pase a un
dominio propio, esa garantía se evapora sin que nadie se entere. Declararlo
explícito hace que sobreviva a la mudanza. El `max-age` propio (31536000 = 365
días) es equivalente al de Firebase (31556926 = 365,25 días) y cumple el mínimo
de la preload list.

---

## Permissions-Policy: por qué esa lista

Se bloquean features que el Coach Hub **verificadamente no usa**. `camera=()`
entra en la lista porque los dos pickers del Hub
(`avatar_web_uploader.dart` y `chat_detail_pane.dart`) usan
`ImageSource.gallery` — nunca `ImageSource.camera`; en web eso es un
`<input type="file">`, que no pide permiso de cámara.

`geolocation=()` es seguro por el mismo motivo: `geolocator` está en
`pubspec.yaml` pero no se usa en ninguna pantalla del Coach Hub.

**Si algún día el Hub necesita cámara o ubicación, hay que sacar la entrada de
esta lista o la feature falla en silencio.**

---

## Seguimientos abiertos (fuera del alcance de este PR)

1. **`croppie` se carga desde unpkg.com sin SRI.** `web/index.html` trae
   `https://unpkg.com/croppie@2.6.5/croppie.min.js` sin atributo `integrity`.
   Si unpkg se compromete o el tag se reapunta, corre JS arbitrario en la página
   que maneja datos de alumnos. Fix: agregar `integrity` + `crossorigin`, o
   bundlear el asset y sacar `unpkg.com` de la CSP.
2. **`google_sign_in` carga GSI en el Coach Hub sin usarse.** Contradice una
   decisión documentada y suma script + cookies de tercero. Si se resuelve, se
   sacan `accounts.google.com` y `apis.google.com` de la CSP.
3. **No hay endpoint de reportes de CSP.** Sin `report-uri`/`report-to`, el modo
   report-only sólo se ve en la consola del navegador de quien mire. Es el
   bloqueante real del paso 1 del checklist de enforcing.
