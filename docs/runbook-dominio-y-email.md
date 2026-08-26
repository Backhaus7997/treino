# Runbook — dominio, email transaccional y Coach Hub web

> [!WARNING]
> **`treino-dev` es el proyecto de PRODUCCIÓN.** No hay un entorno de desarrollo
> separado: todo comando de este documento que lleve `--project treino-dev`
> (o `--project prod`) toca datos de usuarios reales.
> Ver [AGENTS.md § Entornos](../AGENTS.md#-entornos--leer-antes-de-correr-cualquier-comando) y [#826](https://github.com/Backhaus7997/treino/issues/826).

Todo lo que hay que hacer **a mano** para poner en producción el email
transaccional (PR #720, #749) y publicar el Coach Hub web.

El código ya está escrito y testeado. Esto es configuración en cuatro consolas
distintas, y **el orden importa**: hay pasos que rompen si se hacen al revés.

---

## El mapa

Todo cuelga de `gettreino.com`, que ya es tuyo y cuyo DNS ya vive en Vercel
(`ns1/ns2.vercel-dns.com`). **No hace falta comprar ningún dominio.**

| Nombre | Apunta a | Para qué |
|---|---|---|
| `gettreino.com` | Vercel · proyecto `treino-app` | Landing pública (ya anda) |
| `app.gettreino.com` | Vercel · proyecto nuevo | Coach Hub web |
| `send.gettreino.com` | Resend | Remitente del email |
| `auth.gettreino.com` | Firebase Hosting | Action handler de reseteo |

**Un subdominio por servicio, a propósito.** Cada uno falla solo. Si algún día
se lastima la reputación de envío, no se lleva puesta la web.

---

## ⚠️ La trampa: ya hay un SPF

El dominio raíz tiene hoy:

```
gettreino.com  TXT  "v=spf1 include:mailgun.org ~all"
```

Algo tuyo ya manda mail desde ahí (probablemente el formulario de la landing).

**No se pueden tener dos registros SPF en el mismo dominio.** Si agregás el de
Resend en la raíz y queda un segundo `v=spf1`, SPF no falla para el nuevo:
**falla para los dos** (`permerror`), y te tira a spam el mail de Resend *y* el
de Mailgun.

Mandar desde `send.gettreino.com` esquiva esto por completo — el subdominio
tiene su propio SPF, independiente del de la raíz. **No toques el TXT de la
raíz.**

---

## 1 · Resend

1. Crear cuenta y **agregar el dominio `send.gettreino.com`** (el subdominio, no
   la raíz).
2. Resend devuelve registros para cargar en Vercel → Domains → `gettreino.com`:
   - un `TXT` de verificación
   - un `TXT` de **SPF** para el subdominio
   - un `CNAME` (o `TXT`) de **DKIM**
   - opcionalmente un `TXT` de **DMARC** en `_dmarc.gettreino.com`
3. Esperar a que Resend marque el dominio **Verified**. Puede tardar minutos u
   horas según propagación.
4. Crear la **API key**.

> Sin este paso verificado, cada envío devuelve **403**. Por eso las CFs de auth
> están shelved: desplegarlas antes deja endpoints abusables que encolan mail
> que después no sale.

---

## 2 · Firebase — el secret

```bash
firebase functions:secrets:set RESEND_API_KEY --project prod
```

> `--project prod` no es opcional desde [#840](https://github.com/Backhaus7997/treino/issues/840):
> el default de `.firebaserc` es `demo-treino` (proyecto offline del emulador), así
> que el comando pelado **falla** en vez de tocar producción. Vale para todos los
> comandos de este runbook.

El remitente por defecto ya está en el código
(`MAIL_FROM = "TREINO <hola@send.gettreino.com>"`,
`functions/src/mail/send-queued-mail.ts`). Si querés otro, se sobrescribe con la
variable de entorno `MAIL_FROM` — no hace falta tocar código.

---

## 3 · `auth.gettreino.com` — el action handler

**Por qué existe:** el mail sale de `gettreino.com` y el botón de "cambiar mi
contraseña" llevaría a `treino-dev.firebaseapp.com`. Un mail de un dominio que
te manda a **otro** dominio a escribir una contraseña es, literalmente, la forma
de un phishing — y el usuario desconfiado es justo el que no querés perder.

`/__/auth/action` es un namespace reservado que **sirve cualquier sitio de
Firebase Hosting del proyecto**, sin escribir una línea de código.

1. Firebase Console → Hosting → conectar dominio personalizado
   `auth.gettreino.com`.
2. Cargar en Vercel DNS los registros que pida Firebase.
3. Firebase Console → Authentication → Templates → **Customize action URL** →
   `https://auth.gettreino.com/__/auth/action`.

> No sirve moverlo a Vercel: ese path lo sirve Firebase Hosting y nadie más. Es
> la única razón por la que Firebase Hosting sigue en el mapa.

---

## 4 · `app.gettreino.com` — el Coach Hub

El repo ya trae `vercel.json` y `scripts/vercel-build.sh` (instala Flutter
**3.41.9**, el mismo pin que CI, y compila `lib/main_coach_hub.dart`).

1. Vercel → **Add New → Project**, importar `Backhaus7997/treino`.
   - Ojo: hoy la app de Vercel tiene acceso a `Backhaus7997/CodeAssurance-Landing`
     y `Backhaus7997/treino-app`, pero **no** a `Backhaus7997/treino`. Hay que
     ampliarle el acceso en GitHub.
   - Crearlo en **la cuenta personal** (`Martin's projects`), que es donde vive
     `gettreino.com` y donde está el Pro — no en el team `Code Assurance`.
2. Vercel detecta `vercel.json` solo. No hace falta tocar build settings.
3. Agregar el dominio `app.gettreino.com` al proyecto.

### ⚠️ Esto rompe el login si te lo olvidás

Firebase Console → Authentication → Settings → **Authorized domains** →
agregar `app.gettreino.com`.

Sin eso el login web falla con `auth/unauthorized-domain`. Muerde siempre, y
siempre en producción.

---

## 5 · Activar las CFs de auth — en tres tramos

**No se hace de una.** `treino-dev` es producción y el padrón de Auth es uno
solo: no hay dónde ensayar. Sobre un flujo donde el usuario ya está afuera de su
cuenta, primero se comprueba y después se migra.

### 5A · Publicar los callables (el cliente no cambia)

El export ya está descomentado en `functions/src/index.ts`. Solo falta
desplegar:

```bash
firebase deploy --only firestore:rules --project prod
firebase deploy --only functions --project prod
```

**Las reglas primero.** `mail_queue` está cerrada en los cuatro verbos y conviene
que esa protección esté arriba antes de que la colección empiece a existir.

En este tramo **no cambia nada para los usuarios**: `AuthService` sigue yendo a
FirebaseAuth directo, así que los mails de recuperación siguen saliendo por las
plantillas default. Si algo sale mal acá, el flujo real nunca se enteró.

### 5B · Probar el callable a mano

Con una cuenta de prueba propia, invocar `requestPasswordReset` y verificar:

| Qué | Esperado |
|---|---|
| El mail llega | de `send.gettreino.com`, no de `firebaseapp.com` |
| No cae en spam | SPF + DKIM alineados |
| El link del botón | `auth.gettreino.com/__/auth/action` |
| El link funciona | abre el formulario y permite cambiar la contraseña |
| La cola | `mail_queue` → el doc queda en `status: "sent"` |
| El token en reposo | `params.actionLink` **borrado** tras el envío |

Recién con las seis en verde se pasa al 5C.

### 5C · Cambiar el cliente

Editar `lib/features/auth/data/auth_service.dart` (líneas 121 y 130) para llamar
a los callables en vez de a FirebaseAuth, y publicar la app.

A partir de acá los mails de recuperación de los usuarios reales salen por
Resend. Es el único tramo sin vuelta atrás rápida: revertirlo exige otra
publicación de la app.

---

## 6 · Verificar

| Qué | Cómo | Esperado |
|---|---|---|
| Dominio verificado | Resend → Domains | Verified |
| SPF no duplicado | `nslookup -type=TXT send.gettreino.com` | **un solo** `v=spf1` |
| Coach Hub | abrir `app.gettreino.com` | carga el login |
| Login web | entrar con una cuenta de PF | sin `auth/unauthorized-domain` |
| Envío real | pedir un reseteo | llega de `send.gettreino.com` |
| Link del mail | mirar el `href` del botón | `auth.gettreino.com`, no `firebaseapp.com` |
| Cola | Firestore → `mail_queue` | el doc queda en `status: "sent"` |

---

## Deuda conocida

- **Sin deep links.** No hay `assetlinks.json`, ni associated domains, ni
  `autoVerify`. Tres de los cuatro mails no-auth van a ATLETAS, que usan la app
  móvil, así que sus CTA apuntan a la landing como mal menor. El destino
  correcto es la app; requiere configurar Universal Links / App Links.
- **Nadie lee las respuestas.** El dominio no tiene MX: no recibe mail. Alguien
  va a responder "¿y el jueves puedo?" a un aviso de cancelación y va a caer en
  el vacío. Decidir entre `noreply@` o un `Reply-To` a una casilla real.
- **`gettreino-vercel.app` no existe** (NXDOMAIN) y sigue listado en Vercel →
  Domains. Basura para limpiar.
- **El canal push no lee `notificationPrefs`.** Las CFs mandan siempre. Email sí
  lo respeta en las dos filas de `kEmailBackedTypes`.
