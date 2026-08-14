import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/post_privacy.dart';

/// Selector visual compartido por los composers de posts manuales y entrenos.
class PostPrivacySelector extends StatelessWidget {
  const PostPrivacySelector({
    super.key,
    required this.selected,
    required this.hasGym,
    required this.onSelect,
  });

  final PostPrivacy selected;
  final bool hasGym;
  final ValueChanged<PostPrivacy> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.postPrivacySelectorTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.0,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _PrivacyPill(
              label: l10n.postPrivacyFriends,
              privacy: PostPrivacy.followers,
              selected: selected,
              isEnabled: true,
              onSelect: onSelect,
              palette: palette,
            ),
            const SizedBox(width: 12),
            _PrivacyPill(
              label: l10n.postPrivacyGym,
              privacy: PostPrivacy.gym,
              selected: selected,
              isEnabled: hasGym,
              onSelect: onSelect,
              palette: palette,
            ),
            const SizedBox(width: 12),
            _PrivacyPill(
              label: l10n.postPrivacyPublic,
              privacy: PostPrivacy.public,
              selected: selected,
              isEnabled: true,
              onSelect: onSelect,
              palette: palette,
            ),
          ],
        ),
        if (!hasGym) ...[
          const SizedBox(height: 8),
          Text(
            l10n.postPrivacyNoGymHint,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 12,
              color: palette.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _PrivacyPill extends StatelessWidget {
  const _PrivacyPill({
    required this.label,
    required this.privacy,
    required this.selected,
    required this.isEnabled,
    required this.onSelect,
    required this.palette,
  });

  final String label;
  final PostPrivacy privacy;
  final PostPrivacy selected;
  final bool isEnabled;
  final ValueChanged<PostPrivacy> onSelect;
  final AppPalette palette;

  bool get _isActive => selected == privacy;

  @override
  Widget build(BuildContext context) {
    final pill = Semantics(
      button: true,
      selected: _isActive,
      enabled: isEnabled,
      label: label,
      child: TreinoTappable(
        onTap: isEnabled ? () => onSelect(privacy) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: _isActive ? palette.accent : palette.bgCard,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: _isActive ? palette.accent : palette.border,
                ),
              ),
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _isActive ? palette.bg : palette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!isEnabled) {
      return Opacity(opacity: 0.4, child: pill);
    }
    return pill;
  }
}
