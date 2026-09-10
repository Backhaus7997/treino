import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/theme_mode_provider.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

/// Preferencia visual de la cuenta, reunida con el resto de sus ajustes.
class AparienciaTab extends ConsumerWidget {
  const AparienciaTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final mode = ref.watch(sharedPreferencesProvider).maybeWhen(
          data: (_) => ref.watch(themeModeProvider),
          orElse: () => ThemeMode.system,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'APARIENCIA',
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            fontWeight: AppFonts.w700,
            letterSpacing: AppFonts.headingTracking,
            color: palette.textPrimary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppSpacing.hairline),
        Text(
          'Elegí cómo querés ver TREINO en este dispositivo.',
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            color: palette.textMuted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppSpacing.s14),
        Container(
          padding: const EdgeInsets.all(AppSpacing.s8),
          decoration: BoxDecoration(
            color: TreinoCardTokens.background(context),
            border: Border.all(color: TreinoCardTokens.border(context)),
            borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
            boxShadow: TreinoCardTokens.boxShadow,
          ),
          child: Column(
            children: [
              _ThemeOption(
                label: 'Sistema',
                description: 'Sigue el modo de tu dispositivo.',
                selected: mode == ThemeMode.system,
                onTap: () => _set(ref, ThemeMode.system),
              ),
              _ThemeOption(
                label: 'Claro',
                description: 'Fondo claro y contraste alto.',
                selected: mode == ThemeMode.light,
                onTap: () => _set(ref, ThemeMode.light),
              ),
              _ThemeOption(
                label: 'Oscuro',
                description: 'Fondo oscuro para ambientes con poca luz.',
                selected: mode == ThemeMode.dark,
                onTap: () => _set(ref, ThemeMode.dark),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _set(WidgetRef ref, ThemeMode mode) {
    if (!ref.read(sharedPreferencesProvider).hasValue) return;
    ref.read(themeModeProvider.notifier).setMode(mode);
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) => AnimatedContainer(
        key: Key('appearance_${label.toLowerCase()}'),
        // EL HOVER NO ANIMA; el cambio de SELECCIÓN sí — #1063.
        duration:
            selected ? AppMotion.resolve(ctx, AppMotion.fast) : Duration.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.s12,
        ),
        decoration: BoxDecoration(
          color: selected || states.hovered
              ? palette.accent.withValues(alpha: selected ? 0.12 : 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? TreinoIcon.checkCircleFill
                  : TreinoIcon.checkCircleEmpty,
              color: selected ? palette.accent : palette.textMuted,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
                      fontWeight: AppFonts.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
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
    );
  }
}
