import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/tokens.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import '../../../../workout/domain/routine.dart';
import '../../../../workout/domain/routine_source.dart';
import '../../../../workout/domain/routine_status.dart';
import '../../../../workout/domain/routine_visibility.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../widgets/coach_hub_widgets.dart';
import 'routine_actions_provider.dart';
import '../../widgets/athlete_picker_dialog.dart';

/// Grilla de las rutinas del PF, en cards.
///
/// Reemplaza el listado de PERSONAS que había en esta sección. La diferencia
/// no es cosmética: aquel listado partía del alumno y sólo podía contar
/// «cuántas rutinas tiene», así que una plantilla sin asignar —que es la mitad
/// del trabajo de un PF— no aparecía en ningún lado.
///
/// El ancho de card y el `Wrap` replican los de la grilla que ya existía acá,
/// para que la sección no cambie de ritmo al cambiar de contenido.
class RoutineCardGrid extends StatelessWidget {
  const RoutineCardGrid({super.key, required this.routines});

  final List<Routine> routines;

  static const double _targetCardWidth = 300;
  static const double _runSpacing = 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final raw =
            ((available + _runSpacing) / (_targetCardWidth + _runSpacing))
                .floor();
        final columns = raw < 1 ? 1 : raw;
        final cardWidth = (available - _runSpacing * (columns - 1)) / columns;
        return Wrap(
          spacing: _runSpacing,
          runSpacing: _runSpacing,
          children: [
            for (final r in routines)
              SizedBox(
                width: cardWidth,
                child: RoutineCard(key: ValueKey(r.id), routine: r),
              ),
          ],
        );
      },
    );
  }
}

/// Una rutina del PF: nombre, sus etiquetas y el resumen de la prescripción.
class RoutineCard extends ConsumerWidget {
  const RoutineCard({super.key, required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final archivada = routine.status == RoutineStatus.archived;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Dos editores, según qué sea la rutina. No es un detalle de routing:
      // un plan asignado se guarda por `updateAssigned` y necesita el alumno
      // en la URL; una plantilla no tiene alumno y va por `updateTemplate`.
      // Mandar una plantilla al editor de planes la haría pedir un
      // `athleteId` que no existe.
      //
      // `push` y no `go`: el editor tiene su propia flecha atrás, y con `go`
      // se reemplaza la entrada de historial y esa flecha queda sin destino.
      // Es el mismo bug que ya se arregló en Nutrición y en Rutinas.
      onTap: () => context.push(_destino(routine)),
      child: Container(
        key: Key('routine_card_${routine.id}'),
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    routine.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.barlowCondensed,
                      fontWeight: AppFonts.w700,
                      fontSize: AppTextSize.bodyLarge,
                      // Una archivada se lee apagada: sigue siendo tuya y
                      // sigue estando, pero ya no es lo que estás usando.
                      color:
                          archivada ? palette.textMuted : palette.textPrimary,
                    ),
                  ),
                ),
                _MenuDeLaRutina(routine: routine),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            _Etiquetas(routine: routine),
            const SizedBox(height: AppSpacing.s8),
            Text(
              _resumen(routine),
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontSize: AppTextSize.caption,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A qué editor va esta rutina.
  ///
  /// Con alumno → el editor de planes, que lo necesita en la URL. Sin alumno
  /// → el de plantillas. Hoy esas dos formas viven en secciones distintas del
  /// Hub —los planes en Rutinas, las plantillas en Biblioteca—, y esta grilla
  /// es el primer lugar donde se ven juntas.
  static String _destino(Routine r) {
    final alumno = r.assignedTo;
    return alumno == null || alumno.isEmpty
        ? '/template-editor/${r.id}'
        : '/routine-editor/$alumno/${r.id}';
  }

  /// Split · nivel · semanas. Lo que distingue una rutina de otra de un
  /// vistazo, sin abrirla.
  static String _resumen(Routine r) {
    final partes = <String>[
      if ((r.split ?? '').trim().isNotEmpty) r.split!.trim(),
      // i18n: Fase W2
      if (r.numWeeks > 1) '${r.numWeeks} semanas' else '1 semana',
    ];
    return partes.join(' · ');
  }
}

/// Las etiquetas de una rutina: a quién está asignada, si es plantilla, si es
/// pública, si está archivada.
///
/// Van en un `Wrap` porque son de largo variable —el nombre de un alumno puede
/// ser largo— y en una `Row` la card desbordaría en la columna más angosta.
class _Etiquetas extends ConsumerWidget {
  const _Etiquetas({required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final etiquetas = <Widget>[];

    final asignadoA = routine.assignedTo;
    if (asignadoA != null && asignadoA.isNotEmpty) {
      // El nombre se resuelve por su cuenta: la card no lo recibe del padre
      // para que la grilla no tenga que juntar todos los perfiles antes de
      // dibujar nada. Mientras resuelve dice «Asignada», no un nombre falso.
      final pub = ref.watch(userPublicProfileProvider(asignadoA)).valueOrNull;
      final nombre = pub?.displayName?.trim();
      etiquetas.add(_Etiqueta(
        texto: nombre == null || nombre.isEmpty
            ? 'Asignada' // i18n: Fase W2
            : 'Asignada a $nombre', // i18n: Fase W2
        color: palette.accentText,
      ));
    } else if (routine.source == RoutineSource.trainerTemplate) {
      etiquetas.add(_Etiqueta(
        texto: 'Plantilla', // i18n: Fase W2
        color: palette.textMuted,
      ));
    }

    if (routine.visibility == RoutineVisibility.public) {
      etiquetas.add(_Etiqueta(
        texto: 'Pública', // i18n: Fase W2
        color: palette.accentText,
      ));
    }

    if (routine.status == RoutineStatus.archived) {
      etiquetas.add(_Etiqueta(
        texto: 'Archivada', // i18n: Fase W2
        color: palette.textMuted,
      ));
    }

    if (etiquetas.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.hairline,
      runSpacing: AppSpacing.hairline,
      children: etiquetas,
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          fontWeight: AppFonts.w600,
          fontSize: AppTextSize.micro,
          color: color,
        ),
      ),
    );
  }
}

/// El ⋮ de una card: asignar, publicar, archivar, recuperar y eliminar.
///
/// Archivar y eliminar conviven a propósito. La app archiva por defecto —«el
/// documento se conserva para mantener referencias históricas de sesiones»,
/// ADR-USR-04— y eso sigue siendo lo correcto para un plan que alguien
/// entrenó. Eliminar es para lo otro: una plantilla que nunca se entrenó, o un
/// plan cargado mal que no debería figurar en la biblioteca.
///
/// **Archivar se llama distinto según qué sea la rutina, y no es cosmética.**
/// Sobre una PLANTILLA, «Archivar» describe bien lo que pasa: sale de tu
/// biblioteca. Sobre un PLAN ASIGNADO, la misma palabra no dice lo que el PF
/// está buscando cuando entra acá —sacarle la rutina a un alumno para darle
/// otra—, y por no encontrar esa acción llegó a pedirla como una función nueva
/// («desasignar»). No hacía falta ninguna: archivar la copia del alumno ES
/// eso. Faltaba que el menú lo dijera con las palabras del PF.
///
/// **No se puede desasignar de verdad, y está bien.** `assignedTo` y `source`
/// son inmutables por regla de servidor (`firestore.rules`, paths 3 y 4).
/// Convertir la copia del alumno de vuelta en plantilla dejaría sus
/// `Session.routineId` colgando de un documento que pasó a ser del PF. Por eso
/// «Sacársela a X» archiva, y el diálogo no promete lo que no hace.
class _MenuDeLaRutina extends ConsumerStatefulWidget {
  const _MenuDeLaRutina({required this.routine});

  final Routine routine;

  @override
  ConsumerState<_MenuDeLaRutina> createState() => _MenuDeLaRutinaState();
}

class _MenuDeLaRutinaState extends ConsumerState<_MenuDeLaRutina> {
  /// Lado de la caja del botón.
  ///
  /// Es la MISMA medida que el `minimumSize` de abajo, y el spinner que lo
  /// reemplaza mientras la acción corre tiene que ocupar exactamente eso o la
  /// card se mueve sola al tocar el menú. Va con nombre y no como `32` suelto
  /// en los dos lados: duplicado se desincroniza, y además el scan de spacing
  /// lee un literal dentro de un `SizedBox` como separación fuera de escala
  /// —con razón— cuando acá es una dimensión de componente, no un espacio.
  static const double _ladoDelBoton = 32;

  bool _ocupado = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final r = widget.routine;
    final archivada = r.status == RoutineStatus.archived;
    final esPlantilla = r.source == RoutineSource.trainerTemplate;
    final publica = r.visibility == RoutineVisibility.public;
    final nombreAlumno = _nombreDelAlumno(ref, r);

    if (_ocupado) {
      return const SizedBox(
        width: _ladoDelBoton,
        height: _ladoDelBoton,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return TreinoPopupMenuButton<_AccionRutina>(
      tooltip: 'Opciones de la rutina', // i18n
      icon: Icon(TreinoIcon.dotsThree, size: 18, color: palette.textMuted),
      // Misma caja que cualquier acción de fila del Hub: `PopupMenuButton` no
      // reenvía `constraints` a su `IconButton`, sólo `style`.
      iconSize: 18,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(_ladoDelBoton, _ladoDelBoton),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onSelected: _ejecutar,
      // Cada acción se ofrece SÓLO donde es válida. Un ítem de menú que falla
      // siempre es peor que no tenerlo: el PF lo aprieta, ve un error y no
      // aprende por qué.
      //
      // `publicar` es el caso claro: la regla de Firestore restringe el flip
      // de `visibility` a docs `trainer-template` del dueño, así que sobre una
      // rutina asignada sería un botón roto por contrato.
      itemBuilder: (_) => [
        if (esPlantilla && !archivada)
          const PopupMenuItem(
            value: _AccionRutina.asignar,
            child: Text('Asignar a un alumno'), // i18n
          ),
        if (esPlantilla && !archivada)
          PopupMenuItem(
            value: publica ? _AccionRutina.despublicar : _AccionRutina.publicar,
            child: Text(
              publica
                  ? 'Despublicar' // i18n
                  : 'Publicar en la comunidad', // i18n
            ),
          ),
        // Publicar el plan de un alumno, que es lo que el PF pidió («esté
        // asignada o no la rutina, poder publicarla»). NO es el mismo ítem que
        // el de arriba: la regla restringe el flip de `visibility` a
        // `trainer-template`, así que sobre un plan no se publica el documento
        // —se crea una plantilla a partir de él y se publica ESA—. El plan del
        // alumno no se toca, y el ítem lo dice con otras palabras para que no
        // se lea como si publicara su rutina.
        if (!esPlantilla && !archivada)
          const PopupMenuItem(
            value: _AccionRutina.publicarComoPlantilla,
            child: Text('Publicar como plantilla'), // i18n
          ),
        // Archivar, con el nombre que corresponde a lo que el PF está
        // haciendo. Sobre un plan asignado, «Archivar» es correcto y no se
        // entiende; «Sacársela a Juan» es la MISMA operación descrita desde el
        // problema del PF. Ver el dartdoc de la clase.
        if (!archivada)
          PopupMenuItem(
            value: _AccionRutina.archivar,
            child: Text(
              esPlantilla
                  ? 'Archivar' // i18n
                  : nombreAlumno == null
                      ? 'Sacársela al alumno' // i18n
                      : 'Sacársela a $nombreAlumno', // i18n
            ),
          ),
        // El camino de vuelta. Existe desde este cambio: hasta ahora el filtro
        // «Archivadas» te la MOSTRABA y no había forma de volver a usarla,
        // mientras el diálogo prometía que se podía recuperar.
        if (archivada)
          const PopupMenuItem(
            value: _AccionRutina.recuperar,
            child: Text('Recuperar'), // i18n
          ),
        PopupMenuItem(
          value: _AccionRutina.eliminar,
          child: Text(
            'Eliminar', // i18n
            style: TextStyle(color: palette.danger),
          ),
        ),
      ],
    );
  }

  Future<void> _ejecutar(_AccionRutina accion) async {
    final r = widget.routine;
    final asignada = (r.assignedTo ?? '').isNotEmpty;

    // Asignar y publicar NO piden confirmación: no destruyen nada y las dos se
    // deshacen desde este mismo menú. Meterlas en el diálogo de «¿estás
    // seguro?» que existe para borrar le enseñaría al PF a apretar «sí» sin
    // leer, que es cómo se pierde el peso de la advertencia de eliminar.
    if (accion == _AccionRutina.asignar) return _asignar(r);
    if (accion == _AccionRutina.publicar ||
        accion == _AccionRutina.despublicar) {
      return _publicar(r, publicada: accion == _AccionRutina.publicar);
    }
    if (accion == _AccionRutina.recuperar) return _recuperar(r);
    if (accion == _AccionRutina.publicarComoPlantilla) {
      return _publicarComoPlantilla(r);
    }

    // El uid se resuelve DESPUÉS de confirmar. Chequearlo antes hacía que el
    // tap no hiciera nada cuando el stream de auth todavía no emitió: un
    // fallo silencioso, que es lo que hay que evitar. Si falta, la acción
    // falla y lo dice por el mismo camino que cualquier otro error.
    final archivar = accion == _AccionRutina.archivar;
    final nombre = _nombreDelAlumno(ref, r);

    final confirmado = await showTreinoDialog<bool>(
      context,
      builder: (ctx) => TreinoDialog(
        title: !archivar
            ? '¿Eliminar «${r.name}»?' // i18n
            : !asignada
                ? '¿Archivar «${r.name}»?' // i18n
                : nombre == null
                    ? '¿Sacarle «${r.name}» al alumno?' // i18n
                    : '¿Sacarle «${r.name}» a $nombre?', // i18n
        body: Text(
          !archivar
              ? asignada
                  // La advertencia CONCRETA, no un «esto no se puede
                  // deshacer» genérico: un plan asignado pudo entrenarse, y
                  // las sesiones de ese alumno apuntan a este documento.
                  // Archivar existe justamente para no romper eso.
                  // i18n
                  ? 'Se borra para siempre. Los entrenamientos que el alumno '
                      'ya hizo con esta rutina quedan sin referencia. Si sólo '
                      'querés sacarla de circulación, archivala.'
                  // i18n
                  : 'Se borra para siempre. No se puede recuperar.'
              : asignada
                  // Las TRES cosas que el PF necesita saber para no tenerle
                  // miedo, y ninguna de más.
                  //
                  // Lo que NO dice, a propósito: que «tu plantilla queda
                  // intacta». Sería verdad sólo si este plan hubiera salido de
                  // una plantilla, y no hay forma de saberlo — `createAssigned`
                  // se llama desde tres pantallas que arman el plan a mano, y
                  // la rutina no guarda de qué documento se copió. Un cartel
                  // que tranquiliza con algo que puede ser falso es peor que
                  // no tenerlo (AGENTS.md §11.1); el lugar donde esa frase SÍ
                  // es cierta es el aviso de asignar, y ahí está.
                  // i18n
                  ? 'Deja de verla en su perfil y no va a poder seguir '
                      'entrenándola. Los entrenamientos que ya hizo se '
                      'conservan, y la rutina te queda en el filtro '
                      'Archivadas por si se la querés devolver.'
                  // i18n
                  : 'Sale de tu biblioteca y deja de estar activa. Te queda '
                      'en el filtro Archivadas, y desde ahí la recuperás.',
        ),
        primaryLabel: !archivar
            ? 'Eliminar' // i18n
            : !asignada
                ? 'Archivar' // i18n
                : 'Sacársela', // i18n
        onPrimaryTap: () => Navigator.of(ctx).pop(true),
        secondaryLabel: 'Cancelar', // i18n
        onSecondaryTap: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _ocupado = true);
    final trainerId = ref.read(currentUidProvider) ?? '';
    final acciones = ref.read(routineActionsProvider.notifier);
    final ok = trainerId.isEmpty
        ? false
        : accion == _AccionRutina.archivar
            ? await acciones.archive(
                routineId: r.id,
                trainerId: trainerId,
                athleteId: r.assignedTo ?? '',
              )
            : await acciones.delete(routineId: r.id, trainerId: trainerId);

    if (!mounted) return;
    setState(() => _ocupado = false);
    if (!ok) {
      _avisar('No se pudo. Probá de nuevo.'); // i18n
      return;
    }
    // El éxito se avisa sólo al sacarle una rutina a un alumno, y por una
    // razón: con el filtro «Todas» —el default— la card NO desaparece, sólo
    // se le suma la etiqueta «Archivada». Sin una línea que lo diga, el PF
    // hace la acción más delicada del menú y la pantalla se ve casi igual.
    // Eliminar y archivar una plantilla sí se ven: la card se va o se apaga.
    if (archivar && asignada) {
      _avisar(nombre == null
          // i18n
          ? 'Listo. Ya no la ve en su perfil, y te queda en Archivadas.'
          // i18n
          : 'Listo, $nombre ya no la ve. Te queda en Archivadas por si se la '
              'querés devolver.');
    }
  }

  /// El nombre del alumno de una rutina asignada, o `null`.
  ///
  /// `null` cubre DOS casos distintos que el llamador trata igual: que la
  /// rutina no tenga alumno (es plantilla) y que el perfil todavía no haya
  /// resuelto. El segundo importa: mientras carga hay que decir «al alumno», no
  /// un nombre inventado ni un id crudo. Mismo criterio que `_Etiquetas`, que
  /// muestra «Asignada» hasta que el nombre llega.
  static String? _nombreDelAlumno(WidgetRef ref, Routine r) {
    final uid = r.assignedTo;
    if (uid == null || uid.isEmpty) return null;
    final nombre =
        ref.watch(userPublicProfileProvider(uid)).valueOrNull?.displayName;
    final limpio = nombre?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }

  /// Devuelve una rutina archivada a `active`.
  ///
  /// Pide confirmación SÓLO si tiene alumno, y no por ser destructiva —no lo
  /// es— sino porque es visible para otra persona: el plan vuelve al perfil del
  /// alumno y lo puede entrenar de nuevo. Y el alumno lo lee aunque el vínculo
  /// haya terminado (la regla de lectura mira `assignedTo`, no el link), así
  /// que un PF recuperando planes viejos en fila podría devolverle una rutina a
  /// alguien que ya no es su alumno sin darse cuenta. Nombrar a la persona en
  /// el diálogo es lo que lo frena.
  ///
  /// Recuperar una PLANTILLA no le llega a nadie, así que va directo.
  Future<void> _recuperar(Routine r) async {
    final nombre = _nombreDelAlumno(ref, r);
    final asignada = (r.assignedTo ?? '').isNotEmpty;

    if (asignada) {
      final confirmado = await showTreinoDialog<bool>(
        context,
        builder: (ctx) => TreinoDialog(
          title: nombre == null
              ? '¿Devolverle «${r.name}» al alumno?' // i18n
              : '¿Devolverle «${r.name}» a $nombre?', // i18n
          body: const Text(
            // i18n
            'Vuelve a su perfil y la va a poder entrenar de nuevo.',
          ),
          primaryLabel: 'Devolvérsela', // i18n
          onPrimaryTap: () => Navigator.of(ctx).pop(true),
          secondaryLabel: 'Cancelar', // i18n
          onSecondaryTap: () => Navigator.of(ctx).pop(false),
        ),
      );
      if (confirmado != true || !mounted) return;
    }

    setState(() => _ocupado = true);
    final trainerId = ref.read(currentUidProvider) ?? '';
    final ok = trainerId.isEmpty
        ? false
        : await ref.read(routineActionsProvider.notifier).unarchive(
              routineId: r.id,
              trainerId: trainerId,
              athleteId: r.assignedTo ?? '',
            );

    if (!mounted) return;
    setState(() => _ocupado = false);
    if (!ok) {
      _avisar('No se pudo. Probá de nuevo.'); // i18n
      return;
    }
    _avisar(asignada
        // i18n
        ? '«${r.name}» vuelve a estar activa${nombre == null ? '' : ' para $nombre'}.'
        : '«${r.name}» vuelve a tu biblioteca.'); // i18n
  }

  /// Publica el plan de un alumno COMO PLANTILLA.
  ///
  /// No publica el documento del alumno —las reglas lo deniegan, y con razón:
  /// esa copia lleva su nombre y su historial—. Crea una plantilla nueva a
  /// partir de él y publica ESA.
  ///
  /// Pide el nombre, y ése es el punto del diálogo. En «Guardar como copia»
  /// del editor el nombre va automático porque la copia es PRIVADA; acá el
  /// nombre entra al catálogo de la comunidad, y un plan asignado suele
  /// llamarse por su dueño. Heredarlo en silencio filtraría el nombre de una
  /// clienta a un catálogo público.
  Future<void> _publicarComoPlantilla(Routine r) async {
    final nombreAlumno = _nombreDelAlumno(ref, r);
    final nombre = await showTreinoDialog<String>(
      context,
      builder: (ctx) => _DialogoDePublicar(
        nombreInicial: r.name,
        nombreAlumno: nombreAlumno,
      ),
    );
    if (nombre == null || !mounted) return;

    setState(() => _ocupado = true);
    final trainerId = ref.read(currentUidProvider) ?? '';
    final resultado = trainerId.isEmpty
        ? ResultadoDePublicar.falloAlCrear
        : await ref.read(routineActionsProvider.notifier).publicarComoPlantilla(
              plan: r,
              nombre: nombre,
              trainerId: trainerId,
            );

    if (!mounted) return;
    setState(() => _ocupado = false);
    _avisar(switch (resultado) {
      // i18n
      ResultadoDePublicar.ok => '«$nombre» ya es pública. El plan de '
          '${nombreAlumno ?? 'tu alumno'} quedó como estaba.',
      // El caso del medio NO se cuenta como error: la plantilla existe. Decir
      // «no se pudo» mandaría al PF a reintentar y a crear una segunda.
      // i18n
      ResultadoDePublicar.creadaPeroSinPublicar =>
        '«$nombre» se creó en tus plantillas pero no se pudo publicar. '
            'Publicala desde su propio menú — no repitas esto o vas a tener '
            'dos.',
      // i18n
      ResultadoDePublicar.falloAlCrear => 'No se pudo. Probá de nuevo.',
    });
  }

  /// Asigna la plantilla a un alumno elegido en el momento.
  ///
  /// La plantilla NO se consume: `assignTemplateToAthlete` copia. Por eso el
  /// aviso dice «se copió» y no «se movió» — la card sigue en pantalla igual
  /// que antes, y sin decirlo el PF creería que no pasó nada y volvería a
  /// apretar.
  Future<void> _asignar(Routine r) async {
    final athleteId = await pickAthlete(context, ref);
    if (athleteId == null || !mounted) return;

    setState(() => _ocupado = true);
    final trainerId = ref.read(currentUidProvider) ?? '';
    final ok = trainerId.isEmpty
        ? false
        : await ref.read(routineActionsProvider.notifier).assignTemplate(
              template: r,
              athleteId: athleteId,
              trainerId: trainerId,
            );

    if (!mounted) return;
    setState(() => _ocupado = false);
    _avisar(ok
        // i18n
        ? 'Se le asignó una copia de «${r.name}». La plantilla queda acá para '
            'volver a usarla.'
        : 'No se pudo asignar. Probá de nuevo.'); // i18n
  }

  /// Publica o despublica la plantilla en la comunidad.
  Future<void> _publicar(Routine r, {required bool publicada}) async {
    setState(() => _ocupado = true);
    final trainerId = ref.read(currentUidProvider) ?? '';
    final ok = trainerId.isEmpty
        ? false
        : await ref.read(routineActionsProvider.notifier).setPublicada(
              routineId: r.id,
              publicada: publicada,
              trainerId: trainerId,
            );

    if (!mounted) return;
    setState(() => _ocupado = false);
    if (!ok) {
      _avisar('No se pudo. Probá de nuevo.'); // i18n
      return;
    }
    _avisar(publicada
        // i18n
        ? '«${r.name}» ya es pública: cualquiera puede encontrarla y usarla.'
        // Lo de las valoraciones no es un detalle: es la duda que frena a
        // despublicar. Se conservan y vuelven si se republica.
        // i18n
        : '«${r.name}» vuelve a ser privada. Las valoraciones se guardan.');
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }
}

/// Pide el nombre con el que la plantilla va a salir a la comunidad.
///
/// Arranca con el del plan y NO con uno en blanco: nueve de cada diez veces el
/// nombre sirve tal cual, y una caja vacía obliga a reescribir algo que ya
/// existe. Lo que cambia es que ahora se ve antes de publicar.
class _DialogoDePublicar extends StatefulWidget {
  const _DialogoDePublicar({
    required this.nombreInicial,
    required this.nombreAlumno,
  });

  final String nombreInicial;

  /// El nombre del alumno, si su perfil resolvió. Sólo para la advertencia
  /// PROBADA de abajo — `null` significa «no sé», y entonces no se afirma nada.
  final String? nombreAlumno;

  @override
  State<_DialogoDePublicar> createState() => _DialogoDePublicarState();
}

class _DialogoDePublicarState extends State<_DialogoDePublicar> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nombreInicial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// La parte del nombre del alumno que aparece en el nombre propuesto, o
  /// `null` si no aparece ninguna.
  ///
  /// La advertencia se afirma sólo cuando se puede probar, que es el mismo
  /// criterio que `_deniedMessage` del editor: si el perfil no resolvió, no se
  /// dice nada en vez de inventar una sospecha.
  ///
  /// **Match por PALABRA COMPLETA, no por substring**, y contra cada palabra
  /// del nombre del alumno por separado. Las dos cosas son necesarias y las dos
  /// salieron de romperlo:
  ///
  /// - Con substring, un alumno llamado «Ana» hacía saltar la advertencia sobre
  ///   una rutina llamada «Semana de fuerza» — y el cartel dice el nombre, así
  ///   que era una advertencia CONCRETA y FALSA. Peor que ninguna
  ///   (AGENTS.md §11.1), y en la función que existe para no filtrar un nombre.
  /// - Comparando contra el `displayName` entero, un perfil normal como «Sofía
  ///   García» NO matcheaba «Plan de Sofía», que es el caso que esto existe
  ///   para agarrar.
  ///
  /// Se ignoran las palabras de menos de tres letras: son los conectores («de»,
  /// «la») y no nombres. Perder a un alumno cuyo nombre entero mida dos letras
  /// es un falso NEGATIVO —no se avisa— y eso falla del lado seguro: el PF
  /// sigue viendo el nombre en el campo antes de publicar.
  ///
  /// Devuelve la palabra ORIGINAL, con sus acentos y mayúsculas, porque es la
  /// que se muestra: sobre «Sofía García» el cartel tiene que decir «Sofía», no
  /// el nombre completo —que no es lo que dice la rutina— ni «sofia».
  String? get _palabraDelAlumnoEnElNombre {
    final alumno = widget.nombreAlumno?.trim();
    if (alumno == null || alumno.isEmpty) return null;

    final enLaRutina = _palabras(_ctrl.text).toSet();
    for (final palabra in alumno.split(RegExp(r'\s+'))) {
      final plana = _plano(palabra);
      if (plana.length < 3) continue;
      if (enLaRutina.contains(plana)) return palabra;
    }
    return null;
  }

  /// Las palabras de [s], normalizadas: sin acentos, en minúscula y sin nada
  /// que no sea letra o número (para que «Sofía,» y «(Sofía)» cuenten igual).
  static Iterable<String> _palabras(String s) => _plano(s)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((p) => p.isNotEmpty);

  static String _plano(String s) {
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    var out = s.toLowerCase();
    for (var i = 0; i < con.length; i++) {
      out = out.replaceAll(con[i], sin[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final alumno = widget.nombreAlumno;
    final nombraAlAlumno = _palabraDelAlumnoEnElNombre;

    return TreinoDialog(
      title: 'Publicar como plantilla', // i18n
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // Las dos mitades: qué se crea, y qué NO se toca. Sin la segunda,
            // «publicar» sobre el plan de un alumno se lee como que se publica
            // SU rutina — que es justo lo que no pasa.
            // i18n
            alumno == null
                ? 'Se crea una plantilla nueva en tu biblioteca con este '
                    'contenido y se publica. El plan de tu alumno no se toca.'
                : 'Se crea una plantilla nueva en tu biblioteca con este '
                    'contenido y se publica. El plan de $alumno no se toca.',
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontSize: AppTextSize.bodyDense,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          TextField(
            key: const Key('publicar_nombre_field'),
            controller: _ctrl,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: 'Nombre en la comunidad', // i18n
              // `filled` + `fillColor` EXPLÍCITOS, y no por gusto: el tema
              // fuerza `filled` en todo `InputDecoration`, así que un campo
              // sin fondo declarado se pinta con el default y adentro de un
              // diálogo eso sale como una banda oscura que se lee como una
              // línea negra. Mismo criterio que `cuenta_tab.dart`: el campo va
              // un tono MÁS OSCURO que la superficie que lo contiene, para que
              // se lea como campo y no desaparezca en el fondo del diálogo.
              filled: true,
              fillColor: palette.bg,
              isDense: true,
            ),
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontSize: AppTextSize.body,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Este nombre lo va a ver cualquiera que la encuentre.', // i18n
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontSize: AppTextSize.caption,
              color: palette.textMuted,
            ),
          ),
          // La advertencia CONCRETA, y sólo cuando está probada.
          if (nombraAlAlumno != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Ojo: dice «$nombraAlAlumno».', // i18n
              key: const Key('publicar_aviso_nombre_alumno'),
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontWeight: AppFonts.w600,
                fontSize: AppTextSize.caption,
                color: palette.danger,
              ),
            ),
          ],
        ],
      ),
      errorMessage: _error,
      // El botón cambia de nombre cuando el nombre todavía nombra al alumno.
      //
      // NO se bloquea la publicación, y es a propósito. El nombre de esa
      // persona en un catálogo público es un problema real, pero la decisión
      // sigue siendo del PF: puede tener el permiso de su alumna, o la palabra
      // puede ser un falso positivo del match de arriba —«Ana», «Luz», «Sol»
      // son nombres Y palabras—. Un guard que bloquea sobre una heurística
      // deja al PF sin salida el día que la heurística se equivoca, y eso es
      // peor que el problema que resuelve.
      //
      // Lo que sí se saca es el camino por reflejo: con el botón diciendo otra
      // cosa, no se puede publicar sin haber leído que decía algo.
      primaryLabel: nombraAlAlumno == null
          ? 'Publicar' // i18n
          : 'Publicar igual', // i18n
      onPrimaryTap: () {
        final nombre = _ctrl.text.trim();
        // Vacío no pop-ea: cerrar el diálogo sin nombre publicaría una
        // plantilla sin nombre, y devolver `null` en silencio se leería como
        // «cancelé». Se dice qué falta.
        if (nombre.isEmpty) {
          setState(() => _error = 'Poné un nombre.'); // i18n
          return;
        }
        Navigator.of(context).pop(nombre);
      },
      secondaryLabel: 'Cancelar', // i18n
      onSecondaryTap: () => Navigator.of(context).pop(),
    );
  }
}

enum _AccionRutina {
  asignar,
  publicar,
  despublicar,
  publicarComoPlantilla,
  archivar,
  recuperar,
  eliminar,
}
