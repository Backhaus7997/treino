import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../gyms/application/places_providers.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import 'gym_card.dart';

/// Single debounced search box replacing the two-step brand→sucursal picker
/// (retired `GymBrand`/`gymBrandsProvider`/`branchesForBrandProvider`).
///
/// Shared by `step_2_gym.dart` (onboarding) and `profile_gym_screen.dart`
/// (profile edit) per spec gym-catalog "Onboarding and profile-edit pickers
/// share behavior" — both wrap this single widget so their search/loading/
/// error/retry/no-gym behavior stays identical by construction.
///
/// Debounce is a `Timer` owned by this widget (300ms), mirroring
/// `SearchUsersScreen`'s convention (`search_users_screen.dart`) and
/// `searchUsersProvider`'s doc comment: "Debounce lives in the screen
/// (Timer), not here, so this provider stays pure and cacheable" — the same
/// convention `placesSuggestionsProvider` follows (deferred here per Slice 2
/// deviation, see `places_providers.dart`).
///
/// Works WITHOUT location permission: `placesSuggestionsProvider` reads
/// `gymSearchLocationBiasProvider`, which falls back to an unbiased search
/// (no crash, no permission prompt) — this widget has no location-specific
/// branching of its own.
class GymSearchBox extends ConsumerStatefulWidget {
  const GymSearchBox({
    super.key,
    required this.selectedGymId,
    required this.onGymIdSelected,
    this.emptyQueryContent,
  });

  /// Currently-selected gym id (or [kNoGymId]) — highlights the matching
  /// `GymCard`/no-gym option, if any is visible in the current suggestion
  /// list.
  final String? selectedGymId;

  /// Called with a Google Place id on suggestion tap, or [kNoGymId] when the
  /// "OTRO GYM / SIN GYM" option is tapped.
  final void Function(String? gymId) onGymIdSelected;

  /// Optional content rendered in place of the suggestions list when the
  /// search query is empty. `null` (the default) preserves the original
  /// `SizedBox.shrink()` behavior — design gym-selection-v2 AD-10.
  ///
  /// `step_2_gym.dart` (onboarding) omits this and stays byte-for-byte
  /// unchanged; `profile_gym_screen.dart` passes the nearby-gyms list.
  final Widget? emptyQueryContent;

  @override
  ConsumerState<GymSearchBox> createState() => _GymSearchBoxState();
}

class _GymSearchBoxState extends ConsumerState<GymSearchBox> {
  Timer? _debounce;
  String _activeQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _activeQuery = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: _onQueryChanged,
          style: GoogleFonts.barlow(color: palette.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: AppL10n.of(context).profileGymSearchHint,
            prefixIcon: Icon(
              TreinoIcon.search,
              color: palette.textMuted,
              size: 20,
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ),
        const SizedBox(height: 14),
        GymCard(
          name: 'OTRO GYM / SIN GYM',
          address: 'No registramos tu gimnasio',
          selected: widget.selectedGymId == kNoGymId,
          onTap: () => widget.onGymIdSelected(kNoGymId),
        ),
        const SizedBox(height: 12),
        _SuggestionsList(
          query: _activeQuery,
          selectedGymId: widget.selectedGymId,
          onSuggestionTap: widget.onGymIdSelected,
          emptyQueryContent: widget.emptyQueryContent,
        ),
      ],
    );
  }
}

class _SuggestionsList extends ConsumerWidget {
  const _SuggestionsList({
    required this.query,
    required this.selectedGymId,
    required this.onSuggestionTap,
    required this.emptyQueryContent,
  });

  final String query;
  final String? selectedGymId;
  final void Function(String) onSuggestionTap;
  final Widget? emptyQueryContent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.isEmpty) return emptyQueryContent ?? const SizedBox.shrink();

    final suggestionsAsync = ref.watch(placesSuggestionsProvider(query));

    return suggestionsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _ErrorRetry(
        onRetry: () => ref.invalidate(placesSuggestionsProvider(query)),
      ),
      data: (suggestions) {
        if (suggestions.isEmpty) {
          return _EmptyResults(query: query);
        }
        return Column(
          children: [
            for (final suggestion in suggestions) ...[
              GymCard(
                name: suggestion.primaryText,
                address: suggestion.secondaryText ?? '',
                selected: selectedGymId == suggestion.placeId,
                onTap: () => onSuggestionTap(suggestion.placeId),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        'Sin resultados para "$query"',
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppL10n.of(context).profileLoadError,
            style: TextStyle(color: palette.danger, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                AppL10n.of(context).coachRetryLabel,
                style: TextStyle(color: palette.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
