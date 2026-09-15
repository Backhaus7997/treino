import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../feed/application/follow_providers.dart';
import '../../feed/presentation/widgets/feed_empty_state.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../coach/presentation/trainer_dashboard_tab.dart'
    show PendingRequestsView;
import '../../../core/widgets/treino_segmented_pill.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/domain/user_role.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/notification_history_providers.dart';
import '../application/notification_router.dart';
import '../domain/notification_history_item.dart';

/// Nombres de las sub-pestañas, tal como viajan en el `?tab=` de la ruta y en
/// el `deepLink` que mandan las Cloud Functions.
///
/// Son strings y no un enum porque cruzan el límite del proceso: los escribe
/// `notify-link-change.ts` y los lee el router. Un enum acá daría una falsa
/// sensación de que los dos lados están atados por el tipo.
const kTabTodas = 'todas';
const kTabSolicitudes = 'solicitudes';

class NotificationHistoryScreen extends ConsumerStatefulWidget {
  const NotificationHistoryScreen({super.key, this.initialTab});

  /// `'todas'` (default) o `'solicitudes'`, del `?tab=` de la ruta.
  ///
  /// Un valor desconocido cae en «Todas» a propósito: un deep link viejo o mal
  /// escrito tiene que mostrar algo útil, no una pantalla vacía.
  final String? initialTab;

  @override
  ConsumerState<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends ConsumerState<NotificationHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final notifications = ref.watch(notificationHistoryProvider);
    final lastSeenAt = ref.watch(notificationLastSeenAtProvider).valueOrNull;
    final pending =
        uid == null ? 0 : ref.watch(pendingFollowRequestCountProvider(uid));

    // `TreinoSegmentedPill` LEE un `DefaultTabController` ancestro (lo dice su
    // dartdoc): sin él revienta en runtime, no en compilación.
    return DefaultTabController(
      length: 2,
      // Un `initialTab` desconocido cae en «Todas»: un deep link viejo o mal
      // escrito tiene que mostrar algo útil, no una pestaña vacía.
      initialIndex: widget.initialTab == kTabSolicitudes ? 1 : 0,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          ),
          title: Text(
            l10n.notificationHistoryTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TreinoSegmentedPill(labels: ['TODAS', 'SOLICITUDES']),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _TabTodas(
                    uid: uid,
                    notifications: notifications,
                    lastSeenAt: lastSeenAt,
                  ),
                  _TabSolicitudes(pendientesDeAmistad: pending),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pestaña «Todas»: la lista del historial.
///
/// Es un widget con estado propio —y no un método de la pantalla— porque
/// marcar el historial como visto tiene que ser un efecto de MOSTRAR esta
/// lista, no de abrir la pantalla.
///
/// El bug que cierra: con `?tab=solicitudes` el push abría la otra pestaña,
/// «Todas» no se dibujaba nunca, y el `markSeen` del `build` de la pantalla
/// corría igual. Se apagaba el badge de no leídas de avisos que la persona no
/// llegó a ver — información perdida en silencio, sin forma de recuperarla.
///
/// `TabBarView` construye sus páginas de forma perezosa, así que este
/// `initState` no corre hasta que la pestaña se muestra. Eso NO se da por
/// supuesto: lo fija un test que abre en «Solicitudes», verifica que no se
/// marcó nada, toca «TODAS» y recién ahí lo espera.
class _TabTodas extends ConsumerStatefulWidget {
  const _TabTodas({
    required this.uid,
    required this.notifications,
    required this.lastSeenAt,
  });

  final String? uid;
  final AsyncValue<List<NotificationHistoryItem>> notifications;
  final DateTime? lastSeenAt;

  @override
  ConsumerState<_TabTodas> createState() => _TabTodasState();
}

class _TabTodasState extends ConsumerState<_TabTodas> {
  /// Se marcó una vez y no se repite: el `uid` no cambia dentro de una sesión,
  /// y `didUpdateWidget` corre en cada rebuild del padre.
  bool _marcado = false;

  /// Marcar visto en cuanto HAYA uid, no sólo si ya lo había al montar.
  ///
  /// En un arranque en frío desde una notificación, `authRedirect` deja
  /// renderizar la ruta protegida mientras auth todavía resuelve, así que
  /// `currentUidProvider` puede venir `null` en el primer frame. Con esto sólo
  /// en `initState`, ese `null` era DEFINITIVO: cuando el uid llegaba, el
  /// `State` ya estaba montado y se reusaba, `initState` no volvía a correr, y
  /// el historial nunca se daba por visto. El badge de no leídas quedaba viejo
  /// para siempre, en silencio.
  ///
  /// El `build` de la pantalla —de donde vino este código— reintentaba solo en
  /// cada frame y por eso no tenía el problema. Al mover el efecto a donde
  /// corresponde hubo que traerse el reintento con él.
  ///
  /// Lo encontró Codex en la review del PR #1146.
  void _marcarCuandoHayaUid() {
    if (_marcado) return;
    final uid = widget.uid;
    if (uid == null) return;
    _marcado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notificationHistoryRepositoryProvider).markSeen(uid);
    });
  }

  @override
  void initState() {
    super.initState();
    _marcarCuandoHayaUid();
  }

  @override
  void didUpdateWidget(covariant _TabTodas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _marcarCuandoHayaUid();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final notifications = widget.notifications;
    final lastSeenAt = widget.lastSeenAt;
    return notifications.when(
      loading: () => Center(
        key: const Key('notificationHistoryLoading'),
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => _NotificationError(
        onRetry: () => ref.invalidate(notificationHistoryProvider),
      ),
      data: (items) => items.isEmpty
          ? FeedEmptyState(
              key: const Key('notificationHistoryEmpty'),
              icon: TreinoIcon.bell,
              message: l10n.notificationHistoryEmpty,
            )
          : ListView.separated(
              key: const Key('notificationHistoryList'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _NotificationItem(
                notification: items[index],
                unread: notificationIsUnread(
                  items[index],
                  lastSeenAt,
                ),
              ),
            ),
    );
  }
}

/// Pestaña «Solicitudes»: todo lo que espera una decisión de esta persona.
///
/// ## Por qué UNA pestaña y no una por tipo
///
/// «Solicitud» significa dos cosas distintas en el modelo —vinculación
/// (`trainer_links`) y amistad (`follows`)— pero para quien la mira significa
/// una sola: *algo que tengo que aceptar o rechazar*. Partirlas en dos
/// pestañas obligaría a la persona a saber de qué colección salió cada una.
///
/// El PF ve las dos. El alumno sólo tiene amistades, así que el bloque de
/// vinculaciones ni se monta — y la comprobación es por ROL y no por lista
/// vacía, porque una lista vacía también es lo que se ve mientras carga.
class _TabSolicitudes extends ConsumerWidget {
  const _TabSolicitudes({required this.pendientesDeAmistad});

  final int pendientesDeAmistad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final esPf = ref.watch(
          userProfileProvider.select((a) => a.valueOrNull?.role),
        ) ==
        UserRole.trainer;

    // Nada que decidir, para ninguno de los dos caminos.
    if (!esPf && pendientesDeAmistad == 0) {
      return FeedEmptyState(
        key: const Key('solicitudesEmpty'),
        icon: TreinoIcon.users,
        message: l10n.notificationHistoryEmpty,
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pendientesDeAmistad > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: _PendingRequestsBlock(count: pendientesDeAmistad),
            ),
          if (esPf) const PendingRequestsView(),
        ],
      ),
    );
  }
}

class _PendingRequestsBlock extends StatelessWidget {
  const _PendingRequestsBlock({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final label = l10n.notificationPendingRequests(count);
    return Semantics(
      key: const Key('notificationPendingRequests'),
      container: true,
      button: true,
      label: label,
      child: TreinoTappable(
        onTap: () => context.go('/feed/friend-requests'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(TreinoIcon.users, color: palette.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Icon(TreinoIcon.forward, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationItem extends ConsumerWidget {
  const _NotificationItem({required this.notification, required this.unread});

  final NotificationHistoryItem notification;
  final bool unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final actorUid = notification.actorUid;
    final actor = actorUid == null
        ? null
        : ref.watch(userPublicProfileProvider(actorUid)).valueOrNull;
    final semanticsLabel = '${notification.title}. ${notification.body}';

    return Semantics(
      key: Key('notificationItem-${notification.id}'),
      container: true,
      button: true,
      label: semanticsLabel,
      child: TreinoTappable(
        onTap: () => goDeepLink(context, notification.deepLink),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unread
                ? palette.accent.withValues(alpha: 0.08)
                : palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: unread
                  ? palette.accent.withValues(alpha: 0.3)
                  : palette.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (actorUid != null) ...[
                PostAvatar(
                  authorDisplayName: actor?.displayName ?? '',
                  authorAvatarUrl: actor?.avatarUrl,
                  size: 40,
                ),
                const SizedBox(width: 12),
              ] else ...[
                Icon(TreinoIcon.bell, color: palette.textMuted, size: 40),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: GoogleFonts.barlow(
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: palette.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notification.body,
                      style: GoogleFonts.barlow(color: palette.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _relativeTime(
                          notification.createdAt, AppL10n.of(context)),
                      style: GoogleFonts.barlow(
                        fontSize: 11,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationError extends StatelessWidget {
  const _NotificationError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Center(
      key: const Key('notificationHistoryError'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.notificationHistoryError,
            style: GoogleFonts.barlow(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: palette.accent),
            child: Text(l10n.coachRetryLabel),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime createdAt, AppL10n l10n) {
  final delta = DateTime.now().difference(createdAt);
  if (delta.inMinutes < 1) return l10n.chatRelativeJustNow;
  if (delta.inHours < 1) return l10n.chatRelativeMinutes(delta.inMinutes);
  if (delta.inDays < 1) return l10n.chatRelativeHours(delta.inHours);
  if (delta.inDays < 7) return l10n.chatRelativeDays(delta.inDays);
  final local = createdAt.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month';
}
