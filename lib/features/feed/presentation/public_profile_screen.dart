import 'package:flutter/material.dart';
import 'package:treino/core/widgets/treino_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_collapsing_top_bar.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../chat/application/chat_providers.dart';
import '../../moderation/application/moderation_providers.dart'
    show myBlockedUidsProvider;
import '../../moderation/domain/report_target_kind.dart';
import '../../moderation/presentation/moderation_actions.dart';
import '../../workout/application/user_routines_providers.dart';
import '../application/follow_list_providers.dart';
import '../application/post_providers.dart';
import '../application/profile_chat_access_providers.dart';
import '../domain/public_profile_view.dart';
import '../application/public_profile_providers.dart';
import '../domain/follow_status.dart';
import 'widgets/post_card.dart';
import 'widgets/public_profile_follow_button.dart';
import 'widgets/public_profile_hero.dart';
import 'widgets/public_profile_stats_row.dart';
import '../../workout/presentation/widgets/routine_card.dart';

/// Which tab is selected inside the public profile screen.
/// Private to this file — the screen and `_ProfileTabPills` are the only
/// consumers (REQ-PROFILE-TABS-001 forbids cross-feature reuse).
enum _ProfileTab { rutinas, actividad }

/// Per-target tab state. Family keyed by `targetUid` so two simultaneous
/// profile visits don't share state.
final _profileTabProvider =
    StateProvider.autoDispose.family<_ProfileTab, String>(
  (ref, _) => _ProfileTab.rutinas,
);

/// Public profile screen for a non-self user. Watches a single composed
/// view-model provider and routes data / loading / error to subtrees.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final viewAsync = ref.watch(publicProfileViewProvider(targetUid));
    // Sólo para el botón de moderación del AppBar — el resto de la pantalla
    // sigue leyendo `viewAsync.when(...)` para loading/error/data.
    final view = viewAsync.valueOrNull;

    // Scaffold transparente: la pantalla se compone sobre el AppBackground del
    // shell. La barra superior aparece al scrollear (#1559, #1477): en offset 0
    // la flecha y el ⋮ flotan sobre el gradiente del hero, sin fondo ni
    // círculo; al scrollear aparece una barra translúcida con el nombre, así
    // que los posts ya no pasan por debajo de íconos sueltos. Sin esto la
    // subruta empujada sería un callejón sin salida: la barra inferior
    // reemplaza el stack en vez de hacer pop.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TreinoCollapsingTopBar(
        title: view?.authorDisplayName,
        // El nombre grande del hero sale de pantalla ~210 px abajo.
        collapseOffset: 210,
        onBack: () => context.canPop() ? context.pop() : context.go('/feed'),
        // Reportar/Bloquear el perfil — sólo cuando ya resolvió Y no es el
        // propio (moderacion-reporte-y-bloqueo). Nada mientras carga: no hay
        // targetOwnerDisplayName todavía.
        actions: [
          if (view != null && !view.isSelf)
            TreinoTopBarAction(
              icon: TreinoIcon.dotsThree,
              tooltip: l10n.moderationMenuA11y,
              onPressed: () => showModerationMenu(
                context,
                ref,
                targetKind: ReportTargetKind.profile,
                targetId: targetUid,
                targetOwnerUid: targetUid,
                targetOwnerDisplayName: view.authorDisplayName,
              ),
            ),
        ],
        body: viewAsync.when(
          data: (view) {
            final viewerUid =
                ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
            // Privacy gate — Instagram-style. When the target profile is
            // private AND the viewer is neither the owner nor an ACCEPTED
            // follower, hide detailed content (stats numbers, rutinas, actividad).
            // Header (name / avatar / gym) and the SEGUIR button stay visible so
            // the viewer can still send a follow request.
            // El gate de privacidad mira la arista SALIENTE: para ver el
            // contenido de una cuenta privada hay que SEGUIRLA. Que ella te siga
            // a vos no te da acceso a lo suyo (REQ-FOLLOW-010, mismo criterio que
            // el gate de posts en las rules).
            // ⚠️ `gated` es PRESENTACIÓN, no un límite de seguridad
            // (QA-SEC-011, #778). No hay contraparte en las reglas: el `read` de
            // `userPublicProfiles` es `if request.auth != null`
            // (`firestore.rules:942`) y ninguna regla de lectura consulta
            // `isProfilePublic`. Un tercero que no sigue a esta persona puede
            // leer igual racha, workoutsCount, contadores, volumen y PRs, y lo
            // mismo vale para sus posts `public` y sus rutinas `public`. Está
            // medido contra el emulador en `docs/security.md` §4.9.
            //
            // O sea: esconder acá evita mostrarlo en la app, no protege el dato.
            // No agregues copy que le prometa al usuario que esto lo protege, ni
            // asumas enforcement server-side al tocar este bloque. El único gate
            // real es el de `posts` con `privacy: 'friends'`, que vive en las
            // reglas y no depende de este flag.
            final isAcceptedFollower =
                view.outgoingFollow?.status == FollowStatus.accepted;
            final gated = !view.isSelf && !view.isPublic && !isAcceptedFollower;
            final canMessage = !view.isSelf &&
                _canOpenChat(ref, view, targetUid, isAcceptedFollower);
            // Inset inferior para que el último post/rutina despeje la
            // TreinoBottomBar flotante. Acá había un `+ 88` que rearmaba a mano
            // la composición de la barra (72 del pill + 8 de margen + safe
            // area) SOBRE un `padding.bottom` que ya la traía entera: el hueco
            // al final del scroll salía duplicado (#830).
            //
            // Esta pantalla se monta DENTRO del shell: `/feed/profile/:uid` y
            // `/home/profile/:uid` son subrutas de la `ShellRoute`
            // (`router.dart:673` y `:716`), así que la barra se ve y el
            // `Scaffold` del shell ya publicó su caja entera en
            // `padding.bottom`. El `Scaffold` propio de esta pantalla no la
            // toca: no tiene `bottomNavigationBar`, y `extendBodyBehindAppBar`
            // sólo reescribe el inset de ARRIBA.
            //
            // Mismo criterio que su gemela `TrainerPublicProfileScreen`. Ver el
            // dartdoc de [TreinoBottomBar.minHeight].
            final bottomInset = MediaQuery.paddingOf(context).bottom;
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    image: true,
                    label: l10n.a11yAvatarLabel(view.authorDisplayName),
                    child: PublicProfileHero(view: view),
                  ),
                  const SizedBox(height: 20),
                  if (!view.isSelf) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: PublicProfileFollowButton(
                              outgoingFollow: view.outgoingFollow,
                              incomingFollow: view.incomingFollow,
                              viewerUid: viewerUid,
                              targetUid: targetUid,
                              targetIsPublic: view.isPublic,
                            ),
                          ),
                          if (canMessage) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MessageButton(
                                viewerUid: viewerUid,
                                targetUid: targetUid,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (gated) ...[
                    const _PrivateProfileNotice(),
                    const SizedBox(height: 20),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      // Los contadores abren las listas, como en Instagram. La
                      // ruta se arma sobre `matchedLocation` y no sobre
                      // '/feed/profile/...' fijo: este mismo screen está
                      // registrado también bajo /home, y hardcodear /feed haría
                      // saltar la tab resaltada a FEED al abrir la lista desde
                      // INICIO (issue #387).
                      child: PublicProfileStatsRow(
                        workoutsCount: view.workoutsCount,
                        racha: view.racha,
                        followersCount: view.followersCount,
                        followingCount: view.followingCount,
                        onFollowersTap: () => context.push(
                          '${GoRouterState.of(context).matchedLocation}'
                          '/follows?tab=${FollowListKind.followers.name}',
                        ),
                        onFollowingTap: () => context.push(
                          '${GoRouterState.of(context).matchedLocation}'
                          '/follows?tab=${FollowListKind.following.name}',
                        ),
                        followersSemanticsLabel:
                            l10n.followListOpenFollowersA11y,
                        followingSemanticsLabel:
                            l10n.followListOpenFollowingA11y,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _ProfileTabPills(targetUid: targetUid),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _ProfileTabBody(targetUid: targetUid),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            );
          },
          loading: () => Center(
            child: Semantics(
              label: l10n.commonLoading,
              child: CircularProgressIndicator(color: palette.accent),
            ),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child: Semantics(
                liveRegion: true,
                label: l10n.publicProfileLoadErrorA11y,
                child: Text(
                  l10n.publicProfileLoadErrorA11y,
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso que se muestra cuando el perfil es privado y el visitante no es un
/// seguidor aceptado. Ícono de candado + copy corto.
///
/// ⚠️ El copy describe el modelo de aprobación, NO promete protección
/// (QA-SEC-011, #778). Decía "Seguí a esta persona para ver su actividad y sus
/// rutinas públicas", que le insinuaba al lector que ese contenido estaba
/// resguardado. No lo está: las reglas sirven el perfil, sus posts `public` y
/// sus rutinas `public` a cualquier autenticado (`docs/security.md` §4.9).
///
/// La segunda frase atribuye el ocultamiento a **la app**, no a un permiso, y
/// eso es deliberado. La primera versión de este arreglo decía "Seguila para
/// ver su actividad y sus rutinas", que seguía planteando el seguir como
/// **requisito de acceso** — media mentira en vez de la mentira entera. Al
/// lado de un candado y de un título "Perfil privado", eso se lee igual como
/// barrera de seguridad. Si vas a reescribir este texto, la línea es: podés
/// decir qué muestra o deja de mostrar la app, no qué puede o no puede leer
/// el visitante.
/// Si algún día se implementa el gate de verdad —que exige partir
/// `userPublicProfiles` en dos documentos, porque las reglas de Firestore no
/// filtran por campo— este copy se puede volver a endurecer.
class _PrivateProfileNotice extends StatelessWidget {
  const _PrivateProfileNotice();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        children: [
          Icon(TreinoIcon.lock, size: 32, color: palette.textMuted),
          const SizedBox(height: 12),
          Text(
            'Perfil privado', // i18n: Fase W2
            style: GoogleFonts.barlow(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Esta persona aprueba a mano quién la sigue. Hasta que te acepte, la app no muestra su actividad acá.', // i18n: Fase W2
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// ¿Las rules me dejarían abrir (o reabrir) el chat con [targetUid]?
///
/// Espejo de `chatCreateOk` en `firestore.rules` (cambio de producto del
/// 2026-10-21): lo sigo con la arista aceptada, o su perfil es público, o ya
/// hay un chat o un vínculo PF↔alumno vigente ([chatViaRelationshipProvider]:
/// abrir un chat existente es `getOrCreate`, que no pasa por el `create`).
/// Un bloqueo mío gana sobre todo, igual que `notBlocked` en las rules; si el
/// otro me bloqueó no lo puedo leer, y el `create` rebota.
///
/// Si cliente y rules no coinciden el UX miente: o el botón aparece y el
/// chat rebota con permission-denied, o falta cuando el servidor sí lo
/// permitiría. Si cambia `chatCreateOk`, esto cambia con ella.
bool _canOpenChat(
  WidgetRef ref,
  PublicProfileView view,
  String targetUid,
  bool iFollowThem,
) {
  if (ref.watch(myBlockedUidsProvider).contains(targetUid)) return false;
  return iFollowThem ||
      view.isPublic ||
      ref.watch(chatViaRelationshipProvider(targetUid));
}

/// MENSAJE pill on the public profile screen. Sólo se monta cuando
/// [_canOpenChat] da true.
///
/// Tapping it calls `ChatRepository.getOrCreate` and pushes
/// `/coach/chat/{chatId}?other={targetUid}` — the same route already used by
/// `chat_list_screen.dart`, `athlete_coach_view.dart` and
/// `athlete_detail_screen.dart`. The route is misnamed "/coach/" for
/// historical reasons but it's actually generic between any two uids.
class _MessageButton extends ConsumerStatefulWidget {
  const _MessageButton({
    required this.viewerUid,
    required this.targetUid,
  });

  final String viewerUid;
  final String targetUid;

  @override
  ConsumerState<_MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends ConsumerState<_MessageButton> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture the router + messenger BEFORE the await — same protocol as
    // PublicProfileFollowButton: the route may pop mid-write, after which
    // `context` is unmounted. Router + root messenger both survive disposal.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chat = await ref
          .read(chatRepositoryProvider)
          .getOrCreate(selfId: widget.viewerUid, otherId: widget.targetUid);
      router.push('/coach/chat/${chat.chatId}?other=${widget.targetUid}');
    } catch (_) {
      showTreinoToastOn(messenger, 'No pudimos abrir el chat. Probá de nuevo.',
          type: TreinoToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = !_busy;
    final textColor = enabled ? palette.textPrimary : palette.textMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Mensaje', // i18n: Fase W2
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1.0 : 0.6,
          child: GestureDetector(
            onTap: enabled ? _onTap : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: palette.border, width: 1),
              ),
              child: Center(
                child: _busy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.textMuted,
                        ),
                      )
                    : Text(
                        'MENSAJE',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 1.0,
                          color: textColor,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTabPills extends ConsumerWidget {
  const _ProfileTabPills({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_profileTabProvider(targetUid));
    return Row(
      children: [
        Expanded(
          child: _ProfilePill(
            label: 'RUTINAS PÚBLICAS',
            isActive: tab == _ProfileTab.rutinas,
            onTap: () => ref
                .read(_profileTabProvider(targetUid).notifier)
                .state = _ProfileTab.rutinas,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ProfilePill(
            label: 'ACTIVIDAD',
            isActive: tab == _ProfileTab.actividad,
            onTap: () => ref
                .read(_profileTabProvider(targetUid).notifier)
                .state = _ProfileTab.actividad,
          ),
        ),
      ],
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isActive ? palette.accent : palette.border,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.0,
              color: isActive
                  ? TreinoButtonTokens.foreground(context)
                  : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTabBody extends ConsumerWidget {
  const _ProfileTabBody({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_profileTabProvider(targetUid));
    return switch (tab) {
      _ProfileTab.rutinas => _RutinasTabBody(targetUid: targetUid),
      _ProfileTab.actividad => _ActividadTabBody(targetUid: targetUid),
    };
  }
}

class _RutinasTabBody extends ConsumerWidget {
  const _RutinasTabBody({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final routines = ref.watch(publicRoutinesByUserProvider(targetUid));

    if (routines.isEmpty) {
      return _EmptyState(
        palette: palette,
        text: 'Aún no hay rutinas públicas.', // i18n: Fase W2
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final routine in routines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RoutineCard(routine: routine),
            ),
        ],
      ),
    );
  }
}

class _ActividadTabBody extends ConsumerWidget {
  const _ActividadTabBody({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final postsAsync = ref.watch(visiblePostsByAuthorProvider(targetUid));

    return postsAsync.when(
      data: (posts) {
        if (posts.isEmpty) {
          return _EmptyState(
            palette: palette,
            text: 'Aún no hay actividad reciente.', // i18n: Fase W2
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final post in posts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  // Ver nota en feed_screen: PostCard tiene estado local
                  // (detalle expandido) y necesita key estable por post.
                  child: PostCard(key: ValueKey(post.id), post: post),
                ),
            ],
          ),
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
      ),
      error: (_, __) => _EmptyState(
        palette: palette,
        text: 'No pudimos cargar la actividad.', // i18n: Fase W2
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.text});

  final AppPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.barlow(
            fontSize: 14,
            color: palette.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
