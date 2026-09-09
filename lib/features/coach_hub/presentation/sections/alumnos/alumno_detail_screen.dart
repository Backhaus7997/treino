import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/core/utils/date_labels.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/motion/treino_success_check.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/athlete_file_providers.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/wall_clock.dart';
import 'package:treino/features/coach/application/follow_up_entry_providers.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/athlete_file_repository.dart';
import 'package:treino/features/coach/domain/athlete_file.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/follow_up_entry.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/nutrition_plan_presets.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/abrir_chat_con_alumno.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/avatar_color.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/insights/presentation/widgets/daily_heatmap_section.dart';
import 'package:treino/features/insights/presentation/widgets/day_strip_labels.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_progress_chart.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/widgets/performance_progress_chart.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/exercise_frequency_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/application/exercise_feedback_providers.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart'
    show ExerciseProgressionChartLabels;
import 'package:treino/features/workout/presentation/widgets/exercise_progression_section.dart';
import 'package:treino/features/workout/presentation/widgets/most_frequent_exercises_list.dart';
import 'package:treino/features/workout/presentation/widgets/personal_records_list.dart';
import 'package:treino/features/workout/presentation/widgets/session_exercise_block.dart';
import 'package:treino/features/workout/presentation/widgets/feedback_load_error_note.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../infrastructure/browser_download.dart';
import '../pagos/widgets/estado_cuenta_card.dart';
import '../pagos/widgets/marcar_pagado_actions.dart';
import '../pagos/widgets/pagos_table.dart';
import '../pagos/widgets/payment_format.dart';
import 'alumnos_screen.dart' show AlumnoEstado, AlumnoEstadoX, estadoForLink;
import 'resumen_metrics.dart';
import 'package:treino/features/coach_hub/presentation/widgets/skeleton/coach_hub_skeleton.dart';

/// Estado de un grupo de la ficha, para su marca en la barra.
///
/// Tiene un cuarto valor —[desconocido]— y ése es el punto de todo el enum.
/// Con un `bool` "hay contenido", el `false` significa a la vez «está vacío» y
/// «todavía no cargó», y la marca queda igual en los dos casos. Visualmente
/// pasa (no hay punto, y no hay punto es ambiguo), pero el anuncio del lector
/// de pantalla NO: decir «Progreso, sin contenido» sobre un stream que sigue
/// cargando es afirmar algo falso justo en la pregunta que estas marcas
/// existen para contestar. `AGENTS.md` §11.1: una advertencia falsa es peor
/// que ninguna. Con [desconocido] no se afirma nada — se anuncia el nombre del
/// grupo pelado.
enum AlumnoGrupoEstado {
  /// Alguna de las fuentes del grupo está cargando o falló. Sin marca y sin
  /// afirmación.
  desconocido,

  /// Se sabe, y adentro no hay nada. Sin marca, pero el anuncio SÍ lo dice.
  vacio,

  /// Hay contenido. Punto neutro.
  conContenido,

  /// Hay algo esperando una acción del PF. Punto de acento.
  requiereAtencion,
}

/// Qué mostrar en la barra por cada grupo de la ficha.
@immutable
class AlumnoDetailIndicators {
  const AlumnoDetailIndicators({
    this.entrenamiento = AlumnoGrupoEstado.desconocido,
    this.progreso = AlumnoGrupoEstado.desconocido,
    this.plan = AlumnoGrupoEstado.desconocido,
    this.chat = AlumnoGrupoEstado.desconocido,
    this.privado = AlumnoGrupoEstado.desconocido,
    this.pagos = AlumnoGrupoEstado.desconocido,
  });

  final AlumnoGrupoEstado entrenamiento;
  final AlumnoGrupoEstado progreso;
  final AlumnoGrupoEstado plan;
  final AlumnoGrupoEstado chat;
  final AlumnoGrupoEstado privado;
  final AlumnoGrupoEstado pagos;

  @override
  bool operator ==(Object other) =>
      other is AlumnoDetailIndicators &&
      other.entrenamiento == entrenamiento &&
      other.progreso == progreso &&
      other.plan == plan &&
      other.chat == chat &&
      other.privado == privado &&
      other.pagos == pagos;

  @override
  int get hashCode =>
      Object.hash(entrenamiento, progreso, plan, chat, privado, pagos);
}

/// Traduce dos fuentes async a un estado de grupo, sin inventar certeza.
///
/// [hayContenido] sólo se llama cuando las DOS tienen valor; si alguna está
/// cargando o falló, el grupo queda [AlumnoGrupoEstado.desconocido].
AlumnoGrupoEstado _estadoDeFuentes(
  List<AsyncValue<Object?>> fuentes,
  bool Function() hayContenido,
) {
  if (fuentes.any((f) => !f.hasValue)) return AlumnoGrupoEstado.desconocido;
  return hayContenido()
      ? AlumnoGrupoEstado.conContenido
      : AlumnoGrupoEstado.vacio;
}

/// Único punto de composición para responder, por grupo, si hay algo adentro y
/// si eso reclama acción.
///
/// **Está centralizado a propósito.** Contestar «¿cargó mediciones?» sin entrar
/// obliga a suscribir streams que hoy no se abren, porque `TabBarView` sólo
/// construye la pestaña montada. No hay forma de evitar ese costo —es el precio
/// de la pregunta—, pero teniéndolo en un solo provider queda UN lugar donde
/// medirlo y optimizarlo, y se puede testear sin levantar la pantalla.
final alumnoDetailIndicatorsProvider =
    Provider.autoDispose.family<AlumnoDetailIndicators, String>(
  (ref, athleteId) {
    final trainerId = ref.watch(currentUidProvider);
    if (trainerId == null) return const AlumnoDetailIndicators();

    final key = (trainerId: trainerId, athleteId: athleteId);
    final sessions = ref.watch(sessionsByUidProvider(athleteId));
    final routines = ref.watch(assignedRoutinesByTrainerProvider(key));
    final measurements = ref.watch(measurementsForAthleteProvider(athleteId));
    final performance =
        ref.watch(performanceTestsForAthleteProvider(athleteId));
    final nutrition = ref.watch(nutritionPlanProvider(key));
    final files = ref.watch(athleteFilesProvider(key));
    final note = ref.watch(athleteNoteProvider(key));
    final followUp = ref.watch(followUpEntriesProvider(key));
    final pagos = ref.watch(pagosPorCobrarProvider);

    return AlumnoDetailIndicators(
      entrenamiento: _estadoDeFuentes(
        [sessions, routines],
        () =>
            sessions.requireValue.isNotEmpty ||
            routines.requireValue
                .any((routine) => routine.status == RoutineStatus.active),
      ),
      progreso: _estadoDeFuentes(
        [measurements, performance],
        () =>
            measurements.requireValue.isNotEmpty ||
            performance.requireValue.isNotEmpty,
      ),
      plan: _estadoDeFuentes(
        [nutrition, files],
        () => nutrition.requireValue != null || files.requireValue.isNotEmpty,
      ),
      // `hasUnreadFromProvider` ya colapsa loading y error a false y deriva de
      // un stream que el hub tiene abierto — sin listener nuevo. Su "no hay sin
      // leer" no distingue desconocido de vacío, así que acá tampoco se afirma
      // más de lo que se sabe.
      chat: ref.watch(hasUnreadFromProvider(athleteId))
          ? AlumnoGrupoEstado.requiereAtencion
          : AlumnoGrupoEstado.desconocido,
      privado: _estadoDeFuentes(
        [note, followUp],
        () =>
            (note.requireValue?.note.trim().isNotEmpty ?? false) ||
            followUp.requireValue.isNotEmpty,
      ),
      pagos: !pagos.hasValue
          ? AlumnoGrupoEstado.desconocido
          : pagos.requireValue.any((cobro) => cobro.athleteId == athleteId)
              ? AlumnoGrupoEstado.requiereAtencion
              : AlumnoGrupoEstado.vacio,
    );
  },
);

/// Detalle del alumno (`/alumnos/:id`, Fase W2 PR2).
///
/// Header (identidad + estado + métricas denormalizadas) y siete grupos
/// orientados a las tareas del PF. Entrenamiento, Progreso, Plan y Privado
/// contienen un segundo nivel segmentado. Renderiza DENTRO del shell, sin
/// Scaffold (ADR-CHW-005).
class AlumnoDetailScreen extends ConsumerWidget {
  const AlumnoDetailScreen({
    super.key,
    required this.athleteId,
    this.tabInicial,
  });

  final String athleteId;

  /// Seccion en la que abrir la ficha, por su clave (`plan`, `entrenamiento`,
  /// `pagos`, …). `null` abre en Resumen, que es el comportamiento de siempre.
  ///
  /// Se compara contra [_clavesDeTab] y NO contra la etiqueta visible: las
  /// etiquetas son copy —cambian en la pasada de i18n— y una URL no puede
  /// depender de eso.
  final String? tabInicial;

  /// Clave estable de cada pestana, en el mismo orden que [_tabs].
  static const _clavesDeTab = <String>[
    'resumen',
    'entrenamiento',
    'progreso',
    'plan',
    'privado',
    'pagos',
  ];

  static const _tabs = <String>[
    'Resumen', // i18n: Fase W2
    'Entrenamiento',
    'Progreso',
    'Plan',
    'Privado',
    'Pagos',
  ];
  static const _resumenIndex = 0;
  static const _entrenamientoIndex = 1;
  static const _progresoIndex = 2;
  static const _planIndex = 3;
  static const _privadoIndex = 4;
  static const _pagosIndex = 5;

  /// El estado de cada grupo, en el orden EXACTO de [_tabs].
  ///
  /// Indexado por posición y no por el texto del label: un `switch` sobre el
  /// string haría que renombrar una pestaña apagara su marca en silencio, sin
  /// que ningún test lo notara —el test también usaría el nombre nuevo—. Acá
  /// un desalineo es un desborde de índice, que sí se ve.
  static List<AlumnoGrupoEstado> _estados(AlumnoDetailIndicators i) => [
        AlumnoGrupoEstado.desconocido, // Resumen: derivado, nunca lleva marca.
        i.entrenamiento,
        i.progreso,
        i.plan,
        i.privado,
        i.pagos,
      ];

  /// Lo que el punto dice, en palabras. El color solo no es información
  /// accesible (WCAG 1.4.1).
  ///
  /// Con el estado en [AlumnoGrupoEstado.desconocido] se anuncia el nombre
  /// pelado: mientras el stream carga NO se afirma que no haya nada.
  static List<String> _semanticsLabels(AlumnoDetailIndicators i) {
    final estados = _estados(i);
    return [
      for (var n = 0; n < _tabs.length; n++)
        switch ((_tabs[n], estados[n])) {
          (final label, AlumnoGrupoEstado.desconocido) => label,
          ('Pagos', AlumnoGrupoEstado.requiereAtencion) =>
            'Pagos, con cobro pendiente', // i18n: Fase W2
          ('Pagos', _) => 'Pagos, sin cobros pendientes', // i18n: Fase W2
          (final label, AlumnoGrupoEstado.conContenido) =>
            '$label, con contenido', // i18n: Fase W2
          (final label, _) => '$label, sin contenido', // i18n: Fase W2
        },
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final indicators = ref.watch(alumnoDetailIndicatorsProvider(athleteId));
    final profile = ref.watch(userPublicProfileProvider(athleteId)).valueOrNull;
    // Mismo criterio que el roster: el link más reciente NO-pending del alumno
    // (el stream viene requestedAt DESC). Sin el filtro de pending, un alumno
    // re-vinculado mostraría estados contradictorios entre roster y detalle.
    final link = ref
        .watch(trainerLinksStreamProvider)
        .valueOrNull
        ?.where((l) =>
            l.athleteId == athleteId && l.status != TrainerLinkStatus.pending)
        .firstOrNull;
    final conDeudaIds = <String>{
      for (final c in ref.watch(pagosPorCobrarProvider).valueOrNull ?? const [])
        c.athleteId,
    };
    final estado = link == null ? null : estadoForLink(link, conDeudaIds);
    final gymId = profile?.gymId;
    final gymName = gymId == null
        ? null
        : ref.watch(gymByIdProvider(gymId)).valueOrNull?.name;
    final billing = ref.watch(athleteBillingProvider(athleteId)).valueOrNull;

    return DefaultTabController(
      length: _tabs.length,
      initialIndex: () {
        final i = _clavesDeTab.indexOf(tabInicial ?? '');
        // Una clave que no existe cae en Resumen en vez de tirar: la URL la
        // puede escribir cualquiera, y un link viejo tiene que abrir la ficha,
        // no romperla.
        return i < 0 ? _resumenIndex : i;
      }(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackLink(palette: palette),
                const SizedBox(height: 12),
                _Header(
                  athleteId: athleteId,
                  profile: profile,
                  link: link,
                  estado: estado,
                  gymName: gymName,
                  billing: billing,
                  onPago: () => registrarPago(context, ref, athleteId),
                  // Va al Chat, no a un modal. El PF tocaba este botón
                  // esperando el chat y se quedaba adentro de un `Dialog`:
                  // «si toco el chat que me redirija al chat directamente».
                  //
                  // Es EXACTAMENTE lo que hace el botón de chat del roster
                  // —misma función compartida—, así que el mismo ícono lleva
                  // al mismo lugar desde los dos lados.
                  onChat: () => abrirChatConAlumno(context, ref, athleteId),
                  chatSinLeer:
                      indicators.chat == AlumnoGrupoEstado.requiereAtencion,
                  palette: palette,
                ),
                const SizedBox(height: 12),
                _SeccionesTabBar(
                  labels: _tabs,
                  estados: _estados(indicators),
                  semanticsLabels: _semanticsLabels(indicators),
                  palette: palette,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  if (i == _resumenIndex)
                    _ResumenTab(athleteId: athleteId)
                  else if (i == _entrenamientoIndex)
                    _EntrenamientoTab(athleteId: athleteId)
                  else if (i == _progresoIndex)
                    _ProgresoTab(athleteId: athleteId)
                  else if (i == _planIndex)
                    _PlanTab(athleteId: athleteId)
                  else if (i == _privadoIndex)
                    _PrivadoTab(athleteId: athleteId)
                  else if (i == _pagosIndex)
                    _PagosTab(athleteId: athleteId)
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return TreinoTappable(
      onTap: () => context.go('/alumnos'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TreinoIcon.chevronLeft, size: 16, color: palette.textMuted),
          const SizedBox(width: 4),
          Text(
            'Alumnos', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.athleteId,
    required this.profile,
    required this.link,
    required this.estado,
    required this.gymName,
    required this.billing,
    required this.onPago,
    required this.onChat,
    required this.chatSinLeer,
    required this.palette,
  });

  final String athleteId;
  final UserPublicProfile? profile;
  final TrainerLink? link;
  final AlumnoEstado? estado;
  final String? gymName;
  final AthleteBilling? billing;
  final VoidCallback onPago;
  final VoidCallback onChat;
  final bool chatSinLeer;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? 'Atleta'; // i18n: Fase W2
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final sesiones = profile?.workoutsCount ?? 0;
    final racha = profile?.racha ?? 0;
    final avatarUrl = profile?.avatarUrl;
    final desde = link?.acceptedAt;
    final b = billing;
    // .toUtc() para compartir reloj con el pipeline de billing (monthKey/weekKey
    // de pagosPorCobrarProvider y las escrituras usan UTC); evita un desfase de
    // 1 día en el borde del período en AR (UTC-3).
    // Bucket de MES en ART (#671): con UTC, "Prox. cobro" mostraba el mes
    // siguiente al correcto.
    final proxCobro = b == null ? null : nextDueDate(b, argentinaNow());
    // Mismo criterio determinístico que el chat (avatar_color.dart) y el
    // roster (alumnos_screen.dart): sin foto de red, círculo de color estable
    // seedeado por uid + inicial en blanco — evita que todos los alumnos sin
    // avatar se vean iguales (mint plano) en el detalle.
    final hasNetworkAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final avatarColor = avatarColorFor(link?.athleteId ?? athleteId);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: hasNetworkAvatar ? palette.bg : avatarColor,
                backgroundImage:
                    hasNetworkAvatar ? NetworkImage(avatarUrl) : null,
                child: hasNetworkAvatar
                    ? null
                    : Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.barlowCondensed(
                        color: palette.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (estado != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Dot(color: estado!.color(palette)),
                              const SizedBox(width: 6),
                              Text(
                                estado!.label(AppL10n.of(context)),
                                style: TextStyle(
                                    color: estado!.color(palette),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        if (gymName != null)
                          Text(
                            gymName!,
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                        if (desde != null)
                          Text(
                            'Desde ${fmtDate(desde)}', // i18n: Fase W2
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                        if (b != null && b.cadence != BillingCadence.suelto)
                          Text(
                            '${fmtArs(b.amountArs)} · ${_cadenciaLabel(b.cadence)}', // i18n: Fase W2
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                        if (proxCobro != null)
                          Text(
                            'Próx. cobro: ${fmtDayMonth(proxCobro)}', // i18n: Fase W2
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                        // Sesiones y racha entran ACÁ y no en cards propias.
                        // Como cards costaban ~85px de alto en una pantalla
                        // cuyo contenido es lo que el PF vino a mirar: dos
                        // números de dos dígitos no justifican una fila
                        // entera. El número en negrita mantiene la jerarquía
                        // sin la caja.
                        _MetricInline(
                          value: '$sesiones',
                          label: 'sesiones', // i18n: Fase W2
                          palette: palette,
                        ),
                        _MetricInline(
                          value: '$racha d',
                          label: 'de racha', // i18n: Fase W2
                          palette: palette,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // El chat vive ACÁ y no en una pestaña. Como pestaña ocupaba un
              // destino de primer nivel para algo que ya tiene su propia
              // sección en el sidebar; como acción del header no gasta alto y
              // conserva el acceso de un click a ESTE alumno — que la sección
              // no da, porque `/chat` no toma parámetro de alumno.
              _ChatAction(
                onTap: onChat,
                sinLeer: chatSinLeer,
                palette: palette,
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onPago,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.accent,
                  side: BorderSide(color: palette.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Pago', // i18n: Fase W2
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sub-navegación de un grupo — el mismo subrayado que arriba, en chico.
///
/// **Por qué no la píldora del kit.** Era lo que había acá, y su contorno
/// oscuro es lo que se pidió ablandar. No se puede: ese contorno sale de #646
/// (cinco participantes de las pruebas de usabilidad no detectaron el control)
/// y su opacidad ya está en el mínimo que cruza 3:1 —WCAG 1.4.11— en las dos
/// paletas. Medido, componiendo el borde sobre la pista contra el fondo de
/// página:
///
/// | borde | dark | light |
/// |---|---|---|
/// | `textMuted@45` (el actual) | 4,84 | 3,21 |
/// | `textMuted@30` | 2,88 | 2,02 |
/// | `AppPalette.border` | 1,41 | 1,21 |
///
/// Y un relleno no lo reemplaza: `bgCard` contra `bg` da 1,04 en light. O sea
/// que aflojar el contorno ES bajar de 3:1. En vez de debilitar un guard con
/// pruebas de usuario atrás —y en un widget que comparten otras cuatro
/// pantallas— acá se cambia de control: el subrayado no depende de un contorno
/// para leerse como navegación, y es el patrón que esta pantalla ya usa arriba.
///
/// Subordinado a propósito: 13px contra 14, `isScrollable` para que abrace su
/// contenido en vez de repartir el ancho, y sin divisor. Dos barras de
/// subrayado apiladas sólo confunden si pesan igual.
class _SubNav extends StatelessWidget {
  const _SubNav({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    const estilo = TextStyle(
      fontFamily: AppFonts.barlow,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: palette.accentText,
        unselectedLabelColor: palette.textMuted,
        indicatorColor: palette.accentText,
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: estilo,
        // El MISMO estilo en los dos estados: `TabBar` interpola entre ambos y
        // con pesos distintos la tira se re-layoutea en cada cambio.
        unselectedLabelStyle: estilo,
        labelPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
        ),
        tabs: [for (final l in labels) Tab(height: 34, text: l)],
      ),
    );
  }
}

/// Key estable del punto de la pestaña [index].
///
/// Pública y de nivel superior porque el widget que la usa es privado, y lo que
/// hace falta afirmar desde un test es el COLOR del punto — lo único de esto
/// que puede romperse en silencio, y sólo en tema claro.
Key alumnoDetailMarcaKey(int index) => Key('alumno-detail-marca-$index');

/// Navegación de primer nivel de la ficha — `TabBar` con subrayado.
///
/// **Por qué no `TreinoSegmentedPill`.** Ese control es la sub-navegación
/// MOBILE: una pista con contorno y un thumb relleno, pensada para dos o tres
/// celdas angostas. Estirado a seis celdas a lo ancho de un desktop, su
/// contorno y su relleno pesan más que el contenido que encabezan, y no se
/// parece a ninguna otra pantalla del Coach Hub web. La Biblioteca —la otra
/// sección web con pestañas— usa exactamente esto: `labelColor: accent`,
/// `indicatorColor: accent`, `indicatorWeight: 2`. Este es el idioma de acá.
///
/// El contorno de la píldora NO era un capricho: sale de #646 (WCAG 1.4.11,
/// 3:1 para identificar un control) y ahí resolvía que el pill se leyera como
/// un badge decorativo. Acá ese riesgo no aplica del mismo modo — una fila de
/// pestañas con subrayado es un patrón que el usuario ya reconoce, y el
/// indicador de 2px en acento marca la selección con contraste de sobra.
class _SeccionesTabBar extends StatelessWidget {
  const _SeccionesTabBar({
    required this.labels,
    required this.estados,
    required this.semanticsLabels,
    required this.palette,
  });

  final List<String> labels;
  final List<AlumnoGrupoEstado> estados;
  final List<String> semanticsLabels;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: false,
      labelColor: palette.accentText,
      unselectedLabelColor: palette.textMuted,
      indicatorColor: palette.accentText,
      indicatorWeight: 2,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: palette.border,
      // El default de `TabBar` son 16 por lado, que con seis celdas y un punto
      // desborda antes de los 900px de ancho. Mismo valor que usa el pill del
      // kit por la misma razón.
      labelPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
      ),
      labelStyle: const TextStyle(
        fontFamily: AppFonts.barlow,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
      // El MISMO estilo en los dos estados: `TabBar` interpola entre ambos, y
      // con pesos distintos la tira entera se re-layoutea en cada cambio.
      unselectedLabelStyle: const TextStyle(
        fontFamily: AppFonts.barlow,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
      tabs: [
        for (var i = 0; i < labels.length; i++)
          Tab(
            height: 40,
            child: Semantics(
              label: semanticsLabels[i],
              excludeSemantics: true,
              // `FittedBox` y no `Expanded`+ellipsis: es la estrategia que el
              // kit ya eligió para este problema —encoger antes que
              // desbordar— y la que mantiene legible la etiqueta más larga
              // («Entrenamiento») cuando el navegador está angosto. Sin esto
              // la fila desborda 23px a 800 de ancho.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(labels[i]),
                    if (_colorDeMarca(context, estados[i])
                        case final color?) ...[
                      const SizedBox(width: TreinoNavMarkTokens.gap),
                      Container(
                        key: alumnoDetailMarcaKey(i),
                        width: TreinoNavMarkTokens.size,
                        height: TreinoNavMarkTokens.size,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Sin marca cuando el estado se desconoce — un punto sobre un stream que
  /// todavía carga afirmaría algo que no sabemos.
  Color? _colorDeMarca(BuildContext ctx, AlumnoGrupoEstado estado) {
    final t = TreinoNavMarkTokens.of(ctx);
    return switch (estado) {
      AlumnoGrupoEstado.conContenido => t.content,
      AlumnoGrupoEstado.requiereAtencion => t.attention,
      _ => null,
    };
  }
}

/// Abre el chat con el alumno en un panel, sin salir de la ficha.
/// Botón de chat del header, con punto cuando hay mensajes sin leer.
class _ChatAction extends StatelessWidget {
  const _ChatAction({
    required this.onTap,
    required this.sinLeer,
    required this.palette,
  });

  final VoidCallback onTap;
  final bool sinLeer;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: sinLeer
          ? 'Chat, con mensajes sin leer' // i18n: Fase W2
          : 'Chat', // i18n: Fase W2
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Chat', // i18n: Fase W2
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.textPrimary,
            side: BorderSide(color: palette.border),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TreinoIcon.chat, size: 16, color: palette.textPrimary),
              if (sinLeer) ...[
                const SizedBox(width: AppSpacing.hairline),
                Container(
                  width: TreinoNavMarkTokens.size,
                  height: TreinoNavMarkTokens.size,
                  decoration: BoxDecoration(
                    color: TreinoNavMarkTokens.of(context).attention,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Un número del header con su etiqueta, en línea.
///
/// Reemplaza a las cards de «Sesiones» y «Racha», que ocupaban una fila propia
/// de ~85px arriba de la navegación. En esta pantalla el alto es el recurso
/// escaso: todo lo que gasta el encabezado se lo saca al contenido.
class _MetricInline extends StatelessWidget {
  const _MetricInline({
    required this.value,
    required this.label,
    required this.palette,
  });

  final String value;
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // `Text.rich` y NO `RichText`: el segundo no hereda el `DefaultTextStyle`
    // ambiente, así que su span queda sin familia tipográfica y el texto sale
    // en tofu (cuadraditos) cuando la fuente por defecto no tiene los glifos.
    // Se vio renderizando la pantalla contra el seed del gate visual, al lado
    // del golden de CI que sí los mostraba bien.
    return Text.rich(
      TextSpan(
        style: TextStyle(color: palette.textMuted, fontSize: 13),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _PlanTab extends StatelessWidget {
  const _PlanTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _SubNav(labels: ['Nutrición', 'Archivos']), // i18n: Fase W2
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _NutricionTab(athleteId: athleteId),
                _ArchivosTab(athleteId: athleteId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivadoTab extends StatelessWidget {
  const _PrivadoTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Row(
              children: [
                const _SubNav(
                    labels: ['Notas', 'Seguimiento']), // i18n: Fase W2
                const SizedBox(width: 18),
                // El aviso comparte fila con la sub-navegación en vez de
                // gastar una línea propia: dice lo mismo y no le come alto al
                // contenido, que es lo que el PF vino a leer.
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(TreinoIcon.lock, size: 14, color: palette.textMuted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Nada de esto lo ve el alumno.', // i18n: Fase W2
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: palette.textMuted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _NotasPrivadasTab(athleteId: athleteId),
                _SeguimientoTab(athleteId: athleteId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgresoTab extends ConsumerStatefulWidget {
  const _ProgresoTab({required this.athleteId});
  final String athleteId;

  @override
  ConsumerState<_ProgresoTab> createState() => _ProgresoTabState();
}

class _ProgresoTabState extends ConsumerState<_ProgresoTab> {
  Future<void> _openAntropoDialog({Measurement? initial}) async {
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _NuevaMedicionDialog(
        athleteId: widget.athleteId,
        trainerUid: trainerUid,
        initial: initial,
      ),
    );
  }

  Future<void> _openRendimientoDialog({PerformanceTest? initial}) async {
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _NuevoRendimientoDialog(
        athleteId: widget.athleteId,
        trainerUid: trainerUid,
        initial: initial,
      ),
    );
  }

  Future<void> _confirmDeleteMedicion(Measurement m) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar medición?'), // i18n: Fase W2
        content: Text(
          'La medición del ${fmtDate(m.recordedAt)} se va a borrar. '
          'No se puede deshacer.', // i18n: Fase W2
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'), // i18n: Fase W2
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'), // i18n: Fase W2
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(measurementRepositoryProvider).delete(m.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos eliminar la medición.'), // i18n: Fase W2
        ),
      );
    }
  }

  Future<void> _confirmDeleteRendimiento(PerformanceTest t) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar prueba?'), // i18n: Fase W2
        content: Text(
          'La prueba del ${fmtDate(t.recordedAt)} se va a borrar. '
          'No se puede deshacer.', // i18n: Fase W2
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'), // i18n: Fase W2
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'), // i18n: Fase W2
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(performanceTestRepositoryProvider).delete(t.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos eliminar la prueba.'), // i18n: Fase W2
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final measAsync =
        ref.watch(measurementsForAthleteProvider(widget.athleteId));
    final perfAsync =
        ref.watch(performanceTestsForAthleteProvider(widget.athleteId));

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _SubNav(
                labels: ['Antropometría', 'Rendimiento']), // i18n: Fase W2
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildAntropometria(palette, measAsync, perfAsync),
                _buildRendimiento(palette, measAsync, perfAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAntropometria(
    AppPalette palette,
    AsyncValue<List<Measurement>> measAsync,
    AsyncValue<List<PerformanceTest>> perfAsync,
  ) {
    // CustomScrollView y no SingleChildScrollView + Column: la lista de abajo
    // puede tener cientos de filas (un alumno con dos años de tomas), y cada
    // fila es un StatefulWidget con detalle expandible. Adentro de un
    // SingleChildScrollView la lista queda obligada a `shrinkWrap: true` con el
    // scroll propio apagado, que construye TODAS las filas al abrir la
    // sub-vista. Antes de unir Progreso con Mediciones esto no pasaba: la lista
    // colgaba de un `Expanded` y tenía su propio viewport perezoso.
    //
    // Con slivers hay un solo viewport, el header y el chart scrollean junto a
    // la lista, y `SliverList` vuelve a construir sólo lo que se ve
    // (AGENTS.md §6: «ListView.builder para listas largas»).
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProgressHeader(
                  title: 'Mediciones antropométricas', // i18n: Fase W2
                  subtitle:
                      'Peso, composición corporal y circunferencias.', // i18n: Fase W2
                  actionLabel: 'NUEVA MEDICIÓN', // i18n: Fase W2
                  onPressed: _openAntropoDialog,
                  palette: palette,
                ),
                const SizedBox(height: 20),
                _ProgressReading(
                  measurements: measAsync,
                  performanceTests: perfAsync,
                  palette: palette,
                  view: _ProgressView.antropometria,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: _AntropoList(
            measurements: measAsync,
            palette: palette,
            onDelete: _confirmDeleteMedicion,
            onEdit: (m) => _openAntropoDialog(initial: m),
          ),
        ),
      ],
    );
  }

  Widget _buildRendimiento(
    AppPalette palette,
    AsyncValue<List<Measurement>> measAsync,
    AsyncValue<List<PerformanceTest>> perfAsync,
  ) {
    // CustomScrollView y no SingleChildScrollView + Column: la lista de abajo
    // puede tener cientos de filas (un alumno con dos años de tomas), y cada
    // fila es un StatefulWidget con detalle expandible. Adentro de un
    // SingleChildScrollView la lista queda obligada a `shrinkWrap: true` con el
    // scroll propio apagado, que construye TODAS las filas al abrir la
    // sub-vista. Antes de unir Progreso con Mediciones esto no pasaba: la lista
    // colgaba de un `Expanded` y tenía su propio viewport perezoso.
    //
    // Con slivers hay un solo viewport, el header y el chart scrollean junto a
    // la lista, y `SliverList` vuelve a construir sólo lo que se ve
    // (AGENTS.md §6: «ListView.builder para listas largas»).
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProgressHeader(
                  title: 'Pruebas de rendimiento', // i18n: Fase W2
                  subtitle:
                      'Saltos, sprints, 1RM y resistencia.', // i18n: Fase W2
                  actionLabel: 'NUEVA PRUEBA', // i18n: Fase W2
                  onPressed: _openRendimientoDialog,
                  palette: palette,
                ),
                const SizedBox(height: 20),
                _ProgressReading(
                  measurements: measAsync,
                  performanceTests: perfAsync,
                  palette: palette,
                  view: _ProgressView.rendimiento,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: _RendimientoList(
            performanceTests: perfAsync,
            palette: palette,
            onDelete: _confirmDeleteRendimiento,
            onEdit: (t) => _openRendimientoDialog(initial: t),
          ),
        ),
      ],
    );
  }
}

enum _ProgressView { antropometria, rendimiento }

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
    required this.palette,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.hairline),
              Text(
                subtitle,
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: onPressed,
          icon: const Icon(TreinoIcon.plus, size: 16),
          label: Text(actionLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: TreinoButtonTokens.foreground(context),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}

class _ProgressReading extends StatelessWidget {
  const _ProgressReading({
    required this.measurements,
    required this.performanceTests,
    required this.palette,
    required this.view,
  });

  final AsyncValue<List<Measurement>> measurements;
  final AsyncValue<List<PerformanceTest>> performanceTests;
  final AppPalette palette;
  final _ProgressView view;

  @override
  Widget build(BuildContext context) {
    // Antropometría y Rendimiento son fuentes independientes: gateamos juntas
    // (spinner hasta que ambas tengan valor, error si alguna falla). Así nunca
    // afirmamos que falta progreso cuando una de las fuentes es desconocida.
    if (measurements.isLoading || performanceTests.isLoading) {
      return const TreinoStateSwitcher(
        childKey: ValueKey('reading-loading'),
        child: CoachHubSkeleton(filas: 3),
      );
    }
    if (measurements.hasError || performanceTests.hasError) {
      return TreinoStateSwitcher(
        childKey: const ValueKey('reading-error'),
        child:
            _muted(palette, 'No se pudo cargar el progreso.'), // i18n: Fase W2
      );
    }

    final ms = measurements.requireValue;
    final tests = performanceTests.requireValue;
    if (ms.isEmpty && tests.isEmpty) {
      return const SizedBox.shrink();
    }

    if (view == _ProgressView.rendimiento) {
      return tests.length >= 2
          ? PerformanceProgressChart(tests: tests)
          : const SizedBox.shrink();
    }

    if (ms.isEmpty) return const SizedBox.shrink();
    final latest = ms.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _MeasCard(
              label: 'Peso',
              value: latest.weightKg,
              unit: 'kg',
              palette: palette,
            ), // i18n: Fase W2
            const SizedBox(width: 12),
            _MeasCard(
              label: '% Graso',
              value: latest.fatPercentage,
              unit: '%',
              palette: palette,
            ), // i18n: Fase W2
            const SizedBox(width: 12),
            _MeasCard(
              label: 'Cintura',
              value: latest.waistCm,
              unit: 'cm',
              palette: palette,
            ), // i18n: Fase W2
          ],
        ),
        if (ms.length >= 2) ...[
          const SizedBox(height: 20),
          MeasurementProgressChart(measurements: ms),
        ],
      ],
    );
  }
}

class _MeasCard extends StatelessWidget {
  const _MeasCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.palette,
  });

  final String label;
  final double? value;
  final String unit;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: palette.textMuted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              value == null ? '—' : '${_trimNum(value!)} $unit',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _sectionLabel(AppPalette palette, String text) => Text(
      text,
      style: TextStyle(
        color: palette.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );

Widget _muted(AppPalette palette, String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            style: TextStyle(color: palette.textMuted, fontSize: 14)),
      ),
    );

/// Entero si es redondo, un decimal si no (61 → "61", 60.5 → "60.5").
String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Volumen compacto: kg hasta 999, toneladas con un decimal de ahí en más.
String _fmtVolKg(double kg) =>
    kg >= 1000 ? '${(kg / 1000).toStringAsFixed(1)} t' : '${kg.round()} kg';

/// Tab Resumen (W2 PR4): 4 métricas derivadas + heatmap de adherencia de 12
/// semanas. Sólo usa data trainer-readable (sesiones, mediciones, plan
/// activo) vía [ResumenMetrics]. La última-sesión por ejercicio, los datos
/// personales privados, la nota fijada y la próxima sesión se difieren
/// (dependen de `setLogs` owner-only, campos privados o backend nuevo).
class _ResumenTab extends ConsumerWidget {
  const _ResumenTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));
    final measAsync = ref.watch(measurementsForAthleteProvider(athleteId));
    final routinesAsync = ref.watch(assignedRoutinesByTrainerProvider(
      (trainerId: trainerUid ?? '', athleteId: athleteId),
    ));

    // El resumen combina tres fuentes async: spinner hasta que las tres tengan
    // valor, y un único error si alguna falla. Si leyéramos routines/measurements
    // con valueOrNull, un error o un load lento se disfrazaría de «sin plan /
    // sin datos» — data trainer-facing engañosa.
    if (sessionsAsync.isLoading ||
        measAsync.isLoading ||
        routinesAsync.isLoading) {
      return const TreinoStateSwitcher(
        childKey: ValueKey('loading'),
        child: CoachHubSkeleton(filas: 3),
      );
    }
    // measurements (trainer-owned) y routines SIEMPRE son legibles → si alguna
    // falla es un error real del resumen. Las SESIONES, en cambio, dependen de
    // `session_shares`, que el CF borra cuando el link no está `active` (p.ej.
    // pausado) → un permission-denied ahí NO es un error del resumen: lo
    // degradamos a "sin sesiones" y renderizamos igual todo lo que sí se puede
    // (mediciones, plan, próxima sesión, nota, datos personales). Los widgets
    // dependientes de sesiones (adherencia, última sesión) muestran su propio
    // estado vacío.
    if (measAsync.hasError || routinesAsync.hasError) {
      return TreinoStateSwitcher(
        childKey: const ValueKey('error'),
        child:
            _muted(palette, 'No se pudo cargar el resumen.'), // i18n: Fase W2
      );
    }

    final routines = routinesAsync.requireValue;
    final actives = routines.where((r) => r.status == RoutineStatus.active);
    final active =
        actives.where((r) => r.assignedBy == trainerUid).firstOrNull ??
            actives.firstOrNull;
    final sessions = sessionsAsync.valueOrNull ?? const [];
    final m = ResumenMetrics.compute(
      sessions: sessions,
      measurements: measAsync.requireValue,
      weeklyTarget: active?.days.length ?? 0,
      now: AppClock.now(),
    );

    final adh = m.adherencia30dPct;
    final adhDelta = m.adherenciaDeltaPts;
    final volDelta = m.volumenDeltaPct;
    final peso = m.pesoActualKg;
    final pesoDelta = m.pesoDelta30dKg;

    // El peso corporal es la única de las cuatro métricas que NO depende de que
    // haya una rutina asignada: el alumno se pesa igual.
    final pesoCard = _MetricCard(
      palette: palette,
      icon: TreinoIcon.scales,
      label: 'PESO CORPORAL', // i18n: Fase W2
      value: peso == null ? '—' : '${_trimNum(peso)} kg',
      delta: pesoDelta == null
          ? null
          : '${pesoDelta >= 0 ? '+' : ''}${pesoDelta.toStringAsFixed(1)} kg',
      deltaColor: pesoDelta == null
          ? null
          : (pesoDelta >= 0 ? palette.accent : palette.danger),
      caption: pesoDelta == null ? null : '30 días',
    );

    // Sin rutina asignada, las otras tres no son cero: son indefinidas.
    //
    // La fila mostraba «—», «0.0» y «0 kg», con «Sin plan» susurrado dos veces
    // en los captions. Un PF que abre la ficha ve cuatro tarjetas y tres en
    // cero: eso se lee como un alumno que no entrena, no como un alumno al que
    // todavía no le asignaron nada. Y la diferencia entre esas dos lecturas es
    // de quién es el problema.
    //
    // Se dice una vez, con el tamaño que corresponde, y con la salida al lado.
    final kpiRow = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: active == null
            ? [
                _SinRutinaNotice(
                  palette: palette,
                  onAsignar: () => context.push('/routine-editor/$athleteId'),
                ),
                const SizedBox(width: 10),
                pesoCard,
              ]
            : [
                _MetricCard(
                  palette: palette,
                  icon: TreinoIcon.checkCircleFill,
                  label: 'ADHERENCIA 30D', // i18n: Fase W2
                  value: adh == null ? '—' : '${adh.round()}%',
                  delta: adhDelta == null
                      ? null
                      : '${adhDelta >= 0 ? '↑' : '↓'} '
                          '${adhDelta.abs().round()} pts',
                  deltaColor: adhDelta == null
                      ? null
                      : (adhDelta >= 0 ? palette.accent : palette.danger),
                  caption:
                      adh == null ? 'Todavía sin datos' : 'vs 30 días previos',
                ),
                const SizedBox(width: 10),
                _MetricCard(
                  palette: palette,
                  icon: TreinoIcon.calendar,
                  label: 'SESIONES / SEM', // i18n: Fase W2
                  value: m.sesionesPorSemana.toStringAsFixed(1),
                  caption: 'Plan: ${m.weeklyTarget}',
                ),
                const SizedBox(width: 10),
                _MetricCard(
                  palette: palette,
                  icon: TreinoIcon.dumbbell,
                  label: 'VOLUMEN', // i18n: Fase W2
                  value: _fmtVolKg(m.volumenSemanaActualKg),
                  delta: volDelta == null
                      ? null
                      : '${volDelta >= 0 ? '+' : ''}${volDelta.round()}%',
                  deltaColor: volDelta == null
                      ? null
                      : (volDelta >= 0 ? palette.accent : palette.danger),
                  caption:
                      volDelta == null ? 'esta semana' : 'vs semana pasada',
                ),
                const SizedBox(width: 10),
                pesoCard,
              ],
      ),
    );

    final heatmapBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(palette, 'ADHERENCIA · 12 SEMANAS'), // i18n: Fase W2
        const SizedBox(height: 10),
        _AdherenciaHeatmap(
          data: m.heatmap,
          palette: palette,
          // hardcoded for web Coach Hub (i18n: Fase W2)
          dayLabels: weekdayDistinctAbbrevs('es_AR'),
        ),
      ],
    );

    final noteBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(palette, 'NOTA FIJADA'), // i18n: Fase W2
        const SizedBox(height: 10),
        if (trainerUid != null)
          _NoteCard(
            palette: palette,
            trainerId: trainerUid,
            athleteId: athleteId,
          ),
      ],
    );

    final proxSesionBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(palette, 'PRÓXIMA SESIÓN'), // i18n: Fase W2
        const SizedBox(height: 10),
        _ProxSesionCard(palette: palette, athleteId: athleteId),
      ],
    );

    final ultimaSesionBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(
            palette, 'ÚLTIMA SESIÓN · POR EJERCICIO'), // i18n: Fase W2
        const SizedBox(height: 10),
        _UltimaSessionCard(
          palette: palette,
          athleteId: athleteId,
          sessionsAsync: sessionsAsync,
        ),
      ],
    );

    return TreinoStateSwitcher(
      childKey: const ValueKey('data'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            kpiRow,
            const SizedBox(height: 20),
            heatmapBlock,
            const SizedBox(height: 20),
            ultimaSesionBlock,
            const SizedBox(height: 20),
            noteBlock,
            const SizedBox(height: 20),
            proxSesionBlock,
          ],
        ),
      ),
    );
  }
}

/// Reemplaza a las tres métricas que dependen de una rutina cuando no hay
/// ninguna asignada.
///
/// Ocupa el ancho de las tres (`flex: 3`) para que la fila mantenga su ritmo:
/// la tarjeta de peso, que sí tiene dato, sigue midiendo lo mismo que antes y
/// no se estira a media pantalla.
///
/// Es explicación, no error: borde y fondo de tarjeta normal, sin `danger`. Que
/// un alumno todavía no tenga rutina es un paso pendiente del PF, no una falla
/// del alumno — pintarlo en rojo se lo cobraría a quien no corresponde.
class _SinRutinaNotice extends StatelessWidget {
  const _SinRutinaNotice({required this.palette, required this.onAsignar});

  final AppPalette palette;
  final VoidCallback onAsignar;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 3,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(TreinoIcon.dumbbell, size: 20, color: palette.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Sin rutina asignada', // i18n
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
                      fontSize: AppTextSize.body,
                      fontWeight: AppFonts.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                  Text(
                    'Adherencia, sesiones y volumen se miden contra el plan.', // i18n
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
                      fontSize: AppTextSize.caption,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            TextButton.icon(
              onPressed: onAsignar,
              icon: Icon(TreinoIcon.plus, size: 16, color: palette.accent),
              label: Text(
                'Asignar rutina', // i18n
                style: TextStyle(
                  fontFamily: AppFonts.barlow,
                  color: palette.accent,
                  fontWeight: AppFonts.w700,
                  fontSize: AppTextSize.bodyDense,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.palette,
    required this.icon,
    required this.label,
    required this.value,
    this.delta,
    this.deltaColor,
    this.caption,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final String value;
  final String? delta;
  final Color? deltaColor;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    // Delta null/textMuted → neutral (sin dato o estado plano); accent →
    // mejora; danger → retrocedió. El chip de ícono usa el mismo color para
    // que la lectura "bien/mal/neutro" sea inmediata sin leer el texto.
    final tone = deltaColor ?? palette.textMuted;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: tone),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (delta != null || caption != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (delta != null)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        delta!,
                        style: TextStyle(
                          color: tone,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (caption != null)
                    Flexible(
                      child: Text(
                        caption!,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── _NoteCard ─────────────────────────────────────────────────────────────────

/// Tarjeta de la nota fijada del PF sobre el alumno en el tab Resumen (W2 PR9).
///
/// Reutiliza [athleteNoteProvider] — el mismo que usa [_NotasPrivadasTab].
/// Trunca a 3 líneas + "hace X días" del updatedAt. Sin nota → estado vacío.
class _NoteCard extends ConsumerWidget {
  const _NoteCard({
    required this.palette,
    required this.trainerId,
    required this.athleteId,
  });

  final AppPalette palette;
  final String trainerId;
  final String athleteId;

  String _haceDias(DateTime updatedAt) {
    final diff = AppClock.now().difference(updatedAt.toLocal());
    final days = diff.inDays;
    if (days == 0) return 'hoy';
    if (days == 1) return 'hace 1 día';
    return 'hace $days días';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      athleteNoteProvider((trainerId: trainerId, athleteId: athleteId)),
    );
    // El layoutBuilder de TreinoStateSwitcher es un Stack(topCenter) con
    // StackFit.loose: le pasa al hijo minWidth:0, así que un Container con
    // contenido corto (esta card) se encoge y queda centrado. El fix real es
    // dar `width: double.infinity` al Container de adentro (ver el `data`
    // branch abajo); el SizedBox externo solo mantiene el maxWidth completo.
    return SizedBox(
      width: double.infinity,
      child: TreinoStateSwitcher(
        childKey: ValueKey(async.when(
          loading: () => 'loading',
          error: (_, __) => 'error',
          data: (_) => 'data',
        )),
        child: async.when(
          loading: () => SizedBox(
            height: 48,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: palette.accent),
              ),
            ),
          ),
          error: (_, __) => _muted(palette, 'No se pudo cargar la nota.'),
          data: (note) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.bgCard,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: note == null || note.note.trim().isEmpty
                  ? Text(
                      'Sin nota fijada.', // i18n: Fase W2
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.note,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _haceDias(note.updatedAt), // i18n: Fase W2
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

// ── _ProxSesionCard ───────────────────────────────────────────────────────────

/// Tarjeta de la próxima sesión confirmada del alumno (W2 PR9).
///
/// Reutiliza [appointmentsForAthleteStreamProvider] ya presente en
/// agenda_providers.dart. Filtra: confirmed + startsAt futuro, ordena ASC,
/// toma el primero. Sin sesiones → estado vacío.
class _ProxSesionCard extends ConsumerWidget {
  const _ProxSesionCard({required this.palette, required this.athleteId});

  final AppPalette palette;
  final String athleteId;

  String _fmtDate(DateTime dt) {
    // [dt] is an appointment.startsAt: wall-clock UTC per ADR-7 (the UTC fields
    // already REPRESENT Argentina local time). Read them raw — a `.toLocal()`
    // here would wrongly subtract 3h and show the turno earlier than it is
    // (#403). Same convention as the agenda / appointment_detail_sheet.
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y · $hh:$mm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La regla de `appointments` exige filtrar por trainerId — Firestore rechaza
    // un query por athleteId (watchForAthlete es del lado del alumno, no del PF).
    // Usamos el stream del trainer (mismo que el dashboard) con ventana
    // day-truncada ESTABLE y filtramos el alumno en memoria: sin permission-denied
    // y sin índice nuevo.
    final trainerId = ref.watch(currentUidProvider) ?? '';
    // Wall-clock ADR-7 (#671): con el instante UTC real, "Proxima sesion"
    // descartaba los turnos de las proximas 3h.
    final now = nowWall();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final async = ref.watch(trainerAppointmentsStreamProvider(
      TrainerAppointmentsKey(
        trainerId: trainerId,
        fromDate: todayStart,
        toDate: todayStart.add(const Duration(days: 60)),
      ),
    ));
    // width: infinity — ver nota en _NoteCard: el switcher encoge/centra su
    // hijo, sin esto la card queda angosta al medio.
    return SizedBox(
      width: double.infinity,
      child: TreinoStateSwitcher(
        childKey: ValueKey(async.when(
          loading: () => 'loading',
          error: (_, __) => 'error',
          data: (_) => 'data',
        )),
        child: async.when(
          loading: () => SizedBox(
            height: 48,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: palette.accent),
              ),
            ),
          ),
          error: (_, __) => _muted(palette, 'No se pudo cargar la agenda.'),
          data: (appointments) {
            final upcoming = appointments
                .where((a) =>
                    a.athleteId == athleteId &&
                    a.status == AppointmentStatus.confirmed &&
                    a.startsAt.isAfter(now))
                .toList()
              ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
            final next = upcoming.firstOrNull;

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.bgCard,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: next == null
                  ? Text(
                      'Sin sesiones próximas.', // i18n: Fase W2
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmtDate(next.startsAt), // i18n: Fase W2
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${next.durationMin} min', // i18n: Fase W2
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        if (next.noteBefore != null &&
                            next.noteBefore!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            next.noteBefore!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

// ── _UltimaSessionCard ────────────────────────────────────────────────────────

/// Tarjeta con el desglose por ejercicio de la última sesión del alumno (W2 PR9).
///
/// Reutiliza [coachSessionSetLogsProvider] — el mismo que usa [_SetLogsExpansion].
/// Incluye el mismo manejo de permission-denied (alumno no compartió historial).
/// Opcionalmente muestra badge "+N kg" usando [lastWeightByExerciseProvider].
class _UltimaSessionCard extends ConsumerWidget {
  const _UltimaSessionCard({
    required this.palette,
    required this.athleteId,
    required this.sessionsAsync,
  });

  final AppPalette palette;
  final String athleteId;
  final AsyncValue<List<Session>> sessionsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Caja bordeada reutilizable para los estados de texto (error / vacío).
    // stateKey identifica el estado top-level de esta card para que
    // TreinoStateSwitcher cross-fadee error/vacío/data en vez de saltar.
    // width: infinity — ver nota en _NoteCard: el switcher encoge/centra su
    // hijo, sin esto la caja queda angosta al medio.
    Widget box(String stateKey, Widget child) => SizedBox(
          width: double.infinity,
          child: TreinoStateSwitcher(
            childKey: ValueKey(stateKey),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.bgCard,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: child,
            ),
          ),
        );

    // Las sesiones dependen de `session_shares`, que el CF borra cuando el link
    // no está `active` (p.ej. pausado) → ahí la lista da permission-denied. Eso
    // NO es un fallo real: significa que el alumno no está compartiendo su
    // historial ahora. Lo decimos explícitamente en vez de un engañoso «sin
    // sesiones registradas» (que implicaría que nunca entrenó).
    if (sessionsAsync.hasError) {
      final e = sessionsAsync.error;
      final noShare = e is FirebaseException && e.code == 'permission-denied';
      return box(
        'error',
        Text(
          noShare
              ? 'El alumno no compartió su historial.' // i18n: Fase W2
              : 'No se pudo cargar la última sesión.', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
      );
    }

    final sessions = sessionsAsync.valueOrNull ?? const <Session>[];
    if (sessions.isEmpty) {
      return box(
        'empty',
        Text(
          'Sin sesiones registradas.', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
      );
    }

    final lastSession = sessions.first;
    final logsAsync = ref.watch(coachSessionSetLogsProvider(
        (athleteUid: athleteId, sessionId: lastSession.id)));
    final lastWeightAsync = ref.watch(lastWeightByExerciseProvider(athleteId));
    final muted = TextStyle(color: palette.textMuted, fontSize: 12);

    return box(
      'data',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lastSession.routineName, // i18n: Fase W2
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // width: infinity — ver nota en _NoteCard: el switcher encoge/centra.
          SizedBox(
            width: double.infinity,
            child: TreinoStateSwitcher(
              childKey: ValueKey(logsAsync.when(
                loading: () => 'loading',
                error: (_, __) => 'error',
                data: (_) => 'data',
              )),
              child: logsAsync.when(
                loading: () => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: palette.accent),
                  ),
                ),
                error: (e, _) {
                  final noShare =
                      e is FirebaseException && e.code == 'permission-denied';
                  return Text(
                    noShare
                        ? 'El alumno no compartió su historial.' // i18n: Fase W2
                        : 'No se pudo cargar el detalle de la sesión.', // i18n: Fase W2
                    style: muted,
                  );
                },
                data: (logs) {
                  if (logs.isEmpty) {
                    return Text(
                        'Sin series registradas en esta sesión.', // i18n: Fase W2
                        style: muted);
                  }
                  final groups = <String, List<SetLog>>{};
                  for (final log in logs) {
                    groups
                        .putIfAbsent(log.exerciseId, () => <SetLog>[])
                        .add(log);
                  }
                  final lastWeight = lastWeightAsync.valueOrNull;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in groups.entries)
                        _UltimaEjercicioRow(
                          palette: palette,
                          logs: entry.value,
                          progressionKg: lastWeight?[entry.key],
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de un ejercicio en [_UltimaSessionCard]: nombre + nro de sets +
/// badge opcional "+N kg" de progresión.
class _UltimaEjercicioRow extends StatelessWidget {
  const _UltimaEjercicioRow({
    required this.palette,
    required this.logs,
    this.progressionKg,
  });

  final AppPalette palette;
  final List<SetLog> logs;
  final double? progressionKg;

  @override
  Widget build(BuildContext context) {
    final name = logs.first.exerciseName;
    final sets = logs.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$sets × sets', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
          if (progressionKg != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${progressionKg! >= 0 ? '+' : ''}${progressionKg!.toStringAsFixed(1)} kg',
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Heatmap estilo GitHub: 7 filas (días, lunes→domingo) × 12 columnas
/// (semanas, vieja→actual). Cada celda colorea por nivel 0..4.
class _AdherenciaHeatmap extends StatelessWidget {
  const _AdherenciaHeatmap({
    required this.data,
    required this.palette,
    required this.dayLabels,
  });

  /// 12 semanas × 7 días (nivel 0..4), como lo devuelve [ResumenMetrics].
  final List<List<int>> data;
  final AppPalette palette;

  /// Abreviaturas de día sin colisión, lunes→domingo (martes/miércoles no
  /// quedan ambos como 'M'). Calculadas por el caller vía
  /// `weekdayDistinctAbbrevs` — este widget no importa `date_labels.dart`
  /// para mantenerlo desacoplado del cálculo de locale.
  final List<String> dayLabels;
  static const _labelWidth = 22.0;

  // Nivel 0 = celda vacía/muted (sin tinte accent, para que se lea claramente
  // "sin actividad"). Niveles 1..4 = rampa accent que escala del tenue al
  // saturado (mockup: verde claro → verde intenso), bien diferenciable a
  // simple vista entre escalones.
  Color _cellColor(int level) => level <= 0
      ? palette.border.withValues(alpha: 0.4)
      : palette.accent.withValues(alpha: 0.28 + level * 0.18);

  /// `true` si en las 12 semanas no hay UNA sola sesión.
  ///
  /// No es lo mismo que una grilla poco poblada: con actividad esporádica la
  /// grilla informa (se ve dónde entrenó y dónde no). Con cero, las 84 celdas
  /// caen todas al nivel 0 y la card se convierte en un rectángulo gris del
  /// ancho de la pantalla, que se lee como un componente roto y no como un
  /// alumno que todavía no arrancó.
  bool get _sinActividad =>
      data.every((semana) => semana.every((nivel) => nivel <= 0));

  @override
  Widget build(BuildContext context) {
    final axisStyle = TextStyle(color: palette.textMuted, fontSize: 9);

    if (_sinActividad) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(TreinoIcon.calendar, size: 20, color: palette.textMuted),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                'Sin sesiones en las últimas 12 semanas.', // i18n
                style: TextStyle(
                  fontFamily: AppFonts.barlow,
                  fontSize: AppTextSize.bodyDense,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Leyenda arriba a la derecha (mockup): "Menos [swatches] Más".
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Menos', style: axisStyle), // i18n: Fase W2
              const SizedBox(width: 6),
              for (var level = 0; level <= 4; level++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _cellColor(level),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Text('Más', style: axisStyle), // i18n: Fase W2
            ],
          ),
          const SizedBox(height: 10),
          // Celdas anchas tipo "barra" que llenan el ancho de la card (mockup):
          // cada semana es un Expanded, así la grilla se estira full-width en
          // vez de cuadraditos fijos con aire muerto a la derecha.
          for (var day = 0; day < 7; day++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: _labelWidth,
                    child: Text(dayLabels[day], style: axisStyle),
                  ),
                  for (var week = 0; week < data.length; week++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: _cellColor(data[week][day]),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          // Eje temporal alineado con la grilla (deja el ancho de la etiqueta de
          // día a la izquierda para que caiga bajo la primera/última columna).
          Padding(
            padding: const EdgeInsets.only(left: _labelWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('hace 12 sem', style: axisStyle), // i18n: Fase W2
                Text('esta semana', style: axisStyle), // i18n: Fase W2
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _cadenciaLabel(BillingCadence c) => switch (c) {
      BillingCadence.mensual => 'Mensual', // i18n: Fase W2
      BillingCadence.semanal => 'Semanal',
      BillingCadence.porSesion => 'Por sesión',
      BillingCadence.suelto => 'Suelto',
    };

/// Tab Pagos (W2 PR5/PR6): estado de cuenta + historial de pagos + acciones.
///
/// Sólo data trainer-readable: el historial sale de `trainerPaymentsProvider`
/// (que filtra por `trainerId == uid`, única forma que las reglas permiten al
/// entrenador) acotado a este alumno, y el cobro pendiente se reusa de
/// `pagosPorCobrarProvider` (que ya computa cadencia/deuda) sin reimplementar
/// billing. PR6 agrega **registrar pago** (crea un Payment pagado) y **marcar
/// pagado** (settlea un cobro pendiente: `markManyPaid` para los sueltos; crea
/// un Payment pagado con el `periodKey` que corresponda para los recurrentes —
/// misma receta que el dashboard del coach). Los recordatorios y las métricas
/// globales (ingreso del mes/proyección) se difieren.
/// Construye un CSV (RFC-4180) del historial de pagos del alumno. // i18n
///
/// Neutraliza inyección de fórmulas (CSV injection): una celda que arranca con
/// = + - @ (o tab/CR) la interpretan Excel/Sheets como FÓRMULA. `concept` es
/// texto libre, así que prefijamos esas celdas con comilla simple para forzar
/// que se traten como texto literal.
@visibleForTesting
String buildPagosCsv(List<Payment> payments) {
  String esc(String s) {
    // CSV-injection guard (OWASP): prefix a formula-trigger lead with a quote.
    final v = s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;
    return '"${v.replaceAll('"', '""')}"';
  }

  final rows = <String>['FECHA,CONCEPTO,MONTO,ESTADO,PERÍODO'];
  for (final p in payments) {
    final d = p.createdAt.toLocal();
    final fecha = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final estado =
        p.status == PaymentStatus.paid ? 'Pagado' : 'Pendiente'; // i18n
    rows.add([
      esc(fecha),
      esc(p.concept),
      esc(p.amountArs.toString()),
      esc(estado),
      esc(p.periodKey ?? ''),
    ].join(','));
  }
  return rows.join('\r\n');
}

class _PagosTab extends ConsumerWidget {
  const _PagosTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final paymentsAsync = ref.watch(trainerPaymentsProvider);
    final pendingAsync = ref.watch(pagosPorCobrarProvider);

    Widget body;
    String stateKey;
    if (paymentsAsync.isLoading || pendingAsync.isLoading) {
      stateKey = 'loading';
      body = const CoachHubSkeleton(filas: 3);
    } else if (paymentsAsync.hasError || pendingAsync.hasError) {
      stateKey = 'error';
      body =
          _muted(palette, 'No se pudieron cargar los pagos.'); // i18n: Fase W2
    } else {
      stateKey = 'data';
      body =
          _buildPagosBody(context, ref, palette, paymentsAsync, pendingAsync);
    }
    return TreinoStateSwitcher(
      childKey: ValueKey(stateKey),
      child: body,
    );
  }

  Widget _buildPagosBody(
    BuildContext context,
    WidgetRef ref,
    AppPalette palette,
    AsyncValue<List<Payment>> paymentsAsync,
    AsyncValue<List<CobroPendiente>> pendingAsync,
  ) {
    final history = paymentsAsync.requireValue
        .where((p) => p.athleteId == athleteId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pending = pendingAsync.requireValue
        .where((c) => c.athleteId == athleteId)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    _sectionLabel(palette, 'ESTADO DE CUENTA'), // i18n: Fase W2
              ),
              TextButton(
                onPressed: () => registrarPago(context, ref, athleteId),
                child: Text(
                  '+ Registrar pago', // i18n: Fase W2
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          EstadoCuentaCard(
            palette: palette,
            pending: pending,
            onMarcarPagado: (c) => marcarPagado(context, ref, c),
          ),
          const SizedBox(height: 20),
          _sectionLabel(palette, 'HISTORIAL DE PAGOS'), // i18n: Fase W2
          const SizedBox(height: 10),
          if (history.isEmpty)
            _muted(palette, 'Sin pagos registrados todavía.') // i18n: Fase W2
          else
            PagosTable(
              payments: history,
              palette: palette,
              onRecordar: (p) => recordar(
                context,
                ref,
                p,
                ref.read(userProfileProvider).valueOrNull?.paymentAlias,
              ),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                final name = ref
                        .read(userPublicProfileProvider(athleteId))
                        .valueOrNull
                        ?.displayName ??
                    'alumno';
                triggerBrowserDownload(
                  bytes:
                      Uint8List.fromList(utf8.encode(buildPagosCsv(history))),
                  filename: 'pagos_${name.replaceAll(' ', '_')}.csv',
                  mimeType: 'text/csv',
                );
              },
              child: Text(
                'Exportar CSV', // i18n: Fase W2
                style: TextStyle(
                  color: palette.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grupo Entrenamiento: separa lo que el PF arma (Rutina) de lo que el alumno
/// hizo (Sesiones y sus análisis).
class _EntrenamientoTab extends StatelessWidget {
  const _EntrenamientoTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _SubNav(labels: ['Rutina', 'Sesiones']), // i18n: Fase W2
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _RutinaTab(athleteId: athleteId),
                _HistorialTab(athleteId: athleteId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RutinaTab extends ConsumerWidget {
  const _RutinaTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    final routinesAsync = ref.watch(assignedRoutinesByTrainerProvider(
      (trainerId: trainerUid ?? '', athleteId: athleteId),
    ));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _sectionLabel(palette, 'RUTINA ACTIVA')), // i18n
              TextButton.icon(
                onPressed: () =>
                    context.push('/routine-editor/$athleteId'), // i18n
                icon: Icon(TreinoIcon.plus, size: 16, color: palette.accent),
                label: Text(
                  'Asignar rutina', // i18n: Fase W2
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TreinoStateSwitcher(
            childKey: ValueKey(routinesAsync.when(
              loading: () => 'loading',
              error: (_, __) => 'error',
              data: (_) => 'data',
            )),
            child: routinesAsync.when(
              loading: () => _muted(palette, 'Cargando…'), // i18n: Fase W2
              error: (e, _) => _muted(
                  palette, 'No se pudo cargar la rutina.'), // i18n: Fase W2
              data: (routines) {
                final actives =
                    routines.where((r) => r.status == RoutineStatus.active);
                final active = actives
                        .where((r) => r.assignedBy == trainerUid)
                        .firstOrNull ??
                    actives.firstOrNull;
                if (active == null) {
                  return _muted(
                      palette, 'Sin rutina activa asignada.'); // i18n: Fase W2
                }
                return _RutinaCard(
                    routine: active, palette: palette, athleteId: athleteId);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Músculos del día (PR2b) ───────────────────────────────────────────────────

/// Web-surface daily heat-map section.
///
/// Thin wrapper around the shared [DailyHeatmapSection] (AD5 dedupe — see
/// daily_heatmap_section.dart) with hardcoded Spanish labels, same pattern as
/// [_ProgressionTabSection].
///
/// All user-visible strings are hardcoded Spanish — the web Coach Hub does
/// NOT use AppL10n. Marked `// i18n: Fase W2` for future extraction.
///
/// Firestore access: trainer READ on `users/{uid}/sessions`+`setLogs` is
/// already granted by firestore.rules:786-807 (same predicate the mobile
/// coach shell relies on) — no rules change needed.
class _DailyHeatmapTabSection extends StatelessWidget {
  const _DailyHeatmapTabSection({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context) {
    return DailyHeatmapSection(
      athleteId: athleteId,
      labels: DailyHeatmapSectionLabels(
        sectionTitle: 'MÚSCULOS DEL DÍA', // i18n: Fase W2
        dayStripLabels: DayStripLabels(
          todayLabel: 'HOY', // i18n: Fase W2
          emptyDayHint: 'No entrenó este día.', // i18n: Fase W2
          // hardcoded for web Coach Hub (i18n: Fase W2)
          weekdayLetters: weekdayInitials('es_AR'),
        ),
      ),
    );
  }
}

// ── Evolución por ejercicio (PR2) ─────────────────────────────────────────────

/// Web-surface exercise-progression section.
///
/// Thin wrapper around the shared [ExerciseProgressionSection] (AD1 dedupe —
/// see exercise_progression_section.dart) with hardcoded Spanish labels.
///
/// All user-visible strings are hardcoded Spanish — the web Coach Hub does NOT
/// use AppL10n. Marked `// i18n: Fase W2` for future extraction.
///
/// Firestore access: trainer READ on setLogs is granted by firestore.rules:507-520
/// (mirrors the session-share predicate: owner OR linked trainer).
///
/// [PR4] Also owns the [_exerciseSelection] notifier shared with
/// [_MostFrequentExercisesTabSection] below it — tapping a row there selects
/// the exercise here (navigable to the existing exercise progression/detail).
class _ProgressionTabSection extends StatefulWidget {
  const _ProgressionTabSection({
    required this.athleteId,
    required this.palette,
  });

  final String athleteId;
  final AppPalette palette;

  @override
  State<_ProgressionTabSection> createState() => _ProgressionTabSectionState();
}

class _ProgressionTabSectionState extends State<_ProgressionTabSection> {
  final _exerciseSelection = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _exerciseSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExerciseProgressionSection(
          athleteId: widget.athleteId,
          externalExerciseSelection: _exerciseSelection,
          labels: ExerciseProgressionSectionLabels(
            sectionTitle: 'EVOLUCIÓN POR EJERCICIO', // i18n: Fase W2
            loadingText: 'Cargando…', // i18n: Fase W2
            exerciseListErrorText:
                'No se pudo cargar la evolución.', // i18n: Fase W2
            emptyStateText: 'Sin registros de series todavía.', // i18n: Fase W2
            chartLabels: ExerciseProgressionChartLabels(
              heaviestWeightLabel: 'Peso máximo', // i18n: Fase W2
              oneRepMaxLabel: '1RM', // i18n: Fase W2
              bestSetVolumeLabel: 'Mejor serie', // i18n: Fase W2
              bestSessionVolumeLabel: 'Volumen', // i18n: Fase W2
              volumeUnit: 'kg·reps', // i18n: Fase W2
              weightUnit: 'kg', // i18n: Fase W2
              // #555: el count viene acotado al período activo del selector.
              frequencyLabel: (n) => n == 1
                  ? '1 sesión en este período' // i18n: Fase W2
                  : '$n sesiones en este período', // i18n: Fase W2
              singlePointHint:
                  'Necesitás al menos 2 sesiones para ver la evolución.', // i18n: Fase W2
              emptyHint:
                  'Sin datos suficientes para este ejercicio.', // i18n: Fase W2
            ),
            periodLabels: const ChartPeriodLabels(
              last30dLabel: 'Últimos 30 días', // i18n: Fase W2
              thisWeekLabel: 'Esta semana', // i18n: Fase W2
              monthLabel: 'Este mes', // i18n: Fase W2
              last3mLabel: '3 meses', // i18n: Fase W2
              last1yLabel: '1 año', // i18n: Fase W2
            ),
            localeName: 'es_AR', // hardcoded for web Coach Hub (i18n: Fase W2)
            personalRecordsLabels: const PersonalRecordsListLabels(
              sectionTitle: 'RÉCORDS PERSONALES', // i18n: Fase W2
              heaviestWeightLabel: 'Peso máximo', // i18n: Fase W2
              oneRepMaxLabel: '1RM', // i18n: Fase W2
              bestSetVolumeLabel: 'Mejor serie', // i18n: Fase W2
              bestSessionVolumeLabel: 'Volumen', // i18n: Fase W2
              volumeUnit: 'kg·reps', // i18n: Fase W2
              weightUnit: 'kg', // i18n: Fase W2
              emptyText:
                  'Sin datos suficientes para este ejercicio.', // i18n: Fase W2
              localeName: 'es_AR', // i18n: Fase W2
            ),
          ),
        ),
        const SizedBox(height: 24),
        _MostFrequentExercisesTabSection(
          athleteId: widget.athleteId,
          onSelectExercise: (id) => _exerciseSelection.value = id,
        ),
      ],
    );
  }
}

/// [PR4] Web-surface most-frequent-exercises section shown below
/// [_ProgressionTabSection]. Hardcoded Spanish labels — same convention as
/// the rest of this file (`// i18n: Fase W2`).
class _MostFrequentExercisesTabSection extends ConsumerStatefulWidget {
  const _MostFrequentExercisesTabSection({
    required this.athleteId,
    required this.onSelectExercise,
  });

  final String athleteId;
  final void Function(String exerciseId) onSelectExercise;

  @override
  ConsumerState<_MostFrequentExercisesTabSection> createState() =>
      _MostFrequentExercisesTabSectionState();
}

class _MostFrequentExercisesTabSectionState
    extends ConsumerState<_MostFrequentExercisesTabSection> {
  ChartPeriod _selectedPeriod = ChartPeriod.defaultPeriod;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(exerciseFrequencyProvider(
        (athleteUid: widget.athleteId, period: _selectedPeriod)));

    return TreinoStateSwitcher(
      childKey: ValueKey(entriesAsync.when(
        loading: () => 'loading',
        error: (_, __) => 'error',
        data: (_) => 'data',
      )),
      child: entriesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => const SizedBox.shrink(),
        data: (entries) => MostFrequentExercisesList(
          entries: entries,
          selectedPeriod: _selectedPeriod,
          onSelectExercise: widget.onSelectExercise,
          onSelectPeriod: (p) => setState(() => _selectedPeriod = p),
          labels: MostFrequentExercisesListLabels(
            sectionTitle: 'EJERCICIOS MÁS FRECUENTES', // i18n: Fase W2
            sessionCountLabel: (n) => n == 1
                ? '1 sesión' // i18n: Fase W2
                : '$n sesiones', // i18n: Fase W2
            emptyText: 'No hay datos todavía.', // i18n: Fase W2
            periodLabels: const ChartPeriodLabels(
              last30dLabel: 'Últimos 30 días', // i18n: Fase W2
              thisWeekLabel: 'Esta semana', // i18n: Fase W2
              monthLabel: 'Este mes', // i18n: Fase W2
              last3mLabel: '3 meses', // i18n: Fase W2
              last1yLabel: '1 año', // i18n: Fase W2
            ),
          ),
        ),
      ),
    );
  }
}

class _RutinaCard extends StatelessWidget {
  const _RutinaCard({
    required this.routine,
    required this.palette,
    required this.athleteId,
  });
  final Routine routine;
  final AppPalette palette;
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  routine.name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    context.push('/routine-editor/$athleteId/${routine.id}'),
                icon: Icon(TreinoIcon.edit, size: 15, color: palette.accent),
                label: Text('Editar', // i18n: Fase W2
                    style: TextStyle(
                        color: palette.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${routine.days.length} días · ${routine.numWeeks} ${routine.numWeeks == 1 ? 'semana' : 'semanas'}', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          for (final day in routine.days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      day.name,
                      style:
                          TextStyle(color: palette.textPrimary, fontSize: 14),
                    ),
                  ),
                  Text(
                    '${day.slots.length} ${day.slots.length == 1 ? 'ejercicio' : 'ejercicios'}', // i18n: Fase W2
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistorialTable extends StatelessWidget {
  const _HistorialTable({
    super.key,
    required this.sessions,
    required this.palette,
    required this.athleteId,
    this.showStatusBadge = false,
  });
  final List<Session> sessions;
  final AppPalette palette;
  final String athleteId;

  /// If true, the row prefixes the session name with a small status pill
  /// (Completada / Incompleta / En curso).
  final bool showStatusBadge;

  @override
  Widget build(BuildContext context) {
    final h = TextStyle(
        color: palette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                // i18n: Fase W2 (encabezados)
                Expanded(flex: 3, child: Text('FECHA', style: h)),
                Expanded(flex: 4, child: Text('SESIÓN', style: h)),
                Expanded(flex: 2, child: Text('DURACIÓN', style: h)),
                Expanded(
                  flex: 2,
                  child: Text('VOLUMEN', style: h, textAlign: TextAlign.right),
                ),
                const SizedBox(width: 24),
              ],
            ),
          ),
          // Tap a session to expand its real per-exercise set detail
          // (trainer-athlete-set-logs).
          for (final s in sessions)
            _ExpandableSessionRow(
              session: s,
              athleteId: athleteId,
              palette: palette,
              showStatusBadge: showStatusBadge,
            ),
        ],
      ),
    );
  }
}

/// A session row that expands on tap to show the athlete's REAL logged sets
/// for that session (read-only; gated by `session_shares`).
class _ExpandableSessionRow extends ConsumerStatefulWidget {
  const _ExpandableSessionRow({
    required this.session,
    required this.athleteId,
    required this.palette,
    this.showStatusBadge = false,
  });
  final Session session;
  final String athleteId;
  final AppPalette palette;
  final bool showStatusBadge;

  @override
  ConsumerState<_ExpandableSessionRow> createState() =>
      _ExpandableSessionRowState();
}

class _ExpandableSessionRowState extends ConsumerState<_ExpandableSessionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final s = widget.session;
    final c = TextStyle(color: palette.textPrimary, fontSize: 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // MouseRegion(cursor): call-site web — InkWell daba cursor de mano
        // al hover, TreinoTappable no trae MouseRegion. Fix local seguro.
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: TreinoTappable(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      // Historial tab shows active sessions too; fall back to
                      // startedAt when finishedAt is null so the user still
                      // sees WHEN the athlete started it.
                      // Real UTC instants; fmtDate localizes them (#380).
                      s.finishedAt != null
                          ? fmtDate(s.finishedAt!)
                          : widget.showStatusBadge
                              ? fmtDate(s.startedAt)
                              : '—',
                      style: c,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: widget.showStatusBadge
                        ? Row(
                            children: [
                              _SessionStatusPill(session: s, palette: palette),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(s.routineName,
                                    overflow: TextOverflow.ellipsis, style: c),
                              ),
                            ],
                          )
                        : Text(s.routineName,
                            overflow: TextOverflow.ellipsis, style: c),
                  ),
                  Expanded(
                    flex: 2,
                    child:
                        Text('${s.durationMin} min', style: c), // i18n: Fase W2
                  ),
                  Expanded(
                    flex: 2,
                    child:
                        Text('${s.totalVolumeKg.round()} kg', // i18n: Fase W2
                            style: c,
                            textAlign: TextAlign.right),
                  ),
                  SizedBox(
                    width: 24,
                    child: Icon(
                      _expanded ? TreinoIcon.chevronUp : TreinoIcon.chevronDown,
                      size: 16,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          _SetLogsExpansion(
            athleteId: widget.athleteId,
            sessionId: s.id,
            palette: palette,
          ),
      ],
    );
  }
}

/// Loads and renders one session's per-exercise set logs for the trainer.
/// Maps `permission-denied` (athlete hasn't shared) to a friendly placeholder.
class _SetLogsExpansion extends ConsumerWidget {
  const _SetLogsExpansion({
    required this.athleteId,
    required this.sessionId,
    required this.palette,
  });
  final String athleteId;
  final String sessionId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(coachSessionSetLogsProvider(
        (athleteUid: athleteId, sessionId: sessionId)));
    // #628 — ver la nota en athlete_detail_screen: mismo provider, mismo
    // criterio de degradación y el MISMO aviso independiente cuando la lectura
    // falla. Que el PF esté en la web y no en el teléfono no cambia el modo de
    // falla: sin el aviso, "no pudimos leer" se ve igual que "no reportó nada".
    final feedbackAsync = ref.watch(coachSessionExerciseFeedbackProvider(
        (athleteUid: athleteId, sessionId: sessionId)));
    final feedback = feedbackAsync.valueOrNull ?? const <ExerciseFeedback>[];
    final feedbackFailed = feedbackAsync.hasError;
    final l10n = AppL10n.of(context);
    final muted = TextStyle(color: palette.textMuted, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: TreinoStateSwitcher(
        childKey: ValueKey(async.when(
          loading: () => 'loading',
          error: (_, __) => 'error',
          data: (_) => 'data',
        )),
        child: async.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: palette.accent),
            ),
          ),
          error: (e, _) {
            final noShare =
                e is FirebaseException && e.code == 'permission-denied';
            return Text(
              noShare
                  ? 'El alumno no compartió su historial.' // i18n: Fase W2
                  : 'No se pudo cargar el detalle de la sesión.', // i18n: Fase W2
              style: muted,
            );
          },
          data: (logs) {
            final groups =
                buildSessionExerciseGroups(sets: logs, feedback: feedback);
            // Mismo criterio que el athlete-detail mobile (#628): el
            // placeholder es de la sesión sin series Y sin reportes. Con
            // `logs.isEmpty` el PF veía "sin series" y perdía la molestia que
            // el alumno reportó sobre una serie que nunca registró.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Arriba y siempre que haya fallado, aun con la sesión vacía:
                // "no hay series" y "no pudimos leer los reportes" son dos
                // hechos distintos. Este SÍ sale por AppL10n aunque el resto
                // del widget siga en `// i18n: Fase W2` — la clave ya existe
                // (la creó este mismo change) y no había ningún motivo para
                // estrenar deuda de i18n nueva.
                if (feedbackFailed) ...[
                  FeedbackLoadErrorNote(
                      message: l10n.coachSessionFeedbackLoadError),
                  const SizedBox(height: AppSpacing.s8),
                ],
                if (groups.isEmpty)
                  Text(
                      'Sin series registradas en esta sesión.', // i18n: Fase W2
                      style: muted)
                else
                  for (final group in groups)
                    SessionExerciseBlock(
                      exerciseName: group.exerciseName,
                      sets: group.sets,
                      feedback: group.feedback,
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── _NotasPrivadasTab ─────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Notas privadas» del alumno detail.
///
/// UX (W2+):
/// - Text area grande, editable inline (no modal/bottom sheet, hay espacio).
/// - Botón GUARDAR habilitado solo cuando hay cambios pendientes vs lo que
///   trae el stream (compará contra el último save).
/// - Timestamp "Última edición ..." arriba a la derecha si hay una nota
///   guardada previamente.
/// - Empty state = text area vacío + hint. La regla del PF es "solo vos lo
///   ves" — no lo mostrás al alumno en NINGÚN surface.
///
/// Data:
/// - Reusa el mismo stack de mobile (`AthleteNote` + `athleteNoteProvider` +
///   `AthleteNoteRepository`). Sin data model nuevo, sin rules nuevas.
class _NotasPrivadasTab extends ConsumerStatefulWidget {
  const _NotasPrivadasTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_NotasPrivadasTab> createState() => _NotasPrivadasTabState();
}

class _NotasPrivadasTabState extends ConsumerState<_NotasPrivadasTab> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _lastSavedContent = '';
  bool _initialized = false;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _NotasPrivadasTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent swaps to a different athlete, Flutter reuses this
    // State — the controller keeps the previous athlete's text and the
    // "typing wins" gate blocks the new stream from populating it. Reset
    // the local buffer so the new athlete's stream seeds the controller
    // on its first emission.
    if (oldWidget.athleteId != widget.athleteId) {
      _initialized = false;
      _controller.text = '';
      _lastSavedContent = '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Sync `_controller` with the incoming server value the FIRST time the
  /// stream emits data — after that, we own the buffer (typing wins). If the
  /// PF opens the tab, types "foo", and a stale re-emit comes in with an
  /// older `note`, we DON'T overwrite what they typed. Save button drives
  /// the reconciliation.
  void _initFromStream(AthleteNote? note) {
    if (_initialized) return;
    _initialized = true;
    final content = note?.note ?? '';
    _controller.text = content;
    _lastSavedContent = content;
  }

  bool get _hasChanges => _controller.text != _lastSavedContent;

  Future<void> _save(String trainerUid) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final content = _controller.text;
      await ref.read(athleteNoteRepositoryProvider).setNote(
            AthleteNote(
              trainerId: trainerUid,
              athleteId: widget.athleteId,
              note: content,
              updatedAt: DateTime.now(),
            ),
          );
      if (!mounted) return;
      setState(() {
        _lastSavedContent = content;
      });
      final l10n = AppL10n.of(context);
      // Mismo patrón que las 4 snackbars de éxito de Agenda
      // (appointment_detail_dialog.dart): mismo momento de éxito (guardado),
      // mismo feedback — antes solo el guardado de notas del TURNO tenía el
      // check y el de notas privadas del alumno quedaba en texto plano.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TreinoSuccessCheck(size: 18, strokeWidth: 2),
              const SizedBox(width: 10),
              Flexible(child: Text(l10n.coachHubAlumnoDetailNotasSaveSuccess)),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } on FirebaseException catch (_) {
      if (!mounted) return;
      final l10n = AppL10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.coachHubAlumnoDetailNotasSaveError)),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _formatUpdatedAt(DateTime updatedAt) {
    final local = updatedAt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null) {
      return const SizedBox.shrink();
    }
    final noteAsync = ref.watch(
      athleteNoteProvider(
        (trainerId: trainerUid, athleteId: widget.athleteId),
      ),
    );

    return TreinoStateSwitcher(
      childKey: ValueKey(noteAsync.when(
        loading: () => 'loading',
        error: (_, __) => 'error',
        data: (_) => 'data',
      )),
      child: noteAsync.when(
        loading: () => const CoachHubSkeleton(filas: 3),
        error: (_, __) => Center(
          child: Text(
            l10n.coachHubAlumnoDetailNotasLoadError,
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
        ),
        data: (note) {
          // First data emission: seed the text controller. Subsequent emissions
          // are ignored — the PF's local buffer wins to avoid clobbering typing.
          _initFromStream(note);
          final updatedAt = note?.updatedAt;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header row: title + last-updated timestamp ─────────────
                Row(
                  children: [
                    Text(
                      l10n.coachHubAlumnoDetailNotasTitle,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (updatedAt != null)
                      Text(
                        l10n.coachHubAlumnoDetailNotasUpdatedAt(
                            _formatUpdatedAt(updatedAt)),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.coachHubAlumnoDetailNotasSubtitle,
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                // ── Editable text area ──────────────────────────────────────
                Expanded(
                  // Rounded box that clips the scrollable content. Instead of
                  // `TextField(expands: true)` which paints outside its parent
                  // in some Flutter Web configs, we let the TextField grow to
                  // its natural content height inside a SingleChildScrollView
                  // — the SCV owns the scrolling and clips reliably against
                  // the ClipRRect ancestor.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: palette.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: ColoredBox(
                        color: palette.bgCard,
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          thickness: 6,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                            child: TextField(
                              controller: _controller,
                              maxLines: null,
                              minLines: 12,
                              keyboardType: TextInputType.multiline,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 14,
                                height: 1.4,
                              ),
                              decoration: InputDecoration.collapsed(
                                hintText: l10n.coachHubAlumnoDetailNotasHint,
                                hintStyle: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 14,
                                ),
                              ),
                              onChanged: (_) {
                                // Trigger rebuild to toggle save enabled state.
                                setState(() {});
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // ── Save button ─────────────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: (_saving || !_hasChanges)
                        ? null
                        : () => _save(trainerUid),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: TreinoButtonTokens.foreground(context),
                      disabledBackgroundColor:
                          palette.accent.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: TreinoButtonTokens.foreground(context),
                            ),
                          )
                        : Text(
                            l10n.coachHubAlumnoDetailNotasSaveButton,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── _HistorialTab ─────────────────────────────────────────────────────────────

/// Coach Hub web — sub-vista «Sesiones» del alumno detail.
///
/// Timeline cronológico de TODAS las sesiones del alumno (finished OK,
/// finished incompleta/abandonada, y active). Ordenadas más nuevas arriba,
/// vienen así del `sessionsByUidProvider`.
///
/// Muestra TODAS las sesiones (sin límite, sin filtro) con badge de estado,
/// más los análisis del heatmap diario y la progresión por ejercicio.
class _HistorialTab extends ConsumerWidget {
  const _HistorialTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoStateSwitcher(
            childKey: ValueKey(sessionsAsync.when(
              loading: () => 'sessions-loading',
              error: (_, __) => 'sessions-error',
              data: (_) => 'sessions-data',
            )),
            child: sessionsAsync.when(
              loading: () => const CoachHubSkeleton(filas: 3),
              error: (e, _) => _muted(
                palette,
                e is FirebaseException && e.code == 'permission-denied'
                    ? 'El alumno no compartió su historial.' // i18n: Fase W2
                    : 'No pudimos cargar el historial.', // i18n: Fase W2
              ),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return _muted(
                    palette,
                    'Este alumno todavía no registró sesiones.', // i18n: Fase W2
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Historial completo · ${sessions.length} sesiones', // i18n: Fase W2
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Todas las sesiones que registró — completas, incompletas y en curso.', // i18n: Fase W2
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    _HistorialTable(
                      key: const ValueKey('sesiones-table-completa'),
                      sessions: sessions,
                      palette: palette,
                      athleteId: athleteId,
                      showStatusBadge: true,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _DailyHeatmapTabSection(athleteId: athleteId),
          const SizedBox(height: 20),
          _ProgressionTabSection(athleteId: athleteId, palette: palette),
        ],
      ),
    );
  }
}

// ── _SessionStatusPill ────────────────────────────────────────────────────────

/// Small pill/badge rendering the session's completion status: verde
/// «Completa», amarillo «Incompleta», naranja «En curso». Used inside the
/// Historial tab's session rows to distinguish state at a glance.
class _SessionStatusPill extends StatelessWidget {
  const _SessionStatusPill({required this.session, required this.palette});

  final Session session;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusFor(session, palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Returns (label, color) for the session's current state.
  /// - `active` → «En curso» (rare in Historial but we show it if we see it).
  /// - `finished + wasFullyCompleted` → «Completa».
  /// - `finished + !wasFullyCompleted` → «Incompleta» (athlete abandoned).
  static (String, Color) _statusFor(Session s, AppPalette palette) {
    if (s.status == SessionStatus.active) {
      return ('EN CURSO', palette.warning); // i18n: Fase W2
    }
    if (s.wasFullyCompleted) {
      return ('COMPLETA', palette.accent); // i18n: Fase W2
    }
    return ('INCOMPLETA', palette.danger); // i18n: Fase W2
  }
}

// ── _ArchivosTab ──────────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Archivos» del alumno detail.
///
/// Carpeta del PF por alumno para subir PDFs e imágenes (estudios médicos,
/// fotos de postura/lesión, planes impresos). Cada fila deja claro si el
/// archivo sigue privado o está compartido con el alumno.
///
/// Data: reusa `athleteFilesProvider` + `AthleteFileRepository` (Firestore
/// para metadata + Firebase Storage para el binario). El PF administra todos;
/// el alumno sólo puede leer los que tienen `sharedWithAthlete == true`.
///
/// V1 scope:
/// - Solo PDF + imágenes (10 MB max).
/// - Lista simple (más nuevos arriba).
/// - Subir → file picker → upload + set doc.
/// - Descargar → abre `downloadUrl` en tab nueva.
/// - Compartir → prende o apaga el acceso read-only del alumno.
/// - Borrar → confirm dialog → borra Storage + Firestore.
class _ArchivosTab extends ConsumerStatefulWidget {
  const _ArchivosTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_ArchivosTab> createState() => _ArchivosTabState();
}

class _ArchivosTabState extends ConsumerState<_ArchivosTab> {
  bool _uploading = false;

  Future<void> _pickAndUpload(String trainerUid) async {
    if (_uploading) return;
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'gif'],
      withData: true, // Necesitamos bytes para putData en web.
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return;

    setState(() => _uploading = true);
    try {
      final contentType = _guessContentType(picked.name, picked.extension);
      await ref.read(athleteFileRepositoryProvider).upload(
            trainerId: trainerUid,
            athleteId: widget.athleteId,
            fileName: picked.name,
            contentType: contentType,
            bytes: bytes,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosUploadSuccess),
          duration: const Duration(seconds: 2),
        ),
      );
    } on AthleteFileTooLargeException {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosUploadTooLarge),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosUploadError),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmAndDelete(AthleteFile file) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.coachHubAlumnoDetailArchivosDeleteTitle),
        content: Text(
          l10n.coachHubAlumnoDetailArchivosDeleteBody(file.fileName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.coachHubActionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.coachHubActionConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(athleteFileRepositoryProvider).delete(file);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosDeleteError),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null) return const SizedBox.shrink();
    final filesAsync = ref.watch(
      athleteFilesProvider(
        (trainerId: trainerUid, athleteId: widget.athleteId),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.coachHubAlumnoDetailArchivosTitle,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.coachHubAlumnoDetailArchivosSubtitle,
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _uploading ? null : () => _pickAndUpload(trainerUid),
                icon: _uploading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.bg,
                        ),
                      )
                    : Icon(TreinoIcon.upload, size: 16, color: palette.bg),
                label: Text(l10n.coachHubAlumnoDetailArchivosUploadButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: TreinoButtonTokens.foreground(context),
                  disabledBackgroundColor:
                      palette.accent.withValues(alpha: 0.3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            // Sticky-data pattern: si ya emitimos data alguna vez, la
            // seguimos mostrando aunque el stream emita error después
            // (ej. reconnect transient de Firestore). Solo mostramos el
            // error state duro cuando NO hay data previa. El key del
            // StateSwitcher espeja exactamente esa prioridad (hasValue >
            // hasError > loading) para no alterar la lógica, solo agregar
            // el cross-fade.
            child: TreinoStateSwitcher(
              childKey: ValueKey(filesAsync.hasValue
                  ? 'data'
                  : (filesAsync.hasError ? 'error' : 'loading')),
              child: Builder(
                builder: (_) {
                  if (filesAsync.hasValue) {
                    final files = filesAsync.requireValue;
                    if (files.isEmpty) {
                      return Center(
                        child: Text(
                          l10n.coachHubAlumnoDetailArchivosEmpty,
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: palette.textMuted, fontSize: 14),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: palette.border,
                      ),
                      itemBuilder: (_, i) => _ArchivoRow(
                        file: files[i],
                        palette: palette,
                        onDelete: () => _confirmAndDelete(files[i]),
                      ),
                    );
                  }
                  if (filesAsync.hasError) {
                    return Center(
                      child: Text(
                        l10n.coachHubAlumnoDetailArchivosLoadError,
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 14),
                      ),
                    );
                  }
                  return const CoachHubSkeleton(filas: 3);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Deriva contentType desde el nombre/extension del picker. Files desde
  /// web NO siempre traen mimeType poblado (a diferencia de image_picker),
  /// así que armamos el contentType nosotros basado en la extensión.
  static String _guessContentType(String fileName, String? extension) {
    final ext = (extension ?? _extFromName(fileName)).toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  static String _extFromName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot >= fileName.length - 1) return '';
    return fileName.substring(dot + 1);
  }
}

/// Row de un archivo dentro del tab Archivos.
class _ArchivoRow extends ConsumerWidget {
  const _ArchivoRow({
    required this.file,
    required this.palette,
    required this.onDelete,
  });

  final AthleteFile file;
  final AppPalette palette;
  final VoidCallback onDelete;

  Future<void> _open() async {
    final uri = Uri.tryParse(file.downloadUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggleShared(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(athleteFileRepositoryProvider)
          .setShared(file, !file.sharedWithAthlete);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosShareError),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final icon = switch (file.kind) {
      AthleteFileKind.pdf => TreinoIcon.filePdf,
      AthleteFileKind.image => TreinoIcon.image,
      AthleteFileKind.other => TreinoIcon.file,
    };
    final subtitle =
        '${_formatSize(file.sizeBytes)} · ${fmtDate(file.uploadedAt)}';
    // MouseRegion(cursor): call-site web — InkWell daba cursor de mano al
    // hover, TreinoTappable no trae MouseRegion. Fix local seguro.
    // TreinoTappable envuelve solo el icono+texto (Expanded): los IconButton
    // quedan como siblings del Row exterior, fuera de su subtree, para que
    // los dos recognizers no compitan en el gesture arena (ver
    // _ExerciseRow en exercise_picker_sheet.dart).
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: TreinoTappable(
                onTap: _open,
                child: Row(
                  children: [
                    Icon(icon, size: 24, color: palette.textMuted),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.fileName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Tooltip(
              message: file.sharedWithAthlete
                  ? l10n.coachHubAlumnoDetailArchivosUnshareTooltip
                  : l10n.coachHubAlumnoDetailArchivosShareTooltip,
              child: TextButton.icon(
                onPressed: () => _toggleShared(context, ref),
                icon: Icon(
                  file.sharedWithAthlete ? TreinoIcon.eye : TreinoIcon.eyeOff,
                  size: 18,
                ),
                label: Text(
                  file.sharedWithAthlete
                      ? l10n.coachHubAlumnoDetailArchivosSharedLabel
                      : l10n.coachHubAlumnoDetailArchivosPrivateLabel,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: file.sharedWithAthlete
                      ? palette.accentText
                      : palette.textMuted,
                  textStyle: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.caption,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.coachHubAlumnoDetailArchivosOpenTooltip,
              onPressed: _open,
              icon:
                  Icon(TreinoIcon.download, size: 18, color: palette.textMuted),
            ),
            IconButton(
              tooltip: l10n.coachHubAlumnoDetailArchivosDeleteTooltip,
              onPressed: onDelete,
              icon: Icon(TreinoIcon.trash, size: 18, color: palette.danger),
            ),
          ],
        ),
      ),
    );
  }

  /// KB si < 1 MB, MB con 1 decimal si mayor. Redondeo defensivo.
  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Subvista de mediciones antropométricas.
class _AntropoList extends StatelessWidget {
  const _AntropoList({
    required this.measurements,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final AsyncValue<List<Measurement>> measurements;
  final AppPalette palette;
  final Future<void> Function(Measurement) onDelete;
  final Future<void> Function(Measurement) onEdit;

  /// Devuelve un SLIVER, no una caja.
  ///
  /// Es lo que le devuelve el renderizado perezoso a esta lista. Como caja,
  /// adentro del scroll de la sub-vista, la lista quedaba obligada a
  /// `shrinkWrap: true` y construía las cientos de filas de un alumno con
  /// historial largo apenas se abría la pestaña. `SliverList` construye sólo
  /// lo que entra en pantalla, y comparte el viewport con el header y el chart.
  @override
  Widget build(BuildContext context) {
    if (measurements.hasValue) {
      final all = measurements.requireValue;
      // Provider ordena ASC — queremos DESC para "más nuevas arriba".
      final ms = all.reversed.toList();
      if (ms.isEmpty) {
        return SliverToBoxAdapter(
          child: TreinoStateSwitcher(
            childKey: const ValueKey('empty'),
            child: Center(
              child: Text(
                'Este alumno todavía no tiene mediciones cargadas.', // i18n: Fase W2
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 14),
              ),
            ),
          ),
        );
      }
      // Sin TreinoStateSwitcher en esta rama, a propósito: envuelve una caja y
      // acá el hijo es un sliver. Las transiciones de estado siguen animadas en
      // las ramas de vacío, error y carga, que son las que se alternan.
      return SliverList.separated(
        itemCount: ms.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: palette.border),
        itemBuilder: (_, i) => _MedicionRow(
          measurement: ms[i],
          palette: palette,
          onDelete: () => onDelete(ms[i]),
          onEdit: () => onEdit(ms[i]),
        ),
      );
    }
    if (measurements.hasError) {
      return SliverToBoxAdapter(
        child: TreinoStateSwitcher(
          childKey: const ValueKey('error'),
          child: Center(
            child: Text(
              'No pudimos cargar las mediciones.', // i18n: Fase W2
              style: TextStyle(color: palette.textMuted, fontSize: 14),
            ),
          ),
        ),
      );
    }
    return const SliverToBoxAdapter(
      child: TreinoStateSwitcher(
        childKey: ValueKey('loading'),
        child: CoachHubSkeleton(filas: 3),
      ),
    );
  }
}

/// Subvista de pruebas de rendimiento.
class _RendimientoList extends StatelessWidget {
  const _RendimientoList({
    required this.performanceTests,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final AsyncValue<List<PerformanceTest>> performanceTests;
  final AppPalette palette;
  final Future<void> Function(PerformanceTest) onDelete;
  final Future<void> Function(PerformanceTest) onEdit;

  /// Devuelve un SLIVER, no una caja — ver el dartdoc de [_AntropoList.build].
  @override
  Widget build(BuildContext context) {
    if (performanceTests.hasValue) {
      final all = performanceTests.requireValue;
      final tests = all.reversed.toList();
      if (tests.isEmpty) {
        return SliverToBoxAdapter(
          child: TreinoStateSwitcher(
            childKey: const ValueKey('empty'),
            child: Center(
              child: Text(
                'Este alumno todavía no tiene pruebas de rendimiento cargadas.', // i18n: Fase W2
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 14),
              ),
            ),
          ),
        );
      }
      return SliverList.separated(
        itemCount: tests.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: palette.border),
        itemBuilder: (_, i) => _RendimientoRow(
          test: tests[i],
          palette: palette,
          onDelete: () => onDelete(tests[i]),
          onEdit: () => onEdit(tests[i]),
        ),
      );
    }
    if (performanceTests.hasError) {
      return SliverToBoxAdapter(
        child: TreinoStateSwitcher(
          childKey: const ValueKey('error'),
          child: Center(
            child: Text(
              'No pudimos cargar las pruebas.', // i18n: Fase W2
              style: TextStyle(color: palette.textMuted, fontSize: 14),
            ),
          ),
        ),
      );
    }
    return const SliverToBoxAdapter(
      child: TreinoStateSwitcher(
        childKey: ValueKey('loading'),
        child: CoachHubSkeleton(filas: 3),
      ),
    );
  }
}

/// Row de una medición individual. Tap para expandir y ver TODOS los campos
/// cargados (los que son null no se muestran para no ensuciar la UI).
class _MedicionRow extends StatefulWidget {
  const _MedicionRow({
    required this.measurement,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final Measurement measurement;
  final AppPalette palette;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_MedicionRow> createState() => _MedicionRowState();
}

class _MedicionRowState extends State<_MedicionRow> {
  bool _expanded = false;

  /// Summary line: los 3 campos que suele pedir el PF: peso, % grasa, cintura.
  /// Si alguno es null, se omite del summary.
  String _summary() {
    final m = widget.measurement;
    final parts = <String>[];
    if (m.weightKg != null) parts.add('${m.weightKg} kg');
    if (m.fatPercentage != null) parts.add('${m.fatPercentage}% grasa');
    if (m.waistCm != null) parts.add('cintura ${m.waistCm} cm');
    if (parts.isEmpty) return 'Sin datos de composición'; // i18n: Fase W2
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.measurement;
    final palette = widget.palette;
    // MouseRegion(cursor): call-site web — InkWell daba cursor de mano al
    // hover, TreinoTappable no trae MouseRegion. Fix local seguro.
    // TreinoTappable envuelve solo el ícono de expandir + texto (Expanded):
    // los IconButton de Editar/Eliminar quedan como siblings del Row
    // exterior, fuera de su subtree, para que los dos recognizers no
    // compitan en el gesture arena (ver _ExerciseRow en
    // exercise_picker_sheet.dart).
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TreinoTappable(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 22,
                          color: palette.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fmtDate(m.recordedAt),
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _summary(),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Editar', // i18n: Fase W2
                  onPressed: widget.onEdit,
                  icon: Icon(Icons.edit, size: 18, color: palette.textMuted),
                ),
                IconButton(
                  tooltip: 'Eliminar', // i18n: Fase W2
                  onPressed: widget.onDelete,
                  icon: Icon(TreinoIcon.trash, size: 18, color: palette.danger),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 12, 8, 0),
                child: _MedicionDetail(measurement: m, palette: palette),
              ),
          ],
        ),
      ),
    );
  }
}

/// Detalle expandido de una medición. Muestra solo los campos con valor.
/// Layout: 2 columnas de "label: valor" para aprovechar el ancho del web.
class _MedicionDetail extends StatelessWidget {
  const _MedicionDetail({required this.measurement, required this.palette});

  final Measurement measurement;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final m = measurement;
    final entries = <(String, String)>[
      // Composición
      if (m.weightKg != null) ('Peso', '${m.weightKg} kg'),
      if (m.fatPercentage != null) ('% grasa', '${m.fatPercentage}%'),
      if (m.muscleMassKg != null) ('Masa muscular', '${m.muscleMassKg} kg'),
      // Trunk
      if (m.shouldersCm != null) ('Hombros', '${m.shouldersCm} cm'),
      if (m.chestCm != null) ('Pecho', '${m.chestCm} cm'),
      if (m.waistCm != null) ('Cintura', '${m.waistCm} cm'),
      if (m.hipsCm != null) ('Cadera', '${m.hipsCm} cm'),
      if (m.glutesCm != null) ('Glúteos', '${m.glutesCm} cm'),
      // Upper
      if (m.bicepsLCm != null) ('Bíceps izq.', '${m.bicepsLCm} cm'),
      if (m.bicepsRCm != null) ('Bíceps der.', '${m.bicepsRCm} cm'),
      if (m.bicepsFlexedLCm != null)
        ('Bíceps flex. izq.', '${m.bicepsFlexedLCm} cm'),
      if (m.bicepsFlexedRCm != null)
        ('Bíceps flex. der.', '${m.bicepsFlexedRCm} cm'),
      if (m.forearmLCm != null) ('Antebrazo izq.', '${m.forearmLCm} cm'),
      if (m.forearmRCm != null) ('Antebrazo der.', '${m.forearmRCm} cm'),
      // Lower
      if (m.upperThighLCm != null) ('Muslo sup. izq.', '${m.upperThighLCm} cm'),
      if (m.upperThighRCm != null) ('Muslo sup. der.', '${m.upperThighRCm} cm'),
      if (m.midThighLCm != null) ('Muslo med. izq.', '${m.midThighLCm} cm'),
      if (m.midThighRCm != null) ('Muslo med. der.', '${m.midThighRCm} cm'),
      if (m.calfLCm != null) ('Gemelo izq.', '${m.calfLCm} cm'),
      if (m.calfRCm != null) ('Gemelo der.', '${m.calfRCm} cm'),
    ];

    if (entries.isEmpty && (m.notes ?? '').isEmpty) {
      return Text(
        'Esta medición no tiene valores cargados.', // i18n: Fase W2
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      );
    }

    // Split en 2 columnas para aprovechar ancho del web.
    final half = (entries.length / 2).ceil();
    final left = entries.take(half).toList();
    final right = entries.skip(half).toList();

    Widget colFor(List<(String, String)> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: colFor(left)),
            const SizedBox(width: 24),
            Expanded(child: colFor(right)),
          ],
        ),
        if ((m.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Nota',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            m.notes!,
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Dialog modal para cargar (o editar) una medición antropométrica.
///
/// Todos los campos son opcionales — el PF loguea solo lo que midió esa
/// sesión. Composición corporal siempre expandida (más común); las
/// circunferencias en 3 secciones colapsables para no abrumar.
///
/// PR#3 (2026-07-03): si [initial] es no-nulo → **modo edición**. El
/// formulario arranca pre-populado con los valores actuales y guarda con
/// `MeasurementRepository.update` preservando `id`/`recordedBy`/
/// `athleteId`/`recordedAt`. Si es nulo → **modo crear** con `.add`.
class _NuevaMedicionDialog extends ConsumerStatefulWidget {
  const _NuevaMedicionDialog({
    required this.athleteId,
    required this.trainerUid,
    this.initial,
  });

  final String athleteId;
  final String trainerUid;
  final Measurement? initial;

  @override
  ConsumerState<_NuevaMedicionDialog> createState() =>
      _NuevaMedicionDialogState();
}

class _NuevaMedicionDialogState extends ConsumerState<_NuevaMedicionDialog> {
  final _formKey = GlobalKey<FormState>();

  // Composición
  final _weightC = TextEditingController();
  final _fatC = TextEditingController();
  final _muscleC = TextEditingController();
  // Trunk
  final _shouldersC = TextEditingController();
  final _chestC = TextEditingController();
  final _waistC = TextEditingController();
  final _hipsC = TextEditingController();
  final _glutesC = TextEditingController();
  // Upper
  final _bicepsLC = TextEditingController();
  final _bicepsRC = TextEditingController();
  final _bicepsFlexedLC = TextEditingController();
  final _bicepsFlexedRC = TextEditingController();
  final _forearmLC = TextEditingController();
  final _forearmRC = TextEditingController();
  // Lower
  final _upperThighLC = TextEditingController();
  final _upperThighRC = TextEditingController();
  final _midThighLC = TextEditingController();
  final _midThighRC = TextEditingController();
  final _calfLC = TextEditingController();
  final _calfRC = TextEditingController();
  // Meta
  final _notesC = TextEditingController();

  bool _trunkExpanded = false;
  bool _upperExpanded = false;
  bool _lowerExpanded = false;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    // Pre-populate controllers con los valores existentes.
    void set(TextEditingController c, double? v) {
      if (v != null) c.text = v.toString();
    }

    set(_weightC, initial.weightKg);
    set(_fatC, initial.fatPercentage);
    set(_muscleC, initial.muscleMassKg);
    set(_shouldersC, initial.shouldersCm);
    set(_chestC, initial.chestCm);
    set(_waistC, initial.waistCm);
    set(_hipsC, initial.hipsCm);
    set(_glutesC, initial.glutesCm);
    set(_bicepsLC, initial.bicepsLCm);
    set(_bicepsRC, initial.bicepsRCm);
    set(_bicepsFlexedLC, initial.bicepsFlexedLCm);
    set(_bicepsFlexedRC, initial.bicepsFlexedRCm);
    set(_forearmLC, initial.forearmLCm);
    set(_forearmRC, initial.forearmRCm);
    set(_upperThighLC, initial.upperThighLCm);
    set(_upperThighRC, initial.upperThighRCm);
    set(_midThighLC, initial.midThighLCm);
    set(_midThighRC, initial.midThighRCm);
    set(_calfLC, initial.calfLCm);
    set(_calfRC, initial.calfRCm);
    if (initial.notes != null) _notesC.text = initial.notes!;

    // Auto-expand secciones que tienen algún valor cargado, así el PF ve
    // los campos sin tener que abrir manualmente cada sección.
    _trunkExpanded = initial.shouldersCm != null ||
        initial.chestCm != null ||
        initial.waistCm != null ||
        initial.hipsCm != null ||
        initial.glutesCm != null;
    _upperExpanded = initial.bicepsLCm != null ||
        initial.bicepsRCm != null ||
        initial.bicepsFlexedLCm != null ||
        initial.bicepsFlexedRCm != null ||
        initial.forearmLCm != null ||
        initial.forearmRCm != null;
    _lowerExpanded = initial.upperThighLCm != null ||
        initial.upperThighRCm != null ||
        initial.midThighLCm != null ||
        initial.midThighRCm != null ||
        initial.calfLCm != null ||
        initial.calfRCm != null;
  }

  @override
  void dispose() {
    for (final c in [
      _weightC,
      _fatC,
      _muscleC,
      _shouldersC,
      _chestC,
      _waistC,
      _hipsC,
      _glutesC,
      _bicepsLC,
      _bicepsRC,
      _bicepsFlexedLC,
      _bicepsFlexedRC,
      _forearmLC,
      _forearmRC,
      _upperThighLC,
      _upperThighRC,
      _midThighLC,
      _midThighRC,
      _calfLC,
      _calfRC,
      _notesC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Parse defensivo: acepta coma o punto, vacío → null, no-parseable → null.
  double? _parse(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final initial = widget.initial;
    try {
      // En edición preservamos id + recordedBy + athleteId + recordedAt
      // (Firestore rule exige que los inmutables no cambien).
      final measurement = Measurement(
        id: initial?.id ?? '',
        athleteId: widget.athleteId,
        recordedBy: widget.trainerUid,
        recordedAt: initial?.recordedAt ?? DateTime.now(),
        weightKg: _parse(_weightC),
        fatPercentage: _parse(_fatC),
        muscleMassKg: _parse(_muscleC),
        shouldersCm: _parse(_shouldersC),
        chestCm: _parse(_chestC),
        waistCm: _parse(_waistC),
        hipsCm: _parse(_hipsC),
        glutesCm: _parse(_glutesC),
        bicepsLCm: _parse(_bicepsLC),
        bicepsRCm: _parse(_bicepsRC),
        bicepsFlexedLCm: _parse(_bicepsFlexedLC),
        bicepsFlexedRCm: _parse(_bicepsFlexedRC),
        forearmLCm: _parse(_forearmLC),
        forearmRCm: _parse(_forearmRC),
        upperThighLCm: _parse(_upperThighLC),
        upperThighRCm: _parse(_upperThighRC),
        midThighLCm: _parse(_midThighLC),
        midThighRCm: _parse(_midThighRC),
        calfLCm: _parse(_calfLC),
        calfRCm: _parse(_calfRC),
        notes: _notesC.text.trim().isEmpty ? null : _notesC.text.trim(),
      );
      final repo = ref.read(measurementRepositoryProvider);
      if (_isEditing) {
        await repo.update(measurement);
      } else {
        await repo.add(measurement);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Medición actualizada.' // i18n: Fase W2
              : 'Medición guardada.'), // i18n: Fase W2
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar la medición.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? 'Editar medición' // i18n: Fase W2
                    : 'Nueva medición', // i18n: Fase W2
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cargá los campos que hayas medido. Todos son opcionales.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NuevaMedicionSection(
                          title: 'COMPOSICIÓN CORPORAL', // i18n: Fase W2
                          palette: palette,
                          expanded: true,
                          onToggle: null,
                          children: [
                            _NuevaMedicionField(
                                label: 'Peso',
                                suffix: 'kg',
                                controller: _weightC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: '% grasa',
                                suffix: '%',
                                controller: _fatC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Masa muscular',
                                suffix: 'kg',
                                controller: _muscleC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'CIRCUNFERENCIAS TRUNK', // i18n: Fase W2
                          palette: palette,
                          expanded: _trunkExpanded,
                          onToggle: () =>
                              setState(() => _trunkExpanded = !_trunkExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Hombros',
                                suffix: 'cm',
                                controller: _shouldersC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Pecho',
                                suffix: 'cm',
                                controller: _chestC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Cintura',
                                suffix: 'cm',
                                controller: _waistC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Cadera',
                                suffix: 'cm',
                                controller: _hipsC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Glúteos',
                                suffix: 'cm',
                                controller: _glutesC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'MIEMBROS SUPERIORES', // i18n: Fase W2
                          palette: palette,
                          expanded: _upperExpanded,
                          onToggle: () =>
                              setState(() => _upperExpanded = !_upperExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Bíceps izq.',
                                suffix: 'cm',
                                controller: _bicepsLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Bíceps der.',
                                suffix: 'cm',
                                controller: _bicepsRC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Bíceps flex. izq.',
                                suffix: 'cm',
                                controller: _bicepsFlexedLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Bíceps flex. der.',
                                suffix: 'cm',
                                controller: _bicepsFlexedRC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Antebrazo izq.',
                                suffix: 'cm',
                                controller: _forearmLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Antebrazo der.',
                                suffix: 'cm',
                                controller: _forearmRC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'MIEMBROS INFERIORES', // i18n: Fase W2
                          palette: palette,
                          expanded: _lowerExpanded,
                          onToggle: () =>
                              setState(() => _lowerExpanded = !_lowerExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Muslo sup. izq.',
                                suffix: 'cm',
                                controller: _upperThighLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Muslo sup. der.',
                                suffix: 'cm',
                                controller: _upperThighRC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Muslo med. izq.',
                                suffix: 'cm',
                                controller: _midThighLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Muslo med. der.',
                                suffix: 'cm',
                                controller: _midThighRC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Gemelo izq.',
                                suffix: 'cm',
                                controller: _calfLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Gemelo der.',
                                suffix: 'cm',
                                controller: _calfRC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesC,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Nota (opcional)', // i18n: Fase W2
                            labelStyle: TextStyle(color: palette.textMuted),
                            filled: true,
                            fillColor: palette.bgCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.border),
                            ),
                          ),
                          style: TextStyle(color: palette.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'), // i18n: Fase W2
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: TreinoButtonTokens.foreground(context),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: TreinoButtonTokens.foreground(context),
                            ),
                          )
                        : const Text('GUARDAR'), // i18n: Fase W2
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sección del dialog de nueva medición. Si `onToggle` es null, siempre
/// expandida (composición corporal). Si es non-null, header clickeable para
/// colapsar/expandir.
class _NuevaMedicionSection extends StatelessWidget {
  const _NuevaMedicionSection({
    required this.title,
    required this.palette,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final AppPalette palette;
  final bool expanded;
  final VoidCallback? onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (onToggle != null)
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              size: 18,
              color: palette.textMuted,
            ),
          if (onToggle != null) const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onToggle != null)
          // MouseRegion(cursor): call-site web — InkWell daba cursor de
          // mano al hover, TreinoTappable no trae MouseRegion.
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: TreinoTappable(onTap: onToggle, child: header),
          )
        else
          header,
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            // 2 columnas
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final c in children)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 240),
                    child: SizedBox(
                      width: 270,
                      child: c,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Campo numérico del dialog. Acepta coma o punto como decimal.
class _NuevaMedicionField extends StatelessWidget {
  const _NuevaMedicionField({
    required this.label,
    required this.suffix,
    required this.controller,
    required this.palette,
  });

  final String label;
  final String suffix;
  final TextEditingController controller;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(color: palette.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: palette.textMuted, fontSize: 12),
          suffix: Text(
            suffix,
            style: TextStyle(color: palette.textMuted, fontSize: 11),
          ),
          isDense: true,
          filled: true,
          fillColor: palette.bgCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: palette.accent, width: 1.5),
          ),
        ),
        validator: (v) {
          final s = v?.trim().replaceAll(',', '.') ?? '';
          if (s.isEmpty) return null; // opcional
          final parsed = double.tryParse(s);
          if (parsed == null) return 'Número inválido'; // i18n: Fase W2
          if (parsed < 0 || parsed > 500) {
            return 'Fuera de rango'; // i18n: Fase W2
          }
          return null;
        },
      ),
    );
  }
}

// ── Rendimiento (PR#2) ────────────────────────────────────────────────────────

/// Row de una prueba de rendimiento individual.
class _RendimientoRow extends StatefulWidget {
  const _RendimientoRow({
    required this.test,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final PerformanceTest test;
  final AppPalette palette;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_RendimientoRow> createState() => _RendimientoRowState();
}

class _RendimientoRowState extends State<_RendimientoRow> {
  bool _expanded = false;

  /// Summary line: los 3 campos más marker del test — CMJ, Sprint 10m,
  /// Sentadilla 1RM. Si alguno es null se omite.
  String _summary() {
    final t = widget.test;
    final parts = <String>[];
    if (t.cmjCm != null) parts.add('CMJ ${t.cmjCm} cm');
    if (t.sprint10mS != null) parts.add('10m ${t.sprint10mS}s');
    if (t.squat1rmKg != null) parts.add('Sent. ${t.squat1rmKg} kg');
    if (parts.isEmpty) return 'Sin métricas cargadas'; // i18n: Fase W2
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.test;
    final palette = widget.palette;
    // MouseRegion(cursor): call-site web — InkWell daba cursor de mano al
    // hover, TreinoTappable no trae MouseRegion. Fix local seguro.
    // TreinoTappable envuelve solo el ícono de expandir + texto (Expanded):
    // los IconButton de Editar/Eliminar quedan como siblings del Row
    // exterior, fuera de su subtree, para que los dos recognizers no
    // compitan en el gesture arena (ver _ExerciseRow en
    // exercise_picker_sheet.dart).
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TreinoTappable(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 22,
                          color: palette.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fmtDate(t.recordedAt),
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _summary(),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Editar', // i18n: Fase W2
                  onPressed: widget.onEdit,
                  icon: Icon(Icons.edit, size: 18, color: palette.textMuted),
                ),
                IconButton(
                  tooltip: 'Eliminar', // i18n: Fase W2
                  onPressed: widget.onDelete,
                  icon: Icon(TreinoIcon.trash, size: 18, color: palette.danger),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 12, 8, 0),
                child: _RendimientoDetail(test: t, palette: palette),
              ),
          ],
        ),
      ),
    );
  }
}

/// Detalle expandido de una prueba de rendimiento. Muestra solo los campos
/// con valor cargado, agrupados por categoría (saltos / sprints / 1RM /
/// resistencia).
class _RendimientoDetail extends StatelessWidget {
  const _RendimientoDetail({required this.test, required this.palette});

  final PerformanceTest test;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final t = test;
    final entries = <(String, String)>[
      // Saltos
      if (t.cmjCm != null) ('CMJ', '${t.cmjCm} cm'),
      if (t.squatJumpCm != null) ('Squat Jump', '${t.squatJumpCm} cm'),
      if (t.abalakovCm != null) ('Abalakov', '${t.abalakovCm} cm'),
      if (t.broadJumpCm != null) ('Salto largo', '${t.broadJumpCm} cm'),
      // Sprints
      if (t.sprint10mS != null) ('Sprint 10m', '${t.sprint10mS} s'),
      if (t.sprint20mS != null) ('Sprint 20m', '${t.sprint20mS} s'),
      if (t.sprint30mS != null) ('Sprint 30m', '${t.sprint30mS} s'),
      if (t.sprint40mS != null) ('Sprint 40m', '${t.sprint40mS} s'),
      // 1RM
      if (t.squat1rmKg != null) ('Sentadilla 1RM', '${t.squat1rmKg} kg'),
      if (t.benchPress1rmKg != null)
        ('Press banca 1RM', '${t.benchPress1rmKg} kg'),
      if (t.deadlift1rmKg != null) ('Peso muerto 1RM', '${t.deadlift1rmKg} kg'),
      if (t.overheadPress1rmKg != null)
        ('Press militar 1RM', '${t.overheadPress1rmKg} kg'),
      if (t.pullUp1rmKg != null) ('Dominada 1RM', '${t.pullUp1rmKg} kg'),
      // Resistencia
      if (t.vo2maxMlKgMin != null) ('VO2 máx', '${t.vo2maxMlKgMin} ml/kg/min'),
      if (t.courseNavetteLevel != null)
        ('Course Navette', 'nivel ${t.courseNavetteLevel}'),
      if (t.cooperMeters != null) ('Cooper', '${t.cooperMeters} m'),
      if (t.sitAndReachCm != null) ('Sit & Reach', '${t.sitAndReachCm} cm'),
    ];

    if (entries.isEmpty && (t.notes ?? '').isEmpty) {
      return Text(
        'Esta prueba no tiene valores cargados.', // i18n: Fase W2
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      );
    }

    final half = (entries.length / 2).ceil();
    final left = entries.take(half).toList();
    final right = entries.skip(half).toList();

    Widget colFor(List<(String, String)> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: colFor(left)),
            const SizedBox(width: 24),
            Expanded(child: colFor(right)),
          ],
        ),
        if ((t.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Nota',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.notes!,
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Dialog modal para cargar (o editar) una prueba de rendimiento.
///
/// Todos los campos opcionales. Saltos siempre expandido (la sección más
/// común según el research de PT); Sprints, 1RM y Resistencia colapsables
/// por default para no abrumar.
///
/// PR#3 (2026-07-03): si [initial] es no-nulo → **modo edición**. Mismo
/// pattern que `_NuevaMedicionDialog`.
class _NuevoRendimientoDialog extends ConsumerStatefulWidget {
  const _NuevoRendimientoDialog({
    required this.athleteId,
    required this.trainerUid,
    this.initial,
  });

  final String athleteId;
  final String trainerUid;
  final PerformanceTest? initial;

  @override
  ConsumerState<_NuevoRendimientoDialog> createState() =>
      _NuevoRendimientoDialogState();
}

class _NuevoRendimientoDialogState
    extends ConsumerState<_NuevoRendimientoDialog> {
  final _formKey = GlobalKey<FormState>();

  // Saltos
  final _cmjC = TextEditingController();
  final _squatJumpC = TextEditingController();
  final _abalakovC = TextEditingController();
  final _broadJumpC = TextEditingController();
  // Sprints
  final _sprint10C = TextEditingController();
  final _sprint20C = TextEditingController();
  final _sprint30C = TextEditingController();
  final _sprint40C = TextEditingController();
  // 1RM
  final _squat1rmC = TextEditingController();
  final _bench1rmC = TextEditingController();
  final _deadlift1rmC = TextEditingController();
  final _overhead1rmC = TextEditingController();
  final _pullUp1rmC = TextEditingController();
  // Resistencia
  final _vo2maxC = TextEditingController();
  final _courseNavetteC = TextEditingController();
  final _cooperC = TextEditingController();
  final _sitAndReachC = TextEditingController();
  // Meta
  final _notesC = TextEditingController();

  bool _sprintsExpanded = false;
  bool _oneRmExpanded = false;
  bool _resistExpanded = false;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;

    void set(TextEditingController c, double? v) {
      if (v != null) c.text = v.toString();
    }

    set(_cmjC, initial.cmjCm);
    set(_squatJumpC, initial.squatJumpCm);
    set(_abalakovC, initial.abalakovCm);
    set(_broadJumpC, initial.broadJumpCm);
    set(_sprint10C, initial.sprint10mS);
    set(_sprint20C, initial.sprint20mS);
    set(_sprint30C, initial.sprint30mS);
    set(_sprint40C, initial.sprint40mS);
    set(_squat1rmC, initial.squat1rmKg);
    set(_bench1rmC, initial.benchPress1rmKg);
    set(_deadlift1rmC, initial.deadlift1rmKg);
    set(_overhead1rmC, initial.overheadPress1rmKg);
    set(_pullUp1rmC, initial.pullUp1rmKg);
    set(_vo2maxC, initial.vo2maxMlKgMin);
    set(_courseNavetteC, initial.courseNavetteLevel);
    set(_cooperC, initial.cooperMeters);
    set(_sitAndReachC, initial.sitAndReachCm);
    if (initial.notes != null) _notesC.text = initial.notes!;

    _sprintsExpanded = initial.sprint10mS != null ||
        initial.sprint20mS != null ||
        initial.sprint30mS != null ||
        initial.sprint40mS != null;
    _oneRmExpanded = initial.squat1rmKg != null ||
        initial.benchPress1rmKg != null ||
        initial.deadlift1rmKg != null ||
        initial.overheadPress1rmKg != null ||
        initial.pullUp1rmKg != null;
    _resistExpanded = initial.vo2maxMlKgMin != null ||
        initial.courseNavetteLevel != null ||
        initial.cooperMeters != null ||
        initial.sitAndReachCm != null;
  }

  @override
  void dispose() {
    for (final c in [
      _cmjC,
      _squatJumpC,
      _abalakovC,
      _broadJumpC,
      _sprint10C,
      _sprint20C,
      _sprint30C,
      _sprint40C,
      _squat1rmC,
      _bench1rmC,
      _deadlift1rmC,
      _overhead1rmC,
      _pullUp1rmC,
      _vo2maxC,
      _courseNavetteC,
      _cooperC,
      _sitAndReachC,
      _notesC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final initial = widget.initial;
    try {
      final test = PerformanceTest(
        id: initial?.id ?? '',
        athleteId: widget.athleteId,
        recordedBy: widget.trainerUid,
        recordedAt: initial?.recordedAt ?? DateTime.now(),
        cmjCm: _parse(_cmjC),
        squatJumpCm: _parse(_squatJumpC),
        abalakovCm: _parse(_abalakovC),
        broadJumpCm: _parse(_broadJumpC),
        sprint10mS: _parse(_sprint10C),
        sprint20mS: _parse(_sprint20C),
        sprint30mS: _parse(_sprint30C),
        sprint40mS: _parse(_sprint40C),
        squat1rmKg: _parse(_squat1rmC),
        benchPress1rmKg: _parse(_bench1rmC),
        deadlift1rmKg: _parse(_deadlift1rmC),
        overheadPress1rmKg: _parse(_overhead1rmC),
        pullUp1rmKg: _parse(_pullUp1rmC),
        vo2maxMlKgMin: _parse(_vo2maxC),
        courseNavetteLevel: _parse(_courseNavetteC),
        cooperMeters: _parse(_cooperC),
        sitAndReachCm: _parse(_sitAndReachC),
        notes: _notesC.text.trim().isEmpty ? null : _notesC.text.trim(),
      );
      final repo = ref.read(performanceTestRepositoryProvider);
      if (_isEditing) {
        await repo.update(test);
      } else {
        await repo.add(test);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Prueba actualizada.' // i18n: Fase W2
              : 'Prueba guardada.'), // i18n: Fase W2
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar la prueba.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? 'Editar prueba de rendimiento' // i18n: Fase W2
                    : 'Nueva prueba de rendimiento', // i18n: Fase W2
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cargá los campos que hayas medido. Todos son opcionales.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NuevaMedicionSection(
                          title: 'SALTOS', // i18n: Fase W2
                          palette: palette,
                          expanded: true,
                          onToggle: null,
                          children: [
                            _NuevaMedicionField(
                                label: 'CMJ',
                                suffix: 'cm',
                                controller: _cmjC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Squat Jump',
                                suffix: 'cm',
                                controller: _squatJumpC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Abalakov',
                                suffix: 'cm',
                                controller: _abalakovC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Salto largo',
                                suffix: 'cm',
                                controller: _broadJumpC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'SPRINTS', // i18n: Fase W2
                          palette: palette,
                          expanded: _sprintsExpanded,
                          onToggle: () => setState(
                              () => _sprintsExpanded = !_sprintsExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Sprint 10m',
                                suffix: 's',
                                controller: _sprint10C,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Sprint 20m',
                                suffix: 's',
                                controller: _sprint20C,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Sprint 30m',
                                suffix: 's',
                                controller: _sprint30C,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Sprint 40m',
                                suffix: 's',
                                controller: _sprint40C,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'FUERZA MÁXIMA 1RM', // i18n: Fase W2
                          palette: palette,
                          expanded: _oneRmExpanded,
                          onToggle: () =>
                              setState(() => _oneRmExpanded = !_oneRmExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Sentadilla',
                                suffix: 'kg',
                                controller: _squat1rmC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Press banca',
                                suffix: 'kg',
                                controller: _bench1rmC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Peso muerto',
                                suffix: 'kg',
                                controller: _deadlift1rmC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Press militar',
                                suffix: 'kg',
                                controller: _overhead1rmC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Dominada',
                                suffix: 'kg',
                                controller: _pullUp1rmC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'RESISTENCIA / FLEXIBILIDAD', // i18n: Fase W2
                          palette: palette,
                          expanded: _resistExpanded,
                          onToggle: () => setState(
                              () => _resistExpanded = !_resistExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'VO2 máx',
                                suffix: 'ml/kg/min',
                                controller: _vo2maxC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Course Navette',
                                suffix: 'nivel',
                                controller: _courseNavetteC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Cooper',
                                suffix: 'm',
                                controller: _cooperC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Sit & Reach',
                                suffix: 'cm',
                                controller: _sitAndReachC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesC,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Nota (opcional)', // i18n: Fase W2
                            labelStyle: TextStyle(color: palette.textMuted),
                            filled: true,
                            fillColor: palette.bgCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.border),
                            ),
                          ),
                          style: TextStyle(color: palette.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'), // i18n: Fase W2
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: TreinoButtonTokens.foreground(context),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: TreinoButtonTokens.foreground(context),
                            ),
                          )
                        : const Text('GUARDAR'), // i18n: Fase W2
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SeguimientoTab ──────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Seguimiento» del alumno detail.
///
/// Log cronológico privado del PF sobre un alumno. Múltiples entradas
/// datadas con tag categórico (general/entrenamiento/nutricion/molestia/
/// motivacion). Diferencia con Notas privadas (hoja libre única):
/// Seguimiento es un TIMELINE de eventos/observaciones — cada entrada tiene
/// su timestamp y tag.
///
/// Reusa `followUpEntriesProvider` (stream DESC) +
/// `FollowUpEntryRepository.add/update/delete`. Trainer-only en rules.
class _SeguimientoTab extends ConsumerStatefulWidget {
  const _SeguimientoTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_SeguimientoTab> createState() => _SeguimientoTabState();
}

class _SeguimientoTabState extends ConsumerState<_SeguimientoTab> {
  Future<void> _openDialog({FollowUpEntry? initial}) async {
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _NuevaEntradaSeguimientoDialog(
        athleteId: widget.athleteId,
        trainerUid: trainerUid,
        initial: initial,
      ),
    );
  }

  Future<void> _confirmDelete(FollowUpEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar entrada?'), // i18n: Fase W2
        content: Text(
          'La entrada del ${fmtDate(entry.recordedAt)} se va a borrar. '
          'No se puede deshacer.', // i18n: Fase W2
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'), // i18n: Fase W2
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'), // i18n: Fase W2
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(followUpEntryRepositoryProvider).delete(entry.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos eliminar la entrada.'), // i18n: Fase W2
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null) return const SizedBox.shrink();
    final entriesAsync = ref.watch(
      followUpEntriesProvider(
        (trainerId: trainerUid, athleteId: widget.athleteId),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seguimiento privado', // i18n: Fase W2
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bitácora del PF con observaciones, molestias y decisiones. Solo vos las ves.', // i18n: Fase W2
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('NUEVA ENTRADA'), // i18n: Fase W2
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: TreinoButtonTokens.foreground(context),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            // Mismo patrón sticky-data que _ArchivosTab: el key espeja
            // hasValue > hasError > loading para no cambiar la lógica.
            child: TreinoStateSwitcher(
              childKey: ValueKey(entriesAsync.hasValue
                  ? 'data'
                  : (entriesAsync.hasError ? 'error' : 'loading')),
              child: Builder(
                builder: (_) {
                  if (entriesAsync.hasValue) {
                    final entries = entriesAsync.requireValue;
                    if (entries.isEmpty) {
                      return Center(
                        child: Text(
                          'No hay entradas de seguimiento todavía.', // i18n: Fase W2
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: palette.textMuted, fontSize: 14),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _SeguimientoEntryCard(
                        entry: entries[i],
                        palette: palette,
                        onEdit: () => _openDialog(initial: entries[i]),
                        onDelete: () => _confirmDelete(entries[i]),
                      ),
                    );
                  }
                  if (entriesAsync.hasError) {
                    return Center(
                      child: Text(
                        'No pudimos cargar el seguimiento.', // i18n: Fase W2
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 14),
                      ),
                    );
                  }
                  return const CoachHubSkeleton(filas: 3);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de una entrada del seguimiento.
class _SeguimientoEntryCard extends StatelessWidget {
  const _SeguimientoEntryCard({
    required this.entry,
    required this.palette,
    required this.onEdit,
    required this.onDelete,
  });

  final FollowUpEntry entry;
  final AppPalette palette;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                fmtDate(entry.recordedAt),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              _TagChip(tag: entry.tag, palette: palette),
              const Spacer(),
              IconButton(
                tooltip: 'Editar', // i18n: Fase W2
                onPressed: onEdit,
                icon: Icon(Icons.edit, size: 18, color: palette.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'Eliminar', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash, size: 18, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.text,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip pequeño coloreado según el tag.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.palette});

  final FollowUpTag tag;
  final AppPalette palette;

  static (String, Color) _labelAndColor(FollowUpTag tag, AppPalette palette) {
    switch (tag) {
      case FollowUpTag.general:
        return ('GENERAL', palette.textMuted);
      case FollowUpTag.entrenamiento:
        return ('ENTRENAMIENTO', palette.accent);
      case FollowUpTag.nutricion:
        return ('NUTRICIÓN', palette.warning);
      case FollowUpTag.molestia:
        return ('MOLESTIA', palette.danger);
      case FollowUpTag.motivacion:
        return ('MOTIVACIÓN', palette.highlight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _labelAndColor(tag, palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Dialog modal para crear (o editar) una entrada del seguimiento.
class _NuevaEntradaSeguimientoDialog extends ConsumerStatefulWidget {
  const _NuevaEntradaSeguimientoDialog({
    required this.athleteId,
    required this.trainerUid,
    this.initial,
  });

  final String athleteId;
  final String trainerUid;
  final FollowUpEntry? initial;

  @override
  ConsumerState<_NuevaEntradaSeguimientoDialog> createState() =>
      _NuevaEntradaSeguimientoDialogState();
}

class _NuevaEntradaSeguimientoDialogState
    extends ConsumerState<_NuevaEntradaSeguimientoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _textC = TextEditingController();
  late FollowUpTag _tag;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _textC.text = initial.text;
      _tag = initial.tag;
    } else {
      _tag = FollowUpTag.general;
    }
  }

  @override
  void dispose() {
    _textC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final initial = widget.initial;
    final repo = ref.read(followUpEntryRepositoryProvider);
    try {
      if (_isEditing && initial != null) {
        await repo.update(
          initial.copyWith(text: _textC.text.trim(), tag: _tag),
        );
      } else {
        await repo.add(
          trainerId: widget.trainerUid,
          athleteId: widget.athleteId,
          text: _textC.text.trim(),
          tag: _tag,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Entrada actualizada.' // i18n: Fase W2
              : 'Entrada guardada.'), // i18n: Fase W2
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar la entrada.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isEditing
                      ? 'Editar entrada' // i18n: Fase W2
                      : 'Nueva entrada de seguimiento', // i18n: Fase W2
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TreinoDropdown<FollowUpTag>(
                  initialValue: _tag,
                  onChanged: (v) {
                    if (v != null) setState(() => _tag = v);
                  },
                  decoration: InputDecoration(
                    labelText: 'Categoría', // i18n: Fase W2
                    labelStyle: TextStyle(color: palette.textMuted),
                  ),
                  items: [
                    for (final t in FollowUpTag.values)
                      DropdownMenuItem(
                        value: t,
                        child: Text(_TagChip._labelAndColor(t, palette).$1),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _textC,
                  maxLines: 6,
                  minLines: 4,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Texto', // i18n: Fase W2
                    hintText:
                        'Ej: Cambio a bloque de fuerza, foco en press banca…', // i18n: Fase W2
                    labelStyle: TextStyle(color: palette.textMuted),
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: palette.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Escribí algo'; // i18n: Fase W2
                    if (s.length > 4900) {
                      return 'Muy largo (max 4900 caracteres)'; // i18n: Fase W2
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'), // i18n: Fase W2
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: TreinoButtonTokens.foreground(context),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: TreinoButtonTokens.foreground(context),
                              ),
                            )
                          : const Text('GUARDAR'), // i18n: Fase W2
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── _NutricionTab ────────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Nutrición» del alumno detail (W2+).
///
/// El PF arma un plan de alimentación estructurado por comidas (desayuno,
/// almuerzo, cena…), cada una con grupos de alimentos (hidratos, proteínas,
/// vegetales…) y cada grupo con opciones que el alumno elige.
///
/// Modelo: `NutritionPlan → Meal → FoodGroup → FoodOption`. Ver
/// `nutrition_plan.dart` para detalle. En este MVP solo el PF arma el plan;
/// el alumno NO lo ve todavía en mobile (feature scoped aparte).
///
/// Comportamiento:
/// - Al abrir por primera vez muestra 6 comidas preset (desayuno, media
///   mañana, almuerzo, merienda, colación, cena) con grupos vacíos.
/// - El PF edita libremente y guarda con botón explícito «GUARDAR PLAN».
/// - Cambios locales viven en `_draft` — el stream de Firestore se lee al
///   entrar y cuando el PF guarda vuelve a persistir todo el doc.
/// - Sin auto-save (evitamos writes innecesarios y forms rotos).
class _NutricionTab extends ConsumerStatefulWidget {
  const _NutricionTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_NutricionTab> createState() => _NutricionTabState();
}

class _NutricionTabState extends ConsumerState<_NutricionTab> {
  NutritionPlan? _draft;
  bool _loadedOnce = false;
  bool _saving = false;
  int _idCounter = 0;

  String _newId(String prefix) {
    _idCounter++;
    // Sin Date.now() porque en tests / hot reload no queremos ids
    // dependientes de tiempo real. El id solo tiene que ser único en la
    // sesión — Firestore acepta cualquier string.
    return '$prefix-$_idCounter';
  }

  void _seedIfNeeded(NutritionPlan? persisted, String trainerUid) {
    if (_loadedOnce) return;
    _loadedOnce = true;
    if (persisted != null) {
      _draft = persisted;
    } else {
      _draft = NutritionPlan(
        id: '${trainerUid}_${widget.athleteId}',
        trainerId: trainerUid,
        athleteId: widget.athleteId,
        title: '',
        meals: defaultPresetMeals(),
        updatedAt: DateTime(2000),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _NutricionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset cross-alumno para que el swap no muestre el plan del anterior.
    if (oldWidget.athleteId != widget.athleteId) {
      _draft = null;
      _loadedOnce = false;
      _idCounter = 0;
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final clean = draft.sanitizeForSave();
    if (clean.meals.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'El plan está vacío. Agregá al menos una comida con nombre.', // i18n: Fase W2
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(nutritionPlanRepositoryProvider).save(clean);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Plan guardado.'), // i18n: Fase W2
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar el plan.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Draft mutators ─────────────────────────────────────────────────────
  void _updateTitle(String title) {
    setState(() => _draft = _draft!.copyWith(title: title));
  }

  void _addMeal() {
    setState(() {
      _draft = _draft!.copyWith(meals: [
        ..._draft!.meals,
        Meal(
          id: _newId('meal'),
          // Vacío intencional — el placeholder "Nueva comida" se muestra
          // como hintText del TextFormField. Sin nombre real, el sanitize
          // dropea la comida al guardar si el PF no la completa.
          name: '',
          time: '',
          groups: const [],
        ),
      ]);
    });
  }

  void _removeMeal(String mealId) {
    setState(() {
      _draft = _draft!.copyWith(
        meals: _draft!.meals.where((m) => m.id != mealId).toList(),
      );
    });
  }

  void _updateMeal(String mealId, Meal updated) {
    setState(() {
      _draft = _draft!.copyWith(
        meals: _draft!.meals
            .map((m) => m.id == mealId ? updated : m)
            .toList(growable: false),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null) return const SizedBox.shrink();
    final planAsync = ref.watch(
      nutritionPlanProvider(
        (trainerId: trainerUid, athleteId: widget.athleteId),
      ),
    );

    if (planAsync.hasValue) {
      _seedIfNeeded(planAsync.requireValue, trainerUid);
    } else if (planAsync.hasError && !_loadedOnce) {
      // Error al leer — dejamos que el PF arme el plan igual (arranca desde
      // presets). El save intentará persistir; si sigue fallando el error
      // se muestra en el snackbar.
      _seedIfNeeded(null, trainerUid);
    }

    if (_draft == null) {
      return const TreinoStateSwitcher(
        childKey: ValueKey('loading'),
        child: CoachHubSkeleton(filas: 3),
      );
    }

    return TreinoStateSwitcher(
      childKey: const ValueKey('form'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan de alimentación', // i18n: Fase W2
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Armá el plan por comidas, grupos y opciones. Solo vos lo ves.', // i18n: Fase W2
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: TreinoButtonTokens.foreground(context),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: TreinoButtonTokens.foreground(context),
                          ),
                        )
                      : const Text('GUARDAR PLAN'), // i18n: Fase W2
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                // Small top padding — el label flotante del TextFormField
                // extiende ~8px arriba del border cuando el field tiene
                // valor. Sin este padding el label queda clippeado por el
                // SingleChildScrollView al scrollear.
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      initialValue: _draft!.title,
                      decoration: InputDecoration(
                        labelText:
                            'Título del plan (opcional)', // i18n: Fase W2
                        hintText:
                            'Ej: Progresión 4 - Semana 9 en adelante', // i18n: Fase W2
                        labelStyle: TextStyle(color: palette.textMuted),
                        hintStyle: TextStyle(
                          color: palette.textMuted.withValues(alpha: 0.6),
                        ),
                        filled: true,
                        fillColor: palette.bgCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: palette.border),
                        ),
                      ),
                      style:
                          TextStyle(color: palette.textPrimary, fontSize: 14),
                      onChanged: _updateTitle,
                    ),
                    const SizedBox(height: 16),
                    for (final meal in _draft!.meals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MealEditor(
                          meal: meal,
                          palette: palette,
                          newIdFor: _newId,
                          onChanged: (u) => _updateMeal(meal.id, u),
                          onDelete: () => _removeMeal(meal.id),
                        ),
                      ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _addMeal,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('AGREGAR COMIDA'), // i18n: Fase W2
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.accent,
                        side: BorderSide(color: palette.accent),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor de una comida (nombre + hora + grupos). Se colapsa con un ExpansionTile
/// para que el PF pueda tener muchas comidas y no perder el foco.
class _MealEditor extends StatelessWidget {
  const _MealEditor({
    required this.meal,
    required this.palette,
    required this.newIdFor,
    required this.onChanged,
    required this.onDelete,
  });

  final Meal meal;
  final AppPalette palette;
  final String Function(String prefix) newIdFor;
  final ValueChanged<Meal> onChanged;
  final VoidCallback onDelete;

  void _updateGroup(FoodGroup updated) {
    onChanged(meal.copyWith(
      groups: meal.groups
          .map((g) => g.id == updated.id ? updated : g)
          .toList(growable: false),
    ));
  }

  void _removeGroup(String groupId) {
    onChanged(meal.copyWith(
      groups: meal.groups.where((g) => g.id != groupId).toList(),
    ));
  }

  void _addGroup() {
    onChanged(meal.copyWith(groups: [
      ...meal.groups,
      FoodGroup(
        id: newIdFor('group'),
        // Vacío intencional — placeholder "Nuevo grupo" en el hintText del
        // TextFormField. Sin nombre real, el sanitize dropea el grupo.
        name: '',
        selectionMode: SelectionMode.chooseOne,
        options: const [],
      ),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Theme(
        // Quitar los divisores default y el splash raro del ExpansionTile.
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: palette.textMuted,
          collapsedIconColor: palette.textMuted,
          title: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: meal.name,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nombre de la comida', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  onChanged: (v) => onChanged(meal.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: meal.time ?? '',
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Hora', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                    prefixIcon: Icon(Icons.schedule,
                        size: 14, color: palette.textMuted),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 22, minHeight: 22),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(color: palette.textPrimary, fontSize: 12),
                  onChanged: (v) => onChanged(meal.copyWith(time: v)),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Eliminar comida', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash, size: 16, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          children: [
            for (final group in meal.groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _GroupEditor(
                  group: group,
                  palette: palette,
                  newIdFor: newIdFor,
                  onChanged: _updateGroup,
                  onDelete: () => _removeGroup(group.id),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addGroup,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('AGREGAR GRUPO'), // i18n: Fase W2
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor de un grupo de alimentos dentro de una comida.
class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    required this.group,
    required this.palette,
    required this.newIdFor,
    required this.onChanged,
    required this.onDelete,
  });

  final FoodGroup group;
  final AppPalette palette;
  final String Function(String prefix) newIdFor;
  final ValueChanged<FoodGroup> onChanged;
  final VoidCallback onDelete;

  void _updateOption(FoodOption updated) {
    onChanged(group.copyWith(
      options: group.options
          .map((o) => o.id == updated.id ? updated : o)
          .toList(growable: false),
    ));
  }

  void _removeOption(String optionId) {
    onChanged(group.copyWith(
      options: group.options.where((o) => o.id != optionId).toList(),
    ));
  }

  void _addOption() {
    onChanged(group.copyWith(options: [
      ...group.options,
      FoodOption(id: newIdFor('opt'), name: ''),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: group.name,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nombre del grupo', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  onChanged: (v) => onChanged(group.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              _SelectionModeSelector(
                mode: group.selectionMode,
                palette: palette,
                onChanged: (m) => onChanged(group.copyWith(selectionMode: m)),
              ),
              IconButton(
                tooltip: 'Eliminar grupo', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash, size: 14, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final option in group.options)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _OptionRow(
                option: option,
                palette: palette,
                onChanged: _updateOption,
                onDelete: () => _removeOption(option.id),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add, size: 12),
              label: const Text('AGREGAR OPCIÓN'), // i18n: Fase W2
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle compacto entre modo de selección `chooseOne` y `all` — se muestra
/// como dos pills side-by-side.
class _SelectionModeSelector extends StatelessWidget {
  const _SelectionModeSelector({
    required this.mode,
    required this.palette,
    required this.onChanged,
  });

  final SelectionMode mode;
  final AppPalette palette;
  final ValueChanged<SelectionMode> onChanged;

  Widget _pill(String label, bool active, VoidCallback onTap) {
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? palette.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: active ? palette.accent : palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? palette.accent : palette.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill(
          'ELEGIR UNA', // i18n: Fase W2
          mode == SelectionMode.chooseOne,
          () => onChanged(SelectionMode.chooseOne),
        ),
        const SizedBox(width: 4),
        _pill(
          'TODAS', // i18n: Fase W2
          mode == SelectionMode.all,
          () => onChanged(SelectionMode.all),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Fila de una opción del grupo: nombre + cantidad + unidad + notas.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.palette,
    required this.onChanged,
    required this.onDelete,
  });

  final FoodOption option;
  final AppPalette palette;
  final ValueChanged<FoodOption> onChanged;
  final VoidCallback onDelete;

  InputDecoration _dec(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
          color: palette.textMuted.withValues(alpha: 0.6),
          fontSize: 12,
        ),
        filled: true,
        fillColor: palette.bgCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: palette.border),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(color: palette.textPrimary, fontSize: 12);
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: TextFormField(
            initialValue: option.name,
            decoration:
                _dec('Alimento (ej: 5 discos de arroz)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) => onChanged(option.copyWith(name: v)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: option.quantity ?? '',
            decoration: _dec('Cant.'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) =>
                onChanged(option.copyWith(quantity: v.isEmpty ? null : v)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: option.unit ?? '',
            decoration: _dec('Unidad (grs, ml…)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) =>
                onChanged(option.copyWith(unit: v.isEmpty ? null : v)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          child: TextFormField(
            initialValue: option.notes ?? '',
            decoration: _dec('Notas (marca, aclaraciones…)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) =>
                onChanged(option.copyWith(notes: v.isEmpty ? null : v)),
          ),
        ),
        IconButton(
          tooltip: 'Eliminar opción', // i18n: Fase W2
          onPressed: onDelete,
          icon: Icon(TreinoIcon.trash, size: 12, color: palette.danger),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
      ],
    );
  }
}
