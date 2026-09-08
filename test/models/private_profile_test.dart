import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';
import 'package:meupet_agenda_app/models/private_profile.dart';

void main() {
  group('PrivateProfile.fromMap', () {
    test('parses the firestore document', () {
      final createdAt = Timestamp.fromDate(DateTime(2026, 1, 2, 3, 4));
      final profile = PrivateProfile.fromMap('u1', {
        'cpf': '52998224725',
        'cpfLast2': '25',
        'address': {
          'postalCode': '01310100',
          'street': 'Avenida Paulista',
          'number': '1578',
          'complement': '8 andar',
          'neighborhood': 'Bela Vista',
          'city': 'Sao Paulo',
          'state': 'SP',
          'country': 'BR',
        },
        'createdAt': createdAt,
        'updatedAt': createdAt,
      });

      expect(profile.userId, 'u1');
      expect(profile.cpfCanonical, '52998224725');
      expect(profile.cpfLast2, '25');
      expect(profile.address.postalCode, '01310100');
      expect(profile.address.street, 'Avenida Paulista');
      expect(profile.address.number, '1578');
      expect(profile.address.complement, '8 andar');
      expect(profile.address.neighborhood, 'Bela Vista');
      expect(profile.address.city, 'Sao Paulo');
      expect(profile.address.state, 'SP');
      expect(profile.address.country, 'BR');
      expect(profile.createdAt, DateTime(2026, 1, 2, 3, 4));
      expect(profile.updatedAt, DateTime(2026, 1, 2, 3, 4));
    });

    test('applies defaults for missing timestamps and a missing address', () {
      final profile = PrivateProfile.fromMap('u2', {
        'cpf': '52998224725',
        'cpfLast2': '25',
      });

      expect(profile.userId, 'u2');
      expect(profile.cpfCanonical, '52998224725');
      expect(profile.cpfLast2, '25');
      expect(profile.createdAt, isNull);
      expect(profile.updatedAt, isNull);
      expect(profile.address.street, '');
      expect(profile.address.complement, isNull);
      expect(profile.address.country, 'BR');
    });
  });

  group('PrivateProfile.cpfMasked', () {
    test('masks all digits but the last two, from cpfLast2', () {
      final profile = PrivateProfile(
        userId: 'u5',
        cpfCanonical: '52998224725',
        cpfLast2: '25',
        address: const PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1578',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      expect(profile.cpfMasked, '***.***.***-25');
    });

    test('falls back to the canonical CPF tail when cpfLast2 is missing', () {
      final profile = PrivateProfile(
        userId: 'u6',
        cpfCanonical: '52998224725',
        cpfLast2: '',
        address: const PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1578',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      expect(profile.cpfMasked, '***.***.***-25');
    });

    test('reports missing when no CPF data exists', () {
      final profile = PrivateProfile(
        userId: 'u7',
        cpfCanonical: '',
        cpfLast2: '',
        address: const PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1578',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      expect(profile.cpfMasked, 'Nao informado');
    });
  });

  group('PrivateProfile round-trip', () {
    test('toMap/fromMap preserves all fields including null complement', () {
      final original = PrivateProfile(
        userId: 'u3',
        cpfCanonical: '52998224725',
        cpfLast2: '25',
        address: PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1578',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 2, 1),
      );

      final restored = PrivateProfile.fromMap(
        original.userId,
        original.toMap(),
      );

      expect(restored.userId, original.userId);
      expect(restored.cpfCanonical, original.cpfCanonical);
      expect(restored.cpfLast2, original.cpfLast2);
      expect(restored.address.postalCode, original.address.postalCode);
      expect(restored.address.street, original.address.street);
      expect(restored.address.number, original.address.number);
      expect(restored.address.complement, isNull);
      expect(restored.address.neighborhood, original.address.neighborhood);
      expect(restored.address.city, original.address.city);
      expect(restored.address.state, original.address.state);
      expect(restored.address.country, 'BR');
      expect(restored.createdAt, DateTime(2026, 1, 1));
      expect(restored.updatedAt, DateTime(2026, 2, 1));
    });

    test('toMap writes the canonical cpf and last two digits', () {
      final profile = PrivateProfile(
        userId: 'u4',
        cpfCanonical: '52998224725',
        cpfLast2: '25',
        address: PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1578',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      expect(profile.toMap()['cpf'], '52998224725');
      expect(profile.toMap()['cpfLast2'], '25');
      expect(profile.toMap()['address'], isA<Map<String, dynamic>>());
    });
  });
}
