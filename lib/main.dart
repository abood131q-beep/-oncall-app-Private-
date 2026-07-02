import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'map_page.dart' show MapPage;
import 'driver_page.dart' show DriverPage;
import 'config.dart';
import 'admin_dashboard.dart' show AdminDashboard;
import 'places_service.dart';
import 'socket_service.dart';
import 'notification_service.dart';
import 'session_service.dart';
import 'wallet_page.dart';
import 'notifications_page.dart';
import 'app_theme.dart';
import 'scooter_page.dart';
import 'profile_page.dart';

// ===== بيانات المستخدم الحالي =====
// ===== ApiService - مركزة طلبات HTTP =====
class ApiService {
  static Future<Map?> getBalance(String phone) async {
    try {
      final res = await SessionService.get('/balance/$phone');
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { debugPrint('ApiService.getBalance: ${e.toString()}'); }
    return null;
  }

  static Future<Map?> requestTaxi(Map body) async {
    try {
      final res = await SessionService.post('/taxi/request', body);
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { debugPrint('ApiService.requestTaxi: ${e.toString()}'); }
    return null;
  }

  static Future<List> getPassengerTrips(String phone) async {
    try {
      final res = await SessionService.get('/taxi/trips/passenger/$phone');
      if (res.statusCode == 200) return jsonDecode(res.body) as List;
    } catch (e) { debugPrint('ApiService.getTrips: ${e.toString()}'); }
    return [];
  }

  static Future<Map?> getFareEstimate(Map body) async {
    try {
      final res = await SessionService.post('/fare/estimate', body);
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { debugPrint('ApiService.getFare: ${e.toString()}'); }
    return null;
  }

  static Future<bool> checkIsAdmin() async {
    try {
      final res = await SessionService.get('/auth/verify');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['session']?['role'] == 'admin';
      }
    } catch (e) { debugPrint('ApiService.checkAdmin: ${e.toString()}'); }
    return false;
  }

  static Future<Map?> rateTrip(int tripId, int rating, String comment) async {
    try {
      final res = await SessionService.post('/taxi/trips/$tripId/rate', {
        'rating': rating, 'comment': comment,
      });
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { debugPrint('ApiService.rateTrip: ${e.toString()}'); }
    return null;
  }

  static Future<Map?> requestTaxiRide({
    required String pickup, required String destination,
    required String phone, required String paymentMethod,
    double? pickupLat, double? pickupLng,
    double? destLat, double? destLng,
  }) async {
    try {
      final res = await SessionService.post('/taxi/request', {
        'pickup': pickup, 'destination': destination,
        'phone': phone, 'payment_method': paymentMethod,
        'pickupLat': pickupLat, 'pickupLng': pickupLng,
        'destLat': destLat, 'destLng': destLng,
      });
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { debugPrint('ApiService.requestTaxi: ${e.toString()}'); }
    return null;
  }

  static Future<List> getNotifications(String phone) async {
    try {
      final res = await SessionService.get('/notifications/$phone');
      if (res.statusCode == 200) return jsonDecode(res.body) as List;
    } catch (e) { debugPrint('ApiService.getNotifications: ${e.toString()}'); }
    return [];
  }
}

// ===== بيانات الجلسة - تُقرأ وتُكتب عبر SessionService =====
// المتغيرات المحلية للتوافق مع الكود الحالي
// SessionService هو المصدر الحقيقي
String _currentUserPhone = '';
String _currentUserName = '';
double _currentUserBalance = 0;
double? _currentLat;
double? _currentLng;

// Getters تقرأ من SessionService أولاً
String get currentUserPhone => SessionService.phone.isNotEmpty ? SessionService.phone : _currentUserPhone;
set currentUserPhone(String v) { _currentUserPhone = v; }

String get currentUserName => SessionService.name.isNotEmpty ? SessionService.name : _currentUserName;
set currentUserName(String v) { _currentUserName = v; SessionService.name = v; }

double get currentUserBalance => SessionService.balance > 0 ? SessionService.balance : _currentUserBalance;
set currentUserBalance(double v) { _currentUserBalance = v; SessionService.balance = v; }

double? get currentLat => SessionService.lat ?? _currentLat;
set currentLat(double? v) { _currentLat = v; SessionService.lat = v; }

double? get currentLng => SessionService.lng ?? _currentLng;
set currentLng(double? v) { _currentLng = v; SessionService.lng = v; }

void main() {
  runApp(const OnCallApp());
}

class OnCallApp extends StatefulWidget {
  const OnCallApp({super.key});
  @override
  State<OnCallApp> createState() => _OnCallAppState();
}

class _OnCallAppState extends State<OnCallApp> {
  bool _isDarkMode = false;

  // للوصول من الصفحات الأخرى
  static _OnCallAppState? _instance;
  static bool get isDark => _instance?._isDarkMode ?? false;
  static void toggleTheme() {
    _instance?.setState(() => _instance!._isDarkMode = !_instance!._isDarkMode);
  }

  @override
  void initState() {
    super.initState();
    _instance = this;
    NotificationService.init();
  }

  @override
  void dispose() {
    _instance = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      title: 'On Call',
      home: const RoleSelectionPage(),
    );
  }
}

// ===== اختيار الدور =====
class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_taxi, size: 80, color: Colors.indigo),
              const SizedBox(height: 16),
              const Text('On Call', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('تطبيق التنقل الذكي', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 50),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginPage(isDriver: false))),
                  icon: const Icon(Icons.person),
                  label: const Text('دخول كراكب', style: TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginPage(isDriver: true))),
                  icon: const Icon(Icons.drive_eta),
                  label: const Text('دخول كسائق', style: TextStyle(fontSize: 18)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== تسجيل الدخول =====
class LoginPage extends StatefulWidget {
  final bool isDriver;
  const LoginPage({super.key, required this.isDriver});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phoneController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  Future<void> login() async {
    final phone = phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => errorMessage = 'أدخل رقم الهاتف');
      return;
    }
    if (phone.length < 3 || !RegExp(r'^[0-9]+$').hasMatch(phone)) {
      setState(() => errorMessage = 'رقم الهاتف غير صحيح - أرقام فقط');
      return;
    }
    setState(() { isLoading = true; errorMessage = null; });
    try {
      if (!mounted) return;

      Map<String, dynamic> result;
      if (widget.isDriver) {
        result = await SessionService.loginDriver(phone);
      } else {
        result = await SessionService.loginPassenger(phone);
      }

      if (!mounted) return;
      if (result['success'] == true) {
        // مزامنة المتغيرات الـ global مع SessionService
        currentUserPhone = SessionService.phone;
        currentUserName = SessionService.name;
        currentUserBalance = SessionService.balance;

        if (widget.isDriver) {
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const DriverPage()));
        } else {
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const PassengerHomePage()));
        }
      } else {
        setState(() => errorMessage = result['message']?.toString() ?? 'فشل تسجيل الدخول');
      }
    } catch (e) {
      debugPrint('❌ Error: ${e.toString()}');
      setState(() => errorMessage = 'تعذر الاتصال بالسيرفر');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isDriver ? 'دخول السائق' : 'دخول الراكب')),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.isDriver ? Icons.drive_eta : Icons.person, size: 64, color: Colors.indigo),
            const SizedBox(height: 24),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف',
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                errorText: errorMessage,
              ),
            ),
            const SizedBox(height: 16),
            LoadingButton(
              isLoading: isLoading,
              label: 'دخول',
              icon: Icons.login,
              onPressed: login,
            ),
          ],
        ),
      ),
    );
  }
}

// ===== الصفحة الرئيسية للراكب =====
class PassengerHomePage extends StatefulWidget {
  const PassengerHomePage({super.key});

  @override
  State<PassengerHomePage> createState() => _PassengerHomePageState();
}

class _PassengerHomePageState extends State<PassengerHomePage> {
  double balance = currentUserBalance;
  String locationStatus = '📍 جاري تحديد موقعك...';

  @override
  void initState() {
    super.initState();
    loadBalance();
    _getLocation();
  }

  Future<void> loadBalance() async {
    try {
      final response = await SessionService.get('/balance/$currentUserPhone');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => balance = (data['balance'] ?? 0).toDouble());
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  Future<void> _getLocation() async {
    if (kIsWeb) {
      // Chrome: موقع افتراضي الكويت
      setState(() => locationStatus = '📍 الكويت (Chrome)');
      currentLat = 29.3759;
      currentLng = 47.9774;
      return;
    }

    // iPhone/Android: GPS حقيقي
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => locationStatus = '⚠️ فعّل خدمة الموقع');
        currentLat = 29.3759;
        currentLng = 47.9774;
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => locationStatus = '⚠️ افتح الإعدادات للسماح بالموقع');
        currentLat = 29.3759;
        currentLng = 47.9774;
        return;
      }
      if (permission == LocationPermission.denied) {
        setState(() => locationStatus = '⚠️ لم تُمنح صلاحية الموقع');
        return;
      }

      setState(() => locationStatus = '🔄 جاري تحديد موقعك...');

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      currentLat = position.latitude;
      currentLng = position.longitude;
      setState(() => locationStatus = '✅ ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}');
      debugPrint('✅ iPhone GPS: ${position.latitude}, ${position.longitude}');

    } catch (e) {
      debugPrint('Location error: $e');
      setState(() => locationStatus = '⚠️ تعذر تحديد الموقع');
      currentLat = 29.3759;
      currentLng = 47.9774;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚕 On Call'),
        actions: [

          // زر الإشعارات مع Badge
          StatefulBuilder(
            builder: (ctx, setS) {
              NotificationService.onNewNotification = () { if (mounted) setS(() {}); };
              final count = NotificationService.unreadCount;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const NotificationsPage()))
                        .then((_) => setS(() {})),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6, top: 6,
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
Builder(
            builder: (ctx) {
              final appState = ctx.findAncestorStateOfType<_OnCallAppState>();
              final isDark = appState?._isDarkMode ?? false;
              return IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode_outlined),
                tooltip: isDark ? 'وضع النهار' : 'الوضع الليلي',
                onPressed: () => _OnCallAppState.toggleTheme(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل خروج',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تسجيل خروج'),
                  content: Text('هل تريد تسجيل خروج الحساب $currentUserPhone؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        // ✅ تسجيل خروج حقيقي
                        await SessionService.logout();
                        currentUserPhone = '';
                        currentUserName = '';
                        currentUserBalance = 0;
                        currentLat = null;
                        currentLng = null;
                        Navigator.pop(ctx);
                        // العودة لصفحة الدخول وإزالة جميع الصفحات السابقة
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
                          (route) => false,
                        );
                      },
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('خروج'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // رصيد المستخدم
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text('💰 رصيدك', style: TextStyle(color: Colors.white70)),
                  Text('${balance.toStringAsFixed(3)} د.ك',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(locationStatus, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 0.95,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _HomeButton(icon: Icons.local_taxi, label: 'طلب تكسي', color: Colors.indigo,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const PassengerTaxiPage()))),
                  _HomeButton(icon: Icons.map, label: 'الخريطة', color: Colors.teal,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const MapPage()))),
                  _HomeButton(icon: Icons.electric_scooter, label: 'السكوترات', color: Colors.orange,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ScooterPage()))),
                  _HomeButton(icon: Icons.history, label: 'رحلاتي', color: Colors.purple,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const TripHistoryPage()))),
                  _HomeButton(icon: Icons.admin_panel_settings, label: 'لوحة المشرف', color: Colors.red,
                      onTap: () async {
                          // تحقق مزدوج: واجهة + سيرفر
                          final adminPhones = ['112', '99999999', 'admin'];
                          if (!adminPhones.contains(currentUserPhone)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('غير مصرح'),
                                  backgroundColor: Colors.red));
                            return;
                          }
                          // تحقق من السيرفر أيضاً
                          final isAdmin = await ApiService.checkIsAdmin();
                          if (!mounted) return;
                          if (!isAdmin) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('غير مصرح - صلاحيات المشرف مطلوبة'),
                                  backgroundColor: Colors.red));
                            return;
                          }
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminDashboard()));
                        }),
                  _HomeButton(icon: Icons.person, label: 'ملفي', color: Colors.indigo,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ProfilePage()))),
                  _HomeButton(icon: Icons.account_balance_wallet, label: 'محفظتي', color: Colors.green,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const WalletPage()))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _HomeButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ===== صفحة طلب التكسي =====
class PassengerTaxiPage extends StatefulWidget {
  const PassengerTaxiPage({super.key});

  @override
  State<PassengerTaxiPage> createState() => _PassengerTaxiPageState();
}

class _PassengerTaxiPageState extends State<PassengerTaxiPage> {
  final pickupController = TextEditingController();
  final destController = TextEditingController();

  // إحداثيات المواقع المختارة
  double? pickupLat;
  double? pickupLng;
  double? destLat;
  double? destLng;
  String pickupName = '';
  String destName = '';

  bool isLoading = false;
  Map? tripResult;
  String? errorMessage;
  String selectedPayment = 'cash';

  @override
  void initState() {
    super.initState();
    if (currentLat != null && currentLng != null) {
      pickupLat = currentLat;
      pickupLng = currentLng;
      pickupController.text = 'موقعك الحالي 📍';
    }
    // تحقق من رحلة نشطة للمستخدم الحالي
    _checkActiveTrip();
  }

  Future<void> _checkActiveTrip() async {
    if (currentUserPhone.isEmpty) return;
    try {
      final response = await SessionService.get('/taxi/trips/passenger/$currentUserPhone');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final trips = jsonDecode(response.body) as List;
        // ابحث عن رحلة نشطة
        final activeTrip = trips.firstWhere(
          (t) => ['waiting_driver','accepted','arrived','in_progress'].contains(t['status']),
          orElse: () => null,
        );
        if (activeTrip != null && mounted) {
          setState(() => tripResult = {'trip': activeTrip, 'driver': null});
          // انضم للغرفة
          final tripId = activeTrip['id'] is int
              ? activeTrip['id'] as int
              : int.tryParse(activeTrip['id'].toString()) ?? 0;
          if (tripId > 0) {
            if (!SocketService.isConnected) SocketService.connectWithToken(SessionService.token);
            SocketService.joinAsPassenger(tripId, currentUserPhone);
          }
        }
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  // بيانات الأجرة من API
  Map? fareData;
  String priceType = 'عادي';
  bool isPeak = false;

  Future<void> _fetchFareEstimate() async {
    if (pickupLat == null || destLat == null) return;
    try {
      final response = await SessionService.post('/fare/estimate', {
          'pickupLat': pickupLat, 'pickupLng': pickupLng,
          'destLat': destLat, 'destLng': destLng,
        });
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          fareData = data;
          priceType = data['priceType'] ?? 'عادي';
          isPeak = data['multiplier'] != null && (data['multiplier'] as num) > 1.0;
        });
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  // قانون Haversine الصحيح
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    const toRad = math.pi / 180;
    final dLat = (lat2 - lat1) * toRad;
    final dLng = (lng2 - lng1) * toRad;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * toRad) * math.cos(lat2 * toRad) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.asin(math.sqrt(a));
    return R * c;
  }

  String _estimateFare() {
    if (fareData != null) return (fareData!['total'] ?? 0).toStringAsFixed(3);
    if (pickupLat == null || destLat == null) return '~0.750';
    final dist = _haversineKm(pickupLat!, pickupLng!, destLat!, destLng!);
    final fare = 0.5 + dist * 0.20;
    return fare.toStringAsFixed(3);
  }

  Future<void> orderTaxi() async {
    final pickup = pickupName.isNotEmpty ? pickupName : pickupController.text.trim();
    final dest = destName.isNotEmpty ? destName : destController.text.trim();
    debugPrint('🚕 orderTaxi called: pickup="$pickup" dest="$dest" lat=$pickupLat lng=$pickupLng');

    if (pickup.isEmpty || dest.isEmpty) {
      setState(() => errorMessage = 'اختر موقع الانطلاق والوجهة');
      return;
    }

    setState(() { isLoading = true; errorMessage = null; tripResult = null; });
    try {
      final response = await SessionService.post('/taxi/request', {
        'pickup': pickup,
        'destination': dest,
        'phone': currentUserPhone,
        'pickupLat': pickupLat ?? currentLat,
        'pickupLng': pickupLng ?? currentLng,
        'destLat': destLat,
        'destLng': destLng,
        'payment_method': selectedPayment,
      });

      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => tripResult = data);
        final tripId = data['trip']['id'] is int
            ? data['trip']['id'] as int
            : int.tryParse(data['trip']['id'].toString()) ?? 0;
        if (!SocketService.isConnected) SocketService.connectWithToken(SessionService.token);
        SocketService.joinAsPassenger(tripId, currentUserPhone);
        debugPrint('🔌 Joined trip room after request: $tripId');
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PassengerTrackingPage(tripId: tripId),
          )).then((_) {
            if (mounted) setState(() => tripResult = null);
          });
        }
      } else {
        setState(() => errorMessage = data['message'] ?? 'حدث خطأ');
      }
    } catch (e) {
      debugPrint('❌ Error: ${e.toString()}');
      setState(() => errorMessage = 'تعذر الاتصال بالسيرفر');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلب تكسي 🚕')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ===== موقع الانطلاق =====
            PlacesSearchField(
              hint: 'موقع الانطلاق',
              prefixIcon: Icons.my_location,
              iconColor: Colors.green,
              controller: pickupController,
              biasLat: currentLat,
              biasLng: currentLng,
              onPlaceSelected: (place) {
                setState(() {
                  pickupLat = place.lat;
                  pickupLng = place.lng;
                  pickupName = place.name;
                  pickupController.text = place.name;
                });
              },
            ),

            // زر الموقع الحالي
            if (currentLat != null)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    pickupLat = currentLat;
                    pickupLng = currentLng;
                    pickupName = 'موقعي الحالي';
                    pickupController.text = 'موقعي الحالي 📍';
                  });
                },
                icon: const Icon(Icons.gps_fixed, size: 16),
                label: const Text('استخدام موقعي الحالي', style: TextStyle(fontSize: 13)),
              ),

            const SizedBox(height: 14),

            // ===== الوجهة =====
            PlacesSearchField(
              hint: 'الوجهة',
              prefixIcon: Icons.flag,
              iconColor: Colors.red,
              controller: destController,
              biasLat: currentLat,
              biasLng: currentLng,
              onPlaceSelected: (place) {
                setState(() {
                  destLat = place.lat;
                  destLng = place.lng;
                  destName = place.name;
                  destController.text = place.name;
                });
                _fetchFareEstimate();
              },
            ),

            // معلومات الأجرة التقريبية
            if (pickupLat != null && destLat != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.attach_money,
                        size: 16, color: isPeak ? Colors.orange : Colors.indigo),
                    const SizedBox(width: 8),
                    Text(
                      '${isPeak ? "🔥 ذروة - " : ""}الأجرة التقريبية: ${_estimateFare()} د.ك',
                      style: TextStyle(
                        color: isPeak ? Colors.orange.shade700 : Colors.indigo,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (fareData != null) ...[
                      const Spacer(),
                      Text(
                        '${(fareData!['distanceKm'] ?? 0).toStringAsFixed(1)} كم',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(errorMessage!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ],
            // اختيار طريقة الدفع
            const Text('طريقة الدفع:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _PaymentMethodButton(
                  icon: '💵', label: 'نقداً',
                  selected: selectedPayment == 'cash',
                  onTap: () => setState(() => selectedPayment = 'cash'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PaymentMethodButton(
                  icon: '👛', label: 'المحفظة',

                  selected: selectedPayment == 'wallet',
                  onTap: () => setState(() => selectedPayment = 'wallet'),
                ),
              ),
            ]),

            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isLoading ? null : orderTaxi,
              icon: isLoading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.local_taxi),
              label: const Text('اطلب سيارة الآن', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            if (tripResult != null &&
                (tripResult!['trip']?['user_phone'] == currentUserPhone ||
                 tripResult!['trip']?['user_phone'] == null)) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✅ تم إرسال الطلب بنجاح',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                      const Divider(),
                      Text('رقم الرحلة: #${tripResult!['trip']?['id'] ?? '-'}'),
                      Text('السائق: ${tripResult!['driver']?['name'] ?? 'جاري البحث...'}'),
                      Text('الأجرة التقريبية: ${tripResult!['trip']?['estimatedFare']?.toStringAsFixed(3) ?? '-'} د.ك'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PassengerTrackingPage(
                              tripId: tripResult!['trip']['id'] is int 
                                  ? tripResult!['trip']['id'] as int
                                  : int.parse(tripResult!['trip']['id'].toString()),
                            ),
                          )),
                          icon: const Icon(Icons.map),
                          label: const Text('تتبع السائق'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===== صفحة تتبع السائق =====
class PassengerTrackingPage extends StatefulWidget {
  final int tripId;
  const PassengerTrackingPage({super.key, required this.tripId});

  @override
  State<PassengerTrackingPage> createState() => _PassengerTrackingPageState();
}

class _PassengerTrackingPageState extends State<PassengerTrackingPage> {
  String tripStatus = 'waiting_driver';
  String driverName = '';
  double? estimatedFare;
  double? finalFare;
  double liveDistKm = 0;
  int liveDurMin = 0;
  double liveFare = 0;
  bool showRating = false;
  int selectedRating = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchStatus(); // جلب الحالة الأولى فوراً

    // ✅ Socket - listener مخصص لهذه الرحلة
    if (!SocketService.isConnected) SocketService.connectWithToken(SessionService.token);
    SocketService.joinAsPassenger(widget.tripId, currentUserPhone);

    // استمع لأي حدث يخص هذه الرحلة
    SocketService.socket.on('trip:updated', _onSocketEvent);
    SocketService.socket.on('trip:accepted', _onSocketEvent);
    SocketService.socket.on('driver:moved', _onDriverMoved);

    // HTTP backup كل 20 ثانية — Socket يتولى التحديث الفوري
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _fetchStatus();
    });
  }

  void _onSocketEvent(dynamic raw) {
    if (!mounted) return;
    try {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data['id'];
      final idInt = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
      if (idInt != 0 && idInt != widget.tripId) return;

      final newStatus = data['status']?.toString() ?? '';
      debugPrint('🎯 Socket event for trip ${widget.tripId}: $newStatus');

      setState(() {
        if (newStatus.isNotEmpty) tripStatus = newStatus;
        if (data['driver_name'] != null) driverName = data['driver_name'].toString();
        if (data['finalFare'] != null) finalFare = (data['finalFare'] as num).toDouble();
        if (data['estimatedFare'] != null) estimatedFare = (data['estimatedFare'] as num).toDouble();
        if (newStatus == 'completed') showRating = true;
      });

      // إشعارات حسب الحالة
      switch (newStatus) {
        case 'accepted':
          NotificationService.notifyTripAccepted(driverName.isNotEmpty ? driverName : 'السائق');
          break;
        case 'arrived':
          NotificationService.notifyDriverArrived();
          break;
        case 'in_progress':
          NotificationService.notifyTripStarted();
          break;
        case 'completed':
          final fare = finalFare?.toStringAsFixed(3) ?? '0';
          NotificationService.notifyTripCompleted(fare);
          break;
      }


    } catch (e) {
      debugPrint('_onSocketEvent error: $e');
    }
  }

  void _onDriverMoved(dynamic raw) {
    if (!mounted) return;
    try {
      final data = Map<String, dynamic>.from(raw as Map);
      final id = data['tripId'];
      final idInt = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
      if (idInt != 0 && idInt != widget.tripId) return;

      if (data['liveStats'] != null) {
        setState(() {
          liveDistKm = (data['liveStats']['distanceKm'] ?? 0).toDouble();
          liveDurMin = (data['liveStats']['durationMinutes'] ?? 0).toInt();
          liveFare = (data['liveStats']['currentFare'] ?? 0).toDouble();
        });
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  @override
  void dispose() {
    _timer?.cancel();
    SocketService.socket.off('trip:updated', _onSocketEvent);
    SocketService.socket.off('trip:accepted', _onSocketEvent);
    SocketService.socket.off('driver:moved', _onDriverMoved);
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final response = await SessionService.get('/taxi/trips/${widget.tripId}/location');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          final s = data['status']?.toString() ?? '';
          if (s.isNotEmpty) tripStatus = s;
          if (data['estimatedFare'] != null) estimatedFare = (data['estimatedFare'] as num).toDouble();
          if (data['finalFare'] != null) finalFare = (data['finalFare'] as num).toDouble();
          if (data['driverName'] != null) driverName = data['driverName'].toString();
          if (data['liveStats'] != null) {
            liveDistKm = (data['liveStats']['distanceKm'] ?? 0).toDouble();
            liveDurMin = (data['liveStats']['durationMinutes'] ?? 0).toInt();
            liveFare = (data['liveStats']['currentFare'] ?? 0).toDouble();
          }
          if (tripStatus == 'completed') showRating = true;
        });
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  final commentController = TextEditingController();

  Future<void> _submitRating(int rating) async {
    try {
      // ✅ ApiService
      await ApiService.rateTrip(widget.tripId, rating, commentController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('شكراً على تقييمك ⭐'), backgroundColor: Colors.green));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) { debugPrint("Error: $e"); }
  }

  String _statusText() {
    switch (tripStatus) {
      case 'waiting_driver': return '⏳ جاري البحث عن أقرب سائق...';
      case 'accepted': return '🚕 السائق في الطريق إليك';
      case 'arrived': return '📍 السائق وصل - انزل الآن';
      case 'in_progress': return '🚗 الرحلة جارية';
      case 'completed': return '✅ وصلت بسلامة';
      case 'cancelled': return '❌ تم إلغاء الرحلة';
      case 'no_driver': return '😔 لا يوجد سائقون متاحون الآن';
      default: return tripStatus;
    }
  }

  Color _statusColor() {
    switch (tripStatus) {
      case 'waiting_driver': return Colors.grey;
      case 'accepted': return Colors.orange;
      case 'arrived': return Colors.deepOrange;
      case 'in_progress': return Colors.blue;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      case 'no_driver': return Colors.red.shade300;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تتبع رحلتك')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // حالة الرحلة
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _statusColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _statusColor(), width: 2),
              ),
              child: Column(children: [
                Text(_statusText(),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _statusColor())),
                if (driverName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.drive_eta, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('السائق: $driverName', style: const TextStyle(color: Colors.grey)),
                  ]),
                ],
                if (estimatedFare != null && finalFare == null) ...[
                  const SizedBox(height: 8),
                  Text('الأجرة التقريبية: ${estimatedFare!.toStringAsFixed(3)} د.ك',
                      style: const TextStyle(color: Colors.grey)),
                ],
                if (finalFare != null) ...[
                  const SizedBox(height: 8),
                  Text('الأجرة النهائية: ${finalFare!.toStringAsFixed(3)} د.ك',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                ],
              ]),
            ),

            // عداد مباشر
            if (tripStatus == 'in_progress' && liveDurMin > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade900,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      const Text('المسافة', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      Text('${liveDistKm.toStringAsFixed(2)} كم',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                    Column(children: [
                      const Text('الوقت', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      Text('$liveDurMin دقيقة',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                    Column(children: [
                      const Text('الأجرة', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      Text('${liveFare.toStringAsFixed(3)} د.ك',
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                    ]),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => MapPage(tripId: widget.tripId))),
                icon: const Icon(Icons.map),
                label: const Text('فتح الخريطة'),
              ),
            ),

            const SizedBox(height: 12),

            if (tripStatus == 'waiting_driver')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await SessionService.put('/taxi/trips/${widget.tripId}/status', {'status': 'cancelled'});
                    if (!mounted) return;
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  label: const Text('إلغاء الرحلة', style: TextStyle(color: Colors.red)),
                ),
              ),

            if (showRating) ...[
              const SizedBox(height: 24),
              const Text('قيّم رحلتك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                selectedRating == 0 ? 'اضغط على النجوم'
                  : selectedRating == 1 ? '😞 سيء'
                  : selectedRating == 2 ? '😐 مقبول'
                  : selectedRating == 3 ? '🙂 جيد'
                  : selectedRating == 4 ? '😊 جيد جداً'
                  : '🤩 ممتاز!',
                style: TextStyle(
                  color: selectedRating >= 4 ? Colors.green
                      : selectedRating >= 3 ? Colors.orange : Colors.grey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => setState(() => selectedRating = i + 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      i < selectedRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: i < selectedRating ? 44 : 38,
                    ),
                  ),
                )),
              ),
              if (selectedRating > 0) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'أضف تعليقاً (اختياري)...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.comment_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _submitRating(selectedRating),
                    icon: const Icon(Icons.send),
                    label: const Text('إرسال التقييم', style: TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('تخطي'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===== زر طريقة الدفع =====
class _PaymentMethodButton extends StatelessWidget {
  final String icon, label;
  final bool selected;
  final VoidCallback onTap;
  const _PaymentMethodButton({required this.icon, required this.label,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A237E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF1A237E) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Widget تفصيل الأجرة =====
class _FareItem extends StatelessWidget {
  final String label, value;
  const _FareItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}

// ===== سجل الرحلات =====
class TripHistoryPage extends StatefulWidget {
  const TripHistoryPage({super.key});

  @override
  State<TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<TripHistoryPage> {
  List trips = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() { loading = true; error = null; });
    try {
      if (currentUserPhone.isEmpty) {
        setState(() { error = 'سجّل دخولك أولاً'; loading = false; });
        return;
      }
      final response = await SessionService.get('/taxi/trips/passenger/$currentUserPhone');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() { trips = data; loading = false; });
      } else {
        setState(() { error = 'فشل تحميل الرحلات'; loading = false; });
      }
    } catch (e) {
      debugPrint('❌ Error: ${e.toString()}');
      setState(() { error = 'تعذر الاتصال بالسيرفر'; loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل رحلاتي'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTrips)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
              : trips.isEmpty
                  ? const Center(child: Text('لا توجد رحلات سابقة'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: trips.length,
                      itemBuilder: (context, i) {
                        final trip = trips[i];
                        final status = trip['status'] ?? '';
                        final fare = trip['final_fare'] ?? trip['finalFare'] ?? trip['estimated_fare'] ?? trip['estimatedFare'];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: Icon(
                              status == 'completed' ? Icons.check_circle : Icons.local_taxi,
                              color: status == 'completed' ? Colors.green : Colors.orange,
                            ),
                            title: Text('${trip['pickup'] ?? '-'} → ${trip['destination'] ?? '-'}'),
                            subtitle: Text(
                              'السائق: ${trip['driver_name'] ?? '-'}\n'
                              'الأجرة: ${fare != null ? fare.toStringAsFixed(3) : '-'} د.ك',
                            ),
                            trailing: trip['rating'] != null
                                ? Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 16),
                                    Text('${trip['rating']}'),
                                  ])
                                : null,
                          ),
                        );
                      },
                    ),
    );
  }
}

// ===== السكوترات =====
class ScootersPage extends StatefulWidget {
  const ScootersPage({super.key});

  @override
  State<ScootersPage> createState() => _ScootersPageState();
}

class _ScootersPageState extends State<ScootersPage> {
  List scooters = [];
  bool loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    loadScooters();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) loadScooters();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> loadScooters() async {
    try {
      final response = await SessionService.get('/scooters');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() { scooters = data; loading = false; });
      }
    } catch (e) {
      debugPrint('❌ Error: ${e.toString()}');
      setState(() => loading = false);
    }
  }

  Future<void> rentScooter(int id) async {
    try {
      final phone = currentUserPhone.isNotEmpty ? currentUserPhone : '99999999';
      final response = await SessionService.post('/scooter/rent', {'scooterId': id, 'phone': phone});
      final data = jsonDecode(response.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data['message'] ?? 'تم'),
        backgroundColor: data['success'] == true ? Colors.green : Colors.red,
      ));
      if (data['success'] == true) loadScooters();
    } catch (e) {
      debugPrint('❌ Error: ${e.toString()}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر الاتصال بالسيرفر'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('السكوترات'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: loadScooters)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : scooters.isEmpty
              ? const Center(child: Text('لا توجد سكوترات'))
              : ListView.builder(
                  itemCount: scooters.length,
                  itemBuilder: (context, index) {
                    final scooter = scooters[index];
                    final isAvailable = scooter['status'] == 'available';
                    final name = scooter['name'] ?? scooter['scooter_code'] ?? 'سكوتر ${scooter['id']}';
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.electric_scooter,
                            color: isAvailable ? Colors.green : Colors.red),
                        title: Text(name),
                        subtitle: Text('البطارية: ${scooter['battery'] ?? 0}%  |  ${isAvailable ? "متاح ✅" : "مشغول 🔴"}'),
                        trailing: ElevatedButton(
                          onPressed: isAvailable ? () => rentScooter(scooter['id']) : null,
                          child: const Text('استئجار'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
