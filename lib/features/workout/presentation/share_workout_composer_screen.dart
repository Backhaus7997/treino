import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../feed/application/create_post_notifier.dart' show kMaxPostChars;
import '../../feed/domain/workout_snapshot.dart';
import '../../feed/presentation/widgets/workout_snapshot_detail.dart';
import '../application/post_workout_notifier.dart';
import '../application/session_muscle_distribution.dart';
import '../application/session_providers.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';

/// Composer del post de entreno: el atleta edita el texto (precargado con el
/// default de siempre), adjunta UNA foto opcional y ve el detalle que va a
/// quedar visible para el resto antes de publicar.
///
/// Reemplaza el share de 1 tap del resumen post-entreno: compartir SIEMPRE
/// pasa por acá (con el default precargado son 2 taps para quien no quiere
/// editar nada).
///
/// Lee la sesión con la MISMA key de provider que el resumen, así Riverpod
/// dedupea el fetch en vez de re-leer Firestore al abrir el composer.
class ShareWorkoutComposerScreen extends ConsumerWidget {
  const ShareWorkoutComposerScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final key = (uid: uid, sessionId: sessionId);
    final summaryAsync = ref.watch(sessionSummaryProvider(key));
    // Best-effort igual que en el resumen: si el catálogo falla, el preview
    // aparece sin mini-gráfico y publicar sigue andando.
    final distribution =
        ref.watch(sessionMuscleDistributionProvider(key)).valueOrNull;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: summaryAsync.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: palette.accent)),
            error: (_, __) => _ComposerError(
              onRetry: () => ref.invalidate(sessionSummaryProvider(key)),
            ),
            data: (data) {
              final session = data.session;
              if (session == null) {
                return _ComposerError(
                  onRetry: () => ref.invalidate(sessionSummaryProvider(key)),
                );
              }
              return _ComposerBody(
                session: session,
                setLogs: data.setLogs,
                snapshot: buildWorkoutSnapshot(
                  setLogs: data.setLogs,
                  setsByAxis: distribution?.setsByAxis ?? const {},
                  volumeKgByAxis: distribution?.volumeKgByAxis ?? const {},
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _ComposerBody extends ConsumerStatefulWidget {
  const _ComposerBody({
    required this.session,
    required this.setLogs,
    required this.snapshot,
  });

  final Session session;
  final List<SetLog> setLogs;
  final WorkoutSnapshot snapshot;

  @override
  ConsumerState<_ComposerBody> createState() => _ComposerBodyState();
}

class _ComposerBodyState extends ConsumerState<_ComposerBody> {
  TextEditingController? _controller;
  String? _photoPath;
  bool _photoError = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// El default vive en el ARB, así que el controller no puede inicializarse
  /// en initState (no hay context de localizaciones todavía). Se crea en el
  /// primer build y NO se re-crea después, para no pisar lo que el usuario
  /// va escribiendo en cada rebuild.
  TextEditingController _ensureController(String initialText) {
    return _controller ??= TextEditingController(text: initialText);
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;
    setState(() {
      _photoPath = file.path;
      _photoError = false;
    });
  }

  Future<void> _publish() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    final text = _controller?.text.trim() ?? '';

    try {
      await ref.read(postWorkoutNotifierProvider.notifier).shareWorkout(
            widget.session,
            text: text,
            // QA-FEED-364/389: ejercicios DISTINTOS de la sesión → el "N ej."
            // de la card.
            exerciseCount:
                widget.setLogs.map((s) => s.exerciseId).toSet().length,
            localPhotoPath: _photoPath,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.workoutSnackShareSuccess)),
      );
      if (!context.mounted) return;
      context.go('/workout');
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.workoutSnackShareError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final controller = _ensureController(l10n.workoutPostAutoCompleteText);
    final isSharing = ref.watch(postWorkoutNotifierProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComposerHeader(
          isSharing: isSharing,
          // El texto vacío no publica (mismo criterio que el composer manual);
          // el largo lo acota maxLength en el campo.
          canPublish: !isSharing,
          onPublish: _publish,
          controller: controller,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  maxLines: null,
                  maxLength: kMaxPostChars,
                  keyboardType: TextInputType.multiline,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 16,
                    color: palette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.shareWorkoutComposerHint,
                    hintStyle: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 16,
                      color: palette.textMuted,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterStyle: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: palette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PhotoField(
                  photoPath: _photoPath,
                  hasError: _photoError,
                  onPick: _pickPhoto,
                  onRemove: () => setState(() {
                    _photoPath = null;
                    _photoError = false;
                  }),
                  onLoadError: () {
                    // El archivo elegido no se puede decodificar — se descarta
                    // acá en vez de fallar recién al subir.
                    if (!mounted) return;
                    setState(() {
                      _photoPath = null;
                      _photoError = true;
                    });
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.shareWorkoutComposerPreviewTitle,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.0,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                WorkoutSnapshotDetail(snapshot: widget.snapshot),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _ComposerHeader extends StatelessWidget {
  const _ComposerHeader({
    required this.isSharing,
    required this.canPublish,
    required this.onPublish,
    required this.controller,
  });

  final bool isSharing;
  final bool canPublish;
  final Future<void> Function() onPublish;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l10n.commonCancel,
            child: GestureDetector(
              onTap: isSharing ? null : () => context.pop(),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Align(
                  widthFactor: 1,
                  child: ExcludeSemantics(
                    child: Icon(TreinoIcon.close, color: palette.textMuted),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Semantics(
            header: true,
            child: Text(
              l10n.shareWorkoutComposerTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          // El botón se deshabilita cuando el texto queda vacío — se escucha
          // el controller para no rebuildear la pantalla entera por tecla.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, __) {
              final enabled = canPublish && value.text.trim().isNotEmpty;
              return Opacity(
                opacity: enabled ? 1.0 : 0.4,
                child: Semantics(
                  button: true,
                  enabled: enabled,
                  label: l10n.shareWorkoutComposerPublish,
                  liveRegion: isSharing,
                  child: GestureDetector(
                    onTap: enabled ? onPublish : null,
                    behavior: HitTestBehavior.opaque,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      child: Center(
                        widthFactor: 1,
                        child: ExcludeSemantics(
                          child: isSharing
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.accent,
                                  ),
                                )
                              : Text(
                                  l10n.shareWorkoutComposerPublish,
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
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Photo field ──────────────────────────────────────────────────────────────

class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.photoPath,
    required this.hasError,
    required this.onPick,
    required this.onRemove,
    required this.onLoadError,
  });

  final String? photoPath;
  final bool hasError;
  final Future<void> Function() onPick;
  final VoidCallback onRemove;
  final VoidCallback onLoadError;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    if (photoPath == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: l10n.shareWorkoutComposerAddPhoto,
            child: GestureDetector(
              onTap: onPick,
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
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
                            TreinoIcon.image,
                            size: 16,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ExcludeSemantics(
                          child: Text(
                            l10n.shareWorkoutComposerAddPhoto,
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
              ),
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: 8),
            Text(
              l10n.shareWorkoutComposerPhotoError,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: palette.danger,
              ),
            ),
          ],
        ],
      );
    }

    return Stack(
      alignment: Alignment.topRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SizedBox(
              width: double.infinity,
              child: Image.file(
                // El path viene de image_picker; se resuelve como archivo
                // local sin pasar por red (mismo patrón que
                // AvatarPickerButton).
                File(photoPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => onLoadError());
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Semantics(
            button: true,
            label: l10n.shareWorkoutComposerRemovePhoto,
            child: GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: palette.bg.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: ExcludeSemantics(
                  child: Icon(
                    TreinoIcon.close,
                    size: 18,
                    color: palette.textPrimary,
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

// ── Error state ──────────────────────────────────────────────────────────────

class _ComposerError extends StatelessWidget {
  const _ComposerError({required this.onRetry});

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
                l10n.workoutSnackShareError,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
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
      ),
    );
  }
}
