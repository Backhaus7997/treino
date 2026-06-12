// T-I18N-024 RED — PR#3a Sub-task C: profile_cuenta_section ARB key existence tests
//
// Verifies verbatim values for T-I18N-024/025 keys. Fails until ARB keys
// are added and flutter gen-l10n is run.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _testApp(Widget child) => MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    );

void main() {
  group('AppL10n — PR#3a Sub-task C keys', () {
    testWidgets('profileCuentaTitle verbatim', (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaTitle, 'CUENTA');
    });

    testWidgets('profileCuentaSolicitudesTitle verbatim', (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaSolicitudesTitle, 'Solicitudes de amistad');
    });

    testWidgets('profileCuentaSolicitudesSubtitle(3) verbatim', (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaSolicitudesSubtitle(3), '3 nuevas');
    });

    testWidgets('profileCuentaDatosPersonalesTitle verbatim', (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaDatosPersonalesTitle, 'Datos personales');
    });

    testWidgets('profileCuentaDatosPersonalesSubtitle verbatim',
        (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaDatosPersonalesSubtitle, 'Editá tu info');
    });

    testWidgets('profileCuentaGimnasioTitle verbatim', (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaGimnasioTitle, 'Gimnasio');
    });

    testWidgets('profileCuentaNoGym verbatim', (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaNoGym, 'Sin gym');
    });

    testWidgets('profileCuentaMisRutinasTitle verbatim', (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaMisRutinasTitle, 'Mis rutinas');
    });

    testWidgets('profileCuentaRutinasSubtitle(2) verbatim', (tester) async {
      late AppL10n l10n;
      await tester.pumpWidget(_testApp(Builder(builder: (ctx) {
        l10n = AppL10n.of(ctx);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(l10n.profileCuentaRutinasSubtitle(2), '2 activas');
    });
  });
}
