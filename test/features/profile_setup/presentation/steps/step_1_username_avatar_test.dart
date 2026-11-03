import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile_setup/presentation/steps/step_1_username_avatar.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Step1UsernameAvatar()),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    );

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  // E2E 1.3.0: en iOS el autocorrector cambió `carrilb` por `carrion` al
  // cerrar el teclado. Un @handle no es una palabra del diccionario: ni
  // corrección ni sugerencias.
  testWidgets('el username no pasa por el autocorrector ni las sugerencias',
      (tester) async {
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });
}
