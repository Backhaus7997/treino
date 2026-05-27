import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../workout/application/session_providers.dart' show currentUidProvider;
import '../application/commercial_plan_providers.dart';
import '../domain/commercial_plan.dart';

/// Trainer-side list of commercial plans. Stacked cards (one per plan), with
/// the active set on top and archived dimmed below. Floating CTA "+ NUEVO
/// PLAN" pushes the editor.
class CommercialPlansListScreen extends ConsumerWidget {
  const CommercialPlansListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';

    if (uid.isEmpty) {
      return _Scaffold(
        palette: palette,
        body: Center(
          child: Text(
            'Iniciá sesión para ver tus planes.',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
          ),
        ),
      );
    }

    final plansAsync =
        ref.watch(commercialPlansForTrainerStreamProvider(uid));

    return _Scaffold(
      palette: palette,
      onCreateTap: () => context.push('/profile/commercial-plans/new'),
      body: plansAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
        error: (_, __) => Center(
          child: Text(
            'No pudimos cargar tus planes.',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
          ),
        ),
        data: (plans) {
          if (plans.isEmpty) return _EmptyState(palette: palette);
          final active = plans
              .where((p) => p.status == CommercialPlanStatus.active)
              .toList();
          final archived = plans
              .where((p) => p.status == CommercialPlanStatus.archived)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
            physics: const ClampingScrollPhysics(),
            children: [
              if (active.isNotEmpty) ...[
                for (final p in active) ...[
                  _PlanCard(plan: p, palette: palette),
                  const SizedBox(height: 12),
                ],
              ],
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'ARCHIVADOS',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                for (final p in archived) ...[
                  Opacity(
                    opacity: 0.55,
                    child: _PlanCard(plan: p, palette: palette),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Scaffold extends StatelessWidget {
  const _Scaffold({
    required this.palette,
    required this.body,
    this.onCreateTap,
  });

  final AppPalette palette;
  final Widget body;
  final VoidCallback? onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  TreinoIcon.back,
                  size: 20,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'PLANES COMERCIALES',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 1.0,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: body),
        if (onCreateTap != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onCreateTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    '+ NUEVO PLAN',
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(TreinoIcon.sparkle, size: 48, color: palette.textMuted),
            const SizedBox(height: 18),
            Text(
              'Todavía no creaste planes.',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Armá tu primer plan comercial — definí el precio, la duración y qué incluye.',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.palette});
  final CommercialPlan plan;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.push('/profile/commercial-plans/${plan.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border, width: 1),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name.toUpperCase(),
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 0.5,
                            color: palette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          plan.billingFrequency.label,
                          style: GoogleFonts.barlow(
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${_formatPrice(plan.priceArs)}',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.durationMonths == 1
                            ? '1 mes'
                            : '${plan.durationMonths} meses',
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (plan.shortDescription.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  plan.shortDescription,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                    height: 1.4,
                    color: palette.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (plan.includes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final inc in plan.includes)
                      _IncludeChip(label: inc.label, palette: palette),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatPrice(int amount) {
    final s = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

class _IncludeChip extends StatelessWidget {
  const _IncludeChip({required this.label, required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withAlpha(30),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: palette.accent, width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w500,
          fontSize: 11,
          color: palette.accent,
        ),
      ),
    );
  }
}
