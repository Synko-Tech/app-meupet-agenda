import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meupet_agenda_app/services/cep_service.dart';

void main() {
  group('CepService.lookup', () {
    test('does not call the network for a CEP without 8 digits', () async {
      final client = MockClient((request) async {
        throw StateError('a chamada nao deveria acontecer');
      });
      final service = CepService(client: client);

      expect(
        () => service.lookup('123'),
        throwsA(
          isA<CepException>().having(
            (e) => e.kind,
            'kind',
            CepExceptionKind.invalid,
          ),
        ),
      );
    });

    test('calls the exact ViaCEP URL', () async {
      Uri? captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response('{}', 200);
      });
      final service = CepService(client: client);

      await service.lookup('01310-100');

      expect(captured, Uri.parse('https://viacep.com.br/ws/01310100/json/'));
    });

    test('parses a valid response', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'cep': '01310-100',
            'logradouro': 'Avenida Paulista',
            'bairro': 'Bela Vista',
            'localidade': 'Sao Paulo',
            'uf': 'SP',
          }),
          200,
        ),
      );
      final service = CepService(client: client);

      final lookup = await service.lookup('01310100');

      expect(lookup.postalCode, '01310100');
      expect(lookup.street, 'Avenida Paulista');
      expect(lookup.neighborhood, 'Bela Vista');
      expect(lookup.city, 'Sao Paulo');
      expect(lookup.state, 'SP');
    });

    test('throws notFound when ViaCEP returns {erro: true}', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'erro': true}), 200),
      );
      final service = CepService(client: client);

      expect(
        () => service.lookup('99999999'),
        throwsA(
          isA<CepException>().having(
            (e) => e.kind,
            'kind',
            CepExceptionKind.notFound,
          ),
        ),
      );
    });

    test('throws invalid when the HTTP status is not 200', () async {
      final client = MockClient(
        (request) async => http.Response('Bad Request', 400),
      );
      final service = CepService(client: client);

      expect(
        () => service.lookup('01310100'),
        throwsA(
          isA<CepException>().having(
            (e) => e.kind,
            'kind',
            CepExceptionKind.invalid,
          ),
        ),
      );
    });

    test('throws unavailable for invalid JSON', () async {
      final client = MockClient(
        (request) async => http.Response('nao-e-json', 200),
      );
      final service = CepService(client: client);

      expect(
        () => service.lookup('01310100'),
        throwsA(
          isA<CepException>().having(
            (e) => e.kind,
            'kind',
            CepExceptionKind.unavailable,
          ),
        ),
      );
    });

    test('throws unavailable for network errors', () async {
      final client = MockClient(
        (request) async => throw http.ClientException('connection refused'),
      );
      final service = CepService(client: client);

      expect(
        () => service.lookup('01310100'),
        throwsA(
          isA<CepException>().having(
            (e) => e.kind,
            'kind',
            CepExceptionKind.unavailable,
          ),
        ),
      );
    });
  });
}
