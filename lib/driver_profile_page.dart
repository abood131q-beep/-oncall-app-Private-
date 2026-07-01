import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'session_service.dart';
import 'main.dart' show currentUserPhone;

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});
  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage>
    with SingleTickerProviderStateMixin {
  Map? stats;
  List trips = [];
  bool loading = true;
  bool editingInfo = false;
  bool savingInfo = false;
  late TabController _tabController;
  final nameController = TextEditingController();
  final carController = TextEditingController();
  final plateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    nameController.dispose();
    carController.dispose();
    plateController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        SessionService.get('/driver/stats/$currentUserPhone'),
        SessionService.get('/driver/trips/$currentUserPhone'),
      ]);
      if (!mounted) return;
      Map? s;
      List t = [];
      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        s = data['stats'];
      }
      if (results[1].statusCode == 200) {
        t = jsonDecode(results[1].body);
      }
      setState(() {
        stats = s;
        trips = t;
        nameController.text = s?['driverName'] ?? '';
        carController.text = s?['carName'] ?? '';
        plateController.text = s?['plate'] ?? '';
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveInfo() async {
    setState(() => savingInfo = true);
    try {
      await SessionService.post('/driver/update', {
          'phone': currentUserPhone,
          'name': nameController.text.trim(),
          'car_name': carController.text.trim(),
          'plate': plateController.text.trim(),
        });
      if (!mounted) return;
      setState(() { editingInfo = false; savingInfo = false; });
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ تم حفظ البيانات'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) setState(() => savingInfo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A237E),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(editingInfo ? Icons.close : Icons.edit_note),
                onPressed: () => setState(() => editingInfo = !editingInfo),
              ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
            ],
            flexibleSpace: FlexibleSpaceBar(background: _buildHeader()),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.bar_chart, size: 20), text: 'الإحصائيات'),
                Tab(icon: Icon(Icons.badge, size: 20), text: 'بياناتي'),
                Tab(icon: Icon(Icons.history, size: 20), text: 'الرحلات'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [_statsTab(), _infoTab(), _tripsTab()],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = stats?['driverName'] ?? 'السائق';
    final rating = (stats?['avgRating'] ?? 5.0).toDouble();
    final isOnline = stats?['driverStatus'] == 'online';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B6E), Color(0xFF3949AB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amber, width: 2.5),
                  ),
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: const TextStyle(fontSize: 38, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green : Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    isOnline ? '● متصل' : '● غير متصل',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if ((stats?['carName'] ?? '').isNotEmpty)
              Text(
                '${stats!['carName']}  •  ${stats?['plate'] ?? ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...List.generate(5, (i) => Icon(
                  i < rating.floor() ? Icons.star : (i < rating ? Icons.star_half : Icons.star_border),
                  color: Colors.amber, size: 16,
                )),
                const SizedBox(width: 6),
                Text(rating.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Text('(${stats?['completedTrips'] ?? 0} رحلة)',
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _statsTab() {
    final total = (stats?['totalEarnings'] ?? 0.0).toDouble();
    final today = (stats?['todayEarnings'] ?? 0.0).toDouble();
    final week = (stats?['weekEarnings'] ?? 0.0).toDouble();
    final hours = (stats?['totalHours'] ?? 0.0).toDouble();
    final acceptance = (stats?['acceptanceRate'] ?? 100).toInt();
    final completed = stats?['completedTrips'] ?? 0;
    final cancelled = stats?['cancelledTrips'] ?? 0;
    final totalTrips = stats?['totalTrips'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // بطاقة أرباح اليوم
            _EarningCard(
              title: 'أرباح اليوم',
              amount: today,
              subtitle: '${trips.where((t) {
                try {
                  final d = DateTime.parse(t['created_at'] ?? '');
                  final now = DateTime.now();
                  return d.day == now.day && t['status'] == 'completed';
                } catch (_) { return false; }
              }).length} رحلة اليوم',
              color: Colors.orange,
              icon: Icons.today,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _EarningCard(
                title: 'هذا الأسبوع',
                amount: week,
                subtitle: '',
                color: Colors.blue,
                icon: Icons.date_range,
                compact: true,
              )),
              const SizedBox(width: 12),
              Expanded(child: _EarningCard(
                title: 'إجمالي الأرباح',
                amount: total,
                subtitle: '',
                color: Colors.green,
                icon: Icons.account_balance_wallet,
                compact: true,
              )),
            ]),
            const SizedBox(height: 16),

            // إحصائيات الرحلات
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📊 إحصائيات الرحلات',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 14),
                  Row(children: [
                    _MiniStat('$totalTrips', 'إجمالي', Colors.purple),
                    _MiniStat('$completed', 'مكتملة', Colors.green),
                    _MiniStat('$cancelled', 'ملغاة', Colors.red),
                    _MiniStat('${hours}h', 'ساعات', Colors.teal),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // نسبة القبول
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('نسبة القبول', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: acceptance >= 80 ? Colors.green.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('$acceptance%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16,
                            color: acceptance >= 80 ? Colors.green : Colors.orange,
                          )),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: acceptance / 100,
                      minHeight: 12,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                          acceptance >= 80 ? Colors.green : Colors.orange),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    acceptance >= 90 ? '🌟 ممتاز! أنت من أفضل السائقين'
                        : acceptance >= 80 ? '✅ جيد جداً - حافظ على هذا المستوى'
                        : acceptance >= 60 ? '⚠️ حاول قبول المزيد من الرحلات'
                        : '❌ نسبة القبول منخفضة جداً',
                    style: TextStyle(
                      fontSize: 12,
                      color: acceptance >= 80 ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ساعات العمل
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.access_time, color: Colors.teal, size: 28),
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('إجمالي ساعات العمل', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('$hours ساعة',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)),
                  Text('${stats?['totalMinutes'] ?? 0} دقيقة',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.badge, color: Color(0xFF1A237E)),
                const SizedBox(width: 8),
                const Text('بيانات السائق', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (editingInfo)
                  FilledButton.icon(
                    onPressed: savingInfo ? null : _saveInfo,
                    icon: savingInfo
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 16),
                    label: const Text('حفظ'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  ),
              ]),
              const Divider(height: 24),
              if (!editingInfo) ...[
                _InfoRow(Icons.person, 'الاسم', stats?['driverName'] ?? '-'),
                _InfoRow(Icons.phone, 'الهاتف', currentUserPhone),
                _InfoRow(Icons.directions_car, 'السيارة', stats?['carName']?.toString().isNotEmpty == true ? stats!['carName'] : 'غير محدد'),
                _InfoRow(Icons.pin, 'اللوحة', stats?['plate']?.toString().isNotEmpty == true ? stats!['plate'] : 'غير محدد'),
                _InfoRow(Icons.star, 'التقييم', '${(stats?['avgRating'] ?? 5.0).toStringAsFixed(1)} / 5.0 ⭐'),
                _InfoRow(Icons.circle, 'الحالة', stats?['driverStatus'] == 'online' ? 'متصل 🟢' : 'غير متصل 🔴'),
              ] else ...[
                _Field(nameController, 'الاسم الكامل', Icons.person),
                const SizedBox(height: 12),
                _Field(carController, 'نوع السيارة', Icons.directions_car),
                const SizedBox(height: 12),
                _Field(plateController, 'رقم اللوحة', Icons.pin),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tripsTab() {
    if (trips.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('لا توجد رحلات بعد', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      itemBuilder: (_, i) {
        final t = trips[i];
        final status = t['status'] ?? '';
        final done = status == 'completed';
        final fare = (t['final_fare'] ?? t['finalFare'] ?? t['estimated_fare'] ?? 0) as num;
        final rating = t['rating'];

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: done ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    done ? '✅ مكتملة' : status == 'cancelled' ? '❌ ملغاة' : '⏳ ${status}',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold,
                      color: done ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                Text(
                  '${fare.toStringAsFixed(3)} د.ك',
                  style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15,
                    color: done ? Colors.green.shade700 : Colors.grey,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.my_location, size: 13, color: Colors.green),
                const SizedBox(width: 4),
                Expanded(child: Text(t['pickup'] ?? '-',
                    style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ]),
              Row(children: [
                const Icon(Icons.flag, size: 13, color: Colors.red),
                const SizedBox(width: 4),
                Expanded(child: Text(t['destination'] ?? '-',
                    style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ]),
              if (t['duration_minutes'] != null && t['duration_minutes'] > 0) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${t['duration_minutes']} دقيقة',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (t['total_distance'] != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.route, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('${(t['total_distance'] as num).toStringAsFixed(2)} كم',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ]),
              ],
              if (rating != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  ...List.generate(5, (i) => Icon(
                    i < (rating as num).toInt() ? Icons.star : Icons.star_border,
                    color: Colors.amber, size: 14,
                  )),
                  const SizedBox(width: 4),
                  Text('$rating / 5', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ],
            ]),
          ),
        );
      },
    );
  }
}

// ===== Widgets =====
class _EarningCard extends StatelessWidget {
  final String title, subtitle;
  final double amount;
  final Color color;
  final IconData icon;
  final bool compact;

  const _EarningCard({
    required this.title, required this.amount, required this.subtitle,
    required this.color, required this.icon, this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.75)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(height: 6),
              Text('${amount.toStringAsFixed(3)} د.ك',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ])
          : Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text('${amount.toStringAsFixed(3)} د.ك',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
            ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _MiniStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A237E).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF1A237E), size: 18),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  const _Field(this.controller, this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1A237E)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
        ),
      ),
    );
  }
}
