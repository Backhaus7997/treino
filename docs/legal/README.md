# `docs/legal/` — documentos legales de TREINO

Fuente de verdad de los textos legales. Lo que hoy ve el usuario in-app vive en
`lib/features/auth/presentation/legal/legal_content.dart`; estos documentos son
su reemplazo, y hay que portarlos ahí y publicarlos en `gettreino.com/legal/*`.

**Ninguno está publicado. Todos son borradores.**

| Documento | Qué es | Estado |
|---|---|---|
| [AUDITORIA-legal-vigente.md](./AUDITORIA-legal-vigente.md) | Contraste del texto vigente contra el código. 18 hallazgos | Leer primero |
| [terminos-y-condiciones.md](./terminos-y-condiciones.md) | Reemplazo de `kTermsSections` | Borrador — 3 cláusulas esperan D2, D3, D4/D6 |
| [politica-de-privacidad.md](./politica-de-privacidad.md) | Reemplazo de `kPrivacySections`, contra el mapa de datos real | Borrador |
| [descargo-medico.md](./descargo-medico.md) | Asunción de riesgo + dónde mostrarlo | Borrador — **revisión legal obligatoria** |
| [contrato-entrenador.md](./contrato-entrenador.md) | Términos para PFs: independencia, datos de alumnos, planes | Borrador — **revisión legal obligatoria** |
| [consentimiento-datos-salud.md](./consentimiento-datos-salud.md) | Texto + spec del flujo de consentimiento expreso | Borrador |
| [normas-de-comunidad.md](./normas-de-comunidad.md) | Publicable + spec de reporte y bloqueo (Apple 1.2) | Borrador |
| [retencion-y-borrado.md](./retencion-y-borrado.md) | Qué se borra, qué se conserva. URL para Google Play | Borrador |
| [aviso-legal.md](./aviso-legal.md) | Identificación del titular | Borrador |
| [guia-legal-treino.pdf](./guia-legal-treino.pdf) | Guía de decisiones y trámites para el Product Owner | Vigente |

## Lo que falta, y por qué

| Documento | Bloqueado por |
|---|---|
| Términos de suscripción | **D4** (medio de cobro) y **D6** (reembolsos) |
| Botón de arrepentimiento y baja online | **D4** y **D6**. Res. 424/2020 |
| Política de cookies | **D3** (países) y relevar qué carga la landing, que vive en otro proyecto de Vercel |
| Licencias de software libre | No es un documento: es cablear `showLicensePage` de Flutter, que hoy no está en el código |

## Titular

**BACKHAUSTIN S.A.S.** — CUIT 30-71929587-4. Constituida el 23 de enero de 2026
(Ley 27.349), inscripta por resolución de la Dirección General de Inspección de
Personas Jurídicas de Córdoba del 5 de febrero de 2026, matrícula N° 46468-A.
TREINO es un servicio prestado por esa sociedad.

## Cuentas de las tiendas — pendiente de decisión

Verificado el 2026-08-31: **Apple está enrolada como Individual** (Team ID
J66AQRRM96) y **Play como Personal** (nombre público «Code assurance dev»,
sitio `code-assurance.com`). Ninguna de las dos está a nombre de la sociedad, y
el nombre que ve el usuario en Play no coincide con el titular de los
documentos.

Es decisión del Product Owner, no del equipo de desarrollo. Detalle, riesgos y
los dos caminos posibles en la sección 4 de
[`guia-legal-treino.pdf`](./guia-legal-treino.pdf). Tiene fecha encima: la
membresía de Apple renueva el **5 de septiembre de 2026**.

## Decisiones ya tomadas

| # | Decisión | Resuelta |
|---|---|---|
| D1 | Titular: **BACKHAUSTIN S.A.S.** | 2026-08-31 |
| D5 | **TREINO no intermedia la plata entre alumno y PF.** Es sólo vía de comunicación. El único dinero que maneja la plataforma es la suscripción del PF, y a futuro la del alumno | 2026-08-31 |

D5 tiene que quedar escrita en dos lugares cuando se redacten los Términos: la
cláusula correspondiente y un aviso **visible en la pantalla de pagos**. La app
registra la deuda y publica el alias de cobro — facilita el pago aunque no lo
procese, y el usuario no tiene por qué asumir la diferencia.

Las cuatro pendientes (edad mínima, países, cobro de la suscripción,
reembolsos) están en la sección 3 de la guía.

## Lo que NO está acá

Los documentos que no salen del código —Términos y Condiciones, contrato del PF,
descargo médico, términos de suscripción, arrepentimiento— dependen de
decisiones del titular. Están relevados en la guía de tareas que acompaña a este
directorio.

## Dónde se publica cada documento

Mapa completo en la **sección 9** de [`guia-legal-treino.pdf`](./guia-legal-treino.pdf):
direcciones de `gettreino.com`, campos de las dos consolas, puntos de acceso en
la app y en el Coach Hub.

Dos cosas de esa sección que son trabajo de desarrollo:

- **Hoy los legales sólo se alcanzan desde el registro y el login**
  (`Navigator.push` desde `TermsCheckbox` / `TermsNoticeText`). No hay ruta ni
  entrada desde Perfil: con la cuenta ya creada, nadie puede releer lo que
  aceptó. Hay que agregar **Perfil → Legales**.
- **`/eliminar-cuenta` va en la raíz de `gettreino.com`**, no bajo `/legal`.
  Google exige que sea alcanzable desde un navegador sin instalar la app.

## El texto se GENERA, no se copia

Los `.md` de este directorio son la **fuente única**. El archivo que muestra la
app y el HTML del sitio se generan desde acá:

```bash
python3 scripts/build_legal_content.py
```

Produce:

| Salida | Para |
|---|---|
| `lib/features/auth/presentation/legal/legal_content.dart` | La app |
| `build/legal-web/*.html` + `index.html` | Publicar en `gettreino.com/legal/` |

**No edites `legal_content.dart` a mano.** Lleva un encabezado que lo dice. Es
el mismo trato que con freezed: se edita la fuente, se corre el generador, la
salida no se toca.

### Convenciones en cada `.md`

```markdown
<!-- treino-legal
slug: privacidad
title: Política de Privacidad
dart: kPrivacySections
-->
```

- Lo publicable arranca en `<!-- publish:start -->`, o si no hay marcador, en el
  primer `## `.
- `<!-- publish:end -->` corta: lo que sigue es interno (anexos, specs de
  producto).
- Un `.md` sin bloque `treino-legal` se ignora — así la auditoría y este README
  nunca se publican.

### El gate de pendientes

Si queda un marcador `[[...]]` dentro del texto publicable, **el generador
aborta**. Es a propósito: evita que un `[[PENDIENTE: sede social]]` llegue a un
usuario. Hoy hay 29 y por eso `legal_content.dart` todavía no se generó.

Para previsualizar sin publicar:

```bash
python3 scripts/build_legal_content.py --preview --allow-pending
```

### El gate de desfasaje

`ci.yml` corre `--check` en el job `analyze-and-test`: si alguien edita un `.md`
y no regenera, **el PR falla**. Con eso el drift deja de ser un descuido posible
y pasa a ser un error de build.

## Antes de publicar

1. Completar los `[[PENDIENTE]]` restantes. El titular ya está identificado —
   **BACKHAUSTIN S.A.S.**, CUIT 30-71929587-4, matrícula 46468-A del Registro
   Público de Córdoba. Faltan el domicilio de la sede social y la casilla de
   contacto bajo `gettreino.com`.
2. Revisión de un profesional legal. Obligatoria para el descargo médico y el
   contrato del PF; recomendable para el resto.
3. Portar el texto a `legal_content.dart` y publicar en `gettreino.com/legal/*`.
4. Cargar las URLs en App Store Connect y en Play Console.

Verificado contra el código el **2026-08-31**.
