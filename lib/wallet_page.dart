import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'session_service.dart';
import 'main.dart' show currentUserPhone, currentUserBalance;

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with SingleTickerProviderStateMixin {
  double balance = 0;
  List transactions = [];
  bool loading = true;
  late TabController _tabController;

  final amounts = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final response = await SessionService.get('/wallet/transactions/$currentUserPhone');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          balance = (data['balance'] ?? 0).toDouble();
          transactions = data['transactions'] ?? [];
          currentUserBalance = balance;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _charge(double amount, String method) async {
    try {
      final response = await SessionService.post('/wallet/charge', {
        'phone': currentUserPhone,
        'amount': amount,
        'method': method,
      });
      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => balance = (data['balance'] ?? 0).toDouble());
        currentUserBalance = balance;
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ تمت إضافة ${amount.toStringAsFixed(3)} د.ك'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر الشحن'), backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showChargeDialog() {
    final customController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('شحن المحفظة 💰',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              // مبالغ سريعة
              const Text('مبالغ سريعة', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: amounts.map((a) => GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _charge(a, 'quick');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Text(
                      '${a.toStringAsFixed(a == a.truncate() ? 0 : 3)} د.ك',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                  ),
                )).toList(),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // مبلغ مخصص
              const Text('مبلغ مخصص', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: customController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: 'أدخل المبلغ',
                        suffixText: 'د.ك',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () {
                      final amount = double.tryParse(customController.text);
                      if (amount != null && amount > 0) {
                        Navigator.pop(ctx);
                        _charge(amount, 'custom');
                      }
                    },
                    child: const Text('شحن'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // طرق الدفع
              const Text('طرق الدفع', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _PayMethodChip('💵 نقداً', true),
                  const SizedBox(width: 8),
                  _PayMethodChip('💳 كي نت', false, note: 'قريباً'),
                  const SizedBox(width: 8),
                  _PayMethodChip('🍎 Apple Pay', false, note: 'قريباً'),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 200,
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
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      const Icon(Icons.account_balance_wallet,
                          color: Colors.white70, size: 28),
                      const SizedBox(height: 4),
                      const Text('رصيد المحفظة',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        '${balance.toStringAsFixed(3)} د.ك',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _showChargeDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('شحن الرصيد',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.history, size: 18), text: 'السجل'),
                Tab(icon: Icon(Icons.payment, size: 18), text: 'طرق الدفع'),
              ],
            ),
          ),
        ],
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [_historyTab(), _methodsTab()],
              ),
      ),
    );
  }

  Widget _historyTab() {
    if (transactions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 60, color: Colors.grey),
            SizedBox(height: 12),
            Text('لا توجد عمليات بعد', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: transactions.length,
        itemBuilder: (_, i) {
          final t = transactions[i];
          final type = t['type'] ?? '';
          final amount = (t['amount'] ?? 0) as num;
          final isDeposit = type == 'deposit';
          final isCash = type == 'cash_payment';

          IconData icon;
          Color color;
          String label;

          switch (type) {
            case 'deposit':
              icon = Icons.add_circle;
              color = Colors.green;
              label = 'شحن رصيد';
              break;
            case 'trip_payment':
              icon = Icons.local_taxi;
              color = Colors.blue;
              label = 'أجرة رحلة';
              break;
            case 'cash_payment':
              icon = Icons.money;
              color = Colors.grey;
              label = 'دفع نقدي';
              break;
            default:
              icon = Icons.swap_horiz;
              color = Colors.grey;
              label = type;
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 1,
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              title: Text(t['description'] ?? label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              subtitle: Text(
                t['created_at'] ?? '',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isDeposit ? '+' : isCash ? '' : '-'}${amount.toStringAsFixed(3)} د.ك',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDeposit ? Colors.green : isCash ? Colors.grey : Colors.red,
                    ),
                  ),
                  if (t['balance_after'] != null && !isCash)
                    Text(
                      'الرصيد: ${(t['balance_after'] as num).toStringAsFixed(3)}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _methodsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _MethodCard(
            icon: '💵',
            name: 'نقداً',
            description: 'ادفع للسائق مباشرة عند وصولك',
            available: true,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: '👛',
            name: 'المحفظة الإلكترونية',
            description: 'يُخصم تلقائياً من رصيدك عند إنهاء الرحلة',
            available: true,
            color: Colors.indigo,
            extraInfo: 'رصيدك: ${balance.toStringAsFixed(3)} د.ك',
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: '💳',
            name: 'كي نت KNET',
            description: 'الدفع المباشر عبر شبكة كي نت الكويتية',
            available: false,
            color: Colors.blue,
            comingSoon: true,
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: '💳',
            name: 'فيزا / ماستركارد',
            description: 'الدفع ببطاقات الائتمان والخصم',
            available: false,
            color: Colors.purple,
            comingSoon: true,
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: '🍎',
            name: 'Apple Pay',
            description: 'الدفع السريع عبر Apple Pay',
            available: false,
            color: Colors.black87,
            comingSoon: true,
          ),
        ],
      ),
    );
  }
}

// ===== Widgets =====

class _PayMethodChip extends StatelessWidget {
  final String label;
  final bool available;
  final String? note;
  const _PayMethodChip(this.label, this.available, {this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: available ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: available ? Colors.green.shade300 : Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500,
            color: available ? Colors.green.shade700 : Colors.grey,
          )),
          if (note != null)
            Text(note!, style: const TextStyle(fontSize: 9, color: Colors.orange)),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final String icon, name, description;
  final bool available;
  final Color color;
  final bool comingSoon;
  final String? extraInfo;

  const _MethodCard({
    required this.icon, required this.name, required this.description,
    required this.available, required this.color,
    this.comingSoon = false, this.extraInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: available ? color.withValues(alpha: 0.3) : Colors.grey.shade200,
        ),
        boxShadow: [BoxShadow(
          color: available ? color.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
        )],
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: (available ? color : Colors.grey).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 6),
                  if (available)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('متاح', style: TextStyle(color: Colors.green, fontSize: 10)),
                    ),
                  if (comingSoon)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('قريباً', style: TextStyle(color: Colors.orange, fontSize: 10)),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (extraInfo != null) ...[
                  const SizedBox(height: 4),
                  Text(extraInfo!, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                ],
              ],
            ),
          ),
          Icon(
            available ? Icons.check_circle : Icons.lock_outline,
            color: available ? Colors.green : Colors.grey.shade300,
          ),
        ],
      ),
    );
  }
}
