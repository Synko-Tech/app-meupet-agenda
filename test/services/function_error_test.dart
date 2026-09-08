import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/services/function_error.dart';
import 'package:mocktail/mocktail.dart';

class MockFunctionsException extends Mock
    implements FirebaseFunctionsException {}

void main() {
  group('friendlyErrorMessage', () {
    test('prefers the server message verbatim', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn('Horario ja reservado.');
      when(() => error.code).thenReturn('functions/already-exists');

      expect(friendlyErrorMessage(error), 'Horario ja reservado.');
    });

    test('trims the server message', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn('  Mensagem com espacos.  ');
      when(() => error.code).thenReturn('functions/invalid-argument');

      expect(friendlyErrorMessage(error), 'Mensagem com espacos.');
    });

    test('maps unauthenticated without a message', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn('');
      when(() => error.code).thenReturn('functions/unauthenticated');

      expect(friendlyErrorMessage(error), 'Sessao expirada. Entre novamente.');
    });

    test('maps permission-denied without a message', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn(null);
      when(() => error.code).thenReturn('functions/permission-denied');

      expect(
        friendlyErrorMessage(error),
        'Voce nao tem permissao para esta acao.',
      );
    });

    test('maps not-found to a friendly unavailable message', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn(null);
      when(() => error.code).thenReturn('functions/not-found');

      expect(
        friendlyErrorMessage(error),
        'Servico indisponivel no momento. Tente novamente mais tarde.',
      );
    });

    test('hides a technical NOT_FOUND message behind the fallback', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn('NOT_FOUND');
      when(() => error.code).thenReturn('functions/not-found');

      expect(
        friendlyErrorMessage(error),
        'Servico indisponivel no momento. Tente novamente mais tarde.',
      );
    });

    test('keeps domain messages over the not-found fallback', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn('Profissional nao encontrado.');
      when(() => error.code).thenReturn('functions/not-found');

      expect(friendlyErrorMessage(error), 'Profissional nao encontrado.');
    });

    test('hides technical PERMISSION_DENIED behind the fallback', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn('PERMISSION_DENIED');
      when(() => error.code).thenReturn('functions/permission-denied');

      expect(
        friendlyErrorMessage(error),
        'Voce nao tem permissao para esta acao.',
      );
    });

    test('maps failed-precondition without a message', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn(null);
      when(() => error.code).thenReturn('functions/failed-precondition');

      expect(friendlyErrorMessage(error), 'Operacao nao permitida no momento.');
    });

    test('maps invalid-argument without a message', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn(null);
      when(() => error.code).thenReturn('functions/invalid-argument');

      expect(
        friendlyErrorMessage(error),
        'Dados invalidos. Verifique as informacoes.',
      );
    });

    test('maps already-exists without a message', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn(null);
      when(() => error.code).thenReturn('functions/already-exists');

      expect(friendlyErrorMessage(error), 'Horario ja reservado.');
    });

    test('maps unavailable without a message', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn(null);
      when(() => error.code).thenReturn('functions/unavailable');

      expect(
        friendlyErrorMessage(error),
        'Servico indisponivel. Tente novamente em instantes.',
      );
    });

    test('falls back to a generic message for unknown codes', () {
      final error = MockFunctionsException();
      when(() => error.message).thenReturn(null);
      when(() => error.code).thenReturn('functions/aborted');

      expect(
        friendlyErrorMessage(error),
        'Falha na operacao. Tente novamente.',
      );
    });

    test('strips Bad state prefix from plain errors', () {
      expect(friendlyErrorMessage(StateError('Agenda cheia')), 'Agenda cheia');
    });

    test('strips Exception prefix from plain errors', () {
      expect(friendlyErrorMessage(Exception('Falha de rede')), 'Falha de rede');
    });

    test('keeps plain errors unchanged', () {
      expect(friendlyErrorMessage('erro generico'), 'erro generico');
    });
  });
}
