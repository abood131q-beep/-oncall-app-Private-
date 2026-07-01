import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'session_service.dart';
import 'main.dart' show currentUserPhone, currentUserBalance;
import 'app_theme.dart';

class ScooterPage extends StatefulWidget {
  const ScooterPage({super.key});
  @override
  State<ScooterPage> createState() => _ScooterPageState();
}

class _ScooterPageState extends State<ScooterPage>
    with SingleTickerProviderStateMixin {
  List scooters = [];
  List history = [];
  Map? activeRide;
  bool loading = true;
  Timer? _rideTimer;
  int _rideDuration = 0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _rideTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        SessionService.get('/scooters'),
        SessionService.get('/scooter/history/$currentUserPhone'),
        SessionService.get('/scooter/active/$currentUserPhone'),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0].statusCode == 200) scooters = jsonDecode(results[0].body);
        if (results[1].statusCode == 200) history = jsonDecode(results[1].body);
        if (results[2].statusCode == 200) {
          final data = jsonDecode(results[2].body);
          if (data['active'] == true) {
            activeRide = data;
            _rideDuration = data['durationMinutes'] ?? 0;
            _startRideTimer();
          }
        }
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _startRideTimer() {
    _rideTimer?.cancel();
    _rideTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _rideDuration++);
      _checkActiveRide();
    });
  }

  Future<void> _checkActiveRide() async {
    try {
      final res = await SessionService.get('/scooter/active/$currentUserPhone');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        if (data['active'] == true) {
          setState(() {
            activeRide = data;
            _rideDuration = data['durationMinutes'] ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint('Error: ${e.toString()}');
    }
  }

  Future<void> _unlockScooter(Map scooter) async {
    if (currentUserBalance < 0.5) {
      _showError('رصيد غير كافٍ - الحد الأدنى 0.500 د.ك');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Text('🛴', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 8),
          Text(scooter['name'] ?? 'سكوتر'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _InfoRow(Icons.battery_full, 'البطارية', '${scooter['battery']}%',
              color: _batteryColor(scooter['battery'] ?? 0)),
          _InfoRow(Icons.attach_money, 'السعر', '0.050 د.ك / دقيقة'),
          _InfoRow(Icons.timer, 'الحد الأدنى', '0.500 د.ك'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'ستبدأ الفوترة فور فتح القفل',
              style: TextStyle(color: Colors.blue, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_open, size: 18),
            label: const Text('فتح القفل'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => loading = true);
      final response = await SessionService.post('/scooter/unlock', {'scooterId': scooter['id'], 'phone': currentUserPhone});
      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        _showSuccess('🛴 تم فتح القفل! استمتع برحلتك');
        _loadData();
      } else {
        _showError(data['message'] ?? 'فشل فتح القفل');
      }
    } catch (e) {
      if (mounted) _showError('تعذر الاتصال بالسيرفر');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _endRide() async {
    if (activeRide == null) return;
    final scooterId = activeRide!['scooter']?['id'];
    final fare = (activeRide!['currentFare'] ?? 0.5).toDouble();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🏁 إنهاء الرحلة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _InfoRow(Icons.timer, 'المدة', '$_rideDuration دقيقة'),
          _InfoRow(Icons.attach_money, 'الأجرة التقريبية', '${fare.toStringAsFixed(3)} د.ك'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('متابعة الرحلة')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إنهاء الرحلة'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => loading = true);
      final response = await SessionService.post('/scooter/end-ride', {'scooterId': scooterId, 'phone': currentUserPhone});
      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        _rideTimer?.cancel();
        activeRide = null;
        currentUserBalance = (data['newBalance'] ?? 0).toDouble();
        _showSuccess('✅ انتهت الرحلة - الأجرة: ${(data['fare'] as num).toStringAsFixed(3)} د.ك');
        _loadData();
      } else {
        _showError(data['message'] ?? 'فشل إنهاء الرحلة');
      }
    } catch (e) {
      if (mounted) _showError('تعذر الاتصال');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Color _batteryColor(int battery) {
    if (battery >= 60) return Colors.green;
    if (battery >= 30) return Colors.orange;
    return Colors.red;
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: activeRide != null ? 220 : 130,
            pinned: true,
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade800, Colors.teal.shade500],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('🛴 السكوترات',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${scooters.where((s) => s['status'] == 'available').length} متاح',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),

                      // رحلة نشطة
                      if (activeRide != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('🟢 رحلة جارية',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                Text('$_rideDuration دقيقة • ${((activeRide!['currentFare'] ?? 0) as num).toStringAsFixed(3)} د.ك',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ]),
                              ElevatedButton(
                                onPressed: _endRide,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                                child: const Text('إنهاء'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                )),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(icon: Icon(Icons.directions_bike, size: 18), text: 'المتاحة'),
                Tab(icon: Icon(Icons.map, size: 18), text: 'الخريطة'),
                Tab(icon: Icon(Icons.history, size: 18), text: 'السجل'),
              ],
            ),
          ),
        ],
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [_scootersList(), _scootersMap(), _historyTab()],
              ),
      ),
    );
  }

  Widget _scootersList() {
    final available = scooters.where((s) => s['status'] == 'available').toList();
    final busy = scooters.where((s) => s['status'] != 'available').toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (available.isNotEmpty) ...[
            _SectionTitle('✅ متاح (${available.length})'),
            ...available.map((s) => _ScooterCard(
              scooter: s,
              onUnlock: activeRide == null ? () => _unlockScooter(s) : null,
              batteryColor: _batteryColor(s['battery'] ?? 0),
            )),
            const SizedBox(height: 16),
          ],
          if (busy.isNotEmpty) ...[
            _SectionTitle('🔴 مشغول (${busy.length})'),
            ...busy.map((s) => _ScooterCard(
              scooter: s,
              onUnlock: null,
              batteryColor: _batteryColor(s['battery'] ?? 0),
            )),
          ],
          if (scooters.isEmpty)
            const EmptyState(
              title: 'لا توجد سكوترات',
              subtitle: 'سيتم إضافة سكوترات قريباً',
              icon: Icons.directions_bike,
            ),
        ],
      ),
    );
  }

  Widget _scootersMap() => const Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.map, size: 64, color: Colors.grey),
      SizedBox(height: 12),
      Text('خريطة السكوترات', style: TextStyle(fontSize: 16)),
      Text('افتح الخريطة الرئيسية لرؤية السكوترات',
          style: TextStyle(color: Colors.grey, fontSize: 13)),
    ]),
  );

  Widget _historyTab() {
    if (history.isEmpty) {
      return const EmptyState(
        title: 'لا توجد رحلات سابقة',
        subtitle: 'ابدأ رحلتك الأولى بالسكوتر',
        icon: Icons.history,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (_, i) {
        final ride = history[i];
        final duration = ride['duration_minutes'] ?? 0;
        final fare = (ride['fare'] ?? 0) as num;
        final isActive = ride['status'] == 'active';
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  const Text('🛴', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(ride['scooter_name'] ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(isActive ? '🟢 جارية' : '✅ منتهية',
                      style: TextStyle(
                        color: isActive ? Colors.green : Colors.grey,
                        fontSize: 11, fontWeight: FontWeight.bold,
                      )),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _InfoChip(Icons.timer, '$duration دقيقة', Colors.blue),
                const SizedBox(width: 8),
                _InfoChip(Icons.attach_money, '${fare.toStringAsFixed(3)} د.ك', Colors.green),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

// ===== Widgets =====
class _ScooterCard extends StatelessWidget {
  final Map scooter;
  final VoidCallback? onUnlock;
  final Color batteryColor;

  const _ScooterCard({required this.scooter, this.onUnlock, required this.batteryColor});

  @override
  Widget build(BuildContext context) {
    final available = scooter['status'] == 'available';
    final battery = scooter['battery'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: available ? batteryColor.withValues(alpha: 0.3) : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: available ? Colors.teal.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text('🛴', style: TextStyle(
                  fontSize: 26,
                  color: available ? null : Colors.grey,
                )),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(scooter['name'] ?? '-',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(scooter['scooter_code'] ?? '-',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                Icon(Icons.battery_full, size: 16, color: batteryColor),
                const SizedBox(width: 2),
                Text('$battery%', style: TextStyle(
                  color: batteryColor, fontWeight: FontWeight.bold, fontSize: 13,
                )),
              ]),
              Text(available ? '0.050 د.ك/دقيقة' : 'مشغول',
                  style: TextStyle(
                    color: available ? Colors.teal : Colors.grey,
                    fontSize: 11,
                  )),
            ]),
          ]),
          // شريط البطارية
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: battery / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(batteryColor),
              minHeight: 6,
            ),
          ),
          if (available && onUnlock != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onUnlock,
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('فتح القفل'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color? color;
  const _InfoRow(this.icon, this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 16, color: color ?? Colors.grey),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
      Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color)),
    ]),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
    ]),
  );
}
