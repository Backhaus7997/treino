import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/exercise_feedback_submitter.dart';
import '../../domain/exercise_feedback.dart';

/// Abre el sheet de "Comentar / Reportar" para un ejercicio de la sesión.
///
/// [setNumber] null ⇒ el reporte queda a nivel ejercicio, sin serie.
Future<void> showExerciseFeedbackSheet(
  BuildContext context, {
  required String uid,
  required String sessionId,
  required String exerciseId,
  required String exerciseName,
  int? setNumber,
  ImagePicker? picker,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.of(context).bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => ExerciseFeedbackSheet(
      uid: uid,
      sessionId: sessionId,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      picker: picker,
    ),
  );
}

/// Lo que el alumno le dice a su PF durante la sesión (#628): texto libre,
/// foto opcional y el chip de tipo.
///
/// Contraparte simétrica de [CoachNote], que es el mismo canal en la otra
/// dirección. Y el motivo de que exista: hasta acá el alumno tenía chat —que
/// llega descolgado del ejercicio— o esperar al post-entreno, que llega tarde
/// por definición. Una molestia articular reportada tarde es una lesión que se
/// pudo evitar.
///
/// El sheet NO toca el estado de la sesión: no pausa el cronómetro de
/// descanso, no pierde la serie en curso, y no escribe nada hasta que el
/// usuario toca ENVIAR.
class ExerciseFeedbackSheet extends ConsumerStatefulWidget {
  const ExerciseFeedbackSheet({
    required this.uid,
    required this.sessionId,
    required this.exerciseId,
    required this.exerciseName,
    this.setNumber,
    this.picker,
    super.key,
  });

  final String uid;
  final String sessionId;
  final String exerciseId;
  final String exerciseName;

  /// Serie sobre la que se reporta, o null para el ejercicio entero.
  final int? setNumber;

  /// Inyectable para tests de widget — sin esto el picker abre un canal de
  /// plataforma que en el test host no existe.
  final ImagePicker? picker;

  @override
  ConsumerState<ExerciseFeedbackSheet> createState() =>
      _ExerciseFeedbackSheetState();
}

class _ExerciseFeedbackSheetState extends ConsumerState<ExerciseFeedbackSheet> {
  /// Máximo de caracteres del cuadro de texto. Más estricto que el cap de
  /// `firestore.rules` (2000) a propósito: esto se escribe con una mano, entre
  /// series. Si alguna vez se sube, el techo del servidor manda.
  static const int _maxTextLength = 500;

  final TextEditingController _textController = TextEditingController();
  ExerciseFeedbackKind _kind = ExerciseFeedbackKind.comment;
  String? _localPhotoPath;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Habilita/deshabilita ENVIAR sin que el padre se entere: es estado de
    // presentación local, no de negocio (AGENTS.md regla 6).
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _hasContent =>
      _textController.text.trim().isNotEmpty || _localPhotoPath != null;

  Future<void> _pickPhoto(ImageSource source) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picker = widget.picker ?? ImagePicker();
    try {
      final file = await picker.pickImage(
        source: source,
        // Bajar la resolución acá es lo que hace que el cap de 15 MB casi
        // nunca se toque: la foto es para que el PF vea la postura o dónde
        // duele, no para imprimirla.
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _localPhotoPath = file.path);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.exerciseFeedbackPhotoError)),
      );
    }
  }

  Future<void> _onSubmit() async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _submitting = true);
    try {
      await ref.read(exerciseFeedbackSubmitterProvider).submit(
            uid: widget.uid,
            sessionId: widget.sessionId,
            exerciseId: widget.exerciseId,
            exerciseName: widget.exerciseName,
            kind: _kind,
            setNumber: widget.setNumber,
            text: _textController.text,
            localPhotoPath: _localPhotoPath,
          );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.exerciseFeedbackSuccess)),
      );
    } on ArgumentError catch (e) {
      // Foto demasiado pesada o formato no soportado — el mensaje del guard
      // client-side es accionable; el permission-denied del server no.
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
            content: Text(e.message?.toString() ?? l10n.exerciseFeedbackError)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.exerciseFeedbackError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.exerciseFeedbackSheetTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 0.5,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.hairline),
            Text(
              widget.setNumber == null
                  ? widget.exerciseName
                  : l10n.exerciseFeedbackSheetAnchorSet(
                      widget.exerciseName,
                      widget.setNumber!,
                    ),
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 18),

            // Chips de tipo. Separación fija entre los dos, no repartida a lo
            // ancho: son dos opciones, no una barra segmentada.
            Row(
              children: [
                _KindChip(
                  label: l10n.exerciseFeedbackKindComment,
                  icon: TreinoIcon.chat,
                  selected: _kind == ExerciseFeedbackKind.comment,
                  onTap: _submitting
                      ? null
                      : () =>
                          setState(() => _kind = ExerciseFeedbackKind.comment),
                ),
                const SizedBox(width: 8),
                _KindChip(
                  label: l10n.exerciseFeedbackKindDiscomfort,
                  icon: TreinoIcon.warning,
                  selected: _kind == ExerciseFeedbackKind.discomfort,
                  onTap: _submitting
                      ? null
                      : () => setState(
                          () => _kind = ExerciseFeedbackKind.discomfort),
                ),
              ],
            ),
            if (_kind == ExerciseFeedbackKind.discomfort) ...[
              const SizedBox(height: 8),
              // Transparencia deliberada: el usuario tiene que saber que ESTE
              // chip le avisa al PF y el otro no. Sin esto, o reporta todo
              // como molestia "por las dudas", o no reporta nada.
              Text(
                l10n.exerciseFeedbackDiscomfortNotice,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 18),

            TextField(
              key: const Key('exercise_feedback_text'),
              controller: _textController,
              enabled: !_submitting,
              maxLength: _maxTextLength,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.barlow(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.exerciseFeedbackTextHint,
                hintStyle: GoogleFonts.barlow(color: palette.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.border),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.accent),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
            const SizedBox(height: 8),

            if (_localPhotoPath == null)
              Row(
                children: [
                  _PhotoSourceButton(
                    key: const Key('exercise_feedback_camera'),
                    label: l10n.exerciseFeedbackPhotoCamera,
                    icon: TreinoIcon.image,
                    onTap: _submitting
                        ? null
                        : () => _pickPhoto(ImageSource.camera),
                  ),
                  const SizedBox(width: 8),
                  _PhotoSourceButton(
                    key: const Key('exercise_feedback_gallery'),
                    label: l10n.exerciseFeedbackPhotoGallery,
                    icon: TreinoIcon.attach,
                    onTap: _submitting
                        ? null
                        : () => _pickPhoto(ImageSource.gallery),
                  ),
                ],
              )
            else
              _PhotoPreview(
                path: _localPhotoPath!,
                onRemove: _submitting
                    ? null
                    : () => setState(() => _localPhotoPath = null),
                removeLabel: l10n.exerciseFeedbackPhotoRemove,
              ),
            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.exerciseFeedbackCancel,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.8,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('exercise_feedback_submit'),
                    // "Nada de reportes vacíos" (#628) empieza acá: el botón
                    // ni se habilita. El repositorio y firestore.rules lo
                    // vuelven a chequear — tres capas para la misma regla,
                    // porque las tres protegen cosas distintas (UX, error
                    // accionable, y el dato en sí).
                    onPressed: (_hasContent && !_submitting) ? _onSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      // NO `palette.bg`: ese token invierte entre temas y en
                      // light da 1.57:1 sobre el mint. `foreground` devuelve
                      // ink950 invariante — AGENTS.md regla 2.
                      foregroundColor: TreinoButtonTokens.foreground(context),
                      disabledBackgroundColor:
                          palette.accent.withValues(alpha: 0.5),
                      disabledForegroundColor:
                          TreinoButtonTokens.foreground(context),
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                TreinoButtonTokens.foreground(context),
                              ),
                            ),
                          )
                        : Text(
                            l10n.exerciseFeedbackSubmit,
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.8,
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

/// Chip de tipo. Dos estados: elegido (acento) y no elegido (borde).
class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? palette.accent : palette.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.6,
                  color: selected ? palette.accent : palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoSourceButton extends StatelessWidget {
  const _PhotoSourceButton({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: palette.textMuted),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.6,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.path,
    required this.onRemove,
    required this.removeLabel,
  });

  final String path;
  final VoidCallback? onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.file(
            File(path),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            // La miniatura se decodifica a su tamaño real de pintado — sin
            // esto, una foto de cámara entra entera en memoria para mostrarse
            // en 64 px, justo mientras el player está corriendo.
            cacheWidth: 128,
            cacheHeight: 128,
            errorBuilder: (_, __, ___) => Container(
              width: 64,
              height: 64,
              color: palette.bg,
              child: Icon(TreinoIcon.image, color: palette.textMuted),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          button: true,
          child: GestureDetector(
            key: const Key('exercise_feedback_remove_photo'),
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Text(
                removeLabel,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.6,
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
