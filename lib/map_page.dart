import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'config.dart';
import 'session_service.dart';
import 'main.dart' show currentUserPhone, currentLat, currentLng;
import 'socket_service.dart';

const LatLng _defaultLocation = LatLng(29.3759, 47.9774);

class MapPage extends StatefulWidget {
  final int? tripId;
  const MapPage({super.key, this.tripId});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  Position? currentPosition;
  GoogleMapController? mapController;
  Timer? _trackingTimer;
  Timer? _mapRefreshTimer;

  // حالة الرحلة
  String tripStatus = '';
  String driverName = '';
  double liveDistance = 0;
  int liveDuration = 0;
  double liveFare = 0;
  double? finalFare;
  bool showRating = false;
  int selectedRating = 0;

  // تتبع السائق
  LatLng? lastDriverPosition;
  bool _cameraFollowsDriver = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _getCurrentLocation();
    await _loadMapData();

    if (widget.tripId != null && widget.tripId! > 0) {
      await _fetchDriverLocation();

      // ✅ Socket Realtime - بدل Timer
      SocketService.joinAsPassenger(widget.tripId!, currentUserPhone);

      SocketService.onDriverMoved((data) {
        if (!mounted) return;
        final lat = data['lat'];
        final lng = data['lng'];
        if (lat != null && lng != null) {
          _updateDriverMarker(lat.toDouble(), lng.toDouble());
        }
        if (data['liveStats'] != null) {
          setState(() {
            liveDistance = (data['liveStats']['distanceKm'] ?? 0).toDouble();
            liveDuration = (data['liveStats']['durationMinutes'] ?? 0).toInt();
            liveFare = (data['liveStats']['currentFare'] ?? 0).toDouble();
          });
        }
        if (data['status'] == 'completed') {
          SocketService.offDriverMoved();
          _fetchDriverLocation();
        }
      });

      SocketService.onTripUpdated((data) {
        if (!mounted) return;
        final newStatus = data['status'] ?? '';
        if (newStatus != tripStatus) {
          setState(() => tripStatus = newStatus);
          if (newStatus == 'completed') {
            SocketService.offTripUpdated();
            setState(() => showRating = true);
          }
        }
      });

      // HTTP fallback كل 15 ثانية — Socket يتولى تحديث الموقع الفوري
      _trackingTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        if (!mounted) return;
        await _fetchDriverLocation();
      });
    }

    _mapRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted) return;
      if (widget.tripId == null) await _loadMapData();
    });
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _mapRefreshTimer?.cancel();
    SocketService.offDriverMoved();
    SocketService.offTripUpdated();
    SocketService.offTripAccepted();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    if (kIsWeb) {
      // Chrome: استخدم الموقع المحفوظ من PassengerHomePage
      return;
    }
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location service disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied forever');
        return;
      }
      if (permission == LocationPermission.denied) return;

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10));

      // تجاهل موقع San Francisco الافتراضي للمحاكي
      if (pos.latitude > 37.0 && pos.latitude < 38.0 && pos.longitude < -121.0) {
        debugPrint('Simulator location ignored');
        return;
      }

      debugPrint('✅ GPS: ${pos.latitude}, ${pos.longitude}');
      if (mounted) setState(() => currentPosition = pos);
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  // ===== تحديث علامة السائق مباشرة (Socket) =====
  void _updateDriverMarker(double lat, double lng) {
    final driverPos = LatLng(lat, lng);
    final hasMovedSignificantly = lastDriverPosition == null ||
        (lastDriverPosition!.latitude - driverPos.latitude).abs() > 0.00005 ||
        (lastDriverPosition!.longitude - driverPos.longitude).abs() > 0.00005;

    if (!hasMovedSignificantly) return;
    lastDriverPosition = driverPos;

    final updatedMarkers = Set<Marker>.from(markers);
    updatedMarkers.removeWhere((m) => m.markerId.value == 'driver_live');
    final driverTitle = driverName.isNotEmpty ? '🚕 $driverName' : '🚕 السائق';
    updatedMarkers.add(Marker(
      markerId: const MarkerId('driver_live'),
      position: driverPos,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: InfoWindow(
        title: driverTitle,
        snippet: _getDriverSnippet(),
      ),
    ));

    if (mounted) {
      // تحديث فقط إذا تغير الموقع فعلاً
      setState(() => markers = updatedMarkers);
      if (_cameraFollowsDriver && mapController != null) {
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(driverPos, 16),
        );
      }
    }
  }

  // ===== جلب موقع السائق كل 3 ثواني =====
  Future<void> _fetchDriverLocation() async {
    if (widget.tripId == null || widget.tripId == 0) return;
    try {
      final response = await SessionService.get('/taxi/trips/${widget.tripId}/location');
      if (response.statusCode != 200 || !mounted) return;

      final data = jsonDecode(response.body);

      setState(() {
        tripStatus = data['status'] ?? '';
        if (data['driverName'] != null && data['driverName'].toString().isNotEmpty) {
          driverName = data['driverName'];
        }
        if (data['finalFare'] != null) finalFare = (data['finalFare']).toDouble();
        if (data['liveStats'] != null) {
          liveDistance = (data['liveStats']['distanceKm'] ?? 0).toDouble();
          liveDuration = (data['liveStats']['durationMinutes'] ?? 0).toInt();
          liveFare = (data['liveStats']['currentFare'] ?? 0).toDouble();
        }
        if (tripStatus == 'completed') {
          _trackingTimer?.cancel();
          showRating = true;
        }
      });

      final driverLat = data['driverLat'];
      final driverLng = data['driverLng'];
      final pickupLat = data['pickupLat'];
      final pickupLng = data['pickupLng'];
      final destLat = data['destLat'];
      final destLng = data['destLng'];
      final route = data['route'] as List? ?? [];

      Set<Marker> updatedMarkers = Set.from(markers);

      // ===== علامة السائق المتحركة =====
      if (driverLat != null && driverLng != null) {
        final driverPos = LatLng(driverLat.toDouble(), driverLng.toDouble());

        final hasMovedSignificantly = lastDriverPosition == null ||
            (lastDriverPosition!.latitude - driverPos.latitude).abs() > 0.00005 ||
            (lastDriverPosition!.longitude - driverPos.longitude).abs() > 0.00005;

        updatedMarkers.removeWhere((m) => m.markerId.value == 'driver_live');
        final title = driverName.isNotEmpty ? '🚕 $driverName' : '🚕 السائق';
        updatedMarkers.add(Marker(
          markerId: const MarkerId('driver_live'),
          position: driverPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: title,
            snippet: _getDriverSnippet(),
          ),
        ));

        // تحريك الكاميرا فقط عند تغيير حقيقي
        if (hasMovedSignificantly && _cameraFollowsDriver) {
          lastDriverPosition = driverPos;
          mapController?.animateCamera(
            CameraUpdate.newLatLng(driverPos),
          );
        }
      }

      // ===== علامة موقع الراكب =====
      if (pickupLat != null && pickupLng != null) {
        updatedMarkers.removeWhere((m) => m.markerId.value == 'pickup_live');
        updatedMarkers.add(Marker(
          markerId: const MarkerId('pickup_live'),
          position: LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: '📍 موقع الراكب'),
        ));
      }

      // ===== علامة الوجهة =====
      if (destLat != null && destLng != null) {
        updatedMarkers.removeWhere((m) => m.markerId.value == 'destination');
        updatedMarkers.add(Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(destLat.toDouble(), destLng.toDouble()),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: '🏁 الوجهة'),
        ));
      }

      // ===== خط المسار =====
      if (route.length > 1) {
        final points = route
            .map<LatLng>((p) => LatLng(p['lat'].toDouble(), p['lng'].toDouble()))
            .toList();
        setState(() {
          polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              color: Colors.blue,
              width: 5,

            ),
          };
        });
      }

      if (mounted) setState(() => markers = updatedMarkers);
    } catch (e) {
      debugPrint('Tracking error: $e');
    }
  }

  String _getDriverSnippet() {
    switch (tripStatus) {
      case 'accepted': return '🚗 في الطريق إليك';
      case 'arrived': return '📍 وصل - في انتظارك';
      case 'in_progress': return '🚗 الرحلة جارية';
      default: return '';
    }
  }

  DateTime? _lastMapLoad;
  Future<void> _loadMapData({bool force = false}) async {
    // لا تُحمّل البيانات إذا مر أقل من 10 ثواني (إلا عند الإجبار)
    if (!force && _lastMapLoad != null &&
        DateTime.now().difference(_lastMapLoad!).inSeconds < 10) return;
    _lastMapLoad = DateTime.now();
    try {
      final results = await Future.wait([
        SessionService.get('/scooters'),
        SessionService.get('/taxis'),
      ]);
      if (!mounted) return;

      final scooters = jsonDecode(results[0].body) as List;
      final taxis = jsonDecode(results[1].body) as List;

      Set<Marker> newMarkers = {};

      // علامات السكوترات
      for (var s in scooters) {
        if (s['lat'] == null || s['lng'] == null) continue;
        final isAvailable = s['status'] == 'available';
        final name = s['name'] ?? s['scooter_code'] ?? 'سكوتر';
        newMarkers.add(Marker(
          markerId: MarkerId('scooter_${s['id']}'),
          position: LatLng(s['lat'].toDouble(), s['lng'].toDouble()),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              isAvailable ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '${isAvailable ? "🛴 متاح" : "🔴 مشغول"} - $name',
            snippet: 'البطارية: ${s['battery']}%',
            onTap: isAvailable ? () => _showRentDialog(s) : null,
          ),
        ));
      }

      // علامات التاكسيات
      for (var t in taxis) {
        if (t['lat'] == null || t['lng'] == null) continue;
        final isOnline = t['status'] == 'online';
        newMarkers.add(Marker(
          markerId: MarkerId('taxi_${t['id']}'),
          position: LatLng(t['lat'].toDouble(), t['lng'].toDouble()),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              isOnline ? BitmapDescriptor.hueYellow : BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: '${isOnline ? "🟡 متاح" : "🟠 مشغول"} - ${t['name']}',
            snippet: isOnline ? 'اضغط لطلب التكسي' : 'مشغول حالياً',
          ),
        ));
      }

      // موقع المستخدم الحالي
      final lat = currentPosition?.latitude ?? currentLat;
      final lng = currentPosition?.longitude ?? currentLng;
      if (lat != null && lng != null) {
        newMarkers.add(Marker(
          markerId: const MarkerId('my_location'),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta),
          infoWindow: const InfoWindow(title: '📱 موقعك الحالي'),
        ));
      }

      if (mounted) setState(() => markers = newMarkers);
    } catch (e) {
      debugPrint('loadMapData error: $e');
    }
  }

  void _showRentDialog(Map scooter) {
    final name = scooter['name'] ?? scooter['scooter_code'] ?? 'سكوتر';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('🛴 $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('البطارية: ${scooter['battery']}%'),
            const Text('السعر: 1.000 د.ك'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final phone = currentUserPhone.isNotEmpty ? currentUserPhone : '99999999';
              try {
                final res = await SessionService.post('/scooter/rent', {'scooterId': scooter['id'], 'phone': phone});
                final data = jsonDecode(res.body);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(data['message'] ?? 'تم'),
                  backgroundColor: data['success'] == true ? Colors.green : Colors.red,
                ));
                if (data['success'] == true) _loadMapData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('تعذر الاتصال'), backgroundColor: Colors.red,
                ));
              }
            },
            child: const Text('استئجار'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateTripStatus(String status) async {
    if (widget.tripId == null) return;
    try {
      await SessionService.put('/taxi/trips/${widget.tripId}/status', {'status': status});
      if (!mounted) return;
      setState(() => tripStatus = status);
      if (status == 'completed') {
        _trackingTimer?.cancel();
        setState(() => showRating = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'arrived' ? '📍 وصلت للراكب'
            : status == 'in_progress' ? '🚗 بدأت الرحلة'
            : '✅ انتهت الرحلة'),
        backgroundColor: status == 'completed' ? Colors.green
            : status == 'in_progress' ? Colors.blue : Colors.orange,
      ));
    } catch (e) {
      debugPrint('updateTripStatus error: $e');
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'waiting_driver': return '⏳ بانتظار السائق';
      case 'accepted': return '✅ تم قبول الرحلة - في الطريق إليك';
      case 'arrived': return '📍 السائق وصل - في انتظارك';
      case 'in_progress': return '🚗 الرحلة جارية';
      case 'completed': return '🏁 انتهت الرحلة';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted': return Colors.orange;
      case 'arrived': return Colors.deepOrange;
      case 'in_progress': return Colors.blue;
      case 'completed': return Colors.green;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // macOS لا يدعم Google Maps
    if (!kIsWeb && Platform.isMacOS) {
      return Scaffold(
        appBar: AppBar(title: const Text('الخريطة')),
        body: const Center(
          child: Text('الخريطة تعمل على iPhone و Android فقط',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
        ),
      );
    }

    // شاشة التقييم
    if (showRating) {
      return Scaffold(
        appBar: AppBar(title: const Text('انتهت الرحلة ✅')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.check_circle, color: Colors.green, size: 80),
              const SizedBox(height: 16),
              const Text('وصلت بسلامة!',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green),
                ),
                child: Column(children: [
                  if (liveDistance > 0.01)
                    Text('📏 المسافة: ${liveDistance.toStringAsFixed(2)} كم',
                        style: const TextStyle(fontSize: 16)),
                  if (liveDuration > 0)
                    Text('⏱ المدة: $liveDuration دقيقة',
                        style: const TextStyle(fontSize: 16)),
                  const Divider(height: 24),
                  Text(
                    '💰 ${(finalFare ?? liveFare).toStringAsFixed(3)} د.ك',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  const Text('الأجرة النهائية',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('✅ تم خصم الأجرة من رصيدك',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 32),
              const Text('قيّم رحلتك ⭐',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => IconButton(
                  icon: Icon(
                    i < selectedRating ? Icons.star : Icons.star_border,
                    color: Colors.amber, size: 44,
                  ),
                  onPressed: () => setState(() => selectedRating = i + 1),
                )),
              ),
              const SizedBox(height: 16),
              if (selectedRating > 0)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (widget.tripId != null) {
                        await SessionService.post('/taxi/trips/${widget.tripId}/rate', {'rating': selectedRating});
                      }
                      if (!mounted) return;
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    icon: const Icon(Icons.send),
                    label: const Text('إرسال التقييم والخروج',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('تخطي'),
              ),
            ],
          ),
        ),
      );
    }

    final mapLat = currentPosition?.latitude ?? currentLat ?? _defaultLocation.latitude;
    final mapLng = currentPosition?.longitude ?? currentLng ?? _defaultLocation.longitude;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الخريطة'),
        actions: [
          // زر تتبع السائق
          if (widget.tripId != null && lastDriverPosition != null)
            IconButton(
              icon: Icon(_cameraFollowsDriver ? Icons.gps_fixed : Icons.gps_not_fixed),
              tooltip: _cameraFollowsDriver ? 'إيقاف التتبع' : 'تتبع السائق',
              onPressed: () => setState(() => _cameraFollowsDriver = !_cameraFollowsDriver),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMapData),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            myLocationEnabled: currentPosition != null,
            myLocationButtonEnabled: currentPosition != null,
            zoomControlsEnabled: true,
            onMapCreated: (c) => mapController = c,
            onCameraMove: (_) {
              // إيقاف التتبع عند تحريك الخريطة يدوياً
              if (_cameraFollowsDriver) {
                setState(() => _cameraFollowsDriver = false);
              }
            },
            initialCameraPosition: CameraPosition(
              target: LatLng(mapLat, mapLng),
              zoom: 15,
            ),
            markers: markers,
            polylines: polylines,
          ),

          // ===== شريط الحالة + أزرار الرحلة =====
          if (widget.tripId != null && widget.tripId! > 0)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // شريط السحب
                    Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // اسم السائق + حالة الرحلة
                    if (tripStatus.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _statusText(tripStatus),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _statusColor(tripStatus),
                              fontSize: 14,
                            ),
                          ),
                          if (driverName.isNotEmpty)
                            Row(children: [
                              const Icon(Icons.drive_eta, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(driverName, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            ]),
                        ],
                      ),

                    // عداد مباشر
                    if (tripStatus == 'in_progress' && liveDuration > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade900,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _LiveStat('المسافة', '${liveDistance.toStringAsFixed(2)} كم'),
                            _LiveStat('الوقت', '$liveDuration دقيقة'),
                            _LiveStat('الأجرة', '${liveFare.toStringAsFixed(3)} د.ك', isHighlight: true),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // زر وصلت للراكب
                    if (tripStatus == 'accepted')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: () => _updateTripStatus('arrived'),
                          icon: const Icon(Icons.location_on),
                          label: const Text('وصلت للراكب', style: TextStyle(fontSize: 16)),
                        ),
                      ),

                    // زر بدأت الرحلة
                    if (tripStatus == 'arrived')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: () => _updateTripStatus('in_progress'),
                          icon: const Icon(Icons.directions_car),
                          label: const Text('بدأت الرحلة', style: TextStyle(fontSize: 16)),
                        ),
                      ),

                    // زر أنهيت الرحلة
                    if (tripStatus == 'in_progress')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: () => _updateTripStatus('completed'),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('أنهيت الرحلة', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ===== Widget إحصائية مباشرة =====
class _LiveStat extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlight;

  const _LiveStat(this.label, this.value, {this.isHighlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Text(
          value,
          style: TextStyle(
            color: isHighlight ? Colors.amber : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isHighlight ? 16 : 14,
          ),
        ),
      ],
    );
  }
}
