import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification_model.dart';

class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _notifications(String businessId) =>
      _firestore.collection('businesses/$businessId/notifications');

  Stream<List<AppNotificationModel>> userNotificationsStream(
    String businessId,
    String userId,
  ) {
    return _notifications(businessId)
        .where('id_usuario', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs
              .map(
                (document) =>
                    AppNotificationModel.fromMap(document.id, document.data()),
              )
              .toList();
          notifications.sort((a, b) => b.sendAt.compareTo(a.sendAt));
          return notifications;
        });
  }

  Future<String> createNotification(
    String businessId,
    AppNotificationModel notification,
  ) async {
    final reference = await _notifications(businessId).add({
      ...notification.toMap(),
      'businessId': businessId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }
}
