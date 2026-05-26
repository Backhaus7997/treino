import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/plan_import_providers.dart';
import '../data/plan_import_repository.dart';
import '../data/template_builder.dart';
import '../infrastructure/browser_download.dart';

/// Upload screen del Coach Hub — paso 1 del flujo de import.
///
/// 1. Botón "Descargar template" → genera xlsx en memoria + browser download
/// 2. File picker para que el PF elija un xlsx
/// 3. Botón "Procesar" → parseAndMatch (client-side) → preview screen
class CoachHubUploadPlanScreen extends ConsumerStatefulWidget {
  const CoachHubUploadPlanScreen({super.key});

  @override
  ConsumerState<CoachHubUploadPlanScreen> createState() =>
      _CoachHubUploadPlanScreenState();
}

class _CoachHubUploadPlanScreenState
    extends ConsumerState<CoachHubUploadPlanScreen> {
  PlatformFile? _pickedFile;
  bool _submitting = false;
  bool _downloadingTemplate = false;
  String? _error;

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _pickedFile = result.files.first);
  }

  Future<void> _downloadTemplate() async {
    if (_downloadingTemplate) return;
    setState(() {
      _downloadingTemplate = true;
      _error = null;
    });

    try {
      final bytes = buildPlanTemplateBytes();
      triggerBrowserDownload(
        bytes: bytes,
        filename: 'treino-plan-template.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos generar el template.');
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _processFile() async {
    if (_submitting) return;
    final file = _pickedFile;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'No pudimos leer el archivo. Volvé a elegirlo.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final parsed = await ref
          .read(planImportRepositoryProvider)
          .parseAndMatch(bytes: Uint8List.fromList(bytes));
      ref.read(parsedPlanProvider.notifier).state = parsed;
      if (!mounted) return;
      context.go('/upload-plan/preview');
    } on PlanImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos procesar el archivo. Probá de nuevo.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final file = _pickedFile;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(palette: palette),
                  const SizedBox(height: 20),
                  _TemplateCard(
                    palette: palette,
                    onDownload: _downloadTemplate,
                    loading: _downloadingTemplate,
                  ),
                  const SizedBox(height: 18),
                  _UploadCard(
                    palette: palette,
                    file: file,
                    onPick: _pickFile,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.danger, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed:
                        (_pickedFile == null || _submitting) ? null : _processFile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                      disabledBackgroundColor:
                          palette.accent.withValues(alpha: 0.3),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.bg,
                            ),
                          )
                        : Text(
                            'PROCESAR PLAN',
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 1.4,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => context.go('/dashboard'),
          icon: Icon(TreinoIcon.arrowLeft, color: palette.textPrimary),
          tooltip: 'Volver',
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TREINO COACH HUB',
                style: GoogleFonts.barlowCondensed(
                  color: palette.highlight,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'IMPORTAR PLAN',
                style: GoogleFonts.barlowCondensed(
                  color: palette.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.palette,
    required this.onDownload,
    required this.loading,
  });
  final AppPalette palette;
  final VoidCallback onDownload;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.download, color: palette.accent, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿No tenés el template?',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Descargá el Excel base con las hojas y columnas '
                  'que esperamos: Plan + Día 1, Día 2…',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: loading ? null : onDownload,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.accent,
                    side: BorderSide(color: palette.accent),
                    shape: const StadiumBorder(),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Descargar template'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.palette,
    required this.file,
    required this.onPick,
  });
  final AppPalette palette;
  final PlatformFile? file;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subí tu plan',
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Archivo .xlsx, hasta 10 MB.',
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (file == null)
            OutlinedButton.icon(
              onPressed: onPick,
              icon: Icon(TreinoIcon.upload, size: 18, color: palette.accent),
              label: const Text('Elegir archivo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.accent,
                side: BorderSide(color: palette.accent),
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Icon(TreinoIcon.fileXls, color: palette.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          file!.name,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatBytes(file!.size),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onPick,
                    child: const Text('Cambiar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
