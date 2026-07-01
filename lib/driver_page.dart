import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'map_page.dart' show MapPage;
import 'driver_profile_page.dart';
import 'config.dart';
import 'main.dart' show currentUserPhone, currentUserName, currentUserBalance, currentLat, currentLng, RoleSelectionPage;
import 'socket_service.dart';
import 'notification_service.dart';
import 'session_service.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  List trips = [];
  bool isLoading = true;
  String errorMessage = '';
  String currentDriverName = '';
  bool isOnline = false;
  Map<int, int> tripCountdowns = {}; // tripId -> ثواني متبقية
  Map<int, Timer> countdownTimers = {};
  Timer? _locationTimer;
  Timer? _autoRefreshTimer;
  int? activeTripId;

  // محاكاة موقع السائق على Chrome
  double _simLat = 29.3765;
  double _simLng = 47.9785;
  int _simStep = 0;

  @override
  void initState() {
    super.initState();
    loadTrips();
    // Socket يتولى التحديث الفوري — polling كاحتياط فقط كل 30 ثانية
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) loadTrips();
    });

    // Socket متصل مسبقاً من SessionService.loginDriver()
    if (!SocketService.isConnected) SocketService.connectWithToken(SessionService.token);
    SocketService.onNewTrip((data) {
      if (mounted) {
        loadTrips();
        NotificationService.notifyNewTrip();
        final tripId = data['id'];
        if (tripId != null && isOnline) {
          final id = tripId is int ? tripId : int.tryParse(tripId.toString()) ?? 0;
          if (id > 0) _startCountdown(id);
        }
      }
    });
    SocketService.onTripUpdated((data) {
      if (!mounted) return;
      // تحديث محلي فوري من Socket — بدون HTTP request
      final tripId = data['id'];
      final newStatus = data['status'];
      if (tripId != null && newStatus != null) {
        setState(() {
          final idx = trips.indexWhere((t) => t['id'] == tripId);
          if (idx != -1) {
            trips[idx] = {...Map<String, dynamic>.from(trips[idx]), 'status': newStatus};
          }
        });
      }
    });
    SocketService.onTripAccepted((data) {
      if (mounted) loadTrips();
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadTrips() async {
    try {
      final driverPhone = currentUserPhone.isNotEmpty ? currentUserPhone : '';
      // جلب اسم السائق الحالي
      if (currentDriverName.isEmpty) {
        try {
          final driverRes = await SessionService.get('/driver/info/$driverPhone');
          if (driverRes.statusCode == 200) {
            final d = jsonDecode(driverRes.body)['driver'];
            if (d != null) currentDriverName = d['name'] ?? '';
          }
        } catch (_) {}
      }
      final response = await http
          .get(Uri.parse('$baseUrl/taxi/trips?driver_phone=$driverPhone'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) setState(() { trips = data; isLoading = false; errorMessage = ''; });
      } else {
        if (mounted) setState(() { errorMessage = 'فشل تحميل الرحلات'; isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { errorMessage = 'تعذر الاتصال بالسيرفر'; isLoading = false; });
    }
  }

  // ===== إرسال موقع السائق =====
  void _startSendingLocation(int tripId) {
    _locationTimer?.cancel();
    activeTripId = tripId;
    _simLat = 29.3765;
    _simLng = 47.9785;
    _simStep = 0;

    // انضم لغرفة الرحلة عبر Socket
    SocketService.joinAsDriver(tripId, currentUserPhone);

    _locationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        double lat, lng;
        if (kIsWeb) {
          // ✅ محاكاة حركة واقعية على Chrome
          _simStep++;
          // حركة سلسة باتجاه الراكب
          final angle = _simStep * 0.15;
          _simLat += 0.00015 * (1 + 0.3 * ((_simStep % 3) - 1));
          _simLng += 0.00015 * (0.8 + 0.2 * ((_simStep % 5) - 2));
          lat = _simLat;
          lng = _simLng;
        } else {
          // ✅ GPS حقيقي على iPhone/Android
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever) return;
          final position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 4));
          lat = position.latitude;
          lng = position.longitude;
        }

        // ✅ إرسال فوري عبر Socket
        SocketService.sendDriverLocation(tripId, lat, lng);
      } catch (e) {
        debugPrint('Location send error: $e');
      }
    });
  }

  void _stopSendingLocation() {
    _locationTimer?.cancel();
    _locationTimer = null;
    activeTripId = null;
    SocketService.offNewTrip();
    SocketService.offTripUpdated();
    // إيقاف جميع العدادات
    for (final timer in countdownTimers.values) { timer.cancel(); }
    countdownTimers.clear();
    tripCountdowns.clear();
  }

  // ===== بدء العداد التنازلي =====
  void _startCountdown(int tripId) {
    countdownTimers[tripId]?.cancel();
    tripCountdowns[tripId] = 30;

    countdownTimers[tripId] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        tripCountdowns[tripId] = (tripCountdowns[tripId] ?? 0) - 1;
        if ((tripCountdowns[tripId] ?? 0) <= 0) {
          timer.cancel();
          countdownTimers.remove(tripId);
          tripCountdowns.remove(tripId);
          loadTrips(); // تحديث بعد انتهاء المهلة
        }
      });
    });
  }

  // ===== رفض الرحلة =====
  Future<void> rejectTrip(int tripId) async {
    countdownTimers[tripId]?.cancel();
    countdownTimers.remove(tripId);
    tripCountdowns.remove(tripId);
    try {
      await SessionService.post('/taxi/trips/$tripId/reject', {'driver_phone': currentUserPhone});
      await loadTrips();
    } catch (e) {
      debugPrint('rejectTrip error: $e');
    }
  }

  Future<void> acceptTrip(int tripId) async {
    try {
      final response = await SessionService.put('/taxi/trips/$tripId/status', {
          'status': 'accepted',
          'driver_phone': currentUserPhone,
        });

      if (response.statusCode == 200) {
        await loadTrips();
        if (!mounted) return;
        _startSendingLocation(tripId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text('✅ تم قبول الرحلة')),
        );
        Navigator.push(context, MaterialPageRoute(builder: (_) => MapPage(tripId: tripId)));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.red, content: Text('فشل قبول الرحلة')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.red, content: Text('تعذر الاتصال بالسيرفر')),
      );
    }
  }

  Future<void> updateStatus(int tripId, String status) async {
    try {
      await SessionService.put('/taxi/trips/$tripId/status', {'status': status});
      if (status == 'completed' || status == 'cancelled') {
        _stopSendingLocation();
      }
      await loadTrips();
    } catch (e) {
      debugPrint('updateStatus error: $e');
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'waiting_driver': return Colors.orange;
      case 'accepted': return Colors.blue;
      case 'arrived': return Colors.deepOrange;
      case 'in_progress': return Colors.indigo;
      case 'completed': return Colors.grey;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String getStatusText(String status) {
    switch (status) {
      case 'waiting_driver': return 'بانتظار سائق ⏳';
      case 'accepted': return 'مقبولة 🚕';
      case 'arrived': return 'وصلت للراكب 📍';
      case 'in_progress': return 'جارية 🚗';
      case 'completed': return 'منتهية ✅';
      case 'cancelled': return 'ملغاة ❌';
      default: return status;
    }
  }

  void _showRatePassengerDialog(int tripId, String passengerPhone) {
    int selectedRating = 0;
    final commentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(children: [
            Text('قيّم الراكب ⭐', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('كيف كانت تجربتك؟', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => GestureDetector(
                onTap: () => setS(() => selectedRating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < selectedRating ? Icons.star : Icons.star_border,
                    color: Colors.amber, size: 38,
                  ),
                ),
              )),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentCtrl,
              decoration: InputDecoration(
                hintText: 'تعليق (اختياري)...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 2,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تخطي')),
            if (selectedRating > 0)
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await SessionService.post('/taxi/trips/$tripId/rate-passenger', {
                        'rating': selectedRating,
                        'comment': commentCtrl.text.trim(),
                        'driver_phone': currentUserPhone,
                      });
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('✅ تم تسجيل التقييم'),
                      backgroundColor: Colors.green,
                    ));
                  } catch (e) {
      debugPrint('Error: ${e.toString()}');
    }
                },
                child: const Text('إرسال'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات التاكسي 🚕'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل خروج',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تسجيل خروج'),
                  content: const Text('هل تريد تسجيل الخروج؟'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                    FilledButton(
                      onPressed: () async {
                        // إيقاف السائق
                        try {
                          await SessionService.post('/driver/status', {'phone': currentUserPhone, 'isOnline': false});
                        } catch (_) {}
                        // مسح البيانات
                        await SessionService.logout();
                        currentUserPhone = '';
                        currentUserName = '';
                        currentUserBalance = 0;
                        _stopSendingLocation();
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
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
          // زر ابدأ / أوقف العمل
          GestureDetector(
            onTap: () async {
              final newStatus = !isOnline;
              try {
                await SessionService.post('/driver/status', {'phone': currentUserPhone, 'isOnline': newStatus});
                setState(() => isOnline = newStatus);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(newStatus ? '🟢 أنت الآن متصل - ستظهر للركاب' : '🔴 أنت الآن غير متصل'),
                    backgroundColor: newStatus ? Colors.green : Colors.grey,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              } catch (_) {}
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey.shade600,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                isOnline ? '🟢 متصل' : '🔴 غير متصل',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          // مؤشر الإرسال المباشر
          if (activeTripId != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: Colors.white, size: 8),
                  SizedBox(width: 4),
                  Text('مباشر', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'ملفي الشخصي',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DriverProfilePage())),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadTrips,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 60, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(errorMessage, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: loadTrips,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : trips.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.local_taxi, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('لا توجد رحلات حالياً', style: TextStyle(fontSize: 18, color: Colors.grey)),
                          const SizedBox(height: 8),
                          const Text('سيتم التحديث تلقائياً كل 5 ثواني', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: loadTrips,
                      child: ListView.builder(
                        itemCount: trips.length,
                        itemBuilder: (context, index) {
                          final trip = trips[index];
                          final status = trip['status'] ?? 'waiting_driver';
                          final isMyTrip = trip['driver_name'] != null &&
                              trip['driver_name'].toString().isNotEmpty;

                          return Card(
                            margin: const EdgeInsets.all(10),
                            elevation: isMyTrip ? 4 : 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isMyTrip && status != 'completed'
                                  ? BorderSide(color: getStatusColor(status), width: 2)
                                  : BorderSide.none,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('رحلة #${trip['id']}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                      Chip(
                                        backgroundColor: getStatusColor(status),
                                        label: Text(getStatusText(status),
                                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    const Icon(Icons.location_on, size: 16, color: Colors.green),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text('${trip['pickup'] ?? '-'}', overflow: TextOverflow.ellipsis)),
                                  ]),
                                  Row(children: [
                                    const Icon(Icons.flag, size: 16, color: Colors.red),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text('${trip['destination'] ?? '-'}', overflow: TextOverflow.ellipsis)),
                                  ]),
                                  Row(children: [
                                    const Icon(Icons.attach_money, size: 16, color: Colors.teal),
                                    const SizedBox(width: 4),
                                    Text('${(trip['estimatedFare'] ?? trip['estimated_fare'] ?? 1).toStringAsFixed(3)} د.ك'),
                                  ]),
                                  const SizedBox(height: 10),

                                  // ===== أزرار حسب الحالة =====

                                  // زر قبول + رفض + عداد
                                  if (status == 'waiting_driver') ...[
                                    // عداد تنازلي
                                    if (tripCountdowns.containsKey(trip['id'])) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: (tripCountdowns[trip['id']] ?? 0) / 30,
                                                backgroundColor: Colors.grey.shade200,
                                                valueColor: AlwaysStoppedAnimation(
                                                  (tripCountdowns[trip['id']] ?? 0) > 10
                                                      ? Colors.green : Colors.red,
                                                ),
                                                minHeight: 6,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${tripCountdowns[trip['id']]}s',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: (tripCountdowns[trip['id']] ?? 0) > 10
                                                  ? Colors.green : Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red.shade50,
                                                foregroundColor: Colors.red,
                                                padding: const EdgeInsets.symmetric(vertical: 12)),
                                            onPressed: () => rejectTrip(trip['id']),
                                            icon: const Icon(Icons.close, size: 18),
                                            label: const Text('رفض'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 12)),
                                            onPressed: () => acceptTrip(trip['id']),
                                            icon: const Icon(Icons.check_circle),
                                            label: const Text('قبول الرحلة', style: TextStyle(fontSize: 16)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  // أزرار التحكم فقط للسائق الصاحب
                                  if (status == 'accepted' && trip['driver_name'] == currentDriverName)
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12)),
                                        onPressed: () => updateStatus(trip['id'], 'arrived'),
                                        icon: const Icon(Icons.location_on),
                                        label: const Text('وصلت للراكب', style: TextStyle(fontSize: 16)),
                                      ),
                                    ),

                                  // زر بدأت الرحلة
                                  if (status == 'arrived' && trip['driver_name'] == currentDriverName)
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12)),
                                        onPressed: () async {
                                          _startSendingLocation(trip['id']);
                                          await updateStatus(trip['id'], 'in_progress');
                                          if (!mounted) return;
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => MapPage(tripId: trip['id']),
                                          ));
                                        },
                                        icon: const Icon(Icons.directions_car),
                                        label: const Text('بدأت الرحلة', style: TextStyle(fontSize: 16)),
                                      ),
                                    ),

                                  // زر فتح الخريطة
                                  if ((status == 'accepted' || status == 'arrived' || status == 'in_progress') && trip['driver_name'] == currentDriverName)
                                    const SizedBox(height: 8),

                                  if ((status == 'accepted' || status == 'arrived' || status == 'in_progress') && trip['driver_name'] == currentDriverName)
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          if (activeTripId != trip['id']) {
                                            _startSendingLocation(trip['id']);
                                          }
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => MapPage(tripId: trip['id']),
                                          ));
                                        },
                                        icon: const Icon(Icons.map),
                                        label: const Text('فتح الخريطة'),
                                      ),
                                    ),

                                  // زر إنهاء الرحلة
                                  if (status == 'in_progress' && trip['driver_name'] == currentDriverName) ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12)),
                                        onPressed: () async {
                                          await updateStatus(trip['id'], 'completed');
                                          if (!mounted) return;
                                          _showRatePassengerDialog(trip['id'], trip['user_phone'] ?? '');
                                        },
                                        icon: const Icon(Icons.check_circle),
                                        label: const Text('إنهاء الرحلة', style: TextStyle(fontSize: 16)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
