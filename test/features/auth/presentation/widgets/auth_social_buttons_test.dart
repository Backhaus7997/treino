import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/auth_social_buttons.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(AuthSocialProvider? pending) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body:
            AuthSocialButtons(onGoogle: null, onApple: null, pending: pending),
      ),
    );

void main() {
  // El OAuth tarda segundos: sin el spinner la pantalla parece colgada.
  testWidgets('sin OAuth en curso: logo de Google y ningún spinner',
      (tester) async {
    await tester.pumpWidget(_wrap(null));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Google en curso: el logo de Google pasa a spinner',
      (tester) async {
    await tester.pumpWidget(_wrap(AuthSocialProvider.google));
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Apple en curso: spinner en Apple, Google conserva su logo',
      (tester) async {
    await tester.pumpWidget(_wrap(AuthSocialProvider.apple));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
