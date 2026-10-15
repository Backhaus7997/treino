import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/plan_import_providers.dart';
import '../data/periodized_template_builder.dart';
import '../domain/periodized_plan.dart';
import '../infrastructure/browser_download.dart';
import 'widgets/import_plan_widgets.dart';

/// Upload screen del Coach Hub — paso 1 del flujo de import.
///
/// 1. Botón "Descargar plantilla" → genera el xlsx periodizado en memoria +
///    browser download
/// 2. File picker para que el PF elija un xlsx
/// 3. Botón "Procesar" → parseo + match (client-side) → vista previa. Si el
///    parser encuentra errores se muestran TODOS con su celda y no se avanza.
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
  List<ImportDiagnostic> _diagnostics = const [];

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _diagnostics = const [];
    });
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
      final bytes = buildPeriodizedTemplateBytes();
      triggerBrowserDownload(
        bytes: bytes,
        filename: 'treino-plantilla-plan.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos generar la plantilla.');
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  /// Nombre inicial de la rutina: el del archivo sin la extensión.
  static String _routineNameOf(String fileName) {
    final base =
        fileName.replaceFirst(RegExp(r'\.xlsx$', caseSensitive: false), '');
    final clean = base.trim();
    return clean.isEmpty ? 'Plan importado' : clean;
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
      _diagnostics = const [];
    });

    try {
      final outcome =
          await ref.read(planImportRepositoryProvider).parseAndMatch(
                bytes: Uint8List.fromList(bytes),
                defaultName: _routineNameOf(file.name),
              );
      final draft = outcome.draft;
      if (draft == null) {
        if (!mounted) return;
        setState(() {
          _diagnostics = outcome.diagnostics;
          _submitting = false;
        });
        return;
      }
      ref.read(periodizedImportProvider.notifier).state = draft;
      if (!mounted) return;
      setState(() => _submitting = false);
      // push (not go): preview is a sub-step, so pop() from it returns here
      // with the picked file still in state and the browser Back works.
      context.push('/upload-plan/preview');
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
    final errors = _diagnostics.where((d) => d.isError).toList();

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(palette: palette),
                  const SizedBox(height: AppSpacing.s20),
                  _TemplateCard(
                    palette: palette,
                    onDownload: _downloadTemplate,
                    loading: _downloadingTemplate,
                  ),
                  const SizedBox(height: AppSpacing.s18),
                  _UploadCard(
                    palette: palette,
                    file: file,
                    onPick: _pickFile,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.s14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: importText(palette.danger,
                          size: AppTextSize.bodyDense),
                    ),
                  ],
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s14),
                    _ErrorsCard(palette: palette, errors: errors),
                  ],
                  const SizedBox(height: AppSpacing.s18),
                  TreinoButton(
                    label: 'PROCESAR PLAN',
                    expand: true,
                    loading: _submitting,
                    onPressed: _pickedFile == null ? null : _processFile,
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

class _ErrorsCard extends StatelessWidget {
  const _ErrorsCard({required this.palette, required this.errors});
  final AppPalette palette;
  final List<ImportDiagnostic> errors;

  @override
  Widget build(BuildContext context) {
    return ImportCard(
      borderColor: palette.danger,
      background: palette.danger.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            errors.length == 1
                ? 'Hay 1 error en el archivo. Corregilo y volvé a subirlo.'
                : 'Hay ${errors.length} errores en el archivo. Corregilos y '
                    'volvé a subirlo.',
            style: importText(
              palette.textPrimary,
              size: AppTextSize.body,
              weight: AppFonts.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          ImportDiagnosticsList(diagnostics: errors),
        ],
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
        TreinoIconButton(
          icon: TreinoIcon.arrowLeft,
          tooltip: 'Volver',
          color: palette.textPrimary,
          // pop back to the dashboard (the push origin); fall back to go()
          // when there's no stack to pop (e.g. deep-linked directly here).
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TREINO COACH HUB',
                style: TextStyle(
                  fontFamily: AppFonts.barlowCondensed,
                  color: palette.highlight,
                  fontSize: AppTextSize.caption,
                  fontWeight: AppFonts.w700,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: AppSpacing.hairline),
              Text(
                'IMPORTAR PLAN',
                style: TextStyle(
                  fontFamily: AppFonts.barlowCondensed,
                  color: palette.textPrimary,
                  fontSize: AppTextSize.heading,
                  fontWeight: AppFonts.w700,
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
    return ImportCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.download, color: palette.accent),
          const SizedBox(width: AppSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿No tenés la plantilla?',
                  style: importText(
                    palette.textPrimary,
                    size: AppTextSize.bodyLarge,
                    weight: AppFonts.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  'Descargá la plantilla: una hoja "Programa" con un bloque '
                  'por día y una columna por semana, y una hoja '
                  '"Instrucciones" con la notación. Es la única que '
                  'aceptamos.',
                  style: importText(
                    palette.textMuted,
                    size: AppTextSize.bodyDense,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                TreinoButton(
                  label: 'Descargar plantilla',
                  variant: TreinoButtonVariant.secondaryAccent,
                  loading: loading,
                  onPressed: onDownload,
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
    final picked = file;
    return ImportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subí tu plan',
            style: importText(
              palette.textPrimary,
              size: AppTextSize.bodyLarge,
              weight: AppFonts.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.hairline),
          Text(
            'Archivo .xlsx, hasta 10 MB.',
            style: importText(palette.textMuted, size: AppTextSize.bodyDense),
          ),
          const SizedBox(height: AppSpacing.s14),
          if (picked == null)
            TreinoButton(
              label: 'Elegir archivo',
              icon: TreinoIcon.upload,
              variant: TreinoButtonVariant.secondaryAccent,
              expand: true,
              onPressed: onPick,
            )
          else
            ImportCard(
              padding: AppSpacing.s12,
              background: palette.bg,
              child: Row(
                children: [
                  Icon(TreinoIcon.fileXls, color: palette.accent),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          picked.name,
                          style: importText(
                            palette.textPrimary,
                            weight: AppFonts.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatBytes(picked.size),
                          style: importText(
                            palette.textMuted,
                            size: AppTextSize.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TreinoButton(
                    label: 'Cambiar',
                    variant: TreinoButtonVariant.ghostAccent,
                    size: TreinoButtonSize.sm,
                    onPressed: onPick,
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
