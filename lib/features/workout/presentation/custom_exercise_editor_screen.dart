import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/custom_exercise_providers.dart';
import '../application/session_providers.dart' show currentUidProvider;
import '../domain/custom_exercise.dart';
import 'widgets/exercise_video_player.dart';

/// Create or edit a trainer's custom exercise. Routed at
/// `/profile/my-exercises/new` (create) or `/profile/my-exercises/:exId`
/// (edit). On submit the user is bounced back to the list.
class CustomExerciseEditorScreen extends ConsumerStatefulWidget {
  const CustomExerciseEditorScreen({super.key, this.exerciseId});

  final String? exerciseId;

  bool get isEditing => exerciseId != null && exerciseId != 'new';

  @override
  ConsumerState<CustomExerciseEditorScreen> createState() =>
      _CustomExerciseEditorScreenState();
}

class _CustomExerciseEditorScreenState
    extends ConsumerState<CustomExerciseEditorScreen> {
  final _nameCtrl = TextEditingController();
  final _muscleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _videoCtrl = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _deleting = false;
  String _videoPreviewUrl = '';
  bool _uploadingVideo = false;
  double _uploadProgress = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _muscleCtrl.dispose();
    _descCtrl.dispose();
    _videoCtrl.dispose();
    super.dispose();
  }

  void _hydrate(CustomExercise ex) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = ex.name;
    _muscleCtrl.text = ex.muscleGroup;
    _descCtrl.text = ex.description;
    _videoCtrl.text = ex.videoUrl ?? '';
    _videoPreviewUrl = ex.videoUrl ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';

    CustomExercise? existing;
    if (widget.isEditing && uid.isNotEmpty) {
      final listAsync = ref.watch(customExercisesForTrainerStreamProvider(uid));
      final list = listAsync.valueOrNull ?? const <CustomExercise>[];
      existing = list.where((e) => e.id == widget.exerciseId).firstOrNull;
      if (existing != null) _hydrate(existing);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                behavior: HitTestBehavior.opaque,
                child:
                    Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
              ),
              const SizedBox(width: 14),
              Text(
                widget.isEditing ? 'EDITAR EJERCICIO' : 'NUEVO EJERCICIO',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 1.0,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              _Label('Nombre', palette: palette),
              const SizedBox(height: 6),
              _Field(
                  controller: _nameCtrl,
                  hint: 'Ej: Sentadilla búlgara',
                  palette: palette),
              const SizedBox(height: 14),
              _Label('Grupo muscular', palette: palette),
              const SizedBox(height: 6),
              _Field(
                  controller: _muscleCtrl,
                  hint: 'Ej: cuádriceps',
                  palette: palette),
              const SizedBox(height: 14),
              _Label('Descripción / cues', palette: palette),
              const SizedBox(height: 6),
              _Field(
                  controller: _descCtrl,
                  hint: 'Notas técnicas opcionales',
                  palette: palette,
                  maxLines: 3),
              const SizedBox(height: 14),
              _Label('Video del ejercicio', palette: palette),
              const SizedBox(height: 6),
              _Field(
                controller: _videoCtrl,
                hint: 'Pegá un link de YouTube',
                palette: palette,
                onChanged: (v) => setState(() => _videoPreviewUrl = v),
              ),
              const SizedBox(height: 8),
              _UploadVideoButton(
                palette: palette,
                uploading: _uploadingVideo,
                progress: _uploadProgress,
                onTap: _uploadingVideo ? null : () => _onPickAndUpload(context),
              ),
              const SizedBox(height: 6),
              Text(
                isFirebaseStorageVideo(_videoPreviewUrl)
                    ? 'Video propio. Se reproduce adentro de TREINO.'
                    : 'YouTube → tu alumno ve el thumbnail; el video se abre en una hoja de Safari sin salir de la app. Subí tu video para que reproduzca inline.',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 11,
                  height: 1.4,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              ExerciseVideoPlayer(
                key: ValueKey(_videoPreviewUrl),
                videoUrl: _videoPreviewUrl.isEmpty ? null : _videoPreviewUrl,
              ),
              if (existing != null) ...[
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _deleting ? null : () => _onDelete(context, ref),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.highlight, width: 1),
                    foregroundColor: palette.highlight,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: _deleting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: palette.highlight),
                        )
                      : Text(
                          'BORRAR EJERCICIO',
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _saving ? null : () => _onSave(context, ref, existing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: palette.bg),
                      )
                    : Text(
                        widget.isEditing
                            ? 'GUARDAR CAMBIOS'
                            : 'GUARDAR EJERCICIO',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onPickAndUpload(BuildContext context) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
    } catch (_) {
      if (!context.mounted) return;
      _toast(context, 'No pudimos abrir la galería.');
      return;
    }
    if (picked == null) return;

    setState(() {
      _uploadingVideo = true;
      _uploadProgress = 0;
    });
    try {
      final service = ref.read(customExerciseVideoUploadServiceProvider);
      final url = await service.upload(
        picked.path,
        onProgress: (fraction) {
          if (!mounted) return;
          setState(() => _uploadProgress = fraction);
        },
      );
      if (!mounted) return;
      setState(() {
        _videoCtrl.text = url;
        _videoPreviewUrl = url;
      });
    } catch (_) {
      if (!context.mounted) return;
      _toast(context, 'No pudimos subir el video.');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingVideo = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _onSave(
    BuildContext context,
    WidgetRef ref,
    CustomExercise? existing,
  ) async {
    final uid = ref.read(currentUidProvider) ?? '';
    if (uid.isEmpty) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast(context, 'Poné un nombre al ejercicio.');
      return;
    }
    final videoUrl = _videoCtrl.text.trim();

    setState(() => _saving = true);
    try {
      final repo = ref.read(customExerciseRepositoryProvider);
      CustomExercise? created;
      if (existing != null) {
        await repo.update(existing.copyWith(
          name: name,
          muscleGroup: _muscleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          videoUrl: videoUrl.isEmpty ? null : videoUrl,
        ));
      } else {
        created = await repo.create(
          trainerId: uid,
          name: name,
          muscleGroup: _muscleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          videoUrl: videoUrl.isEmpty ? null : videoUrl,
        );
      }
      if (!context.mounted) return;
      // Return the freshly created exercise so callers like the picker
      // sheet can auto-select it. Edits still pop with null (no contract
      // change for the regular library list).
      Navigator.of(context).pop(created);
    } catch (_) {
      if (!context.mounted) return;
      _toast(context, 'No pudimos guardar el ejercicio.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onDelete(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUidProvider) ?? '';
    final exId = widget.exerciseId;
    if (uid.isEmpty || exId == null || exId == 'new') return;
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Borrar ejercicio',
            style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary)),
        content: Text(
          'Esta acción no se puede deshacer. Los planes que ya tienen este ejercicio asignado no se ven afectados (guardan el nombre por separado).',
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: palette.textPrimary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: palette.highlight,
                foregroundColor: palette.bg),
            child: Text('Borrar',
                style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(customExerciseRepositoryProvider)
          .delete(trainerId: uid, id: exId);
      if (!context.mounted) return;
      context.pop();
    } catch (_) {
      if (!context.mounted) return;
      _toast(context, 'No pudimos borrar el ejercicio.');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.palette});
  final String text;
  final AppPalette palette;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.barlow(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: palette.textMuted),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.palette,
    this.maxLines = 1,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final AppPalette palette;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: GoogleFonts.barlow(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.barlow(
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: palette.textMuted),
        filled: true,
        fillColor: palette.bgCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
    );
  }
}

class _UploadVideoButton extends StatelessWidget {
  const _UploadVideoButton({
    required this.palette,
    required this.uploading,
    required this.progress,
    required this.onTap,
  });

  final AppPalette palette;
  final bool uploading;
  final double progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            border: Border.all(color: palette.border, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                uploading ? TreinoIcon.play : TreinoIcon.plus,
                size: 18,
                color: palette.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uploading
                          ? 'Subiendo video — ${(progress * 100).clamp(0, 100).toInt()}%'
                          : 'Subir mi propio video',
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      uploading
                          ? 'No cierres la pantalla'
                          : 'MP4 / MOV — reproduce inline en TREINO',
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w400,
                        fontSize: 11,
                        color: palette.textMuted,
                      ),
                    ),
                    if (uploading) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          minHeight: 4,
                          backgroundColor:
                              palette.border.withValues(alpha: 0.6),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(palette.accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
