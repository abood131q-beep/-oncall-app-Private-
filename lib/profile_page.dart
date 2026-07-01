import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'session_service.dart';
import 'main.dart' show currentUserPhone, currentUserName, currentUserBalance;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map? userData;
  List trips = [];
  bool loading = true;
  bool editingName = false;
  final nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        SessionService.get('/balance/$currentUserPhone'),
        SessionService.get('/taxi/trips/passenger/$currentUserPhone'),
      ]);

      if (!mounted) return;
      setState(() {
        if (results[0].statusCode == 200) {
          userData = jsonDecode(results[0].body);
        }
        if (results[1].statusCode == 200) {
          trips = jsonDecode(results[1].body);
        }
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _updateName(String newName) async {
    if (newName.trim().isEmpty) return;
    try {
      await SessionService.post('/user/update', {'phone': currentUserPhone, 'name': newName.trim()});
      if (!mounted) return;
      setState(() {
        currentUserName = newName.trim();
        editingName = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم تحديث الاسم'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر التحديث'), backgroundColor: Colors.red),
      );
    }
  }

  int get _completedTrips => trips.where((t) => t['status'] == 'completed').length;
  int get _cancelledTrips => trips.where((t) => t['status'] == 'cancelled').length;
  double get _totalSpent => trips
      .where((t) => t['status'] == 'completed')
      .fold(0.0, (sum, t) => sum + ((t['final_fare'] ?? t['finalFare'] ?? 0) as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final balance = (userData?['balance'] ?? currentUserBalance ?? 0).toDouble();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ===== Header =====
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.indigo, Color(0xFF3949AB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          // صورة المستخدم
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 45,
                                backgroundColor: Colors.white.withValues(alpha: 0.3),
                                child: Text(
                                  currentUserName.isNotEmpty ? currentUserName[0].toUpperCase() : '؟',
                                  style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // الاسم
                          if (!editingName)
                            GestureDetector(
                              onTap: () {
                                nameController.text = currentUserName;
                                setState(() => editingName = true);
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    currentUserName.isNotEmpty ? currentUserName : 'اضغط لإضافة اسمك',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.edit, color: Colors.white70, size: 16),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: nameController,
                                      autofocus: true,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: const InputDecoration(
                                        hintText: 'أدخل اسمك',
                                        hintStyle: TextStyle(color: Colors.white60),
                                        enabledBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Colors.white60),
                                        ),
                                        focusedBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.check, color: Colors.white),
                                    onPressed: () => _updateName(nameController.text),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white70),
                                    onPressed: () => setState(() => editingName = false),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            currentUserPhone,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadData,
                    ),
                  ],
                ),

                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      // ===== الرصيد =====
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('💰 رصيدك الحالي', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                  Text(
                                    '${balance.toStringAsFixed(3)} د.ك',
                                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _showAddBalanceDialog(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.green,
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('شحن'),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ===== إحصائيات =====
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _StatCard('الرحلات', '$_completedTrips', Icons.local_taxi, Colors.indigo),
                            const SizedBox(width: 12),
                            _StatCard('الملغاة', '$_cancelledTrips', Icons.cancel, Colors.red),
                            const SizedBox(width: 12),
                            _StatCard('المصروف', '${_totalSpent.toStringAsFixed(2)} د.ك', Icons.attach_money, Colors.teal),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ===== معلومات الحساب =====
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.phone, color: Colors.indigo),
                                title: const Text('رقم الهاتف'),
                                subtitle: Text(currentUserPhone),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.history, color: Colors.purple),
                                title: Text('إجمالي الرحلات: ${trips.length}'),
                                subtitle: Text('مكتملة: $_completedTrips | ملغاة: $_cancelledTrips'),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ===== آخر الرحلات =====
                      if (trips.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('آخر الرحلات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('${trips.length} رحلة', style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...trips.take(10).map((trip) {
                          final status = trip['status'] ?? '';
                          final fare = (trip['final_fare'] ?? trip['finalFare'] ?? trip['estimated_fare'] ?? 0) as num;
                          final isCompleted = status == 'completed';
                          final isCancelled = status == 'cancelled';
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isCompleted ? Colors.green.shade50 : isCancelled ? Colors.red.shade50 : Colors.orange.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              isCompleted ? '✅ مكتملة' : isCancelled ? '❌ ملغاة' : '⏳ جارية',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isCompleted ? Colors.green : isCancelled ? Colors.red : Colors.orange,
                                              ),
                                            ),
                                          ),
                                        ]),
                                        Text(
                                          '${fare.toStringAsFixed(3)} د.ك',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: isCompleted ? Colors.green.shade700 : Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      const Icon(Icons.my_location, size: 13, color: Colors.green),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text(trip['pickup'] ?? '-',
                                          style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                    ]),
                                    Row(children: [
                                      const Icon(Icons.flag, size: 13, color: Colors.red),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text(trip['destination'] ?? '-',
                                          style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                    ]),
                                    if (trip['driver_name'] != null) ...[
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        const Icon(Icons.drive_eta, size: 13, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('السائق: ${trip['driver_name']}',
                                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ]),
                                    ],
                                    if (trip['rating'] != null) ...[
                                      const SizedBox(height: 4),
                                      Row(children: List.generate(5, (i) => Icon(
                                        i < (trip['rating'] as num).toInt() ? Icons.star : Icons.star_border,
                                        color: Colors.amber, size: 13,
                                      ))),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _showAddBalanceDialog() {
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('شحن الرصيد'),
        content: TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'المبلغ (د.ك)',
            prefixIcon: Icon(Icons.attach_money),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0) return;
              Navigator.pop(ctx);
              try {
                await SessionService.post('/balance/add', {'phone': currentUserPhone, 'amount': amount});
                _loadData();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ تم إضافة ${amount.toStringAsFixed(3)} د.ك'), backgroundColor: Colors.green),
                );
              } catch (e) {
      debugPrint('Error: ${e.toString()}');
    }
            },
            child: const Text('شحن'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13), textAlign: TextAlign.center),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
