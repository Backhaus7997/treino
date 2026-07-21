/// Tests for pickAthleteForPago — remediación CRITICAL-1 (verify ronda 1,
/// Fase 9 Pagos). El picker resuelve el roster REAL del trainer
/// (`trainerLinksStreamProvider`) para elegir el `athleteId` al que se le
/// registra un pago desde el CTA trainer-wide "+ Registrar pago".
///
/// REQ-PAGW-ACTION-003 (ADR-F9-06).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/athlete_picker_dialog.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

TrainerLink _link({
  required String id,
  required String athleteId,
  required TrainerLinkStatus status,
}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

/// Widget de prueba: dispara [pickAthleteForPago] y expone el resultado como
/// texto (`result:<athleteId>` o `result:null`) para poder assertear sin
/// depender del valor de retorno de `tester.tap` (que no propaga futures).
class _Trigger extends StatefulWidget {
  const _Trigger();

  @override
  State<_Trigger> createState() => _TriggerState();
}

class _TriggerState extends State<_Trigger> {
  String? _result;
  bool _resolved = false;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: const Key('trigger'),
            onPressed: () async {
              final picked = await pickAthleteForPago(context, ref);
              setState(() {
                _result = picked;
                _resolved = true;
              });
            },
            child: const Text('Trigger'),
          ),
          if (_resolved) Text('result:${_result ?? 'null'}'),
        ],
      ),
    );
  }
}

Widget _wrap({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(body: _Trigger()),
      ),
    );

List<Override> _profilesOverride(Map<String, String> namesByAthleteId) => [
      userPublicProfilesBatchProvider.overrideWith((ref, key) async => {
            for (final entry in namesByAthleteId.entries)
              entry.key: UserPublicProfile(
                uid: entry.key,
                displayName: entry.value,
              ),
          }),
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('pickAthleteForPago (REQ-PAGW-ACTION-003)', () {
    testWidgets(
        'SCENARIO 1 — lista solo alumnos active/paused, excluye pending y '
        'terminated', (tester) async {
      final links = [
        _link(id: 'l1', athleteId: 'athlete-1', status: TrainerLinkStatus.active),
        _link(id: 'l2', athleteId: 'athlete-2', status: TrainerLinkStatus.paused),
        _link(id: 'l3', athleteId: 'athlete-3', status: TrainerLinkStatus.pending),
        _link(
            id: 'l4',
            athleteId: 'athlete-4',
            status: TrainerLinkStatus.terminated),
      ];

      await tester.pumpWidget(_wrap(overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        ..._profilesOverride({
          'athlete-1': 'Juana Pérez',
          'athlete-2': 'Martín Gómez',
          'athlete-3': 'Solicitud Pendiente',
          'athlete-4': 'Ex Alumno',
        }),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(find.text('Juana Pérez'), findsOneWidget);
      expect(find.text('Martín Gómez'), findsOneWidget);
      expect(find.text('Solicitud Pendiente'), findsNothing);
      expect(find.text('Ex Alumno'), findsNothing);
    });

    testWidgets(
        'SCENARIO 2 — tocar un alumno cierra el diálogo y devuelve su '
        'athleteId', (tester) async {
      final links = [
        _link(id: 'l1', athleteId: 'athlete-1', status: TrainerLinkStatus.active),
      ];

      await tester.pumpWidget(_wrap(overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        ..._profilesOverride({'athlete-1': 'Juana Pérez'}),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Juana Pérez'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('result:athlete-1'), findsOneWidget);
    });

    testWidgets('SCENARIO 3 — Cancelar devuelve null, no persiste nada',
        (tester) async {
      final links = [
        _link(id: 'l1', athleteId: 'athlete-1', status: TrainerLinkStatus.active),
      ];

      await tester.pumpWidget(_wrap(overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        ..._profilesOverride({'athlete-1': 'Juana Pérez'}),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar')); // i18n
      await tester.pumpAndSettle();

      expect(find.text('result:null'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO 4 — sin alumnos vinculados, mensaje honesto sin crashear',
        (tester) async {
      await tester.pumpWidget(_wrap(overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ..._profilesOverride(const {}),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(
        find.text('Todavía no tenés alumnos vinculados.'), // i18n
        findsOneWidget,
      );
    });
  });
}
