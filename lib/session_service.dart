import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'socket_service.dart';

// ===== نظام الجلسة =====
class SessionService {
  static String _token = '';
  static String _phone = '';
  static String _name = '';
  static double _balance = 0;
  static double? _lat;
  static double? _lng;
  static bool _isDriver = false;
  static int _userId = 0;
  static int _driverId = 0;
  static bool _loginInProgress = false; // يمنع طلبين في نفس الوقت

  // ===== Getters =====
  static String get token => _token;
  static String get phone => _phone;
  static String get name => _name;
  static double get balance => _balance;
  static double? get lat => _lat;
  static double? get lng => _lng;
  static bool get isDriver => _isDriver;
  static int get userId => _userId;
  static int get driverId => _driverId;
  static bool get isLoggedIn => _token.isNotEmpty && _phone.isNotEmpty;

  // ===== Setters =====
  static set name(String v) => _name = v;
  static set balance(double v) => _balance = v;
  static set lat(double? v) => _lat = v;
  static set lng(double? v) => _lng = v;

  // ===== تسجيل دخول الراكب =====
  static Future<Map<String, dynamic>> loginPassenger(String phone) async {
    if (_loginInProgress) return {'success': false, 'message': 'جاري تسجيل الدخول...'};
    _loginInProgress = true;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 Login response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _token = data['token'] ?? '';
          _phone = phone;
          _name = data['user']?['name'] ?? '';
          _balance = ((data['user']?['balance'] ?? 0) as num).toDouble();
          _userId = data['user']?['id'] ?? 0;
          _isDriver = false;
          debugPrint('✅ Session: $_phone | token: ${_token.substring(0, _token.length.clamp(0, 8))}...');
          SocketService.connectWithToken(_token); // ✅ اتصال فوري بعد Login
          return {'success': true, 'user': data['user']};
        }
        return {'success': false, 'message': data['message'] ?? 'فشل تسجيل الدخول'};
      }
      if (response.statusCode == 429) {
        return {'success': false, 'message': 'محاولات كثيرة - انتظر دقيقة'};
      }
      return {'success': false, 'message': 'خطأ ${response.statusCode}'};
    } catch (e) {
      debugPrint('❌ Login error: ${e.toString()}');
      return {'success': false, 'message': 'تعذر الاتصال: ${e.toString()}'};
    } finally {
      _loginInProgress = false;
    }
  }

  // ===== تسجيل دخول السائق =====
  static Future<Map<String, dynamic>> loginDriver(String phone) async {
    if (_loginInProgress) return {'success': false, 'message': 'جاري تسجيل الدخول...'};
    _loginInProgress = true;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/driver/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 Driver login: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _token = data['token'] ?? '';
          _phone = phone;
          _name = data['driver']?['name'] ?? '';
          _driverId = data['driver']?['id'] ?? 0;
          _isDriver = true;
          debugPrint('✅ Driver session: $_phone');
          SocketService.connectWithToken(_token); // ✅ اتصال فوري بعد Login
          return {'success': true, 'driver': data['driver']};
        }
        return {'success': false, 'message': data['message'] ?? 'فشل تسجيل الدخول'};
      }
      if (response.statusCode == 429) {
        return {'success': false, 'message': 'محاولات كثيرة - انتظر 5 دقائق'};
      }
      return {'success': false, 'message': 'خطأ ${response.statusCode}'};
    } catch (e) {
      debugPrint('❌ Driver login error: ${e.toString()}');
      return {'success': false, 'message': 'تعذر الاتصال: ${e.toString()}'};
    } finally {
      _loginInProgress = false;
    }
  }

  // ===== تسجيل الخروج =====
  static Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Logout error: ${e.toString()}');
    } finally {
      _clearSession();
    }
  }

  // ===== مسح الجلسة =====
  static void _clearSession() {
    SocketService.disconnect(); // ✅ قطع Socket عند Logout
    _token = '';
    _phone = '';
    _name = '';
    _balance = 0;
    _lat = null;
    _lng = null;
    _isDriver = false;
    _userId = 0;
    _driverId = 0;
    debugPrint('🔒 Session cleared');
  }

  // ===== Headers للطلبات =====
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_token',
    'x-session-token': _token,
  };

  // ===== GET مع Token =====
  static Future<http.Response> get(String endpoint) async {
    return http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Authorization': 'Bearer $_token',
        'x-session-token': _token,
      },
    ).timeout(const Duration(seconds: 10));
  }

  // ===== POST مع Token =====
  static Future<http.Response> post(String endpoint, Map body) async {
    return http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
  }

  // ===== PUT مع Token =====
  static Future<http.Response> put(String endpoint, Map body) async {
    return http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
  }

  // ===== DELETE مع Token =====
  static Future<http.Response> delete(String endpoint) async {
    return http.delete(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Authorization': 'Bearer $_token',
        'x-session-token': _token,
      },
    ).timeout(const Duration(seconds: 10));
  }
}
