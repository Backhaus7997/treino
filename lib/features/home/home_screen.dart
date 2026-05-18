import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../profile/application/user_providers.dart';
import '../workout/application/session_providers.dart';
import '../workout/domain/session.dart';
import '../workout/domain/set_log.dart';
import '../workout/presentation/widgets/resume_session_modal.dart';
import 'widgets/empezar_entrenamiento_card.dart';
import 'widgets/esta_semana_card.dart';
import 'widgets/home_header.dart';

/// Home screen — single ConsumerWidget that owns the one ref.watch call
/// (REQ-HOME-SCREEN-001). No Scaffold, AppBackground, or SafeArea — those
/// are provided by _ShellScaffold in router.dart (REQ-HOME-SCREEN-002).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    // Resume-on-reopen listener (REQ-SESSION-RESUME-002 / Decision 12).
    // Watches activeSessionForUidProvider; cuando llega un record no-null
    // disparamos el ResumeSessionModal en el siguiente frame.
    ref.listen<AsyncValue<({Session session, List<SetLog> setLogs})?>>(
      activeSessionForUidProvider,
      (prev, next) {
        if (prev is AsyncData &&
            identical((prev as AsyncData).value, next.value)) {
          return;
        }
        _maybeShowResumePrompt(context, ref, next);
      },
    );

    final Widget headerOrSkeleton = profileAsync.when(
      data: (profile) => HomeHeader(profile: profile),
      loading: () => const _HomeHeaderSkeleton(),
      error: (_, __) => const HomeHeader(profile: null),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        physics: const ClampingScrollPhysics(),
        children: [
          headerOrSkeleton,
          const SizedBox(height: 20),
          const EmpezarEntrenamientoCard(),
          const SizedBox(height: 12),
          const EstaSemanaCard(),
        ],
      ),
    );
  }
}

void _maybeShowResumePrompt(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<({Session session, List<SetLog> setLogs})?> next,
) {
  final record = next.valueOrNull;
  if (record == null) return;
  final session = record.session;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => ResumeSessionModal(
        session: session,
        onContinue: () {
          Navigator.of(dialogCtx, rootNavigator: true).pop();
          context.push('/workout/session/resume/${session.id}');
        },
        onDiscard: () async {
          final repo = ref.read(sessionRepositoryProvider);
          await repo.finish(
            uid: session.uid,
            sessionId: session.id,
            finishedAt: DateTime.now(),
            totalVolumeKg: _sumVolume(record.setLogs),
            durationMin: _elapsedMin(session.startedAt),
          );
          if (dialogCtx.mounted) {
            Navigator.of(dialogCtx, rootNavigator: true).pop();
          }
          ref.invalidate(activeSessionForUidProvider);
        },
      ),
    );
  });
}

double _sumVolume(List<SetLog> logs) =>
    logs.fold<double>(0, (acc, l) => acc + l.reps * l.weightKg);

int _elapsedMin(DateTime startedAt) {
  final secs = DateTime.now().difference(startedAt).inSeconds;
  if (secs <= 0) return 1;
  return (secs + 59) ~/ 60;
}

/// Private placeholder that occupies the same 56 px height as [HomeHeader]
/// during [AsyncLoading], preventing a layout jump (REQ-HOME-PROVIDER-003).
class _HomeHeaderSkeleton extends StatelessWidget {
  const _HomeHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 56);
  }
}
