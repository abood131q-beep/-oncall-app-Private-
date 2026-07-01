import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'session_service.dart';

// ===== ألوان لوحة التحكم =====
class _DColors {
  static const indigo  = Color(0xFF4F46E5);
  static const emerald = Color(0xFF10B981);
  static const orange  = Color(0xFFF59E0B);
  static const red     = Color(0xFFEF4444);
  static const blue    = Color(0xFF3B82F6);
  static const purple  = Color(0xFF8B5CF6);
  static const bg      = Color(0xFFF8FAFC);
  static const card    = Color(0xFFFFFFFF);
  static const darkBg  = Color(0xFF0F172A);
  static const darkCard = Color(0xFF1E293B);
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  Map stats = {};
  List trips = [], drivers = [], users = [], backups = [], reports = [];
  List scooters = [], taxis = [];
  bool loading = true;
  bool _firstLoad = true;
  Timer? _autoRefresh;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadAll();
    // تحديث تلقائي كل 30 ثانية
    _autoRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadAll(silent: true);
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) setState(() => loading = true);
    try {
      final results = await Future.wait([
        SessionService.get('/admin/stats'),
        SessionService.get('/admin/trips'),
        SessionService.get('/admin/drivers'),
        SessionService.get('/admin/users'),
        SessionService.get('/admin/backups'),
        SessionService.get('/admin/reports'),
        SessionService.get('/scooters'),
        SessionService.get('/taxis'),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0].statusCode == 200) stats = jsonDecode(results[0].body);
        if (results[1].statusCode == 200) {
          final d = jsonDecode(results[1].body);
          trips = d is Map ? (d['trips'] ?? []) : d;
        }
        if (results[2].statusCode == 200) drivers = jsonDecode(results[2].body);
        if (results[3].statusCode == 200) users = jsonDecode(results[3].body);
        if (results[4].statusCode == 200) backups = jsonDecode(results[4].body)['backups'] ?? [];
        if (results[5].statusCode == 200) reports = jsonDecode(results[5].body);
        if (results[6].statusCode == 200) scooters = jsonDecode(results[6].body);
        if (results[7].statusCode == 200) taxis = jsonDecode(results[7].body);
        loading = false;
        _firstLoad = false;
      });
    } catch (e) {
      debugPrint('AdminDashboard error: ${e.toString()}');
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _DColors.darkBg : _DColors.bg;

    return Scaffold(
      backgroundColor: bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: _DColors.indigo,
            foregroundColor: Colors.white,
            actions: [
              // مؤشر التحديث التلقائي
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                child: _AutoRefreshIndicator(),
              ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => _loadAll()),
              IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _confirmReset),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(isDark),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              isScrollable: true,
              tabs: [
                const Tab(icon: Icon(Icons.dashboard, size: 16), text: 'نظرة عامة'),
                const Tab(icon: Icon(Icons.local_taxi, size: 16), text: 'الرحلات'),
                const Tab(icon: Icon(Icons.drive_eta, size: 16), text: 'السائقون'),
                const Tab(icon: Icon(Icons.people, size: 16), text: 'الركاب'),
                Tab(icon: const Icon(Icons.directions_bike, size: 16),
                    text: 'الأسطول (${scooters.length + taxis.length})'),
                Tab(
                  icon: Stack(clipBehavior: Clip.none, children: [
                    const Icon(Icons.flag, size: 16),
                    if (reports.where((r) => r['status'] == 'pending').isNotEmpty)
                      Positioned(right: -4, top: -4, child: Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      )),
                  ]),
                  text: 'البلاغات',
                ),
                const Tab(icon: Icon(Icons.backup, size: 16), text: 'نسخ احتياطي'),
              ],
            ),
          ),
        ],
        body: _firstLoad && loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _overviewTab(isDark),
                  _tripsTab(isDark),
                  _driversTab(isDark),
                  _usersTab(isDark),
                  _fleetTab(isDark),
                  _reportsTab(isDark),
                  _backupTab(isDark),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final onlineDrivers = stats['onlineDrivers'] ?? 0;
    final activeTrips = stats['activeTrips'] ?? 0;
    final pendingReports = reports.where((r) => r['status'] == 'pending').length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_DColors.indigo, _DColors.indigo.withValues(alpha: 0.8)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
          const Text('لوحة التحكم 🛡️',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            _StatusPill(color: _DColors.emerald, label: '$onlineDrivers سائق متصل'),
            const SizedBox(width: 8),
            _StatusPill(color: _DColors.orange, label: '$activeTrips رحلة نشطة'),
            if (pendingReports > 0) ...[
              const SizedBox(width: 8),
              _StatusPill(color: _DColors.red, label: '$pendingReports بلاغ'),
            ],
          ]),
        ]),
      )),
    );
  }

  // ===== نظرة عامة =====
  Widget _overviewTab(bool isDark) {
    final daily = (stats['dailyStats'] as List?) ?? [];
    final topDrivers = (stats['topDrivers'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // بطاقات الإحصائيات
          _AnimatedStatsGrid(stats: stats, isDark: isDark),
          const SizedBox(height: 16),

          // الرسم الدائري
          Row(children: [
            Expanded(child: _DonutChart(
              title: 'السائقون',
              items: [
                _DonutItem('متصل', (stats['onlineDrivers'] ?? 0).toDouble(), _DColors.emerald),
                _DonutItem('غير متصل', ((stats['totalDrivers'] ?? 0) - (stats['onlineDrivers'] ?? 0)).toDouble(), Colors.grey),
              ],
              isDark: isDark,
            )),
            const SizedBox(width: 12),
            Expanded(child: _DonutChart(
              title: 'الرحلات',
              items: [
                _DonutItem('نشطة', (stats['activeTrips'] ?? 0).toDouble(), _DColors.orange),
                _DonutItem('اليوم', (stats['todayTrips'] ?? 0).toDouble(), _DColors.blue),
                _DonutItem('ملغاة', ((stats['totalTrips'] ?? 0) * 0.05).toDouble(), _DColors.red),
              ],
              isDark: isDark,
            )),
          ]),
          const SizedBox(height: 16),

          // الرسم البياني
          if (daily.isNotEmpty) ...[
            _SectionHeader('📈 رحلات آخر 7 أيام', isDark),
            _ProBarChart(data: daily, isDark: isDark),
            const SizedBox(height: 16),
          ],

          // أفضل السائقين
          if (topDrivers.isNotEmpty) ...[
            _SectionHeader('🏆 أكثر السائقين نشاطاً', isDark),
            _TopDriversCard(drivers: topDrivers, isDark: isDark),
          ],
        ]),
      ),
    );
  }

  // ===== الرحلات مع Timeline =====
  Widget _tripsTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        primary: false,
        padding: const EdgeInsets.all(16),
        itemCount: trips.length,
        itemBuilder: (_, i) => _TripTimelineCard(trip: trips[i], isDark: isDark,
            onCancel: () => _cancelTrip(trips[i]['id'])),
      ),
    );
  }

  // ===== السائقون =====
  Widget _driversTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        primary: false,
        padding: const EdgeInsets.all(16),
        itemCount: drivers.length,
        itemBuilder: (_, i) {
          final d = drivers[i];
          final isOnline = d['status'] == 'online';
          final isActive = d['is_active'] != 0;
          return _ProCard(
            isDark: isDark,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isOnline ? _DColors.emerald.withValues(alpha: 0.2) : Colors.grey.shade200,
                child: Text((d['name'] ?? 'س')[0].toUpperCase(),
                    style: TextStyle(color: isOnline ? _DColors.emerald : Colors.grey, fontWeight: FontWeight.bold)),
              ),
              title: Text(d['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${d['phone'] ?? '-'} • ${d['car_name'] ?? '-'} • ${d['plate'] ?? '-'}',
                  style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(value: isActive, activeColor: _DColors.emerald,
                    onChanged: (_) => _toggleDriver(d['phone'])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnline ? _DColors.emerald.withValues(alpha: 0.1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(isOnline ? '🟢' : '🔴', style: const TextStyle(fontSize: 14)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ===== الركاب =====
  Widget _usersTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        primary: false,
        padding: const EdgeInsets.all(16),
        itemCount: users.length,
        itemBuilder: (_, i) {
          final u = users[i];
          final balance = (u['balance'] ?? 0) as num;
          final isActive = u['is_active'] != 0;
          return _ProCard(
            isDark: isDark,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _DColors.indigo.withValues(alpha: 0.1),
                child: Text((u['name'] ?? 'ر')[0].toUpperCase(),
                    style: const TextStyle(color: _DColors.indigo, fontWeight: FontWeight.bold)),
              ),
              title: Text(u['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(u['phone'] ?? '-'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: balance > 0 ? _DColors.emerald.withValues(alpha: 0.1) : _DColors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${balance.toStringAsFixed(3)} د.ك',
                      style: TextStyle(color: balance > 0 ? _DColors.emerald : _DColors.red,
                          fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 4),
                Switch(value: isActive, activeColor: _DColors.emerald,
                    onChanged: (_) => _toggleUser(u['phone'])),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ===== الأسطول =====
  Widget _fleetTab(bool isDark) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: isDark ? _DColors.darkCard : Colors.white,
          child: const TabBar(
            labelColor: _DColors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _DColors.indigo,
            tabs: [
              Tab(icon: Icon(Icons.directions_bike), text: 'سكوترات'),
              Tab(icon: Icon(Icons.local_taxi), text: 'تاكسي'),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _scootersList(isDark),
          _taxisList(isDark),
        ])),
      ]),
    );
  }

  Widget _scootersList(bool isDark) => Column(children: [
    Padding(
      padding: const EdgeInsets.all(12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${scooters.length} سكوتر', style: const TextStyle(fontWeight: FontWeight.bold)),
        FilledButton.icon(
          onPressed: _addScooterDialog, style: FilledButton.styleFrom(backgroundColor: _DColors.indigo),
          icon: const Icon(Icons.add, size: 16), label: const Text('إضافة'),
        ),
      ]),
    ),
    Expanded(child: ListView.builder(
      primary: false,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: scooters.length,
      itemBuilder: (_, i) {
        final s = scooters[i];
        final available = s['status'] == 'available';
        final battery = (s['battery'] ?? 0) as num;
        final batteryColor = battery > 60 ? _DColors.emerald : battery > 30 ? _DColors.orange : _DColors.red;
        return _ProCard(isDark: isDark, child: Column(children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: available ? _DColors.emerald.withValues(alpha: 0.1) : _DColors.red.withValues(alpha: 0.1),
              child: Icon(Icons.directions_bike, color: available ? _DColors.emerald : _DColors.red, size: 20),
            ),
            title: Text(s['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${s['scooter_code'] ?? '-'} • ${available ? "متاح" : "مشغول"}'),
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                onPressed: () => _deleteScooter(s['id'])),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Icon(Icons.battery_full, size: 14, color: batteryColor),
              const SizedBox(width: 4),
              Text('$battery%', style: TextStyle(color: batteryColor, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: battery / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(batteryColor),
                  minHeight: 6,
                ),
              )),
            ]),
          ),
        ]));
      },
    )),
  ]);

  Widget _taxisList(bool isDark) => Column(children: [
    Padding(
      padding: const EdgeInsets.all(12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${taxis.length} تاكسي', style: const TextStyle(fontWeight: FontWeight.bold)),
        FilledButton.icon(
          onPressed: _addTaxiDialog, style: FilledButton.styleFrom(backgroundColor: _DColors.indigo),
          icon: const Icon(Icons.add, size: 16), label: const Text('إضافة'),
        ),
      ]),
    ),
    Expanded(child: ListView.builder(
      primary: false,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: taxis.length,
      itemBuilder: (_, i) {
        final t = taxis[i];
        final online = t['status'] == 'online';
        return _ProCard(isDark: isDark, child: ListTile(
          leading: CircleAvatar(
            backgroundColor: online ? _DColors.emerald.withValues(alpha: 0.1) : _DColors.orange.withValues(alpha: 0.1),
            child: Icon(Icons.local_taxi, color: online ? _DColors.emerald : _DColors.orange, size: 20),
          ),
          title: Text(t['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('السائق: ${t['driver_id'] != null ? "مرتبط" : "غير مرتبط"}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(online ? '🟢' : '🟠'),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                onPressed: () => _deleteTaxi(t['id'])),
          ]),
        ));
      },
    )),
  ]);

  // ===== البلاغات =====
  Widget _reportsTab(bool isDark) {
    final pending = reports.where((r) => r['status'] == 'pending').toList();
    final resolved = reports.where((r) => r['status'] == 'resolved').toList();
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: reports.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.flag_outlined, size: 60, color: Colors.grey),
              SizedBox(height: 12),
              Text('لا توجد بلاغات', style: TextStyle(color: Colors.grey)),
            ]))
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (pending.isNotEmpty) ...[
                _SectionHeader('⚠️ معلقة (${pending.length})', isDark),
                ...pending.map((r) => _ReportCard(r, isDark: isDark, onResolve: () => _resolveReport(r['id']))),
              ],
              if (resolved.isNotEmpty) ...[
                _SectionHeader('✅ محلولة (${resolved.length})', isDark),
                ...resolved.map((r) => _ReportCard(r, isDark: isDark)),
              ],
            ]),
    );
  }

  // ===== النسخ الاحتياطي =====
  Widget _backupTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_DColors.indigo, _DColors.indigo.withValues(alpha: 0.8)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.backup, color: Colors.white),
              SizedBox(width: 8),
              Text('النسخ الاحتياطي التلقائي',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            const Text('• كل 6 ساعات تلقائياً\n• يحتفظ بآخر 7 نسخ',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _createBackup,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _DColors.indigo),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('إنشاء نسخة الآن', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('النسخ المتاحة (${backups.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('آخر 7 نسخ', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        if (backups.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: Column(children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('لا توجد نسخ', style: TextStyle(color: Colors.grey)),
          ])))
        else
          ...backups.asMap().entries.map((e) {
            final b = e.value;
            final isLatest = e.key == 0;
            final size = ((b['size'] ?? 0) as num) / 1024;
            return _ProCard(isDark: isDark, child: ListTile(
              leading: Icon(Icons.storage, color: isLatest ? _DColors.emerald : Colors.grey),
              title: Row(children: [
                Expanded(child: Text(b['name'] ?? '', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis)),
                if (isLatest) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _DColors.emerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('الأحدث', style: TextStyle(color: _DColors.emerald, fontSize: 10)),
                ),
              ]),
              subtitle: Text('${size.toStringAsFixed(1)} KB'),
            ));
          }),
      ]),
    );
  }

  // ===== Actions =====
  Future<void> _toggleDriver(String phone) async {
    await SessionService.put('/admin/drivers/$phone/toggle', {});
    _loadAll(silent: true);
  }

  Future<void> _toggleUser(String phone) async {
    await SessionService.put('/admin/users/$phone/toggle', {});
    _loadAll(silent: true);
  }

  Future<void> _cancelTrip(int id) async {
    await SessionService.put('/admin/trips/$id/cancel', {});
    _loadAll(silent: true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم إلغاء الرحلة'), backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating));
  }

  Future<void> _deleteScooter(int id) async {
    await SessionService.delete('/admin/scooters/$id');
    _loadAll(silent: true);
  }

  Future<void> _deleteTaxi(int id) async {
    await SessionService.delete('/admin/taxis/$id');
    _loadAll(silent: true);
  }

  Future<void> _resolveReport(int id) async {
    await SessionService.put('/admin/reports/$id/resolve', {});
    _loadAll(silent: true);
  }

  Future<void> _createBackup() async {
    await SessionService.post('/admin/backup', {});
    _loadAll(silent: true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم إنشاء نسخة احتياطية'), backgroundColor: _DColors.emerald,
            behavior: SnackBarBehavior.floating));
  }

  void _addScooterDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إضافة سكوتر'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
        TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'الكود')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () async {
          await SessionService.post('/admin/scooters',
              {'name': nameCtrl.text, 'scooter_code': codeCtrl.text});
          if (!mounted) return;
          Navigator.pop(ctx);
          _loadAll(silent: true);
        }, child: const Text('إضافة')),
      ],
    ));
  }

  void _addTaxiDialog() {
    final nameCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إضافة تاكسي'),
      content: TextField(controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'الاسم (مثال: Taxi 004)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () async {
          await SessionService.post('/admin/taxis', {'name': nameCtrl.text});
          if (!mounted) return;
          Navigator.pop(ctx);
          _loadAll(silent: true);
        }, child: const Text('إضافة')),
      ],
    ));
  }

  void _confirmReset() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('⚠️ إعادة تعيين'),
      content: const Text('سيتم حذف جميع الرحلات وإعادة الأسطول'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () async {
            await Future.wait([
              SessionService.delete('/taxi/trips'),
              SessionService.post('/scooters/reset', {}),
            ]);
            if (!mounted) return;
            Navigator.pop(ctx);
            _loadAll();
          },
          style: FilledButton.styleFrom(backgroundColor: _DColors.red),
          child: const Text('إعادة تعيين'),
        ),
      ],
    ));
  }
}

// ===== Widgets احترافية =====

class _ProCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsets? margin;
  const _ProCard({required this.child, required this.isDark, this.margin});

  @override
  Widget build(BuildContext context) => Container(
    margin: margin ?? const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: isDark ? _DColors.darkCard : _DColors.card,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
          blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

class _StatusPill extends StatelessWidget {
  final Color color;
  final String label;
  const _StatusPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    ]),
  );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionHeader(this.text, this.isDark);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: TextStyle(
      fontSize: 16, fontWeight: FontWeight.bold,
      color: isDark ? Colors.white : Colors.grey.shade800,
    )),
  );
}

// ===== بطاقات الإحصائيات مع Animation =====
class _AnimatedStatsGrid extends StatefulWidget {
  final Map stats;
  final bool isDark;
  const _AnimatedStatsGrid({required this.stats, required this.isDark});
  @override
  State<_AnimatedStatsGrid> createState() => _AnimatedStatsGridState();
}

class _AnimatedStatsGridState extends State<_AnimatedStatsGrid>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedStatsGrid old) {
    super.didUpdateWidget(old);
    _ctrl.reset();
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final cards = [
      _StatData('اليوم', '${s['todayTrips'] ?? 0} رحلة', Icons.today, _DColors.orange,
          '+${s['todayTrips'] ?? 0} اليوم'),
      _StatData('إيراد اليوم', '${((s['todayRevenue'] ?? 0) as num).toStringAsFixed(3)} د.ك',
          Icons.attach_money, _DColors.emerald, 'كويتي دينار'),
      _StatData('الأسبوع', '${s['weekTrips'] ?? 0} رحلة', Icons.date_range, _DColors.blue,
          'آخر 7 أيام'),
      _StatData('إيراد الأسبوع', '${((s['weekRevenue'] ?? 0) as num).toStringAsFixed(3)} د.ك',
          Icons.trending_up, _DColors.purple, 'كويتي دينار'),
      _StatData('إجمالي', '${s['totalTrips'] ?? 0} رحلة', Icons.local_taxi, _DColors.indigo,
          'كل الرحلات'),
      _StatData('الإيراد الكلي', '${((s['totalRevenue'] ?? 0) as num).toStringAsFixed(3)} د.ك',
          Icons.account_balance_wallet, _DColors.red, 'كويتي دينار'),
    ];

    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.1), end: Offset.zero).animate(_anim),
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: cards.map((c) => _GradientStatCard(data: c, isDark: widget.isDark)).toList(),
        ),
      ),
    );
  }
}

class _StatData {
  final String label, value, subtitle;
  final IconData icon;
  final Color color;
  const _StatData(this.label, this.value, this.icon, this.color, this.subtitle);
}

class _GradientStatCard extends StatelessWidget {
  final _StatData data;
  final bool isDark;
  const _GradientStatCard({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? _DColors.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: data.color.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))],
      border: Border.all(color: data.color.withValues(alpha: 0.1)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: data.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(data.icon, color: data.color, size: 18),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: data.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text('↑', style: TextStyle(color: data.color, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(data.value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: data.color)),
        Text(data.label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    ]),
  );
}

// ===== الرسم البياني الاحترافي =====
class _ProBarChart extends StatefulWidget {
  final List data;
  final bool isDark;
  const _ProBarChart({required this.data, required this.isDark});
  @override
  State<_ProBarChart> createState() => _ProBarChartState();
}

class _ProBarChartState extends State<_ProBarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return const SizedBox();
    final maxTrips = data.map((d) => (d['trips'] as num).toInt()).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? _DColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
      ),
      child: Column(children: [
        // tooltip
        if (_selectedIndex != null && _selectedIndex! < data.length)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _DColors.indigo, borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${data[_selectedIndex!]['day']}  •  ${data[_selectedIndex!]['trips']} رحلة  •  ${((data[_selectedIndex!]['revenue'] ?? 0) as num).toStringAsFixed(3)} د.ك',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),

        AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: data.asMap().entries.map((e) {
                final i = e.key;
                final d = e.value;
                final trips = (d['trips'] as num).toInt();
                final factor = maxTrips == 0 ? 0.05 : (trips / maxTrips * _anim.value).clamp(0.05, 1.0);
                final day = (d['day'] as String).substring(5);
                final isSelected = _selectedIndex == i;

                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _selectedIndex = isSelected ? null : i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(children: [
                      Text('$trips',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                              color: isSelected ? _DColors.indigo : Colors.grey)),
                      const SizedBox(height: 4),
                      Expanded(child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: factor.toDouble(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isSelected
                                    ? [_DColors.orange, _DColors.orange.withValues(alpha: 0.7)]
                                    : [_DColors.indigo, _DColors.indigo.withValues(alpha: 0.6)],
                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: isSelected ? [BoxShadow(color: _DColors.indigo.withValues(alpha: 0.3),
                                  blurRadius: 6, offset: const Offset(0, -2))] : [],
                            ),
                          ),
                        ),
                      )),
                      const SizedBox(height: 4),
                      Text(day, style: const TextStyle(fontSize: 8, color: Colors.grey)),
                    ]),
                  ),
                ));
              }).toList(),
            ),
          ),
        ),
      ]),
    );
  }
}

// ===== الرسم الدائري =====
class _DonutItem {
  final String label;
  final double value;
  final Color color;
  const _DonutItem(this.label, this.value, this.color);
}

class _DonutChart extends StatelessWidget {
  final String title;
  final List<_DonutItem> items;
  final bool isDark;
  const _DonutChart({required this.title, required this.items, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final total = items.fold(0.0, (s, i) => s + i.value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? _DColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
      ),
      child: Column(children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 12),
        SizedBox(
          width: 80, height: 80,
          child: CustomPaint(
            painter: _DonutPainter(items: items, total: total),
            child: Center(child: Text(
              '${total.toInt()}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16,
                  color: isDark ? Colors.white : Colors.grey.shade800),
            )),
          ),
        ),
        const SizedBox(height: 10),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: item.color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(child: Text(item.label, style: const TextStyle(fontSize: 11, color: Colors.grey))),
            Text('${item.value.toInt()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey.shade700)),
          ]),
        )),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_DonutItem> items;
  final double total;
  const _DonutPainter({required this.items, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 20) / 2;
    double startAngle = -math.pi / 2;
    if (total == 0) {
      paint.color = Colors.grey.shade200;
      canvas.drawCircle(center, radius, paint);
      return;
    }
    for (final item in items) {
      final sweep = (item.value / total) * 2 * math.pi;
      paint.color = item.color;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

// ===== أفضل السائقين =====
class _TopDriversCard extends StatelessWidget {
  final List drivers;
  final bool isDark;
  const _TopDriversCard({required this.drivers, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final medals = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣'];
    return Container(
      decoration: BoxDecoration(
        color: isDark ? _DColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
      ),
      child: Column(children: drivers.asMap().entries.map((e) {
        final i = e.key;
        final d = e.value;
        final earnings = (d['earnings'] ?? 0) as num;
        return ListTile(
          leading: Text(i < medals.length ? medals[i] : '${i+1}', style: const TextStyle(fontSize: 22)),
          title: Text(d['driver_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${d['total_trips']} رحلة'),
          trailing: Text('${earnings.toStringAsFixed(3)} د.ك',
              style: const TextStyle(color: _DColors.emerald, fontWeight: FontWeight.bold)),
        );
      }).toList()),
    );
  }
}

// ===== Timeline الرحلة =====
class _TripTimelineCard extends StatefulWidget {
  final Map trip;
  final bool isDark;
  final VoidCallback onCancel;
  const _TripTimelineCard({required this.trip, required this.isDark, required this.onCancel});
  @override
  State<_TripTimelineCard> createState() => _TripTimelineCardState();
}

class _TripTimelineCardState extends State<_TripTimelineCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final status = t['status'] ?? '';
    final fare = (t['final_fare'] ?? t['estimated_fare'] ?? 0) as num;
    final isActive = ['waiting_driver', 'accepted', 'arrived', 'in_progress'].contains(status);

    final statusColor = {
      'waiting_driver': _DColors.orange,
      'accepted': _DColors.blue,
      'arrived': _DColors.purple,
      'in_progress': _DColors.indigo,
      'completed': _DColors.emerald,
      'cancelled': _DColors.red,
    }[status] ?? Colors.grey;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: widget.isDark ? _DColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
          border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 4, height: 50,
                decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['pickup'] ?? '-'} ← ${t['destination'] ?? '-'}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${t['driver_name'] ?? 'لا سائق'} • ${t['user_phone'] ?? '-'}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_statusText(status),
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                Text('${fare.toStringAsFixed(3)} د.ك',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: statusColor)),
              ]),
            ]),
          ),

          // Timeline مفصّل
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                _TimelinStep('طلب الرحلة', true, _DColors.emerald),
                _TimelinStep('قبول السائق', ['accepted','arrived','in_progress','completed'].contains(status), _DColors.blue),
                _TimelinStep('وصل السائق', ['arrived','in_progress','completed'].contains(status), _DColors.purple),
                _TimelinStep('بدأت الرحلة', ['in_progress','completed'].contains(status), _DColors.indigo),
                _TimelinStep('انتهت الرحلة', status == 'completed', _DColors.emerald),
                if (isActive) ...[
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(foregroundColor: _DColors.red,
                        side: const BorderSide(color: _DColors.red)),
                    icon: const Icon(Icons.cancel, size: 16),
                    label: const Text('إلغاء الرحلة'),
                  )),
                ],
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  String _statusText(String s) {
    const map = {
      'waiting_driver': 'انتظار', 'accepted': 'مقبولة', 'arrived': 'وصل',
      'in_progress': 'جارية', 'completed': 'مكتملة', 'cancelled': 'ملغاة',
    };
    return map[s] ?? s;
  }
}

class _TimelinStep extends StatelessWidget {
  final String label;
  final bool done;
  final Color color;
  const _TimelinStep(this.label, this.done, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? color : Colors.grey.shade300, size: 18),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(
        fontSize: 12, color: done ? null : Colors.grey.shade400,
        fontWeight: done ? FontWeight.w500 : FontWeight.normal,
      )),
    ]),
  );
}

// ===== البلاغات =====
class _ReportCard extends StatelessWidget {
  final Map report;
  final bool isDark;
  final VoidCallback? onResolve;
  const _ReportCard(this.report, {required this.isDark, this.onResolve});

  @override
  Widget build(BuildContext context) {
    final isPending = report['status'] == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? _DColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPending ? _DColors.red.withValues(alpha: 0.1) : _DColors.emerald.withValues(alpha: 0.1),
          child: Icon(isPending ? Icons.warning : Icons.check,
              color: isPending ? _DColors.red : _DColors.emerald, size: 18),
        ),
        title: Text(report['phone'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(report['description'] ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: isPending && onResolve != null
            ? TextButton(onPressed: onResolve, child: const Text('حل'))
            : const Text('✅', style: TextStyle(fontSize: 18)),
      ),
    );
  }
}

// ===== مؤشر التحديث التلقائي =====
class _AutoRefreshIndicator extends StatefulWidget {
  @override
  State<_AutoRefreshIndicator> createState() => _AutoRefreshIndicatorState();
}

class _AutoRefreshIndicatorState extends State<_AutoRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'تحديث تلقائي كل 10 ثواني',
    child: AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(
          value: _ctrl.value,
          strokeWidth: 2,
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation(Colors.white),
        ),
      ),
    ),
  );
}
