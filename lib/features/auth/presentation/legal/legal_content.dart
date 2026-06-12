/// Contenido de los documentos legales de TREINO (Términos y Condiciones +
/// Política de Privacidad), en es-AR.
///
/// ⚠️ Borrador inicial redactado para el producto. Debe ser revisado por un
/// profesional legal antes de un lanzamiento productivo. Para actualizarlo,
/// editá las listas de [LegalSection] de abajo — la pantalla
/// [LegalDocumentScreen] las renderiza automáticamente.
library;

/// Una sección de un documento legal: un encabezado + su cuerpo.
class LegalSection {
  const LegalSection(this.heading, this.body);

  final String heading;
  final String body;
}

/// Fecha de última actualización mostrada al pie de cada documento.
const String kLegalLastUpdated = '12 de junio de 2026';

/// Email de contacto para consultas legales / de privacidad.
const String kLegalContactEmail = 'equipo@treino.app';

/// Términos y Condiciones de uso.
const List<LegalSection> kTermsSections = <LegalSection>[
  LegalSection(
    '1. Aceptación',
    'Al crear una cuenta y usar TREINO aceptás estos Términos y Condiciones. Si '
        'no estás de acuerdo, no uses la aplicación. Estos términos forman un '
        'acuerdo entre vos y TREINO.',
  ),
  LegalSection(
    '2. Qué es TREINO',
    'TREINO es una aplicación de entrenamiento que te permite armar y seguir '
        'rutinas, registrar tus sesiones, ver tu progreso y, si querés, '
        'conectarte con entrenadores (PFs). TREINO es una herramienta de '
        'organización: no reemplaza el asesoramiento de un profesional.',
  ),
  LegalSection(
    '3. Aviso de salud',
    'TREINO no brinda asesoramiento médico ni profesional de la salud. Antes de '
        'empezar cualquier plan de entrenamiento consultá a un médico o '
        'profesional, especialmente si tenés alguna condición preexistente. '
        'Entrenás bajo tu propia responsabilidad y reconocés que toda actividad '
        'física conlleva riesgos.',
  ),
  LegalSection(
    '4. Tu cuenta',
    'Podés registrarte con email, Google o Apple. Sos responsable de mantener la '
        'confidencialidad de tus credenciales y de toda la actividad de tu '
        'cuenta. Debés tener al menos 16 años, o contar con el consentimiento de '
        'una persona adulta responsable. Los datos que cargás deben ser veraces.',
  ),
  LegalSection(
    '5. Entrenadores (PFs)',
    'Los entrenadores que ofrecen sus servicios en TREINO son profesionales '
        'independientes, no empleados ni representantes de TREINO. Los planes, '
        'consejos y servicios que brindan son de su exclusiva responsabilidad. '
        'TREINO no supervisa ni garantiza el contenido de cada plan ni los '
        'resultados de tu entrenamiento.',
  ),
  LegalSection(
    '6. Uso aceptable',
    'Te comprometés a no usar TREINO para fines ilegales, a no acosar ni dañar a '
        'otros usuarios, a no subir contenido ofensivo, difamatorio o que '
        'infrinja derechos de terceros, y a no intentar vulnerar la seguridad de '
        'la plataforma.',
  ),
  LegalSection(
    '7. Tu contenido',
    'Conservás la titularidad del contenido que cargás (rutinas, fotos, datos de '
        'entrenamiento). Nos otorgás una licencia limitada para almacenarlo y '
        'mostrarlo dentro de la app con el fin de prestarte el servicio.',
  ),
  LegalSection(
    '8. Propiedad intelectual',
    'La aplicación, su marca, diseño, logos y código son propiedad de TREINO y '
        'están protegidos por las leyes aplicables. No podés copiarlos ni '
        'reutilizarlos sin autorización.',
  ),
  LegalSection(
    '9. Disponibilidad y cambios del servicio',
    'Trabajamos para que TREINO esté disponible, pero podemos modificar, '
        'suspender o discontinuar funciones en cualquier momento. No garantizamos '
        'que el servicio esté libre de interrupciones o errores.',
  ),
  LegalSection(
    '10. Limitación de responsabilidad',
    'En la máxima medida permitida por la ley, TREINO no será responsable por '
        'lesiones, daños indirectos, pérdida de datos o perjuicios derivados del '
        'uso de la app, del entrenamiento realizado o de los servicios de '
        'entrenadores independientes.',
  ),
  LegalSection(
    '11. Baja y suspensión',
    'Podés eliminar tu cuenta cuando quieras desde la aplicación. Podemos '
        'suspender o cerrar cuentas que incumplan estos términos o la ley.',
  ),
  LegalSection(
    '12. Cambios a estos términos',
    'Podemos actualizar estos Términos. Si los cambios son relevantes, te lo '
        'avisaremos dentro de la app. El uso continuado implica la aceptación de '
        'la versión vigente.',
  ),
  LegalSection(
    '13. Ley aplicable',
    'Estos Términos se rigen por las leyes de la República Argentina. Cualquier '
        'controversia se someterá a los tribunales competentes que correspondan.',
  ),
  LegalSection(
    '14. Contacto',
    'Por cualquier consulta sobre estos Términos, escribinos a $kLegalContactEmail.',
  ),
];

/// Política de Privacidad.
const List<LegalSection> kPrivacySections = <LegalSection>[
  LegalSection(
    '1. Qué datos recolectamos',
    'Recolectamos: datos de tu cuenta (email, nombre de usuario y foto/avatar si '
        'la cargás); tus datos de entrenamiento (rutinas, sesiones, pesos, '
        'progreso); tu ubicación aproximada solo si la activás; datos de uso y '
        'analítica para mejorar la app; y datos técnicos básicos de tu '
        'dispositivo.',
  ),
  LegalSection(
    '2. Para qué los usamos',
    'Usamos tus datos para prestarte el servicio (guardar y mostrar tus rutinas '
        'y progreso), conectarte con entrenadores si lo elegís, brindarte '
        'soporte, y mejorar y asegurar la aplicación.',
  ),
  LegalSection(
    '3. Base legal',
    'Tratamos tus datos sobre la base de tu consentimiento (que prestás al '
        'aceptar esta política) y de la ejecución del servicio que solicitás, '
        'conforme a la Ley 25.326 de Protección de Datos Personales.',
  ),
  LegalSection(
    '4. Ubicación',
    'Solo accedemos a tu ubicación si la activás expresamente, y únicamente para '
        'mostrarte entrenadores cerca tuyo. Tu ubicación no es visible para otros '
        'usuarios y podés revocar el permiso cuando quieras desde tu dispositivo.',
  ),
  LegalSection(
    '5. Con quién compartimos tus datos',
    'Usamos proveedores de infraestructura como Google Firebase, que actúan como '
        'encargados del tratamiento por nuestra cuenta. Si te vinculás con un '
        'entrenador, este puede ver los datos de entrenamiento necesarios para '
        'asistirte. No vendemos tus datos personales a terceros.',
  ),
  LegalSection(
    '6. Conservación',
    'Conservamos tus datos mientras mantengas tu cuenta. Si la eliminás, '
        'borramos tus datos personales, salvo aquello que debamos conservar por '
        'obligación legal.',
  ),
  LegalSection(
    '7. Tus derechos',
    'Podés acceder, rectificar, actualizar y solicitar la supresión de tus datos '
        '(derecho de habeas data, Ley 25.326). Podés ejercer estos derechos desde '
        'la app o escribiendo a $kLegalContactEmail. La Agencia de Acceso a la '
        'Información Pública es la autoridad de control en Argentina.',
  ),
  LegalSection(
    '8. Seguridad',
    'Aplicamos medidas razonables para proteger tus datos. Sin embargo, ningún '
        'sistema es 100% seguro, por lo que no podemos garantizar seguridad '
        'absoluta.',
  ),
  LegalSection(
    '9. Menores',
    'TREINO no está dirigido a menores de 16 años sin el consentimiento de una '
        'persona adulta responsable. Si creés que un menor nos brindó datos sin '
        'ese consentimiento, escribinos para eliminarlos.',
  ),
  LegalSection(
    '10. Cambios a esta política',
    'Podemos actualizar esta Política de Privacidad. Si los cambios son '
        'relevantes, te lo avisaremos dentro de la app.',
  ),
  LegalSection(
    '11. Responsable y contacto',
    'El responsable del tratamiento de tus datos es TREINO. Por consultas sobre '
        'privacidad o para ejercer tus derechos, escribinos a $kLegalContactEmail.',
  ),
];
