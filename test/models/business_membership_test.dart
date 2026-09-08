import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';

void main() {
  group('BusinessRole', () {
    test('maps firestore values', () {
      expect(BusinessRole.fromFirestore('owner'), BusinessRole.owner);
      expect(BusinessRole.fromFirestore('admin'), BusinessRole.admin);
      expect(
        BusinessRole.fromFirestore('collaborator'),
        BusinessRole.collaborator,
      );
      expect(BusinessRole.fromFirestore('client'), BusinessRole.client);
      expect(BusinessRole.fromFirestore('desconhecido'), BusinessRole.client);
    });

    test('staff roles are owner/admin/collaborator', () {
      expect(BusinessRole.owner.isStaff, isTrue);
      expect(BusinessRole.admin.isStaff, isTrue);
      expect(BusinessRole.collaborator.isStaff, isTrue);
      expect(BusinessRole.client.isStaff, isFalse);
    });

    test('business managers are owner/admin', () {
      expect(BusinessRole.owner.canManageBusiness, isTrue);
      expect(BusinessRole.admin.canManageBusiness, isTrue);
      expect(BusinessRole.collaborator.canManageBusiness, isFalse);
      expect(BusinessRole.client.canManageBusiness, isFalse);
    });
  });

  group('BusinessMembership.fromMap', () {
    test('parses the projection shape', () {
      final membership = BusinessMembership.fromMap('u1', {
        'businessId': 'b1',
        'businessName': 'Pet Shop Central',
        'role': 'owner',
        'ativo': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      });

      expect(membership.userId, 'u1');
      expect(membership.businessId, 'b1');
      expect(membership.businessName, 'Pet Shop Central');
      expect(membership.role, BusinessRole.owner);
      expect(membership.isActive, isTrue);
      expect(membership.createdAt, DateTime(2026, 8, 1));
    });

    test('falls back to client role and active when missing', () {
      final membership = BusinessMembership.fromMap('u1', {'businessId': 'b1'});

      expect(membership.role, BusinessRole.client);
      expect(membership.isActive, isTrue);
      expect(membership.businessName, '');
    });

    test('toMap/fromMap round-trip preserves fields', () {
      final original = BusinessMembership(
        userId: 'u1',
        businessId: 'b1',
        businessName: 'Pet Shop Central',
        role: BusinessRole.admin,
        isActive: true,
      );

      final restored = BusinessMembership.fromMap(
        original.userId,
        original.toMap(),
      );

      expect(restored.userId, original.userId);
      expect(restored.businessId, original.businessId);
      expect(restored.businessName, original.businessName);
      expect(restored.role, original.role);
      expect(restored.isActive, original.isActive);
      expect(restored.toMap()['role'], 'admin');
    });
  });
}
