import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/chat/application/chat_contacts_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/presentation/chat_list_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  AsyncValue<List<ChatContact>> contacts = const AsyncData([]),
}) =>
    ProviderScope(
      overrides: [
        chatContactsProvider.overrideWith((_) => contacts),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: child,
      ),
    );

Chat _chat({
  String chatId = 'aaa_bbb',
  List<String> members = const ['aaa', 'bbb'],
  String? lastMessageText,
  DateTime? lastMessageAt,
  String? lastMessageSenderId,
  Map<String, DateTime>? lastRead,
}) =>
    Chat(
      chatId: chatId,
      members: members,
      createdAt: DateTime.utc(2026, 5, 21, 10, 0),
      lastMessageText: lastMessageText,
      lastMessageAt: lastMessageAt,
      lastMessageSenderId: lastMessageSenderId,
      lastRead: lastRead,
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

void main() {
  group('ChatListScreen', () {
    testWidgets('body uses TreinoStateSwitcher for async transitions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value(const <Chat>[]),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(TreinoStateSwitcher), findsOneWidget);
    });

    testWidgets('empty state cuando no hay chats', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value(const <Chat>[]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sin mensajes todavía'), findsOneWidget);
      expect(find.textContaining('a quienes seguís'), findsOneWidget);
    });

    testWidgets('sin chats pero con contactos: sección, sin estado vacío', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          contacts: const AsyncData([
            ChatContact(uid: 'pf', reason: ChatContactReason.coach),
            ChatContact(uid: 'lu', reason: ChatContactReason.following),
          ]),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value(const <Chat>[]),
            ),
            userPublicProfileProvider('pf')
                .overrideWith((_) => Stream.value(_pub('pf', 'Coach Joe'))),
            userPublicProfileProvider('lu')
                .overrideWith((_) => Stream.value(_pub('lu', 'Lucia'))),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sin mensajes todavía'), findsNothing);
      expect(find.text('ESCRIBILE A…'), findsOneWidget);
      expect(find.text('Coach Joe'), findsOneWidget);
      expect(find.text('Tu PF'), findsOneWidget);
      expect(find.text('Lucia'), findsOneWidget);
      expect(find.text('Lo seguís'), findsOneWidget);
    });

    testWidgets('contactos debajo de los chats existentes', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          contacts: const AsyncData([
            ChatContact(uid: 'lu', reason: ChatContactReason.following),
          ]),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value([
                _chat(
                  lastMessageText: 'hola',
                  lastMessageAt: DateTime.now(),
                  lastMessageSenderId: 'bbb',
                ),
              ]),
            ),
            userPublicProfileProvider('bbb')
                .overrideWith((_) => Stream.value(_pub('bbb', 'Vale'))),
            userPublicProfileProvider('lu')
                .overrideWith((_) => Stream.value(_pub('lu', 'Lucia'))),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final chatY = tester.getTopLeft(find.text('Vale')).dy;
      final headerY = tester.getTopLeft(find.text('ESCRIBILE A…')).dy;
      final contactY = tester.getTopLeft(find.text('Lucia')).dy;
      expect(chatY, lessThan(headerY));
      expect(headerY, lessThan(contactY));
    });

    testWidgets(
        '200 contactos: sólo se piden los perfiles de las filas visibles',
        (tester) async {
      // Cada fila escucha su perfil público. Con una lista eager se abría un
      // listener por contacto al entrar a la pantalla (Codex, #1607).
      var profileReads = 0;
      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          contacts: AsyncData([
            for (var i = 0; i < 200; i++)
              ChatContact(uid: 'u$i', reason: ChatContactReason.following),
          ]),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value(const <Chat>[]),
            ),
            userPublicProfileProvider.overrideWith((ref, uid) {
              profileReads++;
              return Stream.value(_pub(uid, 'Persona $uid'));
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Persona u0'), findsOneWidget);
      expect(profileReads, lessThan(40));
    });

    testWidgets('sin chats y contactos cargando: no afirma el estado vacío', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          contacts: const AsyncLoading(),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value(const <Chat>[]),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Sin mensajes todavía'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('lista de chats — muestra nombre del otro miembro + preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value([
                _chat(
                  chatId: 'aaa_bbb',
                  members: const ['aaa', 'bbb'],
                  lastMessageText: 'arranca a las 18',
                  lastMessageAt: DateTime.now().subtract(
                    const Duration(minutes: 5),
                  ),
                  lastMessageSenderId: 'bbb',
                ),
              ]),
            ),
            userPublicProfileProvider(
              'bbb',
            ).overrideWith((_) => Stream.value(_pub('bbb', 'Coach Joe'))),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coach Joe'), findsOneWidget);
      expect(find.text('arranca a las 18'), findsOneWidget);
    });

    testWidgets('placeholder cuando el chat no tiene mensajes todavía', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value([
                _chat(chatId: 'aaa_bbb', members: const ['aaa', 'bbb']),
              ]),
            ),
            userPublicProfileProvider(
              'bbb',
            ).overrideWith((_) => Stream.value(_pub('bbb', 'Coach Joe'))),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Iniciá la conversación'), findsOneWidget);
    });

    group('_ChatRow unread dot', () {
      final base = DateTime.utc(2026, 6, 1, 10, 0);
      final before = base.subtract(const Duration(minutes: 5));

      testWidgets(
        'unread chat → dot present (finds chatUnreadA11y semantics)',
        (tester) async {
          final handle = tester.ensureSemantics();
          // other sender, lastMessageAt after null lastRead → unread
          await tester.pumpWidget(
            _wrap(
              const ChatListScreen(),
              overrides: [
                currentUidProvider.overrideWith((_) => 'aaa'),
                chatsForCurrentUserProvider.overrideWith(
                  (ref) => Stream.value([
                    _chat(
                      chatId: 'aaa_bbb',
                      members: const ['aaa', 'bbb'],
                      lastMessageText: 'hola',
                      lastMessageAt: base,
                      lastMessageSenderId: 'bbb',
                      lastRead: null,
                    ),
                  ]),
                ),
                userPublicProfileProvider(
                  'bbb',
                ).overrideWith((_) => Stream.value(_pub('bbb', 'Coach Joe'))),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // The dot is a Semantics-wrapped Container
          expect(
            find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'Sin leer',
            ),
            findsOneWidget,
          );
          handle.dispose();
        },
      );

      testWidgets('read chat → no dot', (tester) async {
        final handle = tester.ensureSemantics();
        // lastRead after lastMessageAt → read
        await tester.pumpWidget(
          _wrap(
            const ChatListScreen(),
            overrides: [
              currentUidProvider.overrideWith((_) => 'aaa'),
              chatsForCurrentUserProvider.overrideWith(
                (ref) => Stream.value([
                  _chat(
                    chatId: 'aaa_bbb',
                    members: const ['aaa', 'bbb'],
                    lastMessageText: 'hola',
                    lastMessageAt: before,
                    lastMessageSenderId: 'bbb',
                    lastRead: {'aaa': base},
                  ),
                ]),
              ),
              userPublicProfileProvider(
                'bbb',
              ).overrideWith((_) => Stream.value(_pub('bbb', 'Coach Joe'))),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Sin leer',
          ),
          findsNothing,
        );
        handle.dispose();
      });

      testWidgets('self-sent last message → no dot regardless of lastRead', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _wrap(
            const ChatListScreen(),
            overrides: [
              currentUidProvider.overrideWith((_) => 'aaa'),
              chatsForCurrentUserProvider.overrideWith(
                (ref) => Stream.value([
                  _chat(
                    chatId: 'aaa_bbb',
                    members: const ['aaa', 'bbb'],
                    lastMessageText: 'yo mandé',
                    lastMessageAt: base,
                    lastMessageSenderId: 'aaa', // self sender
                    lastRead: null,
                  ),
                ]),
              ),
              userPublicProfileProvider(
                'bbb',
              ).overrideWith((_) => Stream.value(_pub('bbb', 'Coach Joe'))),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Sin leer',
          ),
          findsNothing,
        );
        handle.dispose();
      });
    });

    testWidgets(
        'fecha absoluta (>7d) se formatea en zona local, no en UTC '
        '[tz-local-date-regression]', (tester) async {
      // lastMessageAt is stored in UTC (TimestampConverter -> toUtc()).
      // Pick a UTC instant just after midnight so any negative-offset zone
      // (e.g. Argentina UTC-3, the target market) rolls back to the previous
      // calendar day. Age it past 7 days so the dd/mm branch is hit.
      final utcInstant = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 10))
          .copyWith(hour: 0, minute: 30, second: 0, millisecond: 0);

      // Expected label is derived from the SAME instant converted to local —
      // this is correct regardless of the test runner's actual timezone, and
      // it fails on the old code that read UTC day/month directly.
      final local = utcInstant.toLocal();
      final expected = '${local.day.toString().padLeft(2, '0')}/'
          '${local.month.toString().padLeft(2, '0')}';

      await tester.pumpWidget(
        _wrap(
          const ChatListScreen(),
          overrides: [
            currentUidProvider.overrideWith((_) => 'aaa'),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream.value([
                _chat(
                  chatId: 'aaa_bbb',
                  members: const ['aaa', 'bbb'],
                  lastMessageText: 'nos vemos',
                  lastMessageAt: utcInstant,
                  lastMessageSenderId: 'bbb',
                ),
              ]),
            ),
            userPublicProfileProvider(
              'bbb',
            ).overrideWith((_) => Stream.value(_pub('bbb', 'Coach Joe'))),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(expected), findsOneWidget);
    });
  });
}
