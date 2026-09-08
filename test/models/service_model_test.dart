import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/service_model.dart';

void main() {
  test('empty() provides sensible defaults', () {
    final service = ServiceModel.empty();
    expect(service.id, '');
    expect(service.name, '');
    expect(service.description, '');
    expect(service.durationMinutes, 60);
    expect(service.price, 0);
    expect(service.isActive, isTrue);
  });

  group('ServiceModel.fromMap', () {
    test('parses the Portuguese firestore keys', () {
      final service = ServiceModel.fromMap('s1', {
        'nome': 'Banho',
        'descricao': 'Banho completo',
        'duracao_minutos': 60,
        'valor': '80,50',
        'ativo': false,
      });

      expect(service.id, 's1');
      expect(service.name, 'Banho');
      expect(service.description, 'Banho completo');
      expect(service.durationMinutes, 60);
      expect(service.price, 80.5);
      expect(service.isActive, isFalse);
    });

    test('parses the English fallback keys and defaults', () {
      final service = ServiceModel.fromMap('s2', {
        'name': 'Tosa',
        'description': 'Tosa higienica',
        'durationMinutes': 45,
        'price': 60.0,
      });

      expect(service.name, 'Tosa');
      expect(service.durationMinutes, 45);
      expect(service.price, 60.0);
      expect(service.isActive, isTrue);
      expect(service.createdAt, isNull);
      expect(service.updatedAt, isNull);
    });

    test('applies defaults for missing numeric fields', () {
      final service = ServiceModel.fromMap('s3', {});
      expect(service.durationMinutes, 0);
      expect(service.price, 0);
      expect(service.isActive, isTrue);
    });

    test('parses timestamps', () {
      final ts = Timestamp.fromDate(DateTime(2026, 1, 1));
      final service = ServiceModel.fromMap('s4', {
        'createdAt': ts,
        'updatedAt': ts,
      });
      expect(service.createdAt, DateTime(2026, 1, 1));
      expect(service.updatedAt, DateTime(2026, 1, 1));
    });
  });

  test('toMap/fromMap round-trip preserves all fields', () {
    final original = ServiceModel(
      id: 's9',
      name: 'Banho',
      description: 'Banho completo',
      durationMinutes: 60,
      price: 80.0,
      isActive: true,
      updatedAt: DateTime(2026, 5, 1),
    );

    final restored = ServiceModel.fromMap(original.id, original.toMap());

    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.description, original.description);
    expect(restored.durationMinutes, 60);
    expect(restored.price, 80.0);
    expect(restored.isActive, isTrue);
    expect(restored.updatedAt, DateTime(2026, 5, 1));
    expect(original.toMap()['nome'], 'Banho');
    expect(original.toMap()['duracao_minutos'], 60);
  });

  group('ServiceModel.copyWith', () {
    const service = ServiceModel(
      id: 's1',
      name: 'Banho',
      description: 'Banho completo',
      durationMinutes: 60,
      price: 80.0,
    );

    test('keeps unchanged values', () {
      final copy = service.copyWith(name: 'Banho Premium');
      expect(copy.id, 's1');
      expect(copy.name, 'Banho Premium');
      expect(copy.durationMinutes, 60);
      expect(copy.price, 80.0);
      expect(copy.isActive, isTrue);
    });

    test('updates active flag', () {
      expect(service.copyWith(isActive: false).isActive, isFalse);
    });
  });
}
