import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../auth/presentation/widgets/auth_pill_button.dart';
import '../../../coach/application/trainer_link_providers.dart'
    show currentAthleteLinkProvider, sessionShareRepositoryProvider;
import '../../application/exercise_feedback_providers.dart';
import '../../data/session_feedback_photo_upload_service.dart';
import '../../domain/exercise_feedback.dart';
import '../../domain/exercise_feedback_kind.dart';

/// What the composer returns through `Navigator.pop` when an entry was written.
///
/// Carries the kind so the caller can pick the right confirmation: a discomfort
/// report notifies the trainer, a plain comment does not, and the copy must not
/// promise a push that never fires.
class ExerciseFeedbackSubmission {
  const ExerciseFeedbackSubmission({required this.kind});

  final ExerciseFeedbackKind kind;
}

/// Opens the athlete → trainer feedback composer for one exercise (issue #628).
///
/// [setNumber] is the set the athlete tapped from; null means the feedback is
/// about the exercise as a whole.
Future<ExerciseFeedbackSubmission?> showExerciseFeedbackSheet({
  required BuildContext context,
  required String uid,
  required String sessionId,
  required String exerciseId,
  required String exerciseName,
  required int slotIndex,
  int? setNumber,
}) {
  return showModalBottomSheet<ExerciseFeedbackSubmission>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ExerciseFeedbackSheet(
      uid: uid,
      sessionId: sessionId,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      slotIndex: slotIndex,
      setNumber: setNumber,
    ),
  );
}

/// Bottom sheet where the athlete writes feedback for their trainer about the
/// exercise they are doing right now.
///
/// The counterpart of [CoachNote] (trainer → athlete, authored in the routine
/// editor): this direction is athlete → trainer, authored live and anchored to
/// the exercise — and optionally the exact set — that prompted it. The anchoring
/// is the point; the chat cannot express "third set of bench press".
///
/// Consent gate: feedback the trainer cannot read has no recipient. Rather than
/// hiding the entry point (which leaves the feature undiscoverable), the sheet
/// always opens and resolves the `session_shares` grant at submit time — the
/// athlete who just wrote "my shoulder hurts" is at peak motivation to share.
/// With no linked trainer at all there is nobody to grant to, so it says so
/// plainly instead of writing into a void.
///
/// A photo is optional and useful for what words are bad at: posture, the
/// machine this gym actually has, the spot that hurts. Either text or a photo is
/// required — never an empty report.
class ExerciseFeedbackSheet extends ConsumerStatefulWidget {
  const ExerciseFeedbackSheet({
    super.key,
    required this.uid,
    required this.sessionId,
    required this.exerciseId,
    required this.exerciseName,
    required this.slotIndex,
    this.setNumber,
  });

  final String uid;
  final String sessionId;
  final String exerciseId;
  final String exerciseName;
  final int slotIndex;
  final int? setNumber;

  @override
  ConsumerState<ExerciseFeedbackSheet> createState() =>
      _ExerciseFeedbackSheetState();
}

class _ExerciseFeedbackSheetState extends ConsumerState<ExerciseFeedbackSheet> {
  final TextEditingController _controller = TextEditingController();
  ExerciseFeedbackKind _kind = ExerciseFeedbackKind.comment;
  bool _submitting = false;
  String? _error;

  /// Local path of the picked photo, before upload. Null ⇒ text-only entry.
  String? _photoPath;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Picks a photo from the gallery or the camera.
  ///
  /// `imageQuality: 80` matches the chat composer — the upload has no
  /// programmatic compression step, so the picker is where size is controlled.
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _photoPath = picked.path;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppL10n.of(context).exerciseFeedbackPhotoError);
    }
  }

  void _removePhoto() => setState(() => _photoPath = null);

  Future<void> _submit() async {
    final l10n = AppL10n.of(context);
    final text = _controller.text.trim();
    // Text OR photo — no empty reports. The rules reject them too.
    if (text.isEmpty && _photoPath == null) {
      setState(() => _error = l10n.exerciseFeedbackEmptyError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // Resolved at submit time, not on open: the athlete may have granted the
      // share from another surface while this sheet was up.
      final granted = await ref
          .read(sessionShareRepositoryProvider)
          .grantedTrainerId(widget.uid);

      if (granted == null) {
        final link = await ref.read(currentAthleteLinkProvider.future);
        if (link == null) {
          if (!mounted) return;
          setState(() {
            _submitting = false;
            _error = l10n.exerciseFeedbackNoTrainerUnlinked;
          });
          return;
        }
        // Linked but not sharing: grant and continue in the same tap. Asking to
        // send this to their trainer IS consent for that trainer to read it.
        await ref
            .read(sessionShareRepositoryProvider)
            .grant(athleteId: widget.uid, trainerId: link.trainerId);
      }

      final repo = ref.read(exerciseFeedbackRepositoryProvider);

      // The doc id is allocated BEFORE the upload so the Storage object
      // references the real document from the first byte (same ordering as
      // PostPhotoUploadService).
      final feedbackId = repo.newFeedbackId(
        uid: widget.uid,
        sessionId: widget.sessionId,
      );

      SessionFeedbackPhoto? photo;
      final localPhoto = _photoPath;
      if (localPhoto != null) {
        photo =
            await ref.read(sessionFeedbackPhotoUploadServiceProvider).upload(
                  localPhoto,
                  sessionId: widget.sessionId,
                  feedbackId: feedbackId,
                );
      }

      try {
        await repo.createWithId(
          uid: widget.uid,
          sessionId: widget.sessionId,
          feedback: ExerciseFeedback(
            id: feedbackId,
            exerciseId: widget.exerciseId,
            exerciseName: widget.exerciseName,
            slotIndex: widget.slotIndex,
            setNumber: widget.setNumber,
            kind: _kind,
            text: text.isEmpty ? null : text,
            photoUrl: photo?.downloadUrl,
            photoPath: photo?.path,
            createdAt: DateTime.now().toUtc(),
          ),
        );
      } catch (e) {
        // The photo uploaded but the doc write failed: delete the object so it
        // does not linger unreferenced. Health data must not be orphaned.
        // Best-effort — the original error is what the athlete needs to see.
        if (photo != null) {
          await ref
              .read(sessionFeedbackPhotoUploadServiceProvider)
              .deleteByPath(photo.path)
              .catchError((_) => false);
        }
        rethrow;
      }

      if (!mounted) return;
      Navigator.of(context).pop(ExerciseFeedbackSubmission(kind: _kind));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l10n.exerciseFeedbackSendError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final setNumber = widget.setNumber;
    final subtitle = setNumber == null
        ? l10n.exerciseFeedbackSheetSubtitleExercise(widget.exerciseName)
        : l10n.exerciseFeedbackSheetSubtitleSet(widget.exerciseName, setNumber);

    return Padding(
      // Keeps the composer above the keyboard.
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.exerciseFeedbackSheetTitle,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  letterSpacing: 1.1,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _KindChip(
                    key: const Key('exercise_feedback_kind_comment'),
                    label: l10n.exerciseFeedbackKindComment,
                    selected: _kind == ExerciseFeedbackKind.comment,
                    color: palette.accent,
                    onTap: _submitting
                        ? null
                        : () => setState(
                            () => _kind = ExerciseFeedbackKind.comment),
                  ),
                  const SizedBox(width: 8),
                  _KindChip(
                    key: const Key('exercise_feedback_kind_discomfort'),
                    label: l10n.exerciseFeedbackKindDiscomfort,
                    selected: _kind == ExerciseFeedbackKind.discomfort,
                    color: palette.warning,
                    onTap: _submitting
                        ? null
                        : () => setState(
                            () => _kind = ExerciseFeedbackKind.discomfort),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                key: const Key('exercise_feedback_text_field'),
                controller: _controller,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) {
                  // Clears a stale "write something first" as soon as they do.
                  if (_error != null && value.trim().isNotEmpty) {
                    setState(() => _error = null);
                  }
                },
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: l10n.exerciseFeedbackTextHint,
                  hintStyle: GoogleFonts.barlow(
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                  filled: true,
                  fillColor: palette.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_photoPath != null)
                _PhotoPreview(
                  path: _photoPath!,
                  onRemove: _submitting ? null : _removePhoto,
                )
              else
                Row(
                  children: [
                    _PhotoButton(
                      key: const Key('exercise_feedback_photo_gallery'),
                      icon: TreinoIcon.image,
                      label: l10n.exerciseFeedbackPhotoGallery,
                      onTap: _submitting
                          ? null
                          : () => _pickPhoto(ImageSource.gallery),
                    ),
                    const SizedBox(width: 8),
                    _PhotoButton(
                      key: const Key('exercise_feedback_photo_camera'),
                      icon: TreinoIcon.camera,
                      label: l10n.exerciseFeedbackPhotoCamera,
                      onTap: _submitting
                          ? null
                          : () => _pickPhoto(ImageSource.camera),
                    ),
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('exercise_feedback_error'),
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.danger,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              AuthPillButton(
                label: l10n.exerciseFeedbackSend,
                showArrow: false,
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Type selector. Two mutually exclusive chips rather than a dropdown: the
/// athlete is mid-set and the choice has to cost one tap. 44pt floor so it
/// stays reachable (a11y baseline).
class _KindChip extends StatelessWidget {
  const _KindChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: TreinoTappable(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.15) : palette.bg,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(
                color: selected ? color : palette.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.8,
                color: selected ? color : palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Photo affordances ─────────────────────────────────────────────────────────

/// Gallery / camera picker button. Two explicit choices instead of one "add
/// photo" that opens a second menu: the athlete is mid-set and every extra tap
/// costs. 44pt floor (a11y baseline).
class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: TreinoTappable(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: palette.textMuted),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thumbnail of the picked photo with a remove affordance.
///
/// Reads the local file directly — the photo has not been uploaded yet at this
/// point, and will not be until the athlete taps send.
class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.path, required this.onRemove});

  final String path;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(path),
            key: const Key('exercise_feedback_photo_preview'),
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            // A picked file that cannot be decoded degrades to a placeholder
            // rather than throwing inside the sheet.
            errorBuilder: (_, __, ___) => Container(
              width: 56,
              height: 56,
              color: palette.bg,
              alignment: Alignment.center,
              child: Icon(TreinoIcon.image, size: 18, color: palette.textMuted),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.exerciseFeedbackPhotoAttached,
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          ),
        ),
        Semantics(
          button: true,
          label: l10n.exerciseFeedbackPhotoRemove,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(9999),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.close, size: 18, color: palette.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}
