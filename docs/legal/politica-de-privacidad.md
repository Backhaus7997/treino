# Política de Privacidad de TREINO

**Última actualización:** [[PENDIENTE — fecha de publicación]]
**Versión:** 2.0 (borrador)

> ⚠️ **BORRADOR — NO PUBLICAR TODAVÍA.**
> Redactado contra el código y las reglas de Firestore, verificado el 2026-08-31.
> Los campos `[[PENDIENTE]]` los completa el titular. Requiere revisión de un
> profesional legal antes de publicarse. Ver
> [`AUDITORIA-legal-vigente.md`](./AUDITORIA-legal-vigente.md).

---

## 1. Quién es responsable de tus datos

El responsable del tratamiento de tus datos personales es:

- **Titular:** [[PENDIENTE — razón social o nombre y apellido]]
- **CUIT:** [[PENDIENTE]]
- **Domicilio:** [[PENDIENTE]]
- **Correo de contacto y ejercicio de derechos:** [[PENDIENTE — casilla real bajo `gettreino.com`]]

En esta política, «TREINO», «nosotros» y «la app» refieren a ese titular.

La autoridad de control en materia de datos personales en la República
Argentina es la **Agencia de Acceso a la Información Pública (AAIP)**, ante la
cual podés presentar un reclamo si considerás que tus derechos fueron
vulnerados.

---

## 2. Un resumen honesto, antes del detalle

TREINO es una app de entrenamiento con una parte social y un espacio donde
entrenadores personales (PF) ofrecen sus servicios. Eso significa que la app
maneja tres cosas que conviene que sepas desde el arranque:

1. **Recolectamos datos sobre tu salud y tu cuerpo.** Medidas corporales, peso,
   dolores que reportás, cómo te sentís cada día. Son datos sensibles y los
   tratamos como tales.
2. **Parte de lo que cargás lo ven otras personas.** Tu entrenador ve lo que
   compartas con él. El feed y los rankings publican contenido a otros usuarios,
   según lo que vos elijas.
3. **No vendemos tus datos, y no hay publicidad ni rastreadores.** No hay SDK de
   ads, no hay data brokers, no cruzamos tu información con terceros para
   perfilarte.

El resto de este documento es el detalle de eso.

---

## 3. Qué datos recolectamos

### 3.1 Datos de tu cuenta

| Dato | Obligatorio | Origen |
|---|---|---|
| Correo electrónico | Sí | Alta con email, Google o Apple |
| Identificador de usuario (`uid`) | Sí | Generado al crear la cuenta |
| Nombre y apellido | No | Lo cargás vos |
| Nombre visible y foto de perfil | No | Lo cargás vos |
| Teléfono | No | Lo cargás vos. **No se publica** |
| Fecha de nacimiento | No | Lo cargás vos. **No se publica** |
| Género | No | Lo cargás vos |
| Gimnasio | No | Lo elegís vos |
| Fecha de aceptación de los términos | Sí | Registrada automáticamente |

### 3.2 Datos de salud y estado físico — categoría sensible

Estos son **datos sensibles** en los términos del art. 2 de la Ley 25.326.
Los recolectamos únicamente si vos los cargás, y sólo con tu consentimiento
expreso.

| Dato | Detalle |
|---|---|
| **Peso y altura** | Los cargás vos en tu perfil |
| **Medidas corporales** | Más de veinte: porcentaje de grasa, masa muscular, cintura, cadera, pecho, hombros, brazos, antebrazos, muslos, gemelos |
| **Molestias y dolores** | Cuando reportás una molestia en un ejercicio, incluyendo **la foto que adjuntes** |
| **Check-in diario** | Cómo te sentís, si tenés dolor, y en qué zonas del cuerpo |
| **Tests de rendimiento físico** | Resultados de las pruebas que registres |
| **Planes de alimentación** | Los que arme tu entrenador para vos |
| **Historial de entrenamiento** | Sesiones, ejercicios, series, pesos y repeticiones |

**Podés usar TREINO sin cargar ninguno de estos datos.** Son todos opcionales.
Si no los cargás, perdés funciones —el seguimiento de progreso, las
estadísticas, el trabajo con tu entrenador— pero la app funciona.

### 3.3 Registros que tu entrenador lleva sobre vos

Si te vinculás con un entrenador, él puede llevar sobre vos, dentro de TREINO:

- **Notas privadas** sobre tu proceso.
- **Un registro cronológico de seguimiento.**
- **Archivos** que suba asociados a vos (hasta 10 MB cada uno).

**Estos registros no se muestran en tu app.** Los escribe y los ve tu
entrenador. Pero son datos personales tuyos, guardados en nuestra
infraestructura, y por lo tanto **tenés derecho a acceder a ellos**. Podés
pedirlos escribiéndonos a la casilla de contacto de la sección 1. Si eliminás
tu cuenta, se borran junto con el resto de tus datos.

Te lo decimos explícitamente porque no lo verías por tu cuenta.

### 3.4 Ubicación

**Si sos atleta:** te pedimos ubicación aproximada, y sólo si la autorizás, para
ordenar por cercanía los gimnasios y entrenadores. Es opcional de verdad: sin el
permiso, la búsqueda funciona por nombre y especialidad. **Tu ubicación no se
publica a otros usuarios.**

**Si sos entrenador:** las ubicaciones donde trabajás forman parte de tu **perfil
público**. Se guardan con coordenadas precisas y se muestran en el mapa a
cualquier usuario de la app. Esto es deliberado —es cómo tus alumnos te
encuentran— pero implica que **elegís vos qué dirección publicar**. Si trabajás
desde tu casa, tenelo presente.

### 3.5 Contenido que generás

| Dato | Quién lo ve |
|---|---|
| Publicaciones del feed, con foto | Según la privacidad que elijas: amigos, comunidad de tu gimnasio, o público |
| Mensajes y archivos del chat con tu entrenador | Vos y tu entrenador |
| Reseñas y puntuaciones a entrenadores | Público |
| Rutinas y plantillas | Vos, salvo que las compartas |
| Participación en rankings del gimnasio | Los usuarios de tu gimnasio, **sólo si activás el opt-in** |

### 3.6 Datos técnicos y de uso

- **Analítica de uso** (Firebase Analytics): pantallas visitadas y eventos de
  uso, para entender qué funciona y qué no.
- **Reportes de error** (Firebase Crashlytics): estado técnico del dispositivo
  cuando la app falla.
- **Token de notificaciones push**, si aceptás recibirlas.
- **Dirección IP y datos de conexión**, inherentes a cualquier servicio de internet.

### 3.7 Si sos entrenador

Además de lo anterior: tu biografía, especialidad, años de experiencia, tarifa
mensual, ubicaciones de trabajo, si atendés online, y tu **alias de cobro**.

⚠️ **El alias de cobro se publica en tu perfil público.** Es un identificador
financiero visible para cualquier usuario de la app. Cargalo sabiendo eso.

---

## 4. Para qué usamos tus datos

| Finalidad | Qué implica |
|---|---|
| **Prestarte el servicio** | Guardar rutinas, registrar sesiones, calcular progreso, mostrarte estadísticas |
| **Vincularte con un entrenador** | Descubrimiento, solicitud de vínculo, chat, agenda, compartir lo que elijas |
| **Función social** | Feed, seguimientos, reacciones, rankings del gimnasio |
| **Comunicaciones** | Verificación de cuenta, recuperación de contraseña, avisos operativos |
| **Notificaciones** | Recordatorios y avisos, si los aceptás |
| **Seguridad** | Prevención de abuso, protección de cuentas, integridad del servicio |
| **Mejora del producto** | Analítica agregada y diagnóstico de errores |
| **Facturación** | Sólo para entrenadores con suscripción paga |

**Lo que NO hacemos:** no vendemos tus datos, no hacemos publicidad, no cedemos
información a data brokers, no cruzamos tu actividad con fuentes externas para
perfilarte, y no usamos tus datos de salud para nada que no sea mostrarte tu
progreso y —si vos lo habilitás— compartirlo con tu entrenador.

---

## 5. Base legal del tratamiento

Tratamos tus datos, conforme a la Ley 25.326 de Protección de Datos Personales, sobre:

- **Tu consentimiento**, que prestás al aceptar esta política al crear la cuenta.
- **Tu consentimiento expreso y específico** para los datos de salud de la
  sección 3.2, que se solicita por separado dentro de la app y podés revocar.
- **La ejecución del servicio** que solicitás al usar la app.
- **El cumplimiento de obligaciones legales**, en particular las registrales y
  fiscales aplicables a la suscripción de entrenadores.

Podés **revocar tu consentimiento** en cualquier momento. Revocarlo puede
implicar que dejemos de poder prestarte parte del servicio.

---

## 6. Quién ve qué

Este es el mapa completo. Vale la pena leerlo entero.

### 6.1 Tu entrenador vinculado

Sólo si aceptás el vínculo, y sólo lo que habilites:

- Tus sesiones de entrenamiento y series, si activás el compartir.
- Tus medidas corporales y tests, si los compartís.
- Tus molestias reportadas, **incluidas las fotos**.
- Tus datos personales de contacto, si activás compartir perfil.
- Los mensajes del chat.

**El canal es de una sola vía en cuanto a escritura:** tu entrenador puede leer
lo que compartas, pero **nunca puede modificar tus datos de entrenamiento**.

**Podés cortar el vínculo cuando quieras**, y con eso cesa el acceso.

### 6.2 Otros usuarios

- Tu perfil público: nombre visible, foto, gimnasio.
- Tus publicaciones, según la privacidad de cada una.
- Tus reseñas a entrenadores.
- Tu posición en los rankings del gimnasio, **sólo si activaste el opt-in**.

**Nunca son públicos:** tu email, tu teléfono, tu fecha de nacimiento, tus
medidas, tus dolores, tu chat, ni tu ubicación si sos atleta.

### 6.3 Proveedores que procesan datos por nuestra cuenta

Actúan como encargados del tratamiento, bajo contrato y sólo siguiendo nuestras
instrucciones:

| Proveedor | Qué procesa |
|---|---|
| **Google (Firebase / Google Cloud)** | Autenticación, base de datos, archivos, notificaciones, analítica, reportes de error |
| **Google Places** | Las búsquedas de gimnasios que hacés |
| **Resend** | Envío de correo transaccional (verificación, recupero de contraseña) |
| **Vercel** | Alojamiento del sitio web y del panel web para entrenadores |
| **CARTO** | Provee las imágenes del mapa. Al cargarlo, tu dirección IP llega a su servidor |
| **Apple / Google** | Si iniciás sesión con sus cuentas, o si contratás por sus tiendas |

Si abrís un video de ejercicio alojado en **YouTube**, se abre en el navegador y
pasás a regirte por las políticas de Google.

### 6.4 Autoridades

Podemos entregar información si nos lo requiere una autoridad competente por vía
legal, o cuando sea necesario para proteger derechos, la seguridad de las
personas o la integridad del servicio.

---

## 7. Transferencia internacional

Nuestros proveedores operan servidores **fuera de la República Argentina**. Al
usar TREINO, tus datos —incluidos los de salud— se almacenan y procesan en el
exterior.

Esta transferencia se realiza al amparo del art. 12 de la Ley 25.326, sobre la
base de tu consentimiento informado y de los acuerdos de tratamiento de datos
suscriptos con cada proveedor.

[[PENDIENTE — a revisar con asesoramiento legal: encuadre exacto y verificación
de la regiones de los proyectos de Firebase.]]

---

## 8. Cuánto tiempo conservamos tus datos

| Dato | Plazo |
|---|---|
| Cuenta y contenido | Mientras la cuenta esté activa |
| Todo lo asociado a tu cuenta | Se elimina al eliminar la cuenta |
| Registros de facturación (entrenadores) | El plazo que exija la normativa fiscal |
| Copias de seguridad | Hasta **28 días**, por el esquema de backup diario |
| Reportes de error | Según la retención de Firebase Crashlytics |

Detalle completo en [`retencion-y-borrado.md`](./retencion-y-borrado.md).

---

## 9. Tus derechos

Tenés derecho a **acceder, rectificar, actualizar y suprimir** tus datos
personales — el derecho de habeas data del art. 43 de la Constitución Nacional y
de la Ley 25.326.

En concreto podés:

| Derecho | Cómo |
|---|---|
| **Acceder** | Escribinos a la casilla de la sección 1 |
| **Rectificar** | Desde el editor de perfil, o escribiéndonos |
| **Suprimir** | Eliminar tu cuenta desde la app. Ver sección 10 |
| **Revocar consentimiento** | Desde los ajustes, o escribiéndonos |
| **Dejar de compartir con tu entrenador** | Desactivando el compartir, o cortando el vínculo |
| **Salir de los rankings** | Desactivando el opt-in |
| **Reclamar** | Ante la AAIP |

Respondemos las solicitudes de acceso dentro de los **diez días corridos** y las
de rectificación o supresión dentro de los **cinco días hábiles**, conforme a los
arts. 14 y 16 de la Ley 25.326. El ejercicio de estos derechos es **gratuito**.

> **Nota del art. 27 de la Ley 25.326:** el titular puede solicitar en cualquier
> momento el retiro o bloqueo de su nombre de nuestras bases.

---

## 10. Eliminación de tu cuenta

Podés eliminar tu cuenta **desde la propia aplicación**, sin pedírselo a nadie.

Al hacerlo se eliminan de forma automática y en cascada: tu perfil, tus rutinas
y sesiones, tus medidas y tests, tus check-ins, tus molestias reportadas y sus
fotos, tus publicaciones, tus archivos, tus vínculos con entrenadores, y **los
registros privados que tu entrenador llevaba sobre vos**.

También podés solicitarlo en:
[[PENDIENTE — URL pública de solicitud de borrado, exigida por Google Play]]

Detalle técnico en [`retencion-y-borrado.md`](./retencion-y-borrado.md).

---

## 11. Seguridad

- Todo el tráfico viaja cifrado por **HTTPS/TLS**.
- El acceso a cada dato está restringido por **reglas de servidor** que se
  evalúan en cada lectura y escritura — no dependen de la app.
- Usamos **Firebase App Check** para bloquear clientes no legítimos.
- Nunca almacenamos tu contraseña: la maneja el proveedor de autenticación.

Ningún sistema es infalible. Si detectamos un incidente que afecte tus datos
personales, te lo comunicaremos y daremos aviso a la autoridad de control cuando
corresponda.

---

## 12. Menores de edad

[[PENDIENTE — DECISIÓN DEL TITULAR. Redactado provisionalmente para 18 años.]]

TREINO no está dirigido a menores de 18 años. No recolectamos deliberadamente
datos de menores. Si tomamos conocimiento de que una cuenta pertenece a un menor
sin la debida autorización, la daremos de baja y eliminaremos sus datos.

Si sos madre, padre o responsable y creés que un menor a tu cargo nos brindó
datos, escribinos y los eliminamos.

---

## 13. Cambios a esta política

Podemos actualizar esta política. Si el cambio es relevante —sobre todo si
amplía las finalidades o afecta datos sensibles— te lo avisaremos dentro de la
app y, cuando corresponda, te pediremos consentimiento nuevo.

La fecha del encabezado indica la última actualización.

---

## 14. Contacto

[[PENDIENTE — nombre del titular, domicilio y casilla de contacto]]

**Autoridad de control:** Agencia de Acceso a la Información Pública (AAIP),
República Argentina.
