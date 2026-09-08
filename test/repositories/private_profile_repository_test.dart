import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';
import 'package:meupet_agenda_app/repositories/private_profile_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}

// mocktail generates noSuchMethod-based mocks; the sealed-class lint does not
// apply to pure test doubles.
// ignore: subtype_of_sealed_class
class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Object?> {}

PrivateProfileRepository buildRepository({
  FirebaseFirestore? firestore,
  HttpsCallable? callable,
  HttpsCallable? updateAddressCallable,
}) {
  return PrivateProfileRepository(
    firestore: firestore ?? MockFirestore(),
    completeOwnProfileCallable: callable ?? MockHttpsCallable(),
    updateOwnAddressCallable: updateAddressCallable ?? MockHttpsCallable(),
  );
}

void main() {
  group('PrivateProfileRepository.privateProfileStream', () {
    test('maps the private document to PrivateProfile', () async {
      final firestore = MockFirestore();
      final collection = MockCollectionReference();
      final docRef = MockDocumentReference();
      final snapshot = MockDocumentSnapshot();

      when(() => firestore.collection('userPrivate')).thenReturn(collection);
      when(() => collection.doc('u1')).thenReturn(docRef);
      when(() => docRef.snapshots()).thenAnswer((_) => Stream.value(snapshot));
      when(() => snapshot.exists).thenReturn(true);
      when(() => snapshot.data()).thenReturn({
        'cpf': '52998224725',
        'cpfLast2': '25',
        'address': {
          'postalCode': '01310100',
          'street': 'Avenida Paulista',
          'number': '1578',
          'neighborhood': 'Bela Vista',
          'city': 'Sao Paulo',
          'state': 'SP',
        },
      });

      final repository = buildRepository(firestore: firestore);
      final profile = await repository.privateProfileStream('u1').first;

      expect(profile, isNotNull);
      expect(profile!.userId, 'u1');
      expect(profile.cpfCanonical, '52998224725');
      expect(profile.cpfLast2, '25');
      expect(profile.address.postalCode, '01310100');
      expect(profile.address.street, 'Avenida Paulista');
      expect(profile.address.number, '1578');
      expect(profile.address.neighborhood, 'Bela Vista');
      expect(profile.address.city, 'Sao Paulo');
      expect(profile.address.state, 'SP');
    });

    test('emits null when the document does not exist', () async {
      final firestore = MockFirestore();
      final collection = MockCollectionReference();
      final docRef = MockDocumentReference();
      final snapshot = MockDocumentSnapshot();

      when(() => firestore.collection('userPrivate')).thenReturn(collection);
      when(() => collection.doc('u9')).thenReturn(docRef);
      when(() => docRef.snapshots()).thenAnswer((_) => Stream.value(snapshot));
      when(() => snapshot.exists).thenReturn(false);

      final repository = buildRepository(firestore: firestore);
      final profile = await repository.privateProfileStream('u9').first;

      expect(profile, isNull);
    });
  });

  group('PrivateProfileRepository.completeOwnProfile', () {
    test('sends the canonical unmasked payload', () async {
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult();
      Map<String, dynamic>? captured;

      when(
        () => result.data,
      ).thenReturn({'profileComplete': true, 'cpfMasked': '***.982.247-25'});
      when(() => callable.call(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as Map<String, dynamic>;
        return result;
      });

      final repository = buildRepository(callable: callable);
      await repository.completeOwnProfile(
        name: 'Maria Souza',
        phone: '(11) 91234-5678',
        cpf: '529.982.247-25',
        address: PostalAddress(
          postalCode: '01310-100',
          street: 'Avenida Paulista',
          number: '1578',
          complement: '8 andar',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      expect(captured, isNotNull);
      expect(captured!['name'], 'Maria Souza');
      expect(captured!['phone'], '(11) 91234-5678');
      expect(captured!['cpf'], '52998224725');

      final address = captured!['address'] as Map<String, dynamic>;
      expect(address['postalCode'], '01310100');
      expect(address['street'], 'Avenida Paulista');
      expect(address['number'], '1578');
      expect(address['complement'], '8 andar');
      expect(address['neighborhood'], 'Bela Vista');
      expect(address['city'], 'Sao Paulo');
      expect(address['state'], 'SP');
      expect(address['country'], 'BR');
    });

    test('omits optional fields when absent', () async {
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult();
      Map<String, dynamic>? captured;

      when(
        () => result.data,
      ).thenReturn({'profileComplete': true, 'cpfMasked': '***.982.247-25'});
      when(() => callable.call(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as Map<String, dynamic>;
        return result;
      });

      final repository = buildRepository(callable: callable);
      await repository.completeOwnProfile(
        name: 'Maria Souza',
        cpf: '52998224725',
        address: PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1578',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      expect(captured!['phone'], isNull);
      expect(
        (captured!['address'] as Map<String, dynamic>)['complement'],
        isNull,
      );
    });

    test('throws StateError when the server response is not a map', () async {
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult();

      when(() => result.data).thenReturn('resposta estranha');
      when(() => callable.call(any())).thenAnswer((_) async => result);

      final repository = buildRepository(callable: callable);

      expect(
        () => repository.completeOwnProfile(
          name: 'Maria Souza',
          cpf: '52998224725',
          address: PostalAddress(
            postalCode: '01310100',
            street: 'Avenida Paulista',
            number: '1578',
            neighborhood: 'Bela Vista',
            city: 'Sao Paulo',
            state: 'SP',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('PrivateProfileRepository.updateOwnAddress', () {
    test('sends the canonical address payload', () async {
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult();
      Map<String, dynamic>? captured;

      when(() => result.data).thenReturn({'updated': true});
      when(() => callable.call(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as Map<String, dynamic>;
        return result;
      });

      final repository = buildRepository(updateAddressCallable: callable);
      await repository.updateOwnAddress(
        address: PostalAddress(
          postalCode: '01310-100',
          street: 'Avenida Paulista',
          number: '1578',
          complement: '8 andar',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'sp',
        ),
      );

      expect(captured, isNotNull);
      final address = captured!['address'] as Map<String, dynamic>;
      expect(address['postalCode'], '01310100');
      expect(address['street'], 'Avenida Paulista');
      expect(address['number'], '1578');
      expect(address['complement'], '8 andar');
      expect(address['neighborhood'], 'Bela Vista');
      expect(address['city'], 'Sao Paulo');
      // UF enviada como digitada; o backend canonicaliza para 'SP'.
      expect(address['state'], 'sp');
      expect(address['country'], 'BR');
      expect(captured!.keys, ['address']);
    });

    test('omits a blank complement', () async {
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult();
      Map<String, dynamic>? captured;

      when(() => result.data).thenReturn({'updated': true});
      when(() => callable.call(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as Map<String, dynamic>;
        return result;
      });

      final repository = buildRepository(updateAddressCallable: callable);
      await repository.updateOwnAddress(
        address: PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1578',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      final address = captured!['address'] as Map<String, dynamic>;
      expect(address.containsKey('complement'), isFalse);
    });

    test('throws StateError when the server response is not a map', () async {
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult();

      when(() => result.data).thenReturn('resposta estranha');
      when(() => callable.call(any())).thenAnswer((_) async => result);

      final repository = buildRepository(updateAddressCallable: callable);

      expect(
        () => repository.updateOwnAddress(
          address: PostalAddress(
            postalCode: '01310100',
            street: 'Avenida Paulista',
            number: '1578',
            neighborhood: 'Bela Vista',
            city: 'Sao Paulo',
            state: 'SP',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
