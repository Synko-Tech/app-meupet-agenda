import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';

void main() {
  group('PostalAddress.fromMap', () {
    test('parses all fields', () {
      final address = PostalAddress.fromMap(const {
        'postalCode': '01310100',
        'street': 'Avenida Paulista',
        'number': '1578',
        'complement': '8 andar',
        'neighborhood': 'Bela Vista',
        'city': 'Sao Paulo',
        'state': 'SP',
        'country': 'BR',
      });

      expect(address.postalCode, '01310100');
      expect(address.street, 'Avenida Paulista');
      expect(address.number, '1578');
      expect(address.complement, '8 andar');
      expect(address.neighborhood, 'Bela Vista');
      expect(address.city, 'Sao Paulo');
      expect(address.state, 'SP');
      expect(address.country, 'BR');
    });

    test('parses the Portuguese fallback keys', () {
      final address = PostalAddress.fromMap(const {
        'cep': '01310100',
        'logradouro': 'Avenida Paulista',
        'numero': '1578',
        'complemento': '8 andar',
        'bairro': 'Bela Vista',
        'cidade': 'Sao Paulo',
        'uf': 'SP',
        'pais': 'BR',
      });

      expect(address.postalCode, '01310100');
      expect(address.street, 'Avenida Paulista');
      expect(address.number, '1578');
      expect(address.complement, '8 andar');
      expect(address.neighborhood, 'Bela Vista');
      expect(address.city, 'Sao Paulo');
      expect(address.state, 'SP');
      expect(address.country, 'BR');
    });

    test('treats a missing complement as null and country as BR', () {
      final address = PostalAddress.fromMap(const {
        'postalCode': '01310100',
        'street': 'Avenida Paulista',
        'number': '1578',
        'neighborhood': 'Bela Vista',
        'city': 'Sao Paulo',
        'state': 'SP',
      });

      expect(address.complement, isNull);
      expect(address.country, 'BR');
    });
  });

  group('PostalAddress round-trip', () {
    test('toMap/fromMap preserves all fields', () {
      final original = PostalAddress(
        postalCode: '01310100',
        street: 'Avenida Paulista',
        number: '1578',
        complement: '8 andar',
        neighborhood: 'Bela Vista',
        city: 'Sao Paulo',
        state: 'SP',
        country: 'BR',
      );

      final restored = PostalAddress.fromMap(original.toMap());

      expect(restored.postalCode, original.postalCode);
      expect(restored.street, original.street);
      expect(restored.number, original.number);
      expect(restored.complement, original.complement);
      expect(restored.neighborhood, original.neighborhood);
      expect(restored.city, original.city);
      expect(restored.state, original.state);
      expect(restored.country, original.country);
    });

    test('round-trip keeps a null complement as null', () {
      final original = PostalAddress(
        postalCode: '01310100',
        street: 'Avenida Paulista',
        number: '1578',
        neighborhood: 'Bela Vista',
        city: 'Sao Paulo',
        state: 'SP',
      );

      final restored = PostalAddress.fromMap(original.toMap());

      expect(restored.complement, isNull);
      expect(restored.country, 'BR');
    });
  });
}
