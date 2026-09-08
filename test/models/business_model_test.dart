import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/business_model.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';

void main() {
  group('BusinessStatus', () {
    test('maps firestore values', () {
      expect(BusinessStatus.fromFirestore('ATIVO'), BusinessStatus.active);
      expect(BusinessStatus.fromFirestore('INATIVO'), BusinessStatus.inactive);
      expect(
        BusinessStatus.fromFirestore('SUSPENSO'),
        BusinessStatus.suspended,
      );
      expect(
        BusinessStatus.fromFirestore('desconhecido'),
        BusinessStatus.active,
      );
    });

    test('round-trips firestore values', () {
      for (final status in BusinessStatus.values) {
        expect(BusinessStatus.fromFirestore(status.firestoreValue), status);
      }
    });
  });

  group('BusinessModel.fromMap', () {
    test('parses the public business shape', () {
      final business = BusinessModel.fromMap('b1', {
        'nome': 'Pet Shop Central',
        'descricao': 'Banho e tosa',
        'timezone': 'America/Sao_Paulo',
        'status': 'ATIVO',
        'ownerId': 'u1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      });

      expect(business.id, 'b1');
      expect(business.name, 'Pet Shop Central');
      expect(business.description, 'Banho e tosa');
      expect(business.timezone, 'America/Sao_Paulo');
      expect(business.status, BusinessStatus.active);
      expect(business.ownerId, 'u1');
      expect(business.isActive, isTrue);
      expect(business.createdAt, DateTime(2026, 8, 1));
    });

    test('parses business registration fields', () {
      final business = BusinessModel.fromMap('b1', {
        'nome': 'Pet Shop Central',
        'razaoSocial': 'Central Pet Comercio LTDA',
        'cnpj': '11222333000181',
        'telefone': '1140028922',
        'endereco': {
          'postalCode': '01310100',
          'street': 'Av. Paulista',
          'number': '1000',
          'neighborhood': 'Bela Vista',
          'city': 'Sao Paulo',
          'state': 'SP',
          'country': 'BR',
        },
        'status': 'ATIVO',
      });

      expect(business.legalName, 'Central Pet Comercio LTDA');
      expect(business.cnpj, '11222333000181');
      expect(business.cnpjMasked, '**.***.***/****-81');
      expect(business.phone, '1140028922');
      expect(business.address, isNotNull);
      expect(business.address!.city, 'Sao Paulo');
      expect(business.address!.state, 'SP');
    });

    test('cnpjMasked is null when cnpj is missing', () {
      final business = BusinessModel.fromMap('b1', {'nome': 'Loja'});
      expect(business.cnpjMasked, isNull);
    });

    test('falls back to defaults when fields are missing', () {
      final business = BusinessModel.fromMap('b1', {'nome': 'Loja'});

      expect(business.timezone, 'America/Sao_Paulo');
      expect(business.status, BusinessStatus.active);
      expect(business.description, isNull);
      expect(business.ownerId, isNull);
      expect(business.legalName, isNull);
      expect(business.cnpj, isNull);
      expect(business.phone, isNull);
      expect(business.address, isNull);
    });

    test('toMap/fromMap round-trip preserves all fields', () {
      final original = BusinessModel(
        id: 'b1',
        name: 'Pet Shop Central',
        description: 'Banho e tosa',
        legalName: 'Central Pet Comercio LTDA',
        cnpj: '11222333000181',
        phone: '1140028922',
        address: PostalAddress(
          postalCode: '01310100',
          street: 'Av. Paulista',
          number: '1000',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
        timezone: 'America/Sao_Paulo',
        status: BusinessStatus.inactive,
        ownerId: 'u1',
      );

      final restored = BusinessModel.fromMap(original.id, original.toMap());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.legalName, original.legalName);
      expect(restored.cnpj, original.cnpj);
      expect(restored.phone, original.phone);
      expect(restored.address?.postalCode, original.address?.postalCode);
      expect(restored.timezone, original.timezone);
      expect(restored.status, original.status);
      expect(restored.ownerId, original.ownerId);
      expect(restored.toMap()['status'], 'INATIVO');
    });
  });
}
