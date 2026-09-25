// GENERADO POR scripts/build_legal_content.py — NO EDITAR A MANO.
//
// La fuente son los markdown de `docs/legal/`. Para cambiar un texto
// legal se edita el .md y se corre:
//
//     python3 scripts/build_legal_content.py
//
// Editar este archivo directamente hace que la app y el sitio digan
// cosas distintas, y entonces no hay forma de probar que acepto el
// usuario. Ver AGENTS.md y docs/legal/README.md.

library;

/// Una seccion de un documento legal: encabezado + cuerpo.
class LegalSection {
  const LegalSection(this.heading, this.body);

  final String heading;
  final String body;
}

/// Ultima revision de Términos y Condiciones.
const String kTermsLastUpdated = '25 de septiembre de 2026';

/// Ultima revision de Política de Privacidad.
const String kPrivacyLastUpdated = '21 de septiembre de 2026';

/// Version vigente de Términos y Condiciones, para evidencia de
/// aceptacion (`UserProfile.accepted...Version`).
///
/// Entero monotonico e independiente por documento:
/// bumpear uno NUNCA obliga a tocar el otro.
const int kTermsVersion = 3;

/// Version vigente de Política de Privacidad, para evidencia de
/// aceptacion (`UserProfile.accepted...Version`).
///
/// Entero monotonico e independiente por documento:
/// bumpear uno NUNCA obliga a tocar el otro.
const int kPrivacyVersion = 4;

/// Fecha (UTC) en la que la version 4 del
/// texto de Política de Privacidad entro en vigencia.
///
/// Machine-comparable, a diferencia del String de display
/// de arriba. Se actualiza UNA sola vez por bump de
/// version, no en cada edicion menor.
final DateTime kPrivacyV4PublishedAt = DateTime.utc(2026, 9, 3);

/// Email de contacto para consultas legales / de privacidad.
const String kLegalContactEmail = 'treino@gettreino.com';

/// Términos y Condiciones.
/// Fuente: docs/legal/terminos-y-condiciones.md
const List<LegalSection> kTermsSections = <LegalSection>[
  LegalSection(
    '1. QUIÉNES SOMOS',
    'TREINO es un servicio prestado por BACKHAUSTIN S.A.S., CUIT 30-71929587-4, inscripta en el Registro Público de Córdoba bajo matrícula N° 46468-A.\n'
        '\n'
        'Al crear una cuenta y usar la aplicación aceptás estos Términos. Si no estás de acuerdo, no la uses.\n'
        '\n'
        'Estos Términos se complementan con la Política de Privacidad, las Normas de Comunidad y el Descargo Médico. Si sos entrenador, además con los Términos para Entrenadores.',
  ),
  LegalSection(
    '2. QUÉ ES TREINO, Y QUÉ NO',
    'TREINO te permite armar y seguir rutinas, registrar tus sesiones, ver tu progreso, compartir contenido con otras personas que entrenan y, si querés, vincularte con un entrenador personal.\n'
        '\n'
        'TREINO es una herramienta de organización y registro. No es un servicio de salud, no reemplaza el asesoramiento de un profesional, y no presta servicios de entrenamiento por sí misma.',
  ),
  LegalSection(
    '3. EDAD MÍNIMA Y CUENTAS DE MENORES',
    'Para crear una cuenta en TREINO tenés que tener 13 años cumplidos. No admitimos cuentas de personas que no hayan alcanzado esa edad.\n'
        '\n'
        'Al crear la cuenta te pedimos tu fecha de nacimiento. Es un dato obligatorio: sin él no se puede completar el alta.\n'
        '\n'
        'Si tenés menos de 18 años seguís siendo menor de edad para la ley argentina, así que necesitás que tu madre, padre o representante legal lea estos Términos, la Política de Privacidad y el Descargo Médico, y dé su consentimiento antes de que uses la aplicación.\n'
        '\n'
        'Si sos madre, padre o representante legal de una persona menor de 18 años que usa TREINO:\n'
        '• Sos responsable de supervisar su uso de la aplicación.\n'
        '• Podés acceder a sus datos, pedir su rectificación y solicitar que los eliminemos en cualquier momento, escribiendo a treino@gettreino.com.\n'
        '• Podés revocar tu consentimiento cuando quieras, lo que implica dar de baja la cuenta.\n'
        '• Tené presente que la aplicación permite vincularse con entrenadores personales independientes, cuyas credenciales TREINO no verifica, y que ese vínculo habilita mensajería privada y el acceso a datos corporales. Ver la sección 6.\n'
        '\n'
        'Si tomamos conocimiento de que una cuenta pertenece a una persona menor de 13 años, o de que una persona menor de 18 la creó sin ese consentimiento, la suspendemos y eliminamos sus datos.\n'
        '\n'
        'Por qué la edad mínima es 13\n'
        '\n'
        'No es un número arbitrario. COPPA, la ley de protección de la infancia en línea de los Estados Unidos, alcanza a los menores de 13 años y les exige un consentimiento parental verificable que TREINO no implementa. Con el piso en 13, ningún usuario de TREINO queda alcanzado por ese régimen.\n'
        '\n'
        'La ley argentina no fija una edad de consentimiento digital: lo que exige es el consentimiento del representante legal mientras la persona sea menor de 18, y eso es lo que pedimos en el alta.\n'
        '\n'
        'Las políticas de familias de las tiendas de aplicaciones no se activan, porque TREINO no se dirige a público infantil: no tiene contenido infantil, no lo promociona y su función es el registro de entrenamiento.\n'
        '\n'
        'La edad es declarada\n'
        '\n'
        'No verificamos tu edad con documentación. Declarar una edad falsa para crear una cuenta es un incumplimiento de estos Términos y habilita la baja de la cuenta en cuanto lo detectemos.',
  ),
  LegalSection(
    '4. TU CUENTA',
    'Podés registrarte con correo electrónico, Google o Apple. En los tres casos se crea una cuenta TREINO.\n'
        '\n'
        'Sos responsable de la confidencialidad de tus credenciales y de la actividad de tu cuenta. Los datos que cargues deben ser veraces. No podés ceder tu cuenta ni compartirla.\n'
        '\n'
        'Hay dos roles: atleta y entrenador. El registro público crea siempre una cuenta de atleta, y el rol no se puede cambiar después. Las cuentas de entrenador las habilita el equipo de TREINO.',
  ),
  LegalSection(
    '5. SALUD Y SEGURIDAD',
    'Entrenás bajo tu propia responsabilidad.\n'
        '\n'
        'Antes de empezar cualquier programa de entrenamiento, consultá a un médico. Si tenés alguna condición preexistente, una lesión, estás embarazada o tomás medicación, es imprescindible.\n'
        '\n'
        'Toda actividad física conlleva riesgos que no pueden eliminarse. Al usar TREINO los asumís voluntariamente.\n'
        '\n'
        'Esta cláusula es un resumen. Lo que rige es el Descargo Médico, que tenés que leer y aceptar por separado.',
  ),
  LegalSection(
    '6. LOS ENTRENADORES SON INDEPENDIENTES',
    'Los entrenadores que ofrecen sus servicios en TREINO son profesionales independientes. No son empleados ni representantes de BACKHAUSTIN S.A.S.\n'
        '• No verificamos sus títulos, matrículas ni credenciales.\n'
        '• No supervisamos ni aprobamos sus planes ni sus indicaciones.\n'
        '• La relación es entre vos y esa persona. Nosotros damos la herramienta.\n'
        '\n'
        'Antes de contratar a alguien, pedile sus credenciales y verificalas.',
  ),
  LegalSection(
    '7. LOS PAGOS CON TU ENTRENADOR NO PASAN POR TREINO',
    'TREINO no intermedia el dinero entre vos y tu entrenador. No lo procesa, no lo retiene, no lo garantiza y no cobra comisión sobre él.\n'
        '\n'
        'La aplicación facilita la comunicación de ese pago: tu entrenador puede registrar lo que le debés y publicar su alias de cobro. Pero el pago ocurre fuera de TREINO y por los medios que acuerden entre ustedes.\n'
        '\n'
        'En consecuencia:\n'
        '• El acuerdo económico es exclusivamente entre vos y tu entrenador.\n'
        '• TREINO no responde si pagaste y no recibiste el servicio, ni si hubo desacuerdo sobre lo acordado.\n'
        '• Los registros de la aplicación son una ayuda de gestión, no un comprobante de pago.\n'
        '• Antes de transferir, verificá con tu entrenador que el alias sea el correcto, por un canal que no sea sólo la app.\n'
        '\n'
        'Si tenés un problema con un entrenador, podés reportarlo. Vamos a revisarlo según las Normas de Comunidad, aunque el conflicto económico en sí no lo resolvemos nosotros.',
  ),
  LegalSection(
    '8. SUSCRIPCIONES Y PAGOS A TREINO',
    'Usar TREINO como atleta es gratuito en su versión básica. Los entrenadores requieren una suscripción, y existe también una suscripción para atletas.\n'
        '\n'
        'Cómo se cobra depende de dónde contrates:\n'
        '• Entrenadores, en el Coach Hub web: el pago lo procesa Mercado Pago y liquida a la cuenta de BACKHAUSTIN S.A.S. Tenés 10 días corridos para arrepentirte y recuperar todo lo pagado, desde el Botón de Arrepentimiento del pie de gettreino.com, sin necesidad de iniciar sesión. Si el último día cae en un día inhábil, el plazo se extiende hasta el primer día hábil siguiente.\n'
        '• Atletas, desde la aplicación móvil: el pago lo procesa App Store o Google Play. La baja y el reembolso los gestiona la tienda, desde los ajustes de suscripciones de tu dispositivo.\n'
        '\n'
        'En los dos casos, pasado el plazo de arrepentimiento podés dar de baja cuando quieras conservando el acceso hasta el final del período pagado.\n'
        '\n'
        'Las condiciones completas están en los Términos de Suscripción.\n'
        '\n'
        'Esto es distinto de los pagos entre vos y tu entrenador, que no pasan por TREINO. Ver la sección 7.',
  ),
  LegalSection(
    '9. TU CONTENIDO',
    'Lo que cargás es tuyo. Conservás la titularidad de tus rutinas, tus fotos, tus publicaciones y tus datos de entrenamiento.\n'
        '\n'
        'Nos otorgás una licencia limitada, no exclusiva y gratuita para almacenarlo, reproducirlo y mostrarlo dentro de la aplicación, con el único fin de prestarte el servicio y de mostrarlo a quienes vos elijas según la privacidad que configures.\n'
        '\n'
        'Esa licencia termina cuando eliminás el contenido o tu cuenta, salvo lo que la política de retención explica que se conserva y por qué.\n'
        '\n'
        'No usamos tu contenido para publicidad ni lo cedemos a terceros con fines comerciales.',
  ),
  LegalSection(
    '10. CÓMO TENÉS QUE COMPORTARTE',
    'Te comprometés a no usar TREINO para fines ilegales, a no acosar ni dañar a otras personas, a no subir contenido ofensivo o que infrinja derechos de terceros, y a no vulnerar la seguridad de la plataforma.\n'
        '\n'
        'Las reglas completas están en las Normas de Comunidad, que forman parte de estos Términos.\n'
        '\n'
        'Podés reportar contenido y bloquear usuarios desde la aplicación. El bloqueo corta el chat, las reacciones, el seguimiento y las reseñas en las dos direcciones.',
  ),
  LegalSection(
    '11. PROPIEDAD INTELECTUAL',
    'La marca TREINO, el diseño de la aplicación, sus logos y su código son propiedad de BACKHAUSTIN S.A.S. y están protegidos por la legislación aplicable. No podés copiarlos, reproducirlos ni reutilizarlos sin autorización escrita.',
  ),
  LegalSection(
    '12. DISPONIBILIDAD DEL SERVICIO',
    'Trabajamos para que TREINO esté disponible, pero podemos modificar, suspender o discontinuar funciones. No garantizamos que el servicio esté libre de interrupciones o de errores.\n'
        '\n'
        'Si vamos a discontinuar una función de la que dependan tus datos, te avisamos con antelación razonable y te damos forma de exportarlos o conservarlos.',
  ),
  LegalSection(
    '13. ALCANCE DEL SERVICIO Y RESPONSABILIDAD',
    'Esta sección delimita qué servicio prestamos, que no es lo mismo que limitar nuestra responsabilidad. La Ley 24.240 de Defensa del Consumidor es de orden público: cualquier cláusula que intente llevarte por debajo del piso que esa ley te reconoce se tiene por no escrita, y nada de lo que sigue pretende hacerlo.\n'
        '\n'
        'Qué hace TREINO. Provee una herramienta para organizar y registrar entrenamientos, un catálogo de rutinas de carácter general, y la infraestructura para que un entrenador personal independiente te asigne planes y se comunique con vos.\n'
        '\n'
        'Qué no hace TREINO. No presta servicios de salud, no diagnostica, no prescribe, no supervisa cómo ejecutás los ejercicios y no evalúa si una rutina es adecuada para tu estado físico. Ninguna rutina del catálogo se arma para vos ni la revisa un profesional para tu caso particular, y eso vale tanto para las producidas con herramientas automáticas como para las publicadas por entrenadores de la plataforma. Ver el Descargo Médico.\n'
        '\n'
        'Los entrenadores son independientes. No son empleados ni representantes de BACKHAUSTIN S.A.S. Contratan directamente con vos, definen sus propios servicios y responden por ellos. No verificamos sus credenciales profesionales, y te lo informamos antes de que te vincules. Los conflictos económicos entre vos y tu entrenador se dirimen entre ustedes.\n'
        '\n'
        'Eximentes. Como en cualquier relación de consumo, nuestra responsabilidad se excluye o atenúa cuando el daño obedece al hecho de un tercero por quien no debemos responder, al hecho del propio damnificado o al caso fortuito, conforme a los arts. 1729, 1730 y 1731 del Código Civil y Comercial.\n'
        '\n'
        'Lo que no excluimos. No limitamos nuestra responsabilidad por dolo ni por culpa grave, ni pretendemos desplazar el deber de seguridad de los arts. 5 y 6 de la Ley 24.240.',
  ),
  LegalSection(
    '14. BAJA Y SUSPENSIÓN',
    'Podés eliminar tu cuenta cuando quieras, desde la aplicación. Lo que pasa con tus datos está en la política de retención.\n'
        '\n'
        'Podemos suspender o cerrar cuentas que incumplan estos Términos o las Normas de Comunidad. Salvo casos graves, te avisamos y podés presentar descargo.',
  ),
  LegalSection(
    '15. CAMBIOS A ESTOS TÉRMINOS',
    'Podemos actualizarlos. Si el cambio es relevante te avisamos dentro de la aplicación y, cuando corresponda, te pedimos que los aceptes de nuevo. El uso continuado implica aceptar la versión vigente.',
  ),
  LegalSection(
    '16. ÁMBITO TERRITORIAL',
    'TREINO se ofrece a nivel mundial.\n'
        '\n'
        'Además de la legislación argentina pueden aplicarse las normas de protección de datos y de defensa del consumidor del país donde residas. Reconocemos y respetamos los derechos que esas normas te reconozcan, aunque sean más amplios que los previstos acá.\n'
        '\n'
        'Si residís en el Espacio Económico Europeo, el Reino Unido, Brasil o cualquier otra jurisdicción cuya normativa de protección de datos te alcance, esos derechos se suman a los que te reconoce la ley argentina y no los desplazan.\n'
        '\n'
        'La Política de Privacidad detalla, para cada finalidad, qué datos tratamos y con qué base legal; cómo se transfieren datos fuera de tu país; los plazos en que notificamos un incidente de seguridad; y cómo ejercer los derechos de acceso, rectificación, supresión, portabilidad y oposición.',
  ),
  LegalSection(
    '17. LEY APLICABLE Y JURISDICCIÓN',
    'Estos Términos se rigen por las leyes de la República Argentina.\n'
        '\n'
        'Si usás TREINO como atleta, sos consumidor. Los conflictos que surjan de estos Términos se resuelven ante los tribunales del lugar donde recibiste o debiste recibir el servicio, conforme al art. 1109 del Código Civil y Comercial. No hay prórroga de jurisdicción: ninguna cláusula puede obligarte a litigar en otra sede, y si la hubiera, la ley la tiene por no escrita. Si residís fuera de la Argentina, el art. 2654 del mismo Código tampoco admite el acuerdo de elección de foro en esta materia.\n'
        '\n'
        'Tampoco te obligamos a arbitraje. El art. 1651, incs. c) y d), lo excluye tanto para las relaciones de consumo como para los contratos por adhesión, cualquiera sea su objeto.\n'
        '\n'
        'Si usás TREINO como entrenador, la relación no es de consumo y las condiciones de competencia están en el Contrato del Entrenador.',
  ),
  LegalSection(
    '18. CONTACTO',
    'BACKHAUSTIN S.A.S. — CUIT 30-71929587-4 Domicilio: Molino de Torres 5301, Córdoba Capital, Provincia de Córdoba (CP 5021), República Argentina Correo: treino@gettreino.com',
  ),
];

/// Política de Privacidad.
/// Fuente: docs/legal/politica-de-privacidad.md
const List<LegalSection> kPrivacySections = <LegalSection>[
  LegalSection(
    '1. QUIÉN ES RESPONSABLE DE TUS DATOS',
    'El responsable del tratamiento de tus datos personales es:\n'
        '• Razón social: BACKHAUSTIN S.A.S.\n'
        '• CUIT: 30-71929587-4\n'
        '• Inscripción: Registro Público de Córdoba, Protocolo de Contratos y Disoluciones, Matrícula N° 46468-A. Resolución de la Dirección General de Inspección de Personas Jurídicas de la Provincia de Córdoba del 5 de febrero de 2026 (Expte. 0007-288597/2026). Constituida el 23 de enero de 2026 bajo el régimen de la Ley 27.349.\n'
        '• Domicilio legal: Molino de Torres 5301, Córdoba Capital, Provincia de Córdoba (CP 5021), República Argentina\n'
        '• Correo de contacto y ejercicio de derechos: treino@gettreino.com\n'
        '\n'
        'TREINO es un servicio prestado por BACKHAUSTIN S.A.S. En esta política, «TREINO», «nosotros» y «la app» refieren a esa sociedad.\n'
        '\n'
        'La autoridad de control en materia de datos personales en la República Argentina es la Agencia de Acceso a la Información Pública (AAIP), ante la cual podés presentar un reclamo si considerás que tus derechos fueron vulnerados.',
  ),
  LegalSection(
    '2. UN RESUMEN HONESTO, ANTES DEL DETALLE',
    'TREINO es una app de entrenamiento con una parte social y un espacio donde entrenadores personales (PF) ofrecen sus servicios. Eso significa que la app maneja tres cosas que conviene que sepas desde el arranque:\n'
        '• Recolectamos datos sobre tu salud y tu cuerpo. Medidas corporales, peso, dolores que reportás, cómo te sentís cada día. Son datos sensibles y los tratamos como tales.\n'
        '• Parte de lo que cargás lo ven otras personas. Tu entrenador ve lo que compartas con él. El feed y los rankings publican contenido a otros usuarios, según lo que vos elijas.\n'
        '• No vendemos tus datos, y no hay publicidad ni rastreadores. No hay SDK de ads, no hay data brokers, no cruzamos tu información con terceros para perfilarte.\n'
        '\n'
        'El resto de este documento es el detalle de eso.',
  ),
  LegalSection(
    '3. QUÉ DATOS RECOLECTAMOS',
    '3.1 Datos de tu cuenta\n'
        '• Dato: Correo electrónico — Obligatorio: Sí — Origen: Alta con email, Google o Apple\n'
        '• Dato: Identificador de usuario (uid) — Obligatorio: Sí — Origen: Generado al crear la cuenta\n'
        '• Dato: Nombre y apellido — Obligatorio: No — Origen: Lo cargás vos\n'
        '• Dato: Nombre visible y foto de perfil — Obligatorio: No — Origen: Lo cargás vos\n'
        '• Dato: Teléfono — Obligatorio: No — Origen: Lo cargás vos. No se publica\n'
        '• Dato: Fecha de nacimiento — Obligatorio: Sí — Origen: La cargás vos al crear la cuenta. No se publica\n'
        '• Dato: Género — Obligatorio: No — Origen: Lo cargás vos\n'
        '• Dato: Gimnasio — Obligatorio: No — Origen: Lo elegís vos\n'
        '• Dato: Fecha de aceptación de los términos — Obligatorio: Sí — Origen: Registrada automáticamente\n'
        '\n'
        'Por qué la fecha de nacimiento es obligatoria. Es el único dato de esta tabla que no pedimos para prestarte el servicio, sino para cumplir la ley: es con lo que verificamos la edad mínima de la sección 12. No se muestra a nadie, no se usa con ningún otro fin, y no se comparte con tu entrenador salvo que vos actives el compartir perfil.\n'
        '\n'
        '3.2 Datos de salud y estado físico — categoría sensible\n'
        '\n'
        'Estos son datos sensibles en los términos del art. 2 de la Ley 25.326. Los recolectamos únicamente si vos los cargás, y sólo con tu consentimiento expreso.\n'
        '• Peso y altura: Los cargás vos en tu perfil\n'
        '• Medidas corporales: Más de veinte: porcentaje de grasa, masa muscular, cintura, cadera, pecho, hombros, brazos, antebrazos, muslos, gemelos\n'
        '• Molestias y dolores: Cuando reportás una molestia en un ejercicio, incluyendo la foto que adjuntes\n'
        '• Check-in diario: Cómo te sentís, si tenés dolor, y en qué zonas del cuerpo\n'
        '• Tests de rendimiento físico: Resultados de las pruebas que registres\n'
        '• Planes de alimentación: Los que arme tu entrenador para vos\n'
        '• Historial de entrenamiento: Sesiones, ejercicios, series, pesos y repeticiones\n'
        '\n'
        'Podés usar TREINO sin cargar ninguno de estos datos. Son todos opcionales. Si no los cargás, perdés funciones —el seguimiento de progreso, las estadísticas, el trabajo con tu entrenador— pero la app funciona.\n'
        '\n'
        '3.3 Registros que tu entrenador lleva sobre vos\n'
        '\n'
        'Si te vinculás con un entrenador, él puede llevar sobre vos, dentro de TREINO:\n'
        '• Notas privadas sobre tu proceso.\n'
        '• Un registro cronológico de seguimiento.\n'
        '• Archivos que suba asociados a vos (hasta 10 MB cada uno).\n'
        '\n'
        'Estos registros no se muestran en tu app. Los escribe y los ve tu entrenador. Pero son datos personales tuyos, guardados en nuestra infraestructura, y por lo tanto tenés derecho a acceder a ellos. Podés pedirlos escribiéndonos a la casilla de contacto de la sección 1. Si eliminás tu cuenta, se borran junto con el resto de tus datos.\n'
        '\n'
        'Te lo decimos explícitamente porque no lo verías por tu cuenta.\n'
        '\n'
        '3.4 Ubicación\n'
        '\n'
        'Si sos atleta: te pedimos ubicación aproximada, y sólo si la autorizás, para ordenar por cercanía los gimnasios y entrenadores. Es opcional de verdad: sin el permiso, la búsqueda funciona por nombre y especialidad. Tu ubicación no se publica a otros usuarios.\n'
        '\n'
        'Tus coordenadas exactas no salen de tu teléfono: para buscar gimnasios le mandamos a nuestro proveedor de mapas una zona aproximada de unos 5 km, no tu punto.\n'
        '\n'
        'Si sos entrenador: las ubicaciones donde trabajás forman parte de tu perfil público. Se guardan con coordenadas precisas y se muestran en el mapa a cualquier usuario de la app. Esto es deliberado —es cómo tus alumnos te encuentran— pero implica que elegís vos qué dirección publicar. Si trabajás desde tu casa, tenelo presente.\n'
        '\n'
        '3.5 Contenido que generás\n'
        '• Publicaciones del feed, con foto: Según la privacidad que elijas: amigos, comunidad de tu gimnasio, o público\n'
        '• Mensajes y archivos del chat con tu entrenador: Vos y tu entrenador\n'
        '• Reseñas y puntuaciones a entrenadores: Público\n'
        '• Rutinas y plantillas: Vos, salvo que las compartas\n'
        '• Participación en rankings del gimnasio: Los usuarios de tu gimnasio, sólo si activás el opt-in\n'
        '\n'
        '3.6 Datos técnicos y de uso\n'
        '• Analítica de uso (Firebase Analytics): pantallas visitadas y eventos de uso, para entender qué funciona y qué no.\n'
        '• Reportes de error (Firebase Crashlytics): estado técnico del dispositivo cuando la app falla.\n'
        '• Token de notificaciones push, si aceptás recibirlas.\n'
        '• Dirección IP y datos de conexión, inherentes a cualquier servicio de internet.\n'
        '\n'
        '3.7 Si sos entrenador\n'
        '\n'
        'Además de lo anterior: tu biografía, especialidad, años de experiencia, tarifa mensual, ubicaciones de trabajo, si atendés online, y tu alias de cobro.\n'
        '\n'
        '⚠️ El alias de cobro se publica en tu perfil público. Es un identificador financiero visible para cualquier usuario de la app. Cargalo sabiendo eso.',
  ),
  LegalSection(
    '4. PARA QUÉ USAMOS TUS DATOS',
    '• Prestarte el servicio: Guardar rutinas, registrar sesiones, calcular progreso, mostrarte estadísticas\n'
        '• Vincularte con un entrenador: Descubrimiento, solicitud de vínculo, chat, agenda, compartir lo que elijas\n'
        '• Función social: Feed, seguimientos, reacciones, rankings del gimnasio\n'
        '• Comunicaciones: Verificación de cuenta, recuperación de contraseña, avisos operativos\n'
        '• Notificaciones: Recordatorios y avisos, si los aceptás\n'
        '• Seguridad: Prevención de abuso, protección de cuentas, integridad del servicio\n'
        '• Mejora del producto: Analítica agregada y diagnóstico de errores\n'
        '• Facturación: Sólo para entrenadores con suscripción paga\n'
        '\n'
        'Lo que NO hacemos: no vendemos tus datos, no hacemos publicidad, no cedemos información a data brokers, no cruzamos tu actividad con fuentes externas para perfilarte, y no usamos tus datos de salud para nada que no sea mostrarte tu progreso y —si vos lo habilitás— compartirlo con tu entrenador.',
  ),
  LegalSection(
    '5. BASE LEGAL DEL TRATAMIENTO',
    'Tratamos tus datos, conforme a la Ley 25.326 de Protección de Datos Personales, sobre:\n'
        '• Tu consentimiento, que prestás al aceptar esta política al crear la cuenta.\n'
        '• Tu consentimiento expreso y específico para los datos de salud de la sección 3.2, que se solicita por separado dentro de la app y podés revocar.\n'
        '• La ejecución del servicio que solicitás al usar la app.\n'
        '• El cumplimiento de obligaciones legales, en particular las registrales y fiscales aplicables a la suscripción de entrenadores.\n'
        '\n'
        'Podés revocar tu consentimiento en cualquier momento. Revocarlo puede implicar que dejemos de poder prestarte parte del servicio.',
  ),
  LegalSection(
    '6. QUIÉN VE QUÉ',
    'Este es el mapa completo. Vale la pena leerlo entero.\n'
        '\n'
        '6.1 Tu entrenador vinculado\n'
        '\n'
        'Sólo si aceptás el vínculo, y sólo lo que habilites:\n'
        '• Tus sesiones de entrenamiento y series, si activás el compartir.\n'
        '• Tus medidas corporales y tests, si los compartís.\n'
        '• Tus molestias reportadas, incluidas las fotos.\n'
        '• Tus datos personales de contacto, si activás compartir perfil.\n'
        '• Los mensajes del chat.\n'
        '\n'
        'El canal es de una sola vía en cuanto a escritura: tu entrenador puede leer lo que compartas, pero nunca puede modificar tus datos de entrenamiento.\n'
        '\n'
        'Podés cortar el vínculo cuando quieras, y con eso cesa el acceso.\n'
        '\n'
        '6.2 Otros usuarios\n'
        '• Tu perfil público: nombre visible, foto, gimnasio.\n'
        '• Tus publicaciones, según la privacidad de cada una.\n'
        '• Tus reseñas a entrenadores.\n'
        '• Tu posición en los rankings del gimnasio, sólo si activaste el opt-in.\n'
        '\n'
        'Nunca son públicos: tu email, tu teléfono, tu fecha de nacimiento, tus medidas, tus dolores, tu chat, ni tu ubicación si sos atleta.\n'
        '\n'
        '6.3 Proveedores que procesan datos por nuestra cuenta\n'
        '\n'
        'Actúan como encargados del tratamiento, bajo contrato y sólo siguiendo nuestras instrucciones:\n'
        '• Google (Firebase / Google Cloud): Autenticación, base de datos, archivos, notificaciones, analítica, reportes de error\n'
        '• Google Places: Las búsquedas de gimnasios que hacés\n'
        '• Resend: Envío de correo transaccional (verificación, recupero de contraseña)\n'
        '• Vercel: Alojamiento del sitio web y del panel web para entrenadores\n'
        '• CARTO: Provee las imágenes del mapa. Al cargarlo, tu dirección IP llega a su servidor\n'
        '• Apple / Google: Si iniciás sesión con sus cuentas, o si contratás por sus tiendas\n'
        '\n'
        'Si abrís un video de ejercicio alojado en YouTube, se abre en el navegador y pasás a regirte por las políticas de Google.\n'
        '\n'
        '6.4 Autoridades\n'
        '\n'
        'Podemos entregar información si nos lo requiere una autoridad competente por vía legal, o cuando sea necesario para proteger derechos, la seguridad de las personas o la integridad del servicio.',
  ),
  LegalSection(
    '7. ALCANCE MUNDIAL Y TRANSFERENCIAS INTERNACIONALES',
    'TREINO se ofrece a nivel mundial. Nuestros proveedores operan servidores fuera de la República Argentina, así que tus datos —incluidos los de salud— se almacenan y procesan en el exterior.\n'
        '\n'
        'Esa transferencia se realiza al amparo del art. 12 de la Ley 25.326, sobre la base de tu consentimiento informado y de los acuerdos de tratamiento suscriptos con cada proveedor.\n'
        '\n'
        'Si residís fuera de la Argentina, pueden aplicarse además las normas de protección de datos de tu país, y reconocemos los derechos que te reconozcan aunque sean más amplios que los previstos acá.\n'
        '\n'
        '7.1 Con qué base legal tratamos cada dato\n'
        '\n'
        'Cuando se aplica el Reglamento General de Protección de Datos europeo, el consentimiento genérico no alcanza: cada finalidad necesita su propia base legal y tiene que estar informada. Esta es la tabla completa.\n'
        '• Para qué: Prestarte el servicio que contrataste — Base legal: Ejecución del contrato, art. 6(1)(b) — Si hay datos de salud: Consentimiento explícito, art. 9(2)(a)\n'
        '• Para qué: Registrar tus medidas, molestias y check-ins — Base legal: Ejecución del contrato, art. 6(1)(b) — Si hay datos de salud: Consentimiento explícito, art. 9(2)(a)\n'
        '• Para qué: Compartir tus datos con el entrenador al que te vinculaste — Base legal: Ejecución del contrato, art. 6(1)(b) — Si hay datos de salud: Consentimiento explícito, art. 9(2)(a)\n'
        '• Para qué: Analítica de producto y mejora del servicio — Base legal: Interés legítimo, art. 6(1)(f) — Si hay datos de salud: No usamos datos de salud identificables\n'
        '• Para qué: Comunicaciones comerciales — Base legal: Tu consentimiento, art. 6(1)(a) — Si hay datos de salud: No aplica\n'
        '• Para qué: Facturación y respaldo contable — Base legal: Obligación legal, art. 6(1)(c) — Si hay datos de salud: No aplica\n'
        '\n'
        'Podés retirar tu consentimiento cuando quieras, y hacerlo no afecta la licitud de lo que tratamos antes de que lo retiraras.\n'
        '\n'
        '7.2 Cómo se amparan las transferencias\n'
        '\n'
        'La Argentina cuenta con decisión de adecuación de la Comisión Europea, de modo que transferir datos desde el Espacio Económico Europeo hacia la Argentina no requiere garantías adicionales. Para los proveedores de infraestructura que operan fuera de esos ámbitos, la transferencia se ampara en los acuerdos de tratamiento de datos suscriptos con cada uno.\n'
        '\n'
        '7.3 Derechos adicionales si te alcanza el RGPD\n'
        '\n'
        'Se suman a los de la sección 9:\n'
        '• Portabilidad (art. 20). Podés pedir una copia de los datos que nos facilitaste, en formato estructurado y de uso común. Alcanza a lo que vos cargaste, no a lo que la aplicación calcula o infiere a partir de eso. Incluye tus datos de salud, precisamente porque los tratamos con tu consentimiento explícito.\n'
        '• Oposición (art. 21). Podés oponerte al tratamiento que hacemos por interés legítimo. Y para las comunicaciones comerciales la oposición es absoluta: si la ejercés, dejamos de enviarlas sin ponderar nada en contra.\n'
        '\n'
        '7.4 Qué hacemos ante un incidente de seguridad\n'
        '• Damos aviso a la autoridad de control sin dilación indebida y, de ser posible, dentro de las 72 horas de haber tomado conocimiento, salvo que sea improbable que el incidente entrañe un riesgo para tus derechos (art. 33 del RGPD).\n'
        '• Te avisamos a vos cuando sea probable que entrañe un alto riesgo para tus derechos y libertades (art. 34).\n'
        '• Si residís en Brasil, el aviso a la ANPD se cursa dentro de los 3 días hábiles, conforme a la Resolución CD/ANPD 15/2024.\n'
        '\n'
        '7.5 Otras jurisdicciones\n'
        '• Brasil. La LGPD se aplica por ofrecer el servicio a personas que están en Brasil. Tus datos de salud son sensibles bajo esa ley y su tratamiento requiere consentimiento específico y destacado.\n'
        '• Reino Unido. Rige el UK GDPR, y la Argentina también tiene adecuación reconocida por el Reino Unido.',
  ),
  LegalSection(
    '8. CUÁNTO TIEMPO CONSERVAMOS TUS DATOS',
    '• Cuenta y contenido: Mientras la cuenta esté activa\n'
        '• Todo lo asociado a tu cuenta: Se elimina al eliminar la cuenta\n'
        '• Registros de facturación (entrenadores): El plazo que exija la normativa fiscal\n'
        '• Copias de seguridad: Hasta 28 días, por el esquema de backup diario\n'
        '• Reportes de error: Según la retención de Firebase Crashlytics\n'
        '\n'
        'Detalle completo en retencion-y-borrado.md.',
  ),
  LegalSection(
    '9. TUS DERECHOS',
    'Tenés derecho a acceder, rectificar, actualizar y suprimir tus datos personales — el derecho de habeas data del art. 43 de la Constitución Nacional y de la Ley 25.326.\n'
        '\n'
        'En concreto podés:\n'
        '• Acceder: Escribinos a la casilla de la sección 1\n'
        '• Rectificar: Desde el editor de perfil, o escribiéndonos\n'
        '• Suprimir: Eliminar tu cuenta desde la app. Ver sección 10\n'
        '• Revocar consentimiento: Desde los ajustes, o escribiéndonos\n'
        '• Dejar de compartir con tu entrenador: Desactivando el compartir, o cortando el vínculo\n'
        '• Salir de los rankings: Desactivando el opt-in\n'
        '• Reclamar: Ante la AAIP\n'
        '\n'
        'Respondemos las solicitudes de acceso dentro de los diez días corridos y las de rectificación o supresión dentro de los cinco días hábiles, conforme a los arts. 14 y 16 de la Ley 25.326. El ejercicio de estos derechos es gratuito.\n'
        '\n'
        'Nota del art. 27 de la Ley 25.326: el titular puede solicitar en cualquier momento el retiro o bloqueo de su nombre de nuestras bases.',
  ),
  LegalSection(
    '10. ELIMINACIÓN DE TU CUENTA',
    'Podés eliminar tu cuenta desde la propia aplicación, sin pedírselo a nadie.\n'
        '\n'
        'Al hacerlo se eliminan de forma automática y en cascada: tu perfil, tus rutinas y sesiones, tus medidas y tests, tus check-ins, tus molestias reportadas y sus fotos, tus publicaciones, tus archivos, tus vínculos con entrenadores, y los registros privados que tu entrenador llevaba sobre vos.\n'
        '\n'
        'También podés solicitarlo en gettreino.com/es/eliminar-cuenta, sin instalar la app y sin iniciar sesión.\n'
        '\n'
        'Detalle técnico en retencion-y-borrado.md.',
  ),
  LegalSection(
    '11. SEGURIDAD',
    '• Todo el tráfico viaja cifrado por HTTPS/TLS.\n'
        '• El acceso a cada dato está restringido por reglas de servidor que se evalúan en cada lectura y escritura — no dependen de la app.\n'
        '• Usamos Firebase App Check para bloquear clientes no legítimos.\n'
        '• Nunca almacenamos tu contraseña: la maneja el proveedor de autenticación.\n'
        '\n'
        'Ningún sistema es infalible. Si detectamos un incidente que afecte tus datos personales, te lo comunicaremos y daremos aviso a la autoridad de control cuando corresponda.',
  ),
  LegalSection(
    '12. PERSONAS MENORES DE 18 AÑOS',
    'La edad mínima para crear una cuenta en TREINO es de 13 años. No admitimos cuentas de personas que no hayan alcanzado esa edad, y la fecha de nacimiento es un dato obligatorio del alta.\n'
        '\n'
        'Si tenés menos de 18 años seguís siendo menor de edad para la ley argentina, así que hace falta el consentimiento de tu madre, padre o representante legal antes de que uses la aplicación y antes de que carguemos cualquier dato tuyo.\n'
        '\n'
        '12.1 Si sos madre, padre o representante legal\n'
        '\n'
        'Tenés derecho a:\n'
        '• Saber qué datos recolectamos de la persona a tu cargo. Están todos descriptos en la sección 3 de esta política, incluidos los datos de salud.\n'
        '• Acceder a esos datos y pedir una copia.\n'
        '• Rectificarlos o pedir que los eliminemos.\n'
        '• Negarte a que sigamos recolectándolos, lo que implica dar de baja la cuenta.\n'
        '• Revocar tu consentimiento en cualquier momento.\n'
        '\n'
        'Escribinos a treino@gettreino.com desde una dirección que podamos asociar a la cuenta y lo resolvemos.\n'
        '\n'
        '12.2 Lo que conviene que sepas antes de consentir\n'
        '\n'
        'Con la misma franqueza con la que está escrito el resto de este documento:\n'
        '• TREINO registra peso, medidas corporales y porcentaje de grasa, y grafica su evolución en el tiempo.\n'
        '• La aplicación permite vincularse con entrenadores personales independientes. TREINO no verifica sus títulos ni sus credenciales. Ese vínculo habilita mensajería privada y el acceso a las medidas, las fotos de molestias y el historial que la persona comparta.\n'
        '• El feed social permite publicar texto y fotos a otros usuarios, y los rankings por gimnasio muestran resultados a la comunidad de ese gimnasio, si se activa el opt-in.\n'
        '\n'
        'Todas esas funciones son opcionales, pero conviene que las conozcas antes de consentir.\n'
        '\n'
        '12.3 Cumplimiento\n'
        '\n'
        'Si tomamos conocimiento de que una cuenta pertenece a una persona menor de 13 años, o de que una persona menor de 18 la creó sin el consentimiento de su representante legal, la suspendemos y eliminamos sus datos.\n'
        '\n'
        '12.4 Por qué el mínimo es 13\n'
        '\n'
        'COPPA, la ley de protección de la infancia en línea de los Estados Unidos, alcanza a los menores de 13 años y exige un consentimiento parental verificable que TREINO no implementa. Con el piso en 13, ningún usuario queda alcanzado por ese régimen.\n'
        '\n'
        'La ley argentina no fija una edad de consentimiento digital. Lo que exige es el consentimiento del representante legal mientras la persona sea menor de 18, y eso es lo que pedimos en el alta.\n'
        '\n'
        'La edad es declarada por quien crea la cuenta y no la verificamos con documentación.',
  ),
  LegalSection(
    '13. CAMBIOS A ESTA POLÍTICA',
    'Podemos actualizar esta política. Si el cambio es relevante —sobre todo si amplía las finalidades o afecta datos sensibles— te lo avisaremos dentro de la app y, cuando corresponda, te pediremos consentimiento nuevo.\n'
        '\n'
        'La fecha del encabezado indica la última actualización.',
  ),
  LegalSection(
    '14. CONTACTO',
    'BACKHAUSTIN S.A.S. — CUIT 30-71929587-4 Domicilio: Molino de Torres 5301, Córdoba Capital, Provincia de Córdoba (CP 5021), República Argentina Correo: treino@gettreino.com\n'
        '\n'
        'Autoridad de control: Agencia de Acceso a la Información Pública (AAIP), República Argentina.',
  ),
];

/// Una entrada del indice de documentos legales.
typedef LegalDocumentEntry = ({
  String title,
  List<LegalSection> sections,
  String lastUpdated,
});

/// Indice de los documentos, para la entrada Perfil -> Legales.
const List<LegalDocumentEntry> kLegalDocuments = <LegalDocumentEntry>[
  (
    title: 'Términos y Condiciones',
    sections: kTermsSections,
    lastUpdated: kTermsLastUpdated,
  ),
  (
    title: 'Política de Privacidad',
    sections: kPrivacySections,
    lastUpdated: kPrivacyLastUpdated,
  ),
];
