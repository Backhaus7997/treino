import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/application/chat_contacts_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/moderation/application/moderation_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';

const _me = 'me';

TrainerLink _link({
  required String trainerId,
  required String athleteId,
  TrainerLinkStatus status = TrainerLinkStatus.active,
}) =>
    TrainerLink(
      id: '${trainerId}_$athleteId',
      trainerId: trainerId,
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 10, 1),
    );

Chat _chat(String other) {
  final members = [_me, other]..sort();
  return Chat(
    chatId: members.join('_'),
    members: members,
    createdAt: DateTime.utc(2026, 10, 1),
    lastMessageAt: DateTime.utc(2026, 10, 2),
  );
}

List<ChatContact> _from({
  List<TrainerLink> links = const [],
  List<String> followers = const [],
  List<String> blocked = const [],
  List<String> chatPartners = const [],
}) =>
    chatContactsFrom(
      selfUid: _me,
      links: links,
      followerUids: followers,
      blockedUids: blocked,
      chatPartnerUids: chatPartners,
    );

void main() {
  group('chatContactsFrom — espejo de chatCreateOk', () {
    test('quien me sigue (follows/{otro}_{yo} aceptada) está habilitado', () {
      expect(
        _from(followers: ['lucia']),
        [const ChatContact(uid: 'lucia', reason: ChatContactReason.follower)],
      );
    });

    test('a quien sigo yo y no me sigue NO está habilitado', () {
      // followAccepted(other, me) es direccional: seguir a alguien no habilita
      // escribirle. Esa persona nunca llega en `followerUids`.
      expect(_from(followers: const []), isEmpty);
    });

    test('vínculo active o paused habilita; pending/terminated no', () {
      final contacts = _from(links: [
        _link(trainerId: 'pf', athleteId: _me),
        _link(
          trainerId: _me,
          athleteId: 'alumno',
          status: TrainerLinkStatus.paused,
        ),
        _link(
          trainerId: _me,
          athleteId: 'pendiente',
          status: TrainerLinkStatus.pending,
        ),
        _link(
          trainerId: 'viejo',
          athleteId: _me,
          status: TrainerLinkStatus.terminated,
        ),
      ]);
      expect(contacts, [
        const ChatContact(uid: 'pf', reason: ChatContactReason.coach),
        const ChatContact(uid: 'alumno', reason: ChatContactReason.athlete),
      ]);
    });

    test('un vínculo ajeno no habilita a nadie', () {
      expect(_from(links: [_link(trainerId: 'x', athleteId: 'y')]), isEmpty);
    });

    test('bloqueados afuera: el primer mensaje rebotaría en senderMayPost', () {
      expect(_from(followers: ['lucia'], blocked: ['lucia']), isEmpty);
    });

    test('con chat ya existente se muestra el chat, no el contacto', () {
      expect(
        _from(followers: ['lucia', 'vale'], chatPartners: [_me, 'lucia']),
        [const ChatContact(uid: 'vale', reason: ChatContactReason.follower)],
      );
    });

    test('PF que además me sigue aparece una sola vez, como PF', () {
      expect(
        _from(
          links: [_link(trainerId: 'pf', athleteId: _me)],
          followers: ['pf'],
        ),
        [const ChatContact(uid: 'pf', reason: ChatContactReason.coach)],
      );
    });
  });

  group('chatContactsProvider — reactivo', () {
    late StreamController<List<String>> followers;
    late ProviderContainer container;

    setUp(() {
      followers = StreamController<List<String>>();
      container = ProviderContainer(overrides: [
        currentUidProvider.overrideWith((_) => _me),
        chatContactLinksAsAthleteProvider
            .overrideWith((_) => Stream.value(const [])),
        chatContactLinksAsTrainerProvider
            .overrideWith((_) => Stream.value(const [])),
        chatContactFollowersProvider.overrideWith((_) => followers.stream),
        chatsForCurrentUserProvider.overrideWith((_) => Stream.value([])),
        blockedUidsProvider(_me).overrideWith((_) => Stream.value(const [])),
      ]);
      addTearDown(container.dispose);
      addTearDown(followers.close);
    });

    Future<AsyncValue<List<ChatContact>>> read() async {
      await pumpEventQueue();
      return container.read(chatContactsProvider);
    }

    test('loading mientras una fuente no emitió: no es "sin contactos"',
        () async {
      container.listen(chatContactsProvider, (_, __) {});
      expect((await read()).isLoading, isTrue);
    });

    test('pasa de no habilitado a habilitado cuando aceptan el follow',
        () async {
      container.listen(chatContactsProvider, (_, __) {});

      followers.add(const []);
      expect((await read()).requireValue, isEmpty);

      followers.add(const ['lucia']);
      expect(
        (await read()).requireValue,
        [const ChatContact(uid: 'lucia', reason: ChatContactReason.follower)],
      );

      // Y sale apenas deja de seguirme.
      followers.add(const []);
      expect((await read()).requireValue, isEmpty);
    });

    test('un error de una fuente es error, no lista vacía', () async {
      container.listen(chatContactsProvider, (_, __) {});
      followers.addError(Exception('permission-denied'));
      expect((await read()).hasError, isTrue);
    });
  });

  test('chatContactsProvider excluye a quien ya tiene chat (stream real)',
      () async {
    final container = ProviderContainer(overrides: [
      currentUidProvider.overrideWith((_) => _me),
      chatContactLinksAsAthleteProvider
          .overrideWith((_) => Stream.value(const [])),
      chatContactLinksAsTrainerProvider
          .overrideWith((_) => Stream.value(const [])),
      chatContactFollowersProvider
          .overrideWith((_) => Stream.value(const ['lucia', 'vale'])),
      chatsForCurrentUserProvider
          .overrideWith((_) => Stream.value([_chat('lucia')])),
      blockedUidsProvider(_me).overrideWith((_) => Stream.value(const [])),
    ]);
    addTearDown(container.dispose);
    container.listen(chatContactsProvider, (_, __) {});
    await pumpEventQueue();
    expect(
      container.read(chatContactsProvider).requireValue,
      [const ChatContact(uid: 'vale', reason: ChatContactReason.follower)],
    );
  });
}
