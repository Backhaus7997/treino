import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';
import '../application/create_post_notifier.dart';
import '../domain/post.dart';
import '../domain/post_privacy.dart';
import 'routine_tag_picker_sheet.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Full-screen form for composing a new post, or editing an existing one
/// when [existingPost] is passed (e.g. via `state.extra` from the router).
///
/// Does NOT own a [Scaffold] — relies on [_ShellScaffold] via the router.
class CreatePostScreen extends ConsumerWidget {
  const CreatePostScreen({super.key, this.existingPost});

  /// The post to edit. `null` (default) composes a brand-new post.
  final Post? existingPost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = createPostNotifierProvider(existingPost);
    final stateAsync = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    return stateAsync.when(
      loading: () => const _CreatePostLoading(),
      error: (_, __) => _CreatePostError(
        onRetry: () => ref.invalidate(provider),
      ),
      data: (state) => _CreatePostBody(state: state, notifier: notifier),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _CreatePostLoading extends StatelessWidget {
  const _CreatePostLoading();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Semantics(
      label: l10n.coachLoadingLabel,
      liveRegion: true,
      child: Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _CreatePostError extends StatelessWidget {
  const _CreatePostError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                TreinoIcon.warning,
                size: 48,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.createPostLoadError,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  label: l10n.commonCancel,
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    behavior: HitTestBehavior.opaque,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      child: Center(
                        widthFactor: 1,
                        child: ExcludeSemantics(
                          child: Text(
                            'CANCELAR',
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Semantics(
                  button: true,
                  label: l10n.coachRetryLabel,
                  child: GestureDetector(
                    onTap: onRetry,
                    behavior: HitTestBehavior.opaque,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      child: Center(
                        widthFactor: 1,
                        child: ExcludeSemantics(
                          child: Text(
                            l10n.coachRetryLabel.toUpperCase(),
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: palette.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _CreatePostBody extends ConsumerStatefulWidget {
  const _CreatePostBody({required this.state, required this.notifier});

  final CreatePostState state;
  final CreatePostNotifier notifier;

  @override
  ConsumerState<_CreatePostBody> createState() => _CreatePostBodyState();
}

class _CreatePostBodyState extends ConsumerState<_CreatePostBody> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = widget.state;
    final notifier = widget.notifier;
    final profileAsync = ref.watch(userProfileProvider);
    final hasGym = profileAsync.valueOrNull?.gymId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CreatePostHeader(state: state, notifier: notifier),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PostTextField(
                  controller: _controller,
                  onChanged: notifier.setText,
                  palette: palette,
                ),
                const SizedBox(height: 8),
                _CharCounter(
                  charCount: state.text.characters.length,
                  palette: palette,
                ),
                const SizedBox(height: 20),
                _PrivacyLabel(palette: palette),
                const SizedBox(height: 12),
                _PrivacyPills(
                  selected: state.privacy,
                  hasGym: hasGym,
                  onSelect: notifier.setPrivacy,
                  palette: palette,
                ),
                if (!hasGym) ...[
                  const SizedBox(height: 8),
                  _PrivacyHelperText(palette: palette),
                ],
                const SizedBox(height: 20),
                _RoutineTagField(state: state, notifier: notifier),
                const SizedBox(height: 20),
                if (state.errorMessage != null) ...[
                  _InlineError(
                    message: state.errorMessage!,
                    palette: palette,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _CreatePostHeader extends ConsumerWidget {
  const _CreatePostHeader({required this.state, required this.notifier});

  final CreatePostState state;
  final CreatePostNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          // CANCELAR
          Semantics(
            button: true,
            label: l10n.commonCancel,
            child: GestureDetector(
              onTap: () => context.pop(),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Align(
                  widthFactor: 1,
                  child: ExcludeSemantics(
                    child: Text(
                      'CANCELAR',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Title
          Semantics(
            header: true,
            child: Text(
              state.isEditing ? l10n.createPostEditTitle : 'NUEVO POST',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          // PUBLICAR / GUARDAR
          Opacity(
            opacity: state.canSubmit ? 1.0 : 0.4,
            child: Semantics(
              button: true,
              enabled: state.canSubmit,
              label: state.isSubmitting
                  ? (state.isEditing
                      ? l10n.createPostSavingA11y
                      : l10n.feedPublishingA11y)
                  : (state.isEditing
                      ? l10n.createPostSaveChangesA11y
                      : l10n.feedCreatePostA11y),
              liveRegion: state.isSubmitting,
              child: GestureDetector(
                onTap: state.canSubmit
                    ? () async {
                        // Capture the root messenger + copy BEFORE the await: the
                        // screen pops on success, after which `context` is unmounted.
                        // The app-level messenger survives the pop, so the success
                        // toast is still delivered on the feed.
                        final messenger = ScaffoldMessenger.of(context);
                        final successMessage = state.isEditing
                            ? l10n.feedPostUpdatedSuccess
                            : l10n.feedPostPublishedSuccess;
                        final ok = await notifier.submit();
                        if (ok && context.mounted) {
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                                SnackBar(content: Text(successMessage)));
                          context.pop();
                        }
                      }
                    : null,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  child: Center(
                    widthFactor: 1,
                    child: ExcludeSemantics(
                      child: state.isSubmitting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.accent,
                              ),
                            )
                          : Text(
                              state.isEditing
                                  ? l10n.createPostSaveChanges
                                  : 'PUBLICAR',
                              style: GoogleFonts.barlowCondensed(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: palette.accent,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text field
// ---------------------------------------------------------------------------

class _PostTextField extends StatelessWidget {
  const _PostTextField({
    required this.controller,
    required this.onChanged,
    required this.palette,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w400,
        fontSize: 16,
        color: palette.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: '¿Qué querés compartir?',
        hintStyle: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 16,
          color: palette.textMuted,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Char counter
// ---------------------------------------------------------------------------

class _CharCounter extends StatelessWidget {
  const _CharCounter({required this.charCount, required this.palette});

  final int charCount;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final isOver = charCount > kMaxPostChars;
    return Text(
      '$charCount / $kMaxPostChars',
      textAlign: TextAlign.end,
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w400,
        fontSize: 12,
        color: isOver ? palette.danger : palette.textMuted,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy
// ---------------------------------------------------------------------------

class _PrivacyLabel extends StatelessWidget {
  const _PrivacyLabel({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      'VISIBILIDAD',
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1.0,
        color: palette.textMuted,
      ),
    );
  }
}

class _PrivacyPills extends StatelessWidget {
  const _PrivacyPills({
    required this.selected,
    required this.hasGym,
    required this.onSelect,
    required this.palette,
  });

  final PostPrivacy selected;
  final bool hasGym;
  final ValueChanged<PostPrivacy> onSelect;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PrivacyPill(
          label: 'AMIGOS',
          privacy: PostPrivacy.friends,
          selected: selected,
          isEnabled: true,
          onSelect: onSelect,
          palette: palette,
        ),
        const SizedBox(width: 12),
        _PrivacyPill(
          label: 'MI GYM',
          privacy: PostPrivacy.gym,
          selected: selected,
          isEnabled: hasGym,
          onSelect: onSelect,
          palette: palette,
        ),
        const SizedBox(width: 12),
        _PrivacyPill(
          label: 'PÚBLICO',
          privacy: PostPrivacy.public,
          selected: selected,
          isEnabled: true,
          onSelect: onSelect,
          palette: palette,
        ),
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
      child: GestureDetector(
        onTap: isEnabled ? () => onSelect(privacy) : null,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: _isActive ? palette.accent : palette.bgCard,
                borderRadius: BorderRadius.circular(20),
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

class _PrivacyHelperText extends StatelessWidget {
  const _PrivacyHelperText({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Asociate a un gym para postear acá',
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w400,
        fontSize: 12,
        color: palette.textMuted,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Routine tag field
// ---------------------------------------------------------------------------

/// Lets the author attach one of their own routines to a manual post. When
/// nothing is attached it renders the "ETIQUETAR RUTINA" chip; tapping opens
/// [showRoutineTagPickerSheet]. Once a routine is chosen it shows the accent
/// pill (same look as the published card) plus a control to detach it.
class _RoutineTagField extends ConsumerWidget {
  const _RoutineTagField({required this.state, required this.notifier});

  final CreatePostState state;
  final CreatePostNotifier notifier;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(authStateChangesProvider).valueOrNull?.uid ?? '';
    final tag = await showRoutineTagPickerSheet(context: context, uid: uid);
    if (tag != null) notifier.setRoutineTag(tag);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final tag = state.routineTag;

    if (tag == null) {
      return Semantics(
        button: true,
        label: 'Etiquetar rutina',
        child: GestureDetector(
          onTap: () => _pick(context, ref),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    TreinoIcon.dumbbell,
                    size: 16,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Text(
                    'ETIQUETAR RUTINA',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Flexible(
          child: Semantics(
            button: true,
            label: 'Cambiar rutina etiquetada: ${tag.routineName}',
            child: GestureDetector(
              onTap: () => _pick(context, ref),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        TreinoIcon.tabWorkout,
                        size: 14,
                        color: palette.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: ExcludeSemantics(
                        child: Text(
                          tag.routineName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            letterSpacing: 0.8,
                            color: palette.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Quitar rutina etiquetada',
          child: GestureDetector(
            onTap: () => notifier.setRoutineTag(null),
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Center(
                widthFactor: 1,
                child: ExcludeSemantics(
                  child: Icon(
                    TreinoIcon.close,
                    size: 18,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inline error
// ---------------------------------------------------------------------------

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.palette});

  final String message;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.danger.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.danger,
        ),
      ),
    );
  }
}
