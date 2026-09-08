import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/athlete_file_providers.dart';
import '../domain/athlete_file.dart';

/// Archivos que cualquier PF, actual o anterior, compartió con el alumno.
class AthleteFilesScreen extends ConsumerWidget {
  const AthleteFilesScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final provider = sharedAthleteFilesProvider(athleteId);
    final filesAsync = ref.watch(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.athleteFilesScreenTitle),
        Expanded(
          child: TreinoStateSwitcher(
            childKey: ValueKey(
              filesAsync.when(
                loading: () => 'loading',
                error: (_, __) => 'error',
                data: (files) => files.isEmpty ? 'empty' : 'data',
              ),
            ),
            child: filesAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: palette.accent),
              ),
              error: (_, __) => _MessageState(
                message: l10n.athleteFilesLoadError,
                retryLabel: l10n.coachRetryLabel,
                onRetry: () => ref.invalidate(provider),
              ),
              data: (files) => files.isEmpty
                  ? _MessageState(message: l10n.athleteFilesEmpty)
                  : _FilesList(files: files),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: () => _safePopOrCoach(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 24,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesList extends StatelessWidget {
  const _FilesList({required this.files});

  final List<AthleteFile> files;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => _FileRow(file: files[index]),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final AthleteFile file;

  Future<void> _open() async {
    final uri = Uri.tryParse(file.downloadUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final icon = switch (file.kind) {
      AthleteFileKind.pdf => TreinoIcon.filePdf,
      AthleteFileKind.image => TreinoIcon.image,
      AthleteFileKind.other => TreinoIcon.file,
    };
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMd(locale).format(file.uploadedAt);

    return Material(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: palette.accentText),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatSize(file.sizeBytes)} · $date',
                      style: GoogleFonts.barlow(
                        fontSize: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.message,
    this.retryLabel,
    this.onRetry,
  });

  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
            if (retryLabel != null && onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: Text(retryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

void _safePopOrCoach(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/coach');
  }
}
