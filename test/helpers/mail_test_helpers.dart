import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/verified_email.dart';

/// `UserProfile.emailVerification` de una cuenta que ya confirmó [email] con el
/// código de 6 dígitos para [role].
///
/// Para todo test que NO trate del gate del mail: describe la cuenta como ya
/// verificada. Lo que decide el redirect es `correoVerificadoParaElRol`: si el
/// `MockUser` del test tiene `email` stubbeado, el gate compara contra ese mail,
/// y sin esta entrada (o con otro mail) manda a /verificar-mail, así que [email]
/// tiene que ser el mismo. Con el `email` sin stubbear (null) el gate no corre,
/// y esta entrada no es lo que deja pasar.
Map<String, VerifiedEmail> mailConfirmadoPara(UserRole role, String email) => {
      role.toJson(): VerifiedEmail(
        email: email,
        verifiedAt: DateTime.utc(2026, 1, 1),
      ),
    };
