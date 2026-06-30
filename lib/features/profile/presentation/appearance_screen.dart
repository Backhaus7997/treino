import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/theme_mode_provider.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';

/// Lets the user pick between System / Light / Dark theme modes.
///
/// Selecting an option calls [ThemeModeNotifier.setMode] immediately —
/// the theme transitions in the same frame. Back navigation does NOT
/// undo the selection (REQ-LM-009, SCENARIO-825, SCENARIO-827, SCENARIO-828).
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final current = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header — matches sibling profile sub-screen pattern ──────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  l10n.appearanceTitle.toUpperCase(),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Radio options ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: palette.textMuted.withValues(alpha: 0.12),
              ),
            ),
            child: RadioGroup<ThemeMode>(
              groupValue: current,
              onChanged: (mode) {
                if (mode == null) return;
                ref.read(themeModeProvider.notifier).setMode(mode);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sistema
                  _AppearanceTile(
                    value: ThemeMode.system,
                    groupValue: current,
                    label: l10n.appearanceSystem,
                    subtitle: l10n.appearanceSystemDesc,
                    palette: palette,
                    isFirst: true,
                  ),
                  _Divider(palette: palette),

                  // Claro
                  _AppearanceTile(
                    value: ThemeMode.light,
                    groupValue: current,
                    label: l10n.appearanceLight,
                    palette: palette,
                  ),
                  _Divider(palette: palette),

                  // Oscuro
                  _AppearanceTile(
                    value: ThemeMode.dark,
                    groupValue: current,
                    label: l10n.appearanceDark,
                    palette: palette,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Private widgets ──────────────────────────────────────────────────────────

class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.palette,
    this.subtitle,
    this.isFirst = false,
    this.isLast = false,
  });

  final ThemeMode value;
  final ThemeMode groupValue;
  final String label;
  final String? subtitle;
  final AppPalette palette;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;

    // Clip the radio tile shape to the card radius on first/last items so the
    // ink splash does not bleed outside the rounded container.
    final borderRadius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(14) : Radius.zero,
      bottom: isLast ? const Radius.circular(14) : Radius.zero,
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: RadioListTile<ThemeMode>(
        value: value,
        activeColor: palette.accent,
        title: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: selected ? palette.accent : palette.textPrimary,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 4,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: palette.textMuted.withValues(alpha: 0.10),
    );
  }
}
