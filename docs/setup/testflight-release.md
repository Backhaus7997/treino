# Release a TestFlight (Codemagic)

Cómo publicar una build de TREINO en TestFlight. El pipeline vive en [`codemagic.yaml`](../../codemagic.yaml).

## Qué hace el pipeline

Al pushear un tag `v*`, Codemagic:

1. Resuelve dependencias (`flutter pub get`).
2. Calcula el **build number** leyendo el último de TestFlight y sumándole 1.
3. Buildea el IPA firmado (`flutter build ipa --release`), con **Automatic code signing**.
4. Sube la build a App Store Connect y la distribuye al grupo de testers.

No hay que tocar el build number a mano nunca. El `version:` de `pubspec.yaml` solo controla la versión **visible** (`0.1.0`); el `+N` de ese campo se ignora en release.

---

## Setup inicial (una sola vez)

### 1. App Store Connect API Key

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → pestaña **Integrations** → **App Store Connect API** → *Team Keys*.
2. **+** → nombre (ej. `Codemagic CI`) → Access: **App Manager** → *Generate*.
3. Descargar el **`.p8`**. Se descarga **una sola vez**: si se pierde, hay que regenerar la key. Guardarlo en el gestor de contraseñas del equipo.
4. Anotar:
   - **Issuer ID** — el UUID arriba de la tabla de keys.
   - **Key ID** — 10 caracteres, en la fila de la key.
   - **Apple ID de la app** (numérico) — Apps → TREINO → **App Information** → General → *Apple ID*.

> El `.p8` **nunca** se commitea. Vive solo en Codemagic.

### 2. Codemagic

1. [codemagic.io](https://codemagic.io) → sign up con GitHub.
2. **Add application** → autorizar la GitHub App sobre `Backhaus7997/treino` (requiere admin en la org).
3. Tipo **Flutter App** → elegir configuración por **`codemagic.yaml`** (no el editor visual: el YAML ya está versionado en el repo).
4. **Teams → Integrations → Apple Developer Portal → Connect**: nombre `treino-asc`, Issuer ID, Key ID y subir el `.p8`.
5. En la app → **Settings → Code signing → iOS → Automatic**, seleccionando la integración `treino-asc` y el bundle `com.backhaus.treino`.
6. Confirmar el nombre exacto del grupo de testers en App Store Connect → TestFlight → *Grupos*.

### 3. Completar `codemagic.yaml`

Reemplazar los tres placeholders. Ninguno es una credencial secreta:

| Placeholder | Valor |
| --- | --- |
| `APP_STORE_CONNECT_INTEGRATION` | el nombre de la integración de Codemagic (ej. `treino-asc`) |
| `APP_STORE_APP_ID` | el Apple ID numérico de la app, entre comillas |
| `BETA_GROUP` | el nombre exacto del grupo de testers |

---

## Publicar una release

```bash
git checkout main && git pull
git tag v0.1.1 && git push origin v0.1.1
```

Eso es todo. Codemagic detecta el tag y arranca el build.

Para cambiar la versión **visible**, editar `version:` en `pubspec.yaml` (ej. `0.2.0+8`) antes de tagear. El `+8` da igual: el build number lo calcula el pipeline.

## Verificar

1. **Codemagic → Builds**: ~10-20 min. Si falla, el log indica el step exacto.
2. **App Store Connect → TestFlight**: la build aparece en *Processing* (10-30 min más).
3. Si pide **Export Compliance**, responderlo. Para no volver a verlo, agregar a `ios/Runner/Info.plist`:
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```
4. **Testers internos**: reciben la build apenas termina el processing.
   **Testers externos**: la primera build de cada versión pasa por *Beta App Review* de Apple (unas horas).

## Troubleshooting

| Síntoma | Causa probable |
| --- | --- |
| `No matching profiles found` | El Automatic code signing no quedó configurado, o la API Key no tiene rol *App Manager*. |
| Build number ya usado | Se subió una build a mano con ese número. El pipeline lo evita solo; volver a tagear. |
| El tag no dispara nada | El webhook no quedó instalado: Codemagic → app → *Settings → Webhooks*, o reconectar el repo. |
| `flutter build ipa` falla por firma | Verificar que el bundle en Codemagic sea exactamente `com.backhaus.treino`. |

## Notas

- El pipeline corre en `mac_mini_m2` y pinnea **Flutter 3.41.9**, igual que [`ci.yml`](../../.github/workflows/ci.yml). Si el equipo actualiza Flutter, actualizar ambos.
- `xcode: latest` no está pinneado a propósito: un número de versión se deprecia y rompe el build.
- `ci.yml` (GitHub Actions) sigue corriendo analyze + tests en cada PR. Codemagic **solo** se ocupa del release de iOS.
