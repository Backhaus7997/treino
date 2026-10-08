import 'package:cloud_functions/cloud_functions.dart';

/// Estampa la marca de pre-consulta en un chat que YA EXISTE.
///
/// [ChatRepository.getOrCreate] sale temprano si el doc existe, y la marca
/// `kind: 'inquiry'` sólo se pone al CREAR. Desde el cliente no hay forma de
/// agregarla después: `firestore.rules` tiene `kind` pineado como inmutable en
/// `chats/update`, y el id del chat es determinístico por par, así que tampoco
/// se puede crear uno nuevo.
///
/// Consecuencia: si entre el alumno y el PF ya existía un chat social —creado
/// cuando el PF lo seguía, y después dejó de seguirlo— el alumno quedaba sin
/// poder escribirle NUNCA MÁS a ese PF.
///
/// El pin no se relaja: lo estampa el servidor. `promoteChatToInquiry` valida
/// con Admin SDK los mismos tres hechos que `chatCreateOk` verifica al crear
/// (que el destinatario sea un PF real, que haya publicado su perfil de
/// discovery, y que no haya cerrado la puerta con `acceptsInquiries`) y recién
/// después escribe. Ver `functions/src/chat/promote-chat-to-inquiry.ts`.
///
/// Separado de [ChatRepository] a propósito, igual que
/// [TrainerLinkPromotionService] lo está de `TrainerLinkRepository`: el
/// repositorio habla Firestore, el servicio habla Cloud Functions.
class ChatInquiryPromotionService {
  ChatInquiryPromotionService({required FirebaseFunctions functions})
      : _functions = functions;

  final FirebaseFunctions _functions;

  /// Pide al servidor que marque como consulta el chat con [trainerId].
  ///
  /// El `chatId` NO viaja: lo deriva el servidor del uid del llamador y de
  /// [trainerId], así que un llamador sólo puede tocar el chat que le
  /// corresponde con ese PF.
  ///
  /// Es idempotente: si ya estaba marcado, o si es un chat de Coach, el
  /// servidor contesta `noop` sin escribir.
  Future<void> promote(String trainerId) async {
    final callable = _functions.httpsCallable('promoteChatToInquiry');
    await callable.call<Map<String, dynamic>>({'trainerId': trainerId});
  }
}
