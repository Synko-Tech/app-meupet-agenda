import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/package_model.dart';

void main() {
  group('CustomerPackageStatus.firestoreValue', () {
    test('maps every status to its firestore string', () {
      expect(CustomerPackageStatus.active.firestoreValue, 'ATIVO');
      expect(CustomerPackageStatus.finished.firestoreValue, 'FINALIZADO');
      expect(CustomerPackageStatus.expired.firestoreValue, 'VENCIDO');
      expect(CustomerPackageStatus.canceled.firestoreValue, 'CANCELADO');
    });
  });

  group('CustomerPackageStatus.label', () {
    test('exposes a display label per status', () {
      expect(CustomerPackageStatus.active.label, 'Ativo');
      expect(CustomerPackageStatus.finished.label, 'Finalizado');
      expect(CustomerPackageStatus.expired.label, 'Vencido');
      expect(CustomerPackageStatus.canceled.label, 'Cancelado');
    });
  });

  group('CustomerPackageStatus.fromFirestore', () {
    test('parses every known status case-insensitively', () {
      expect(
        CustomerPackageStatus.fromFirestore('FINALIZADO'),
        CustomerPackageStatus.finished,
      );
      expect(
        CustomerPackageStatus.fromFirestore('vencido'),
        CustomerPackageStatus.expired,
      );
      expect(
        CustomerPackageStatus.fromFirestore('CANCELADO'),
        CustomerPackageStatus.canceled,
      );
    });

    test('falls back to active for unknown or null values', () {
      expect(
        CustomerPackageStatus.fromFirestore('desconhecido'),
        CustomerPackageStatus.active,
      );
      expect(
        CustomerPackageStatus.fromFirestore(null),
        CustomerPackageStatus.active,
      );
    });
  });

  group('BusinessPackageModel', () {
    test('fromMap parses the Portuguese firestore keys', () {
      final pkg = BusinessPackageModel.fromMap('p1', {
        'id_servico': 's1',
        'serviceName': 'Banho',
        'nome': 'Banho 5x',
        'quantidade_creditos': 5,
        'valor': '150,50',
        'validade_dias': 30,
        'ativo': false,
      });

      expect(pkg.id, 'p1');
      expect(pkg.serviceId, 's1');
      expect(pkg.serviceName, 'Banho');
      expect(pkg.name, 'Banho 5x');
      expect(pkg.totalCredits, 5);
      expect(pkg.price, 150.5);
      expect(pkg.validityDays, 30);
      expect(pkg.isActive, isFalse);
    });

    test('fromMap parses the English fallback keys and defaults', () {
      final pkg = BusinessPackageModel.fromMap('p2', {
        'serviceId': 's2',
        'name': 'Tosa 3x',
        'totalCredits': 3,
        'price': 90.0,
        'validityDays': 60,
      });

      expect(pkg.serviceId, 's2');
      expect(pkg.name, 'Tosa 3x');
      expect(pkg.totalCredits, 3);
      expect(pkg.isActive, isTrue);
      expect(pkg.createdAt, isNull);
    });

    test('toMap/fromMap round-trip preserves all fields', () {
      final original = BusinessPackageModel(
        id: 'p9',
        serviceId: 's1',
        serviceName: 'Banho',
        name: 'Banho 5x',
        totalCredits: 5,
        price: 150.0,
        validityDays: 30,
        isActive: true,
        updatedAt: DateTime(2026, 5, 1),
      );

      final restored = BusinessPackageModel.fromMap(
        original.id,
        original.toMap(),
      );

      expect(restored.id, original.id);
      expect(restored.serviceId, original.serviceId);
      expect(restored.name, original.name);
      expect(restored.totalCredits, 5);
      expect(restored.price, 150.0);
      expect(restored.validityDays, 30);
      expect(restored.isActive, isTrue);
      expect(restored.updatedAt, DateTime(2026, 5, 1));
      expect(original.toMap()['nome'], 'Banho 5x');
    });
  });

  group('CustomerPackageModel', () {
    final validMap = {
      'id_cliente': 'c1',
      'id_pacote': 'p1',
      'id_servico': 's1',
      'packageName': 'Banho 5x',
      'serviceName': 'Banho',
      'creditos_totais': 5,
      'creditos_usados': 2,
      'data_compra': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'data_validade': Timestamp.fromDate(DateTime(2026, 4, 1)),
      'status': 'ATIVO',
    };

    test('fromMap parses the Portuguese firestore keys', () {
      final pkg = CustomerPackageModel.fromMap('cp1', validMap);

      expect(pkg.id, 'cp1');
      expect(pkg.clientId, 'c1');
      expect(pkg.packageId, 'p1');
      expect(pkg.serviceId, 's1');
      expect(pkg.packageName, 'Banho 5x');
      expect(pkg.serviceName, 'Banho');
      expect(pkg.totalCredits, 5);
      expect(pkg.usedCredits, 2);
      expect(pkg.purchaseDate, DateTime(2026, 1, 1));
      expect(pkg.validUntil, DateTime(2026, 4, 1));
      expect(pkg.status, CustomerPackageStatus.active);
    });

    test('fromMap parses the English fallback keys', () {
      final pkg = CustomerPackageModel.fromMap('cp2', {
        'clientId': 'c2',
        'packageId': 'p2',
        'serviceId': 's2',
        'nome': 'Tosa 3x',
        'totalCredits': 3,
        'usedCredits': 3,
        'purchaseDate': '2026-01-01T00:00:00.000',
        'validUntil': '2026-04-01T00:00:00.000',
        'status': 'FINALIZADO',
      });

      expect(pkg.clientId, 'c2');
      expect(pkg.packageName, 'Tosa 3x');
      expect(pkg.status, CustomerPackageStatus.finished);
    });

    group('derived getters', () {
      CustomerPackageModel pkg({
        required int total,
        required int used,
        CustomerPackageStatus status = CustomerPackageStatus.active,
        DateTime? validUntil,
      }) => CustomerPackageModel(
        id: 'cp',
        clientId: 'c',
        packageId: 'p',
        serviceId: 's',
        packageName: 'P',
        serviceName: 'S',
        totalCredits: total,
        usedCredits: used,
        purchaseDate: DateTime(2026, 1, 1),
        // Validade futura por padrao: datas fixas no passado expiram e
        // mudariam o resultado de canUse.
        validUntil: validUntil ?? DateTime.now().add(const Duration(days: 30)),
        status: status,
      );

      test('remainingCredits is the difference', () {
        expect(pkg(total: 5, used: 2).remainingCredits, 3);
      });

      test('canUse requires active status and credits left', () {
        expect(pkg(total: 5, used: 2).canUse, isTrue);
        expect(pkg(total: 5, used: 5).canUse, isFalse);
        expect(
          pkg(total: 5, used: 0, status: CustomerPackageStatus.finished).canUse,
          isFalse,
        );
        expect(
          pkg(total: 5, used: 0, status: CustomerPackageStatus.expired).canUse,
          isFalse,
        );
        expect(
          pkg(total: 5, used: 0, status: CustomerPackageStatus.canceled).canUse,
          isFalse,
        );
      });

      test(
        'canUse rejects an expired package even when ATIVO with credits',
        () {
          final expired = DateTime.now().subtract(const Duration(days: 1));
          expect(pkg(total: 5, used: 0, validUntil: expired).canUse, isFalse);
          expect(pkg(total: 5, used: 0, validUntil: expired).isExpired, isTrue);
        },
      );

      test('isExpired is false for a future validity date', () {
        final future = DateTime.now().add(const Duration(days: 30));
        expect(pkg(total: 5, used: 0, validUntil: future).isExpired, isFalse);
      });

      test('usageProgress clamps between 0 and 1', () {
        expect(pkg(total: 5, used: 2).usageProgress, 0.4);
        expect(pkg(total: 5, used: 99).usageProgress, 1.0);
        expect(pkg(total: 5, used: -3).usageProgress, 0.0);
        expect(pkg(total: 0, used: 0).usageProgress, 0.0);
      });
    });

    test('toMap/fromMap round-trip preserves all fields', () {
      final original = CustomerPackageModel(
        id: 'cp9',
        clientId: 'c1',
        packageId: 'p1',
        serviceId: 's1',
        packageName: 'Banho 5x',
        serviceName: 'Banho',
        totalCredits: 5,
        usedCredits: 2,
        purchaseDate: DateTime(2026, 1, 1),
        validUntil: DateTime(2026, 4, 1),
        status: CustomerPackageStatus.active,
      );

      final restored = CustomerPackageModel.fromMap(
        original.id,
        original.toMap(),
      );

      expect(restored.id, original.id);
      expect(restored.clientId, original.clientId);
      expect(restored.packageId, original.packageId);
      expect(restored.serviceId, original.serviceId);
      expect(restored.packageName, original.packageName);
      expect(restored.totalCredits, 5);
      expect(restored.usedCredits, 2);
      expect(restored.purchaseDate, original.purchaseDate);
      expect(restored.validUntil, original.validUntil);
      expect(restored.status, CustomerPackageStatus.active);
      expect(original.toMap()['status'], 'ATIVO');
    });
  });
}
