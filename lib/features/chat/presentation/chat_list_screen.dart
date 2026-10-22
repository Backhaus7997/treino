import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/motion/treino_shimmer.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../core/persistence/shared_prefs_provider.dart';
import '../../../core/widgets/treino_toast.dart';
import '../application/chat_contacts_providers.dart';
import '../application/chat_providers.dart'
    show
        archivedChatsProvider,
        chatForOtherUidProvider,
        chatHasUnread,
        chatsForCurrentUserProvider,
        inboxChatsProvider;
import '../domain/chat.dart';
import 'chat_actions.dart';
import 'chat_swipe_actions.dart';

/// Pantalla que lista todos los chats del usuario actual.
///
/// Empty state cuando el usuario todavía no tiene ningún chat creado.
/// Cada row navega al ChatScreen del chat correspondiente.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final chatsAsync = ref.watch(inboxChatsProvider);
    final archived = ref.watch(archivedChatsProvider).valueOrNull ?? const [];
    final currentUid = ref.watch(currentUidProvider);
    final contactsAsync = ref.watch(chatContactsProvider);

    // Lo normal es que haya algo debajo: el header del Feed empuja la bandeja,
    // y una notificación de chat arma Feed → Mensajes → chat
    // (`abrirChatConStack`). Ahí todo es un `pop` nativo — flecha, swipe de iOS
    // y back de Android hacen lo mismo.
    //
    // Esto es la red para cuando la bandeja quedó SOLA (un `go` directo a
    // `/feed/messages`, o el fallback de `ChatScreen`): no hay nada que popear,
    // y el back de Android cerraría la app. Ahí volvemos al feed.
    //
    // El `PopScope` sólo bloquea en ESE caso (`canPop == false`), y ahí no le
    // quita nada al swipe de iOS: el gesto no existe sin una ruta debajo. Con
    // la bandeja empujada, `canPop` es true y el gesto queda intacto.
    //
    // `maybeOf` para no exigir un GoRouter en los tests que montan la pantalla
    // suelta.
    final router = GoRouter.maybeOf(context);
    final canPop = router?.canPop() ?? Navigator.of(context).canPop();
    void goBack() {
      if (router != null && !canPop) {
        router.go('/feed');
      } else {
        Navigator.of(context).maybePop();
      }
    }

    return PopScope(
      canPop: canPop || router == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: goBack,
          ),
          title: Text(
            l10n.chatListTitle,
            style: GoogleFonts.barlowCondensed(
              color: palette.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        body: TreinoStateSwitcher(
          childKey: ValueKey(
            archived.isEmpty ? _bodyState(chatsAsync, contactsAsync) : 'data',
          ),
          child: chatsAsync.when(
            loading: () => const _Loading(),
            error: (_, __) => _ErrorState(
              onRetry: () => ref.invalidate(chatsForCurrentUserProvider),
            ),
            data: (chats) {
              final contacts = contactsAsync.valueOrNull ?? const [];
              if (chats.isEmpty && archived.isEmpty) {
                // Sin chats, la pantalla depende de los contactos: mientras
                // cargan no se puede afirmar "no hay a quién escribirle".
                if (contactsAsync.isLoading) return const _Loading();
                if (contactsAsync.hasError) {
                  return _ErrorState(
                    onRetry: () => _invalidateContacts(ref),
                  );
                }
                if (contacts.isEmpty) return const _EmptyState();
              }
              // Lista PLANA de entradas con un builder: sólo se montan las
              // filas visibles. Cada fila escucha su perfil público, así que
              // armarlas todas de una abría un listener por seguido y por
              // chat al entrar a la pantalla.
              final archivedOpen = ref.watch(_archivedOpenProvider);
              // El asomo del swipe va en el primer chat de la bandeja: es el
              // que se ve sin scrollear y el que más se usa.
              final hintChatId =
                  ref.watch(_swipeHintPendingProvider) && chats.isNotEmpty
                      ? chats.first.chatId
                      : null;
              final entries = <_Entry>[
                if (archived.isNotEmpty) ...[
                  _ArchivedHeaderEntry(archived.length),
                  if (archivedOpen)
                    for (final chat in archived)
                      _ChatEntry(chat, archived: true),
                ],
                for (final chat in chats) _ChatEntry(chat),
                if (contacts.isNotEmpty) ...[
                  _HeaderEntry(l10n.chatContactsSectionTitle),
                  for (final contact in contacts) _ContactEntry(contact),
                ] else if (contactsAsync.hasError)
                  _NoticeEntry(l10n.chatContactsError),
              ];
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: entries.length,
                itemBuilder: (_, i) {
                  final entry = entries[i];
                  // Divisor entre filas consecutivas del mismo tipo, igual
                  // que el `separatorBuilder` de antes.
                  final divided = i > 0 &&
                      entries[i - 1].runtimeType == entry.runtimeType &&
                      entry is! _HeaderEntry &&
                      entry is! _ArchivedHeaderEntry;
                  final Widget row = switch (entry) {
                    _ChatEntry(:final chat, :final archived) => _ChatRow(
                        chat: chat,
                        currentUid: currentUid ?? '',
                        archived: archived,
                        hint: !archived && chat.chatId == hintChatId,
                      ),
                    _ArchivedHeaderEntry(:final count) =>
                      _ArchivedHeader(count: count, open: archivedOpen),
                    _ContactEntry(:final contact) =>
                      _ContactRow(contact: contact),
                    _HeaderEntry(:final label) => _SectionHeader(label: label),
                    _NoticeEntry(:final text) => Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          text,
                          style: TextStyle(color: palette.textMuted),
                        ),
                      ),
                  };
                  if (!divided) return row;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, color: palette.border, indent: 76),
                      row,
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────

/// Una fila de la lista plana de [ChatListScreen].
sealed class _Entry {
  const _Entry();
}

final class _ChatEntry extends _Entry {
  const _ChatEntry(this.chat, {this.archived = false});
  final Chat chat;

  /// Fila de Archivados: el long-press ofrece desarchivar.
  final bool archived;
}

final class _ArchivedHeaderEntry extends _Entry {
  const _ArchivedHeaderEntry(this.count);
  final int count;
}

final class _ContactEntry extends _Entry {
  const _ContactEntry(this.contact);
  final ChatContact contact;
}

final class _HeaderEntry extends _Entry {
  const _HeaderEntry(this.label);
  final String label;
}

final class _NoticeEntry extends _Entry {
  const _NoticeEntry(this.text);
  final String text;
}

class _ChatRow extends ConsumerWidget {
  const _ChatRow({
    required this.chat,
    required this.currentUid,
    this.archived = false,
    this.hint = false,
  });

  final Chat chat;
  final String currentUid;

  /// Fila de la sección Archivados: el long-press y el swipe ofrecen
  /// desarchivar.
  final bool archived;

  /// Asoma las acciones del swipe una vez, para enseñar el gesto.
  final bool hint;

  String _otherUidOf(Chat c, String selfUid) {
    return c.members.firstWhere((m) => m != selfUid, orElse: () => '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final otherUid = _otherUidOf(chat, currentUid);
    final pubAsync = ref.watch(userPublicProfileProvider(otherUid));
    final hasUnread = currentUid.isNotEmpty && chatHasUnread(chat, currentUid);

    final row = InkWell(
      onLongPress: currentUid.isEmpty
          ? null
          : () => showChatActionsSheet(
                context,
                ref,
                chatId: chat.chatId,
                uid: currentUid,
                archived: archived,
              ),
      onTap: () {
        // Open the chat via the top-level go_router route so it renders
        // full-screen (no nav bar) with a proper background — the same route
        // the athlete-detail MENSAJE button uses.
        context.push('/coach/chat/${chat.chatId}?other=$otherUid');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: pubAsync.when(
          loading: () => _RowSkeleton(palette: palette),
          // Error NO shimmerea: offline → stream error → un barrido infinito
          // quemaría batería y mentiría ("sigue cargando" cuando ya falló).
          error: (_, __) => _RowSkeleton(palette: palette, shimmer: false),
          data: (pub) {
            // When userPublicProfiles/{uid} is deleted (account deletion cascade),
            // pub is null → show "Usuario eliminado" per ADR-ACCDEL-005.
            final name = pub?.displayName ?? l10n.chatListDeletedUser;
            final avatarUrl = pub?.avatarUrl;
            return Row(
              children: [
                PostAvatar(
                  authorDisplayName: name,
                  authorAvatarUrl: avatarUrl,
                  size: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        chat.lastMessageText ?? l10n.chatListStartConversation,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (chat.lastMessageAt != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    _relativeTime(chat.lastMessageAt!, l10n),
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
                if (hasUnread) ...[
                  const SizedBox(width: 10),
                  Semantics(
                    label: l10n.chatUnreadA11y,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
    if (currentUid.isEmpty) return row;

    // Mismas acciones que el long-press, a un gesto de distancia. Archivar
    // usa el acento y eliminar el rojo, cada uno con su par de texto.
    final archiveAction = ChatSwipeAction(
      icon: TreinoIcon.archive,
      label: archived ? l10n.chatActionUnarchive : l10n.chatActionArchive,
      background: palette.accent,
      foreground: TreinoButtonTokens.foreground(context),
      onTap: () => archived
          ? unarchiveChat(context, ref, chatId: chat.chatId, uid: currentUid)
          : archiveChat(context, ref, chatId: chat.chatId, uid: currentUid),
    );
    final deleteAction = ChatSwipeAction(
      icon: TreinoIcon.trash,
      label: l10n.chatActionDelete,
      background: palette.danger,
      foreground: palette.onDanger,
      onTap: () => confirmAndDeleteChat(
        context,
        ref,
        chatId: chat.chatId,
        uid: currentUid,
      ),
    );
    return ChatSwipeActions(
      rowId: chat.chatId,
      openRow: ref.watch(_openSwipeRowProvider),
      actions: [archiveAction, deleteAction],
      hint: hint,
      onHintShown: () => _markSwipeHintSeen(ref),
      child: row,
    );
  }
}

/// La fila de la bandeja con el swipe abierto. Una sola a la vez.
final _openSwipeRowProvider =
    Provider.autoDispose<ValueNotifier<Object?>>((ref) {
  final notifier = ValueNotifier<Object?>(null);
  ref.onDispose(notifier.dispose);
  return notifier;
});

const _swipeHintSeenKey = 'chat.swipeHintSeen';

/// Si falta enseñar el swipe de la bandeja. Se enseña UNA vez por
/// instalación: es un asomo sutil, no un tour, y repetirlo sería ruido.
///
/// Sin preferencias resueltas no hay asomo: ante la duda, no molestar.
final _swipeHintPendingProvider = Provider.autoDispose<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
  return prefs != null && !(prefs.getBool(_swipeHintSeenKey) ?? false);
});

void _markSwipeHintSeen(WidgetRef ref) {
  final prefs = ref.read(sharedPreferencesProvider).valueOrNull;
  if (prefs == null) return;
  prefs.setBool(_swipeHintSeenKey, true).then((_) {
    ref.invalidate(_swipeHintPendingProvider);
  }).catchError((Object _) {});
}

/// Qué rama del body se está pintando, para que [TreinoStateSwitcher] haga
/// el fade sólo cuando cambia de verdad (no en cada emisión del stream).
String _bodyState(
  AsyncValue<List<Chat>> chats,
  AsyncValue<List<ChatContact>> contacts,
) {
  if (chats.hasError) return 'error';
  final list = chats.valueOrNull;
  if (list == null) return 'loading';
  if (list.isNotEmpty) return 'data';
  if (contacts.hasError) return 'error';
  final c = contacts.valueOrNull;
  if (c == null) return 'loading';
  return c.isEmpty ? 'empty' : 'data';
}

/// Si «Archivados» está desplegada. Vive mientras la pantalla está montada.
final _archivedOpenProvider = StateProvider.autoDispose<bool>((_) => false);

/// Encabezado «Archivados · N», plegado por defecto: arriba de todo para que
/// se encuentre, sin empujar la bandeja hacia abajo. Las filas archivadas son
/// entradas más de la lista plana, así que también se arman de a una.
class _ArchivedHeader extends ConsumerWidget {
  const _ArchivedHeader({required this.count, required this.open});

  final int count;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              ref.read(_archivedOpenProvider.notifier).update((v) => !v),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Icon(TreinoIcon.archive, color: palette.textMuted),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l10n.chatArchivedSectionTitle(count),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  open ? TreinoIcon.chevronUp : TreinoIcon.chevronDown,
                  color: palette.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: palette.border),
      ],
    );
  }
}

void _invalidateContacts(WidgetRef ref) {
  ref
    ..invalidate(chatContactLinksAsAthleteProvider)
    ..invalidate(chatContactLinksAsTrainerProvider)
    ..invalidate(chatContactFollowingProvider);
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Center(
        child: CircularProgressIndicator(color: AppPalette.of(context).accent),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Fila de alguien a quien le podés escribir y todavía no tiene chat. El tap
/// resuelve el chat con `getOrCreate` (lo crea si hace falta) y lo abre por la
/// misma ruta que [_ChatRow].
class _ContactRow extends ConsumerStatefulWidget {
  const _ContactRow({required this.contact});

  final ChatContact contact;

  @override
  ConsumerState<_ContactRow> createState() => _ContactRowState();
}

class _ContactRowState extends ConsumerState<_ContactRow> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    // Router y messenger se capturan ANTES del await: la fila se va de la
    // lista apenas el chat aparece en el stream, y su context muere con ella.
    final router = GoRouter.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final errorText = AppL10n.of(context).chatContactOpenError;
    final uid = widget.contact.uid;
    setState(() => _opening = true);
    try {
      final chat = await ref.read(chatForOtherUidProvider(uid).future);
      await router?.push('/coach/chat/${chat.chatId}?other=$uid');
    } catch (_) {
      showTreinoToastOn(messenger, errorText, type: TreinoToastType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(widget.contact.uid));
    final reason = switch (widget.contact.reason) {
      ChatContactReason.coach => l10n.chatContactReasonCoach,
      ChatContactReason.athlete => l10n.chatContactReasonAthlete,
      ChatContactReason.following => l10n.chatContactReasonFollowing,
    };

    return pubAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: _RowSkeleton(palette: palette),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: _RowSkeleton(palette: palette, shimmer: false),
      ),
      data: (pub) {
        // Cuenta borrada: no hay a quién escribirle.
        if (pub == null) return const SizedBox.shrink();
        final name = pub.displayName ?? l10n.chatListDeletedUser;
        return InkWell(
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                PostAvatar(
                  authorDisplayName: name,
                  authorAvatarUrl: pub.avatarUrl,
                  size: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reason,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _opening
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.accent,
                        ),
                      )
                    : Icon(TreinoIcon.chat, color: palette.accent, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton({required this.palette, this.shimmer = true});
  final AppPalette palette;

  /// `false` cuando el skeleton se muestra por un estado de error (nada
  /// está cargando) — se propaga a [TreinoShimmer.enabled].
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    return TreinoShimmer(
      enabled: shimmer,
      child: Row(
        children: [
          CircleAvatar(radius: 24, backgroundColor: palette.bgCard),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 120, height: 14, color: palette.bgCard),
                const SizedBox(height: 8),
                Container(width: 200, height: 12, color: palette.bgCard),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.chatEmpty, color: palette.textMuted, size: 64),
            const SizedBox(height: 18),
            Text(
              l10n.chatListEmptyTitle,
              style: GoogleFonts.barlowCondensed(
                color: palette.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.chatListEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.chatListError,
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(l10n.chatListRetryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

String _relativeTime(DateTime createdAt, AppL10n l10n) {
  final delta = DateTime.now().difference(createdAt);
  if (delta.inMinutes < 1) return l10n.chatRelativeJustNow;
  if (delta.inHours < 1) return l10n.chatRelativeMinutes(delta.inMinutes);
  if (delta.inDays < 1) return l10n.chatRelativeHours(delta.inHours);
  if (delta.inDays < 7) return l10n.chatRelativeDays(delta.inDays);
  // createdAt is stored in UTC; format the absolute date in the user's local
  // zone so negative-offset regions (e.g. Argentina, UTC-3) don't show the
  // next day for late-evening messages.
  final local = createdAt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m';
}
