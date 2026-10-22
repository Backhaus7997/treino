import 'dart:async' show StreamController;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/chat/application/chat_contacts_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/presentation/chat_list_screen.dart';
import 'package:treino/features/chat/presentation/chat_swipe_actions.dart';
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
  Map<String, DateTime>? archivedAt,
}) =>
    Chat(
      chatId: chatId,
      members: members,
      createdAt: DateTime.utc(2026, 5, 21, 10, 0),
      lastMessageText: lastMessageText,
      lastMessageAt: lastMessageAt,
      lastMessageSenderId: lastMessageSenderId,
      lastRead: lastRead,
      archivedAt: archivedAt,
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

    group('archivar / eliminar', () {
      final last = DateTime.utc(2026, 10, 1, 10);
      late FakeFirebaseFirestore firestore;

      setUp(() async {
        firestore = FakeFirebaseFirestore();
        await firestore.collection('chats').doc('aaa_bbb').set({
          'chatId': 'aaa_bbb',
          'members': ['aaa', 'bbb'],
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
          'lastMessageAt': Timestamp.fromDate(last),
        });
      });

      Future<Map<String, Object?>> chatDoc() async =>
          (await firestore.collection('chats').doc('aaa_bbb').get()).data()!;

      Future<void> pumpList(WidgetTester tester, List<Chat> chats) async {
        await tester.pumpWidget(
          _wrap(
            const ChatListScreen(),
            overrides: [
              currentUidProvider.overrideWith((_) => 'aaa'),
              chatsForCurrentUserProvider
                  .overrideWith((ref) => Stream.value(chats)),
              chatRepositoryProvider
                  .overrideWithValue(ChatRepository(firestore: firestore)),
              userPublicProfileProvider('bbb')
                  .overrideWith((_) => Stream.value(_pub('bbb', 'Vale'))),
            ],
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('long-press → Archivar escribe sólo mi entrada', (
        tester,
      ) async {
        await pumpList(tester, [
          _chat(lastMessageText: 'hola', lastMessageAt: last),
        ]);

        await tester.longPress(find.text('Vale'));
        await tester.pumpAndSettle();
        expect(find.text('Eliminar chat'), findsOneWidget);

        await tester.tap(find.text('Archivar'));
        await tester.runAsync(() => pumpEventQueue());
        await tester.pumpAndSettle();

        expect(((await chatDoc())['archivedAt']! as Map).keys, ['aaa']);
        expect(find.text('Chat archivado'), findsOneWidget);
      });

      testWidgets('Eliminar pide confirmación; cancelar no escribe nada', (
        tester,
      ) async {
        await pumpList(tester, [
          _chat(lastMessageText: 'hola', lastMessageAt: last),
        ]);

        await tester.longPress(find.text('Vale'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar chat'));
        await tester.pumpAndSettle();

        expect(find.text('¿Eliminar el chat?'), findsOneWidget);
        expect(find.textContaining('sólo para vos'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect((await chatDoc()).containsKey('hiddenBefore'), isFalse);

        await tester.longPress(find.text('Vale'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar chat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar'));
        await tester.runAsync(() => pumpEventQueue());
        await tester.pumpAndSettle();
        expect(((await chatDoc())['hiddenBefore']! as Map).keys, ['aaa']);
      });

      testWidgets(
          '200 archivados desplegados: sólo se arman las filas visibles',
          (tester) async {
        // Codex (#1608): desplegar un archivo grande montaba todas las filas, y
        // cada una abre el listener de su perfil.
        var profileReads = 0;
        await tester.pumpWidget(
          _wrap(
            const ChatListScreen(),
            overrides: [
              currentUidProvider.overrideWith((_) => 'aaa'),
              chatsForCurrentUserProvider.overrideWith(
                (ref) => Stream.value([
                  for (var i = 0; i < 200; i++)
                    _chat(
                      chatId: 'aaa_u$i',
                      members: ['aaa', 'u$i'],
                      lastMessageText: 'hola',
                      lastMessageAt: last,
                      archivedAt: {'aaa': last.add(const Duration(minutes: 1))},
                    ),
                ]),
              ),
              userPublicProfileProvider.overrideWith((ref, uid) {
                profileReads++;
                return Stream.value(_pub(uid, 'Persona $uid'));
              }),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(profileReads, 0);

        await tester.tap(find.text('Archivados · 200'));
        await tester.pumpAndSettle();
        expect(find.text('Persona u0'), findsOneWidget);
        expect(profileReads, lessThan(40));
      });

      testWidgets('Archivados: plegado con el conteo, se despliega al tocar', (
        tester,
      ) async {
        await pumpList(tester, [
          _chat(
            lastMessageText: 'hola',
            lastMessageAt: last,
            archivedAt: {'aaa': last.add(const Duration(minutes: 1))},
          ),
        ]);

        // Con el único chat archivado no es el estado vacío.
        expect(find.text('Sin mensajes todavía'), findsNothing);
        expect(find.text('Archivados · 1'), findsOneWidget);
        expect(find.text('Vale'), findsNothing);

        await tester.tap(find.text('Archivados · 1'));
        await tester.pumpAndSettle();
        expect(find.text('Vale'), findsOneWidget);

        await tester.longPress(find.text('Vale'));
        await tester.pumpAndSettle();
        expect(find.text('Desarchivar'), findsOneWidget);
      });

      group('swipe', () {
        testWidgets(
            'P1 de Codex: con la fila abierta, si la bandeja se reordena las '
            'acciones siguen a SU chat y no al que quedó en ese lugar', (
          tester,
        ) async {
          await firestore.collection('chats').doc('aaa_ccc').set({
            'chatId': 'aaa_ccc',
            'members': ['aaa', 'ccc'],
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
            'lastMessageAt': Timestamp.fromDate(last),
          });
          final chats = StreamController<List<Chat>>();
          addTearDown(chats.close);
          await tester.pumpWidget(
            _wrap(
              const ChatListScreen(),
              overrides: [
                currentUidProvider.overrideWith((_) => 'aaa'),
                chatsForCurrentUserProvider.overrideWith((ref) => chats.stream),
                chatRepositoryProvider
                    .overrideWithValue(ChatRepository(firestore: firestore)),
                userPublicProfileProvider('bbb')
                    .overrideWith((_) => Stream.value(_pub('bbb', 'Vale'))),
                userPublicProfileProvider('ccc')
                    .overrideWith((_) => Stream.value(_pub('ccc', 'Ceci'))),
              ],
            ),
          );
          final vale = _chat(lastMessageText: 'hola', lastMessageAt: last);
          Chat ceci(DateTime at) => _chat(
                chatId: 'aaa_ccc',
                members: const ['aaa', 'ccc'],
                lastMessageText: 'che',
                lastMessageAt: at,
              );
          chats.add([vale, ceci(last.subtract(const Duration(hours: 1)))]);
          await tester.pumpAndSettle();

          // Vale arriba, con el swipe abierto.
          await tester.drag(find.text('Vale'), const Offset(-240, 0));
          await tester.pumpAndSettle();
          expect(find.text('Archivar'), findsOneWidget);

          // Le llega un mensaje a Ceci: pasa arriba, Vale baja.
          chats.add([ceci(last.add(const Duration(hours: 1))), vale]);
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(find.text('Ceci')).dy,
            lessThan(tester.getTopLeft(find.text('Vale')).dy),
          );

          // La fila abierta sigue siendo la de Vale, y archivar archiva a Vale.
          expect(find.text('Archivar'), findsOneWidget);
          final valeRow = tester.getRect(find.ancestor(
            of: find.text('Vale'),
            matching: find.byType(ChatSwipeActions),
          ));
          expect(
            valeRow.contains(
              Offset(valeRow.center.dx,
                  tester.getCenter(find.text('Archivar')).dy),
            ),
            isTrue,
          );
          await tester.tap(find.text('Archivar'));
          await tester.runAsync(() => pumpEventQueue());
          await tester.pumpAndSettle();

          expect(((await chatDoc())['archivedAt']! as Map).keys, ['aaa']);
          final ceciDoc =
              (await firestore.collection('chats').doc('aaa_ccc').get())
                  .data()!;
          expect(ceciDoc.containsKey('archivedAt'), isFalse);
        });

        Future<void> swipeLeft(WidgetTester tester) async {
          await tester.drag(find.text('Vale'), const Offset(-240, 0));
          await tester.pumpAndSettle();
        }

        testWidgets('revela Archivar y Eliminar; Archivar escribe', (
          tester,
        ) async {
          await pumpList(tester, [
            _chat(lastMessageText: 'hola', lastMessageAt: last),
          ]);
          // Cerrada, las acciones no existen: no se ven a través de la fila.
          expect(find.text('Archivar'), findsNothing);

          await swipeLeft(tester);
          expect(find.text('Archivar'), findsOneWidget);
          expect(find.text('Eliminar chat'), findsOneWidget);

          await tester.tap(find.text('Archivar'));
          await tester.runAsync(() => pumpEventQueue());
          await tester.pumpAndSettle();

          expect(((await chatDoc())['archivedAt']! as Map).keys, ['aaa']);
          expect(find.text('Chat archivado'), findsOneWidget);
          expect(find.text('Deshacer'), findsOneWidget);
        });

        testWidgets('Eliminar pide confirmación antes de escribir', (
          tester,
        ) async {
          await pumpList(tester, [
            _chat(lastMessageText: 'hola', lastMessageAt: last),
          ]);

          await swipeLeft(tester);
          await tester.tap(find.text('Eliminar chat'));
          await tester.pumpAndSettle();
          expect(find.text('¿Eliminar el chat?'), findsOneWidget);
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          expect((await chatDoc()).containsKey('hiddenBefore'), isFalse);

          await swipeLeft(tester);
          await tester.tap(find.text('Eliminar chat'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Eliminar'));
          await tester.runAsync(() => pumpEventQueue());
          await tester.pumpAndSettle();
          expect(((await chatDoc())['hiddenBefore']! as Map).keys, ['aaa']);
        });

        testWidgets('en Archivados el swipe ofrece Desarchivar', (
          tester,
        ) async {
          await firestore
              .collection('chats')
              .doc('aaa_bbb')
              .update({'archivedAt.aaa': Timestamp.fromDate(last)});
          await pumpList(tester, [
            _chat(
              lastMessageText: 'hola',
              lastMessageAt: last,
              archivedAt: {'aaa': last.add(const Duration(minutes: 1))},
            ),
          ]);
          await tester.tap(find.text('Archivados · 1'));
          await tester.pumpAndSettle();

          await swipeLeft(tester);
          expect(find.text('Archivar'), findsNothing);
          await tester.tap(find.text('Desarchivar'));
          await tester.runAsync(() => pumpEventQueue());
          await tester.pumpAndSettle();

          expect((await chatDoc())['archivedAt'], isEmpty);
          expect(find.text('Chat desarchivado'), findsOneWidget);
        });

        testWidgets('tocar una fila abierta la cierra en vez de abrir el chat',
            (tester) async {
          await pumpList(tester, [
            _chat(lastMessageText: 'hola', lastMessageAt: last),
          ]);

          final y = tester.getCenter(find.text('Vale')).dy;
          await swipeLeft(tester);
          // Abierta, el nombre quedó fuera de pantalla: se toca lo visible.
          await tester.tapAt(Offset(120, y));
          await tester.pumpAndSettle();

          expect(find.text('Archivar'), findsNothing);
          expect((await chatDoc()).containsKey('archivedAt'), isFalse);
        });

        testWidgets(
            'control negativo: un drag desde el borde izquierdo o hacia la '
            'derecha no abre la fila', (tester) async {
          await pumpList(tester, [
            _chat(lastMessageText: 'hola', lastMessageAt: last),
          ]);
          final y = tester.getCenter(find.text('Vale')).dy;

          // El borde es del gesto de volver de iOS.
          await tester.dragFrom(Offset(8, y), const Offset(-240, 0));
          await tester.pumpAndSettle();
          expect(find.text('Archivar'), findsNothing);

          await tester.drag(find.text('Vale'), const Offset(240, 0));
          await tester.pumpAndSettle();
          expect(find.text('Archivar'), findsNothing);
          expect((await chatDoc()).containsKey('archivedAt'), isFalse);
        });
      });
    });
  });
}
