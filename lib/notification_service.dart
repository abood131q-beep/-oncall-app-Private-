import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'session_service.dart';

// ===== نموذج الإشعار =====
class AppNotification {
  final int id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final int? tripId;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    this.tripId,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map json) => AppNotification(
    id: json['id'] ?? 0,
    title: json['title'] ?? '',
    body: json['body'] ?? '',
    type: json['type'] ?? 'general',
    isRead: (json['is_read'] ?? 0) == 1,
    tripId: json['trip_id'],
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
  );

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id, title: title, body: body, type: type,
    isRead: isRead ?? this.isRead, tripId: tripId, createdAt: createdAt,
  );
}

// ===== خدمة الإشعارات =====
class NotificationService {
  static final List<AppNotification> _notifications = [];
  static int _unreadCount = 0;
  static Function()? onNewNotification;

  static List<AppNotification> get notifications => List.unmodifiable(_notifications);
  static int get unreadCount => _unreadCount;

  static Future<void> init() async {
    debugPrint('✅ NotificationService initialized');
  }

  // ===== إضافة إشعار محلي =====
  static void addLocal({
    required String title,
    required String body,
    String type = 'general',
    int? tripId,
  }) {
    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      type: type,
      isRead: false,
      tripId: tripId,
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, notification);
    _unreadCount++;
    debugPrint('📬 $title');
    onNewNotification?.call();
  }

  // ===== جلب من السيرفر =====
  static Future<void> fetchFromServer(String phone) async {
    if (phone.isEmpty) return;
    try {
      final res = await SessionService.get('/notifications/$phone')
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        for (final n in data) {
          final notif = AppNotification.fromJson(n);
          if (!_notifications.any((l) => l.id == notif.id)) {
            _notifications.add(notif);
          }
        }
        _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _unreadCount = _notifications.where((n) => !n.isRead).length;
        onNewNotification?.call();
      }
    } catch (e) {
      debugPrint('fetchNotifications error: $e');
    }
  }

  // ===== تعليم كمقروء =====
  static Future<void> markAllRead(String phone) async {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
    _unreadCount = 0;
    onNewNotification?.call();
    try {
      await SessionService.put('/notifications/$phone/read', {});
    } catch (e) {
      debugPrint('Error: ${e.toString()}');
    }
  }

  static void clearAll() {
    _notifications.clear();
    _unreadCount = 0;
  }

  // ===== إشعارات جاهزة =====
  static void notifyNewTrip() => addLocal(
    title: '🚕 طلب رحلة جديد',
    body: 'يوجد راكب ينتظر - لديك 30 ثانية للقبول!',
    type: 'new_trip',
  );

  static void notifyTripAccepted(String driverName) => addLocal(
    title: '✅ تم قبول رحلتك',
    body: 'السائق $driverName في الطريق إليك',
    type: 'trip_accepted',
  );

  static void notifyDriverArrived() => addLocal(
    title: '📍 السائق وصل',
    body: 'السائق في انتظارك - انزل الآن',
    type: 'driver_arrived',
  );

  static void notifyTripStarted() => addLocal(
    title: '🚗 بدأت الرحلة',
    body: 'استمتع برحلتك مع On Call',
    type: 'trip_started',
  );

  static void notifyTripCompleted(String fare) => addLocal(
    title: '🏁 وصلت بسلامة',
    body: 'الأجرة: $fare د.ك - شكراً لاستخدام On Call ⭐',
    type: 'trip_completed',
  );

  static void notifyLowBalance(double balance) => addLocal(
    title: '⚠️ رصيد منخفض',
    body: 'رصيدك ${balance.toStringAsFixed(3)} د.ك - اشحن الآن',
    type: 'low_balance',
  );

  static void notifyWalletCharged(double amount) => addLocal(
    title: '💰 تم شحن رصيدك',
    body: 'تمت إضافة ${amount.toStringAsFixed(3)} د.ك',
    type: 'wallet_charge',
  );

  // ===== أيقونة ولون =====
  static IconData getIcon(String type) {
    switch (type) {
      case 'new_trip': return Icons.local_taxi;
      case 'trip_accepted': return Icons.check_circle;
      case 'driver_arrived': return Icons.location_on;
      case 'trip_started': return Icons.directions_car;
      case 'trip_completed': return Icons.flag;
      case 'low_balance': return Icons.warning;
      case 'wallet_charge': return Icons.account_balance_wallet;
      default: return Icons.notifications;
    }
  }

  static Color getColor(String type) {
    switch (type) {
      case 'new_trip': return const Color(0xFF1A237E);
      case 'trip_accepted': return Colors.green;
      case 'driver_arrived': return Colors.orange;
      case 'trip_started': return Colors.blue;
      case 'trip_completed': return Colors.green;
      case 'low_balance': return Colors.red;
      case 'wallet_charge': return Colors.green;
      default: return Colors.grey;
    }
  }
}
