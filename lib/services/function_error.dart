import 'package:cloud_functions/cloud_functions.dart';

/// Messages that are pure protocol/HTTP codes (e.g. the endpoint returning
/// 404 before a handler runs, which surfaces as `NOT_FOUND`). They must never
/// be shown verbatim; only real domain messages from the backend win.
const Set<String> _technicalMessages = {
  'NOT_FOUND',
  'NOT FOUND',
  'PERMISSION_DENIED',
  'UNAUTHENTICATED',
  'UNAVAILABLE',
  'INVALID_ARGUMENT',
  'FAILED_PRECONDITION',
  'ALREADY_EXISTS',
  'ABORTED',
};

/// Maps a thrown error from a callable to a user-friendly Portuguese message.
///
/// The backend throws `HttpsError(code, message)` where the message is
/// already user-appropriate ('Horario ja reservado.', 'Fora do horario de
/// atendimento.', ...) — that message is preferred verbatim, unless it is a
/// technical protocol code. The code-based fallbacks cover missing messages
/// and technical codes (e.g. a 404 endpoint response) so users never see
/// raw SDK codes.
String friendlyErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    final message = error.message?.trim() ?? '';
    final isTechnical = _technicalMessages.contains(message.toUpperCase());
    if (message.isNotEmpty && !isTechnical) {
      return message;
    }
    final code = error.code.replaceFirst('functions/', '');
    return switch (code) {
      'unauthenticated' => 'Sessao expirada. Entre novamente.',
      'permission-denied' => 'Voce nao tem permissao para esta acao.',
      // A technical `not-found` (e.g. the endpoint responding 404 because the
      // function is not deployed) must never surface as-is; the backend's own
      // domain messages ('Servico nao encontrado.', ...) still win via
      // the message path above.
      'not-found' =>
        'Servico indisponivel no momento. Tente novamente mais tarde.',
      'failed-precondition' => 'Operacao nao permitida no momento.',
      'invalid-argument' => 'Dados invalidos. Verifique as informacoes.',
      'already-exists' => 'Horario ja reservado.',
      'unavailable' => 'Servico indisponivel. Tente novamente em instantes.',
      _ => 'Falha na operacao. Tente novamente.',
    };
  }
  return error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
}
