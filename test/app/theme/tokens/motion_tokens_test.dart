import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/tokens/motion_tokens.dart';

void main() {
  group('AppMotionTokens — mapeo semántico a AppMotion (valores idénticos)',
      () {
    test('tapFeedback == AppMotion.micro (120ms)', () {
      expect(AppMotionTokens.tapFeedback, AppMotion.micro);
    });

    test('cardStateChange == AppMotion.fast (180ms)', () {
      expect(AppMotionTokens.cardStateChange, AppMotion.fast);
    });

    test('stateSwitch == AppMotion.base (240ms)', () {
      expect(AppMotionTokens.stateSwitch, AppMotion.base);
    });

    test('contentEnter == AppMotion.base (240ms)', () {
      expect(AppMotionTokens.contentEnter, AppMotion.base);
    });

    test('pageTransition == AppMotion.slow (320ms)', () {
      expect(AppMotionTokens.pageTransition, AppMotion.slow);
    });
  });

  group('AppMotionTokens — curvas semánticas', () {
    test('enter == AppMotion.standard', () {
      expect(AppMotionTokens.enter, AppMotion.standard);
    });

    test('reposition == AppMotion.emphasized', () {
      expect(AppMotionTokens.reposition, AppMotion.emphasized);
    });

    test('leave == AppMotion.exit', () {
      expect(AppMotionTokens.leave, AppMotion.exit);
    });
  });

  group('AppMotionTokens — slides semánticos', () {
    test('rowSlide == AppMotion.slideSm (8px)', () {
      expect(AppMotionTokens.rowSlide, AppMotion.slideSm);
    });

    test('cardSlide == AppMotion.slideMd (12px)', () {
      expect(AppMotionTokens.cardSlide, AppMotion.slideMd);
    });

    test('heroSlide == AppMotion.slideLg (20px)', () {
      expect(AppMotionTokens.heroSlide, AppMotion.slideLg);
    });
  });

  group('AppMotionTokens — delegación de accesibilidad', () {
    testWidgets('reduceMotion delega a AppMotion.reduceMotion', (tester) async {
      late bool motionTokensResult;
      late bool appMotionResult;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (ctx) {
              motionTokensResult = AppMotionTokens.reduceMotion(ctx);
              appMotionResult = AppMotion.reduceMotion(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(motionTokensResult, isTrue);
      expect(motionTokensResult, appMotionResult);
    });

    testWidgets('resolve(ctx, cardEntry) retorna Duration.zero si reduceMotion',
        (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (ctx) {
              resolved =
                  AppMotionTokens.resolve(ctx, AppMotionTokens.contentEnter);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, Duration.zero);
    });

    testWidgets('resolve(ctx, cardEntry) sin reduceMotion retorna la duración',
        (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (ctx) {
              resolved =
                  AppMotionTokens.resolve(ctx, AppMotionTokens.contentEnter);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, AppMotionTokens.contentEnter);
    });
  });

  group('AppMotion — intacto (no roto por WU-04)', () {
    // Verifica que los tests originales de AppMotion siguen pasando.
    test('AppMotion.micro sigue siendo 120ms', () {
      expect(AppMotion.micro, const Duration(milliseconds: 120));
    });

    test('AppMotion.base sigue siendo 240ms', () {
      expect(AppMotion.base, const Duration(milliseconds: 240));
    });
  });
}
