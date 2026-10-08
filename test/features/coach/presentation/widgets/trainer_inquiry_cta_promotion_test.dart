// La marca de pre-consulta sobre un chat que YA EXISTE.
//
// `ChatRepository.getOrCreate` sale temprano si el doc existe, y `kind` sólo se
// estampa al CREAR. Desde el cliente no se puede agregar después: está pineado
// inmutable en `chats/update` (firestore.rules) y el id del chat es
// determinístico por par, así que tampoco se puede crear otro.
//
// Consecuencia del bug: un chat social preexistente —creado cuando el PF
// seguía al alumno, y después dejó de seguirlo— dejaba al alumno sin poder
// escribirle NUNCA MÁS a ese PF, con un cartel que le echaba la culpa al
// follow. El pin no se relaja: lo estampa el servidor vía
// `promoteChatToInquiry`. Estos tests fijan CUÁNDO el cliente lo pide.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_inquiry_promotion_service.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_inquiry_cta.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _trainerUid = 'trainer-1';
const _athleteUid = 'athlete-1';
// chatIdFor ordena: 'athlete-1' < 'trainer-1'.
const _chatId = 'athlete-1_trainer-1';

class _FakePromotion implements ChatInquiryPromotionService {
  final List<String> llamadas = [];
  bool explota = false;

  @override
  Future<void> promote(String trainerId) async {
    llamadas.add(trainerId);
    if (explota) throw Exception('callable caída');
  }
}

Future<(_FakePromotion, List<String>)> _tap(
  WidgetTester tester, {
  Map<String, Object?>? chatExistente,
  bool explota = false,
}) async {
  final firestore = FakeFirebaseFirestore();
  if (chatExistente != null) {
    await firestore.collection('chats').doc(_chatId).set({
      'chatId': _chatId,
      'members': [_athleteUid, _trainerUid],
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20)),
      ...chatExistente,
    });
  }
  final promo = _FakePromotion()..explota = explota;
  final navegado = <String>[];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: TrainerInquiryCta(trainerId: _trainerUid),
        ),
      ),
      GoRoute(
        path: '/coach/chat/:id',
        builder: (_, state) {
          navegado.add(state.uri.toString());
          return const Scaffold(body: Text('chat'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWith((_) => _athleteUid),
        chatInquiryPromotionServiceProvider.overrideWithValue(promo),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
  return (promo, navegado);
}

void main() {
  testWidgets('chat social preexistente (sin kind, sin linkId) → PIDE la marca',
      (tester) async {
    // EL CASO DEL BUG. El chat quedó de cuando el PF seguía al alumno.
    final (promo, navegado) = await _tap(tester, chatExistente: const {});

    expect(promo.llamadas, [_trainerUid]);
    expect(navegado, isNotEmpty);
  });

  testWidgets('chat que NO existía → no pide nada (getOrCreate ya lo marcó)',
      (tester) async {
    final (promo, navegado) = await _tap(tester);

    expect(promo.llamadas, isEmpty);
    expect(navegado, isNotEmpty);
  });

  testWidgets('chat de Coach (linkId) → NO pide la marca', (tester) async {
    // Ya escapa por su propia rama en `senderMayPost`. Marcarlo dejaría un
    // campo mentiroso, y la lista de chats lo mostraría como consulta.
    final (promo, _) =
        await _tap(tester, chatExistente: const {'linkId': 'link-1'});

    expect(promo.llamadas, isEmpty);
  });

  testWidgets('chat ya marcado como consulta → NO vuelve a pedirla',
      (tester) async {
    final (promo, _) =
        await _tap(tester, chatExistente: const {'kind': 'inquiry'});

    expect(promo.llamadas, isEmpty);
  });

  testWidgets('si la marca falla, NAVEGA igual', (tester) async {
    // El chat existe y su historial es legible. Que falle la marca no puede
    // costarle al usuario el acceso a la conversación: lo que pierde es el
    // composer, que es exactamente el estado en el que ya estaba.
    final (promo, navegado) =
        await _tap(tester, chatExistente: const {}, explota: true);

    expect(promo.llamadas, [_trainerUid]);
    expect(navegado, isNotEmpty);
  });
}
