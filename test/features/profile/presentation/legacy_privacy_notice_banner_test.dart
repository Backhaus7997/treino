// consentimiento-legal-versionado — R4.
//
// Strict TDD: artefacto RED del grupo 12.
//
// SOLO estado/semántica: `google_fonts` no carga en `flutter_test`, así que
// no hay un solo assert de ancho, wrapping u overflow. Lo que se verifica es
// que el aviso NO bloquea: la app de abajo sigue siendo tapeable.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/legacy_privacy_notice_banner.dart';
import 'package:treino/l10n/app_l10n.dart';

UserProfile _athlete({DateTime? termsAcceptedAt}) => UserProfile(
      uid: 'u1',
      email: 'u@test.com',
      displayName: 'U',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      termsAcceptedAt: termsAcceptedAt,
    );

/// Host que imita el `Stack` de Home: contenido real abajo, aviso encima.
Widget _host(UserProfile profile, {required VoidCallback onTapBehind}) {
  return ProviderScope(
    overrides: [
      userProfileProvider.overrideWith((_) => Stream.value(profile)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const Key('app_behind'),
                behavior: HitTestBehavior.opaque,
                onTap: onTapBehind,
                child: const SizedBox.expand(),
              ),
            ),
            const LegacyPrivacyNoticeBanner(),
          ],
        ),
      ),
    ),
  );
}

void main() {
  final before = kPrivacyV1PublishedAt.subtract(const Duration(days: 30));

  testWidgets('el aviso aparece para el atleta legacy', (tester) async {
    await tester.pumpWidget(
      _host(_athlete(termsAcceptedAt: before), onTapBehind: () {}),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('legacy_privacy_notice_banner')),
      findsOneWidget,
    );
  });

  testWidgets('NO bloquea: la app de abajo sigue respondiendo al tap',
      (tester) async {
    var tapsBehind = 0;
    await tester.pumpWidget(
      _host(
        _athlete(termsAcceptedAt: before),
        onTapBehind: () => tapsBehind++,
      ),
    );
    await tester.pumpAndSettle();

    // Un tap lejos del banner (arriba de todo) llega al contenido.
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();

    expect(tapsBehind, 1);
  });

  testWidgets('se puede cerrar y no vuelve en esta sesión', (tester) async {
    await tester.pumpWidget(
      _host(_athlete(termsAcceptedAt: before), onTapBehind: () {}),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('legacy_privacy_notice_dismiss')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('legacy_privacy_notice_banner')),
      findsNothing,
    );
  });

  testWidgets('el atleta al día no ve nada — ni siquiera layout',
      (tester) async {
    await tester.pumpWidget(
      _host(
        _athlete(termsAcceptedAt: kPrivacyV1PublishedAt),
        onTapBehind: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('legacy_privacy_notice_banner')),
      findsNothing,
    );
    // Sin gate activo el widget colapsa a cero: no puede empujar layout de
    // Home ni cuando no corresponde mostrarlo.
    final rendered = tester.getSize(
      find.byType(LegacyPrivacyNoticeBanner),
    );
    expect(rendered, Size.zero);
  });
}
