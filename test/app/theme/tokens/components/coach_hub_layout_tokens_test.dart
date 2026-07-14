import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/tokens/components/coach_hub_layout_tokens.dart';

void main() {
  group('CoachHubLayoutTokens — constantes de layout del shell', () {
    test('sidebarExpandedWidth == 240.0', () {
      expect(CoachHubLayoutTokens.sidebarExpandedWidth, 240.0);
    });

    test('sidebarCollapsedWidth == 72.0', () {
      expect(CoachHubLayoutTokens.sidebarCollapsedWidth, 72.0);
    });

    test('topBarHeight == 64.0', () {
      expect(CoachHubLayoutTokens.topBarHeight, 64.0);
    });

    test('contentMaxWidth == 1240.0', () {
      expect(CoachHubLayoutTokens.contentMaxWidth, 1240.0);
    });

    test('sidebarItemHeight == 48.0', () {
      expect(CoachHubLayoutTokens.sidebarItemHeight, 48.0);
    });

    test('sidebarAvatarDiameter == 44.0', () {
      expect(CoachHubLayoutTokens.sidebarAvatarDiameter, 44.0);
    });

    test('sidebarBadgeSize == 16.0', () {
      expect(CoachHubLayoutTokens.sidebarBadgeSize, 16.0);
    });

    test('todas las constantes son static const double', () {
      // Verificamos que los valores son del tipo correcto y accesibles
      // sin BuildContext (son constantes de layout, no de color).
      expect(CoachHubLayoutTokens.sidebarExpandedWidth, isA<double>());
      expect(CoachHubLayoutTokens.sidebarCollapsedWidth, isA<double>());
      expect(CoachHubLayoutTokens.topBarHeight, isA<double>());
      expect(CoachHubLayoutTokens.contentMaxWidth, isA<double>());
      expect(CoachHubLayoutTokens.sidebarItemHeight, isA<double>());
      expect(CoachHubLayoutTokens.sidebarAvatarDiameter, isA<double>());
      expect(CoachHubLayoutTokens.sidebarBadgeSize, isA<double>());
    });
  });
}
