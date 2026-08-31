# `docs/legal/` — documentos legales de TREINO

Fuente de verdad de los textos legales. Lo que hoy ve el usuario in-app vive en
`lib/features/auth/presentation/legal/legal_content.dart`; estos documentos son
su reemplazo, y hay que portarlos ahí y publicarlos en `gettreino.com/legal/*`.

**Ninguno está publicado. Todos son borradores.**

| Documento | Qué es | Estado |
|---|---|---|
| [AUDITORIA-legal-vigente.md](./AUDITORIA-legal-vigente.md) | Contraste del texto vigente contra el código. 5 críticos, 7 altos, 6 medios | Leer primero |
| [politica-de-privacidad.md](./politica-de-privacidad.md) | Reemplazo de `kPrivacySections`, escrito contra el mapa de datos real | Borrador, faltan datos del titular |
| [normas-de-comunidad.md](./normas-de-comunidad.md) | Documento publicable + spec de reporte y bloqueo (Apple 1.2) | Borrador + trabajo de producto pendiente |
| [retencion-y-borrado.md](./retencion-y-borrado.md) | Respaldo de las secciones 8 y 10 de privacidad. URL para Google Play | Borrador |

## Lo que NO está acá

Los documentos que no salen del código —Términos y Condiciones, contrato del PF,
descargo médico, términos de suscripción, arrepentimiento— dependen de
decisiones del titular. Están relevados en la guía de tareas que acompaña a este
directorio.

## Antes de publicar

1. Completar todos los `[[PENDIENTE]]`. El bloqueante duro es la identidad del
   responsable: razón social o nombre, CUIT y domicilio.
2. Revisión de un profesional legal. Obligatoria para el descargo médico y el
   contrato del PF; recomendable para el resto.
3. Portar el texto a `legal_content.dart` y publicar en `gettreino.com/legal/*`.
4. Cargar las URLs en App Store Connect y en Play Console.

Verificado contra el código el **2026-08-31**.
