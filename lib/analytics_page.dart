import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'session_service.dart';
import 'app_theme.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});
  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  Map data = {};
  bool loading = true;
  int selectedPeriod = 30;
  late TabController _tabController;

  final periods = [7, 30, 90, 365];
  final periodLabels = ['أسبوع', 'شهر', '3 أشهر', 'سنة'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final res = await SessionService.get('/admin/analytics?period=$selectedPeriod');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() { data = jsonDecode(res.body); loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Map get overview => data['overview'] ?? {};
  List get dailyRevenue => (data['dailyRevenue'] as List?) ?? [];
  List get monthlyRevenue => (data['monthlyRevenue'] as List?) ?? [];
  List get topDrivers => (data['topDrivers'] as List?) ?? [];
  List get topPickups => (data['topPickups'] as List?) ?? [];
  List get topDestinations => (data['topDestinations'] as List?) ?? [];
  List get hourlyDist => (data['hourlyDistribution'] as List?) ?? [];
  double get avgArrival => (data['avgArrivalTime'] ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D1B6E), Color(0xFF3949AB)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('📊 التقارير والإحصائيات',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      // اختيار الفترة
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(periods.length, (i) => GestureDetector(
                            onTap: () {
                              setState(() => selectedPeriod = periods[i]);
                              _loadData();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: selectedPeriod == periods[i]
                                    ? Colors.amber : Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(periodLabels[i],
                                  style: TextStyle(
                                    color: selectedPeriod == periods[i]
                                        ? Colors.black87 : Colors.white,
                                    fontWeight: FontWeight.bold, fontSize: 12,
                                  )),
                            ),
                          )),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                )),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              isScrollable: true,
              tabs: const [
                Tab(icon: Icon(Icons.dashboard, size: 16), text: 'نظرة عامة'),
                Tab(icon: Icon(Icons.trending_up, size: 16), text: 'الأرباح'),
                Tab(icon: Icon(Icons.people, size: 16), text: 'السائقون'),
                Tab(icon: Icon(Icons.location_on, size: 16), text: 'المناطق'),
              ],
            ),
          ),
        ],
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [_overviewTab(), _revenueTab(), _driversTab(), _areasTab()],
              ),
      ),
    );
  }

  // ===== نظرة عامة =====
  Widget _overviewTab() {
    final total = (overview['total'] ?? 0) as num;
    final completed = (overview['completed'] ?? 0) as num;
    final cancelled = (overview['cancelled'] ?? 0) as num;
    final revenue = (overview['revenue'] ?? 0) as num;
    final avgFare = (overview['avg_fare'] ?? 0) as num;
    final avgDuration = (overview['avg_duration'] ?? 0) as num;
    final completionRate = total > 0 ? (completed / total * 100) : 0.0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // بطاقات رئيسية
          Row(children: [
            Expanded(child: _BigStatCard(
              title: 'إجمالي الإيراد',
              value: '${revenue.toStringAsFixed(3)} د.ك',
              icon: Icons.account_balance_wallet,
              color: Colors.green,
              subtitle: 'خلال $selectedPeriod يوم',
            )),
            const SizedBox(width: 12),
            Expanded(child: _BigStatCard(
              title: 'إجمالي الرحلات',
              value: '$total',
              icon: Icons.local_taxi,
              color: Colors.blue,
              subtitle: '$completed مكتملة',
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _BigStatCard(
              title: 'متوسط الأجرة',
              value: '${avgFare.toStringAsFixed(3)} د.ك',
              icon: Icons.attach_money,
              color: Colors.teal,
              subtitle: 'لكل رحلة',
            )),
            const SizedBox(width: 12),
            Expanded(child: _BigStatCard(
              title: 'متوسط زمن الوصول',
              value: '${avgArrival.toStringAsFixed(1)} د',
              icon: Icons.timer,
              color: Colors.orange,
              subtitle: 'دقيقة',
            )),
          ]),
          const SizedBox(height: 16),

          // نسبة الإكمال
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('نسبة إتمام الرحلات',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${completionRate.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18,
                        color: completionRate >= 80 ? Colors.green : Colors.orange,
                      )),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: completionRate / 100,
                    minHeight: 12,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                        completionRate >= 80 ? Colors.green : Colors.orange),
                  ),
                ),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _MiniStat('$completed', 'مكتملة', Colors.green),
                  _MiniStat('$cancelled', 'ملغاة', Colors.red),
                  _MiniStat('${total - completed - cancelled}', 'أخرى', Colors.grey),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // توزيع الطلبات بالساعة
          if (hourlyDist.isNotEmpty) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🕐 توزيع الطلبات بالساعة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 16),
                  _HourlyChart(hourlyDist),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // ===== الأرباح =====
  Widget _revenueTab() {
    final maxRevenue = dailyRevenue.isEmpty ? 1.0
        : dailyRevenue.map((d) => (d['revenue'] as num).toDouble())
            .reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // رسم بياني يومي
        if (dailyRevenue.isNotEmpty) ...[
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('📈 الأرباح اليومية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: dailyRevenue.take(14).map((d) {
                      final rev = (d['revenue'] as num).toDouble();
                      final height = maxRevenue > 0 ? (rev / maxRevenue * 130) : 0.0;
                      final day = (d['day'] as String).substring(5);
                      return Expanded(child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          if (rev > 0)
                            Text(rev.toStringAsFixed(2),
                                style: const TextStyle(fontSize: 7, color: Colors.teal)),
                          const SizedBox(height: 2),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 600),
                            height: height + 2,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3949AB),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(day, style: const TextStyle(fontSize: 8, color: Colors.grey)),
                        ]),
                      ));
                    }).toList(),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // جدول يومي
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(child: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  SizedBox(width: 60, child: Text('رحلات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                  SizedBox(width: 80, child: Text('الإيراد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                ]),
              ),
              const Divider(height: 1),
              ...dailyRevenue.take(30).map((d) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(children: [
                  Expanded(child: Text(d['day'] ?? '-',
                      style: const TextStyle(fontSize: 12))),
                  SizedBox(width: 60, child: Text('${d['completed']}/${d['total_trips']}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12))),
                  SizedBox(width: 80, child: Text(
                    '${(d['revenue'] as num).toStringAsFixed(3)} د.ك',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                  )),
                ]),
              )),
            ],
          ),
        ),
      ]),
    );
  }

  // ===== السائقون =====
  Widget _driversTab() {
    if (topDrivers.isEmpty) return const EmptyState(
      title: 'لا توجد بيانات',
      subtitle: 'ستظهر هنا إحصائيات السائقين',
      icon: Icons.drive_eta,
    );

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: topDrivers.length,
      itemBuilder: (_, i) {
        final d = topDrivers[i];
        final medals = ['🥇','🥈','🥉','4️⃣','5️⃣','6️⃣','7️⃣','8️⃣','9️⃣','🔟'];
        final earnings = (d['earnings'] ?? 0) as num;
        final rating = d['avg_rating'] != null ? (d['avg_rating'] as num).toDouble() : null;
        final rate = (d['completion_rate'] ?? 0) as num;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Text(i < medals.length ? medals[i] : '${i+1}',
                  style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['driver_name'] ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  _InfoChip(Icons.local_taxi, '${d['completed']} رحلة', Colors.blue),
                  const SizedBox(width: 6),
                  _InfoChip(Icons.attach_money, '${earnings.toStringAsFixed(3)} د.ك', Colors.green),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  if (rating != null) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 14),
                    Text(' ${rating.toStringAsFixed(1)}  ',
                        style: const TextStyle(fontSize: 12)),
                  ],
                  const Icon(Icons.check_circle, color: Colors.green, size: 14),
                  Text(' ${rate.toStringAsFixed(0)}% إتمام',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ])),
            ]),
          ),
        );
      },
    );
  }

  // ===== المناطق =====
  Widget _areasTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        if (topPickups.isNotEmpty) ...[
          const Text('📍 أكثر مناطق الانطلاق',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...topPickups.asMap().entries.map((e) {
            final d = e.value;
            final requests = (d['requests'] as num).toInt();
            final maxReq = (topPickups[0]['requests'] as num).toInt();
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text(d['pickup'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        overflow: TextOverflow.ellipsis)),
                    Text('$requests طلب',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: requests / maxReq,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF3949AB)),
                      minHeight: 6,
                    ),
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 20),
        ],
        if (topDestinations.isNotEmpty) ...[
          const Text('🏁 أكثر الوجهات المطلوبة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...topDestinations.asMap().entries.map((e) {
            final d = e.value;
            final requests = (d['requests'] as num).toInt();
            final maxReq = (topDestinations[0]['requests'] as num).toInt();
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text(d['destination'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        overflow: TextOverflow.ellipsis)),
                    Text('$requests طلب',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: requests / maxReq,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(Colors.teal),
                      minHeight: 6,
                    ),
                  ),
                ]),
              ),
            );
          }),
        ],
      ]),
    );
  }
}

// ===== Widgets =====
class _BigStatCard extends StatelessWidget {
  final String title, value, subtitle;
  final IconData icon;
  final Color color;
  const _BigStatCard({required this.title, required this.value,
      required this.subtitle, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1), shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(height: 10),
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
    ]),
  );
}

class _MiniStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _MiniStat(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  ]);
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _HourlyChart extends StatelessWidget {
  final List data;
  const _HourlyChart(this.data);

  @override
  Widget build(BuildContext context) {
    final maxTrips = data.isEmpty ? 1
        : data.map((d) => (d['trips'] as num).toInt()).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(24, (h) {
          final hourData = data.firstWhere(
            (d) => int.parse(d['hour'].toString()) == h,
            orElse: () => {'trips': 0},
          );
          final trips = (hourData['trips'] as num).toInt();
          final height = maxTrips > 0 ? (trips / maxTrips * 60) : 0.0;
          final isPeak = h >= 7 && h <= 9 || h >= 16 && h <= 19;
          return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Container(
              height: height + 2,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: isPeak ? Colors.orange : const Color(0xFF3949AB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (h % 6 == 0)
              Text('${h}h', style: const TextStyle(fontSize: 8, color: Colors.grey)),
          ]));
        }),
      ),
    );
  }
}
