import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/follow_list_providers.dart';
import 'widgets/feed_empty_state.dart';
import 'widgets/user_search_result_tile.dart';

/// Las dos listas del grafo social —SEGUIDORES y SEGUIDOS— de [targetUid].
///
/// Se llega tocando el contador correspondiente en el perfil, como en
/// Instagram, y una vez adentro se cambia de lista con las pills sin volver
/// atrás. [initialKind] decide cuál se abre según qué contador se tocó.
///
/// Las dos listas son **conjuntos distintos**: seguir y ser seguido son
/// hechos independientes desde que el modelo pasó a una arista por dirección.
/// Por eso hay dos providers y no uno con un filtro.
///
/// Ve las listas de cualquiera, no sólo las propias: las rules abren la
/// lectura de las aristas ya `accepted` a cualquier autenticado. Las
/// solicitudes `pending` siguen siendo privadas y no aparecen acá.
class FollowListScreen extends ConsumerStatefulWidget {
  const FollowListScreen({
    super.key,
    required this.targetUid,
    required this.initialKind,
  });

  final String targetUid;
  final FollowListKind initialKind;

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  late FollowListKind _kind = widget.initialKind;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isSelf = ref.watch(currentUidProvider) == widget.targetUid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(targetUid: widget.targetUid, palette: palette),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _KindPills(
            kind: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: _Body(
            targetUid: widget.targetUid,
            kind: _kind,
            isSelf: isSelf,
            palette: palette,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Flecha de volver + el nombre de la persona cuyas listas se están mirando.
///
/// El nombre importa: desde acá se navega a otros perfiles, y sin él es fácil
/// perder de vista de quién era la lista después de un par de saltos.
class _Header extends ConsumerWidget {
  const _Header({required this.targetUid, required this.palette});

  final String targetUid;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    // Mismo fallback que `UserSearchResultTile`, que es la fila de esta misma
    // pantalla: un perfil sin nombre se muestra como "Anónimo". Un título
    // vacío se lee como pantalla rota, no como "esta persona no puso nombre".
    final name = ref
            .watch(userPublicProfileProvider(targetUid))
            .valueOrNull
            ?.displayName ??
        'Anónimo';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l10n.commonBack,
            child: TreinoTappable(
              onTap: () =>
                  context.canPop() ? context.pop() : context.go('/feed'),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(
                    TreinoIcon.back,
                    size: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name.toUpperCase(),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pills
// ---------------------------------------------------------------------------

class _KindPills extends StatelessWidget {
  const _KindPills({required this.kind, required this.onChanged});

  final FollowListKind kind;
  final ValueChanged<FollowListKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return Row(
      children: [
        Expanded(
          child: _Pill(
            label: l10n.followListTabFollowers,
            isActive: kind == FollowListKind.followers,
            onTap: () => onChanged(FollowListKind.followers),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Pill(
            label: l10n.followListTabFollowing,
            isActive: kind == FollowListKind.following,
            onTap: () => onChanged(FollowListKind.following),
          ),
        ),
      ],
    );
  }
}

/// Mismo pill que usa el perfil público para RUTINAS / ACTIVIDAD.
class _Pill extends StatelessWidget {
  const _Pill({
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

    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: TreinoTappable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? palette.accent : palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isActive ? palette.accent : palette.border,
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

/// La rama del shell (`/feed` o `/home`) de la que cuelga esta pantalla.
///
/// SALIR de la lista hacia el perfil de un miembro tiene que quedarse en la
/// misma rama, por la misma razón por la que se ENTRA respetándola:
/// `_ShellScaffold` deriva la tab resaltada del prefijo de la ruta, así que
/// hardcodear `/feed` haría saltar la tab a FEED —y el back caería mal— para
/// quien abrió la lista desde INICIO (issue #387).
///
/// La ubicación acá siempre es `{rama}/profile/{targetUid}/follows`, así que
/// la rama es todo lo anterior a `/profile/`. Si algún día la ruta cambia de
/// forma, cae en `/feed`, que es de dónde se llega en la mayoría de los casos.
String _shellBranch(BuildContext context) {
  final location = GoRouterState.of(context).matchedLocation;
  final i = location.indexOf('/profile/');
  return i > 0 ? location.substring(0, i) : '/feed';
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.targetUid,
    required this.kind,
    required this.isSelf,
    required this.palette,
  });

  final String targetUid;
  final FollowListKind kind;
  final bool isSelf;
  final AppPalette palette;

  /// El vacío se redacta distinto según de quién es la lista: "todavía no
  /// tenés seguidores" y "todavía no tiene seguidores" no son la misma frase,
  /// y la genérica suena a error en las dos.
  String _emptyMessage(AppL10n l10n) => switch ((kind, isSelf)) {
        (FollowListKind.followers, true) => l10n.followListEmptyFollowersSelf,
        (FollowListKind.followers, false) => l10n.followListEmptyFollowers,
        (FollowListKind.following, true) => l10n.followListEmptyFollowingSelf,
        (FollowListKind.following, false) => l10n.followListEmptyFollowing,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final async = ref.watch(followListProvider(followListKey(kind, targetUid)));

    return TreinoStateSwitcher(
      // La key incluye la dirección: sin eso, pasar de una lista vacía a la
      // otra lista vacía no cambiaría de child y el texto no se actualizaría.
      childKey: ValueKey(async.when(
        skipLoadingOnReload: true,
        loading: () => 'loading:${kind.name}',
        error: (_, __) => 'error:${kind.name}',
        data: (list) =>
            list.isEmpty ? 'empty:${kind.name}' : 'data:${kind.name}',
      )),
      // `skipLoadingOnReload` NO es cosmético. El provider de abajo watchea un
      // stream de Firestore, y un stream re-emite seguido: snapshot de cache y
      // después de servidor al abrir, y cada vez que alguien sigue o deja de
      // seguir. Con el default (`false`), CADA re-emisión vuelve el estado a
      // loading, tira la lista abajo, pone el spinner de pantalla completa y
      // manda el scroll a cero — aunque el contenido no haya cambiado en nada.
      // Con `true`, mientras recarga se sigue mostrando lo último bueno.
      child: async.when(
        skipLoadingOnReload: true,
        loading: () => Center(
          child: Semantics(
            label: l10n.commonLoading,
            child: CircularProgressIndicator(color: palette.accent),
          ),
        ),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.followListLoadError,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        data: (profiles) {
          if (profiles.isEmpty) {
            return FeedEmptyState(message: _emptyMessage(l10n));
          }
          // ListView.builder + nada de TreinoFadeSlideIn adentro: el viewport
          // recicla el State de los hijos y la animación de entrada se
          // redispararía al scrollear.
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.paddingOf(context).bottom + 20,
            ),
            itemCount: profiles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final profile = profiles[i];
              return UserSearchResultTile(
                profile: profile,
                onTap: () => context.push(
                  '${_shellBranch(context)}/profile/${profile.uid}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
