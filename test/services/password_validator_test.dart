import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/services/profile_validators.dart';

void main() {
  group('validatePassword - regras de cadastro', () {
    // Cada entrada negativa viola uma regra, mantendo as outras satisfeitas.
    // Assim, remover uma verificacao faz o respectivo teste falhar.
    test('rejeita senha nula', () {
      expect(validatePassword(null), isNotNull);
    });

    test('rejeita senha vazia', () {
      expect(validatePassword(''), isNotNull);
    });

    test('rejeita senha composta apenas de espacos', () {
      expect(validatePassword('        '), isNotNull);
    });

    test('rejeita sete caracteres mesmo com todas as classes exigidas', () {
      expect(validatePassword('Ab1!xyz'), isNotNull);
    });

    test('aceita exatamente oito caracteres com todas as classes', () {
      expect(validatePassword('Ab1!xyzw'), isNull);
    });

    test('aceita mais de oito caracteres com todas as classes', () {
      expect(validatePassword('MeuPet@2026'), isNull);
    });

    test('rejeita senha sem letra maiuscula', () {
      expect(validatePassword('senha@123'), isNotNull);
    });

    test('rejeita senha sem numero', () {
      expect(validatePassword('Senha@abc'), isNotNull);
    });

    test('rejeita senha sem caractere especial', () {
      expect(validatePassword('Senha123'), isNotNull);
    });

    test('aceita caractere especial no inicio', () {
      expect(validatePassword('!Abc1234'), isNull);
    });

    test('aceita caractere especial no fim', () {
      expect(validatePassword('Abc1234#'), isNull);
    });

    test('nao exige letra minuscula que nao faz parte dos requisitos', () {
      expect(validatePassword('ABC1234!'), isNull);
    });
  });
}
