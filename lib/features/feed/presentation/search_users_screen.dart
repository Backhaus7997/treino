import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/search_users_provider.dart';
import 'widgets/feed_empty_state.dart';
import 'widgets/user_search_result_tile.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Full-screen user search.
///
/// Uses [ConsumerStatefulWidget] to hold [TextEditingController] and the
/// [Timer] that drives 300ms debounce. The debounce lives in the screen so
/// [searchUsersProvider] stays pure and cacheable.
///
/// Does NOT own a [Scaffold] — relies on [_ShellScaffold] via the router
/// (per spec REQ-UPS-001 / design Section B.4).
///
/// Privacy: uses [UserPublicProfile] exclusively — never [UserProfile].
/// All search results come from [userPublicProfileRepositoryProvider].
class SearchUsersScreen extends ConsumerStatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  ConsumerState<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends ConsumerState<SearchUsersScreen> {
  late final TextEditingController _controller;
  Timer? _debounce;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _activeQuery = value.trim());
      }
    });
  }

  void _clearQuery() {
    _controller.clear();
    _debounce?.cancel();
    setState(() => _activeQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchUsersHeader(palette: palette),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _SearchTextField(
            controller: _controller,
            palette: palette,
            onChanged: _onQueryChanged,
            onClear: _clearQuery,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _SearchBody(
            activeQuery: _activeQuery,
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

class _SearchUsersHeader extends StatelessWidget {
  const _SearchUsersHeader({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
            child: Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
          ),
          const SizedBox(width: 14),
          Text(
            'BUSCAR USUARIOS',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search TextField
// ---------------------------------------------------------------------------

class _SearchTextField extends StatelessWidget {
  const _SearchTextField({
    required this.controller,
    required this.palette,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final AppPalette palette;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre',
        hintStyle: GoogleFonts.barlow(
          fontSize: 14,
          color: palette.textMuted,
        ),
        filled: true,
        fillColor: palette.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: palette.textMuted.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: palette.textMuted.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return GestureDetector(
              onTap: onClear,
              child: Icon(TreinoIcon.close, size: 18, color: palette.textMuted),
            );
          },
        ),
      ),
      style: GoogleFonts.barlow(
        fontSize: 14,
        color: palette.textPrimary,
      ),
      cursorColor: palette.accent,
    );
  }
}

// ---------------------------------------------------------------------------
// Search Body — state machine
// ---------------------------------------------------------------------------

/// Renders one of the search states based on [activeQuery] and provider result.
///
/// State machine (REQ-UPS-002..005, design Section B.4):
/// - `initial`: activeQuery is empty → show initial empty-state prompt
/// - `typing-below-min`: 0 < len < 2 → show same empty-state (2-char gate)
/// - `loading`: AsyncLoading → spinner (palette.accent color)
/// - `data`: non-empty list → ListView.separated of [UserSearchResultTile]
/// - `empty-results`: empty list → "Sin resultados para..."
/// - `error`: AsyncError → inline error text
class _SearchBody extends ConsumerWidget {
  const _SearchBody({
    required this.activeQuery,
    required this.palette,
  });

  final String activeQuery;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (activeQuery.isEmpty) {
      return const FeedEmptyState(message: 'Buscá usuarios por nombre');
    }

    if (activeQuery.length < kSearchMinChars) {
      return const FeedEmptyState(message: 'Buscá usuarios por nombre');
    }

    final asyncUsers = ref.watch(searchUsersProvider(activeQuery));

    return asyncUsers.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos buscar usuarios. Intentá de nuevo.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (users) {
        if (users.isEmpty) {
          return FeedEmptyState(
            message: 'Sin resultados para "$activeQuery"',
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.paddingOf(context).bottom),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final user = users[i];
            return UserSearchResultTile(
              profile: user,
              onTap: () => context.push('/feed/profile/${user.uid}'),
            );
          },
        );
      },
    );
  }
}
