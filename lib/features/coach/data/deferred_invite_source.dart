/// De dónde saldría una invitación que llegó ANTES de que la app existiera en
/// el teléfono. Hoy: de ningún lado.
///
/// ─── El caso que esto describe, y por qué queda sin resolver ───────────────
///
/// El alumno abre el link sin tener TREINO instalada. El sistema operativo no
/// tiene a quién dársela: lo manda a la tienda. Cuando termina de instalar y
/// abre la app, el link ya no existe en ninguna parte — arranca en frío, sin
/// ninguna pista de por qué se la instaló.
///
/// Eso NO lo resuelve `PendingInviteStore`: ése guarda a disco lo que la app ya
/// recibió, y acá la app todavía no existía. Tampoco los universal links: sólo
/// funcionan si hay app que los reciba. La única forma es que alguien recuerde
/// el click del lado del servidor y lo empareje con la primera apertura — eso
/// es un servicio de deferred deep linking, con fingerprinting del dispositivo.
///
/// ─── Por qué no hay ninguno conectado ──────────────────────────────────────
///
/// Se llegó a integrar Branch y se sacó, con esta razón: **ese viaje todavía no
/// se puede empezar.** La app está en TestFlight y en closed testing de Play,
/// no hay ficha pública, y `web/abrir/alumno.html` no tiene botón de descarga
/// justamente por eso. No hay tienda de dónde instalar, así que no hay
/// continuidad que preservar.
///
/// Y tenerlo igual costaba dos cosas: un SDK nativo inerte en el build, y —peor—
/// una política de privacidad que declaraba un encargado al que no se le
/// mandaba nada. Declarar un tratamiento que no ocurre es tan incorrecto como
/// omitir uno que sí.
///
/// Sin proveedor se pierde EXACTAMENTE ese caso. Los otros cuatro —sin sesión,
/// sin PF, mismo PF, otro PF— andan igual, y el alumno que instaló puede
/// vincularse buscando al PF en la app, que ya funciona. Es un paso manual, no
/// una función faltante.
///
/// ─── Por qué la interfaz se queda ──────────────────────────────────────────
///
/// Porque no cuesta nada y marca dónde entra. El día que haya ficha pública y
/// se pueda MEDIR cuántas invitaciones mueren en ese paso, conectar un
/// proveedor es implementar esto y cambiar el link que genera el Coach Hub: el
/// flujo de invitación no se entera. Sin la interfaz, esa decisión vuelve a
/// empezar por leerse el flujo entero.
library;

/// El PF de la invitación que provocó una instalación, si alguien lo supiera.
abstract class DeferredInviteSource {
  /// Sólo tiene sentido en la primera apertura después de instalar. De ahí en
  /// adelante los links entran por el camino normal.
  Future<String?> trainerIdDeLaInstalacion();
}

/// La implementación de hoy: no hay proveedor.
///
/// No es un placeholder roto. Es la respuesta correcta mientras no exista un
/// viaje que preservar, y el resto del flujo de invitación está construido para
/// no depender de esto.
class SinDeferredInvites implements DeferredInviteSource {
  const SinDeferredInvites();

  @override
  Future<String?> trainerIdDeLaInstalacion() async => null;
}
