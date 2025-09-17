import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Color kPrimary = Color(0xFF1C2D5E);

class PaymentHistoryPage extends StatelessWidget {
  const PaymentHistoryPage({super.key});

  String _fmtMoney(num? v) => '\$${(v ?? 0).toDouble().toStringAsFixed(2)}';
  String _fmtDate(dynamic v) {
    DateTime d;
    if (v is Timestamp) {
      d = v.toDate();
    } else if (v is DateTime) d = v;
    else d = DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    return DateFormat('dd MMM yyyy • h:mm a').format(d);
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'active': return Colors.green;
      case 'completed': return Colors.blue;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _statusChip(String status) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _statusColor(status).withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          status.isEmpty ? '—' : status[0].toUpperCase() + status.substring(1),
          style: TextStyle(
            color: _statusColor(status),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    // No orderBy here → no composite index needed
    final stream = FirebaseFirestore.instance
        .collection('client_purchases')
        .where('userId', isEqualTo: user.uid)
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: kPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Payment History', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snap.error}'),
              ),
            );
          }

          // Sort by purchaseDate DESC on client
          final docs = (snap.data?.docs ?? []).toList()
            ..sort((a, b) {
              final ad = ((a.data() as Map<String, dynamic>)['purchaseDate'] as Timestamp?)
                          ?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bd = ((b.data() as Map<String, dynamic>)['purchaseDate'] as Timestamp?)
                          ?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bd.compareTo(ad);
            });

          if (docs.isEmpty) {
            return const Center(child: Text('No payment history found.'));
          }

          // Summary
          double totalSpent = 0;
          int activeCount = 0, completedCount = 0, cancelledCount = 0;
          for (final d in docs) {
            final data = d.data() as Map<String, dynamic>;
            final price = (data['price'] as num?)?.toDouble() ?? 0.0;
            final status = (data['status'] as String? ?? '').toLowerCase();
            final payStatus = (data['paymentStatus'] as String? ?? '').toLowerCase();
            if (payStatus == 'completed') totalSpent += price;
            if (status == 'active') activeCount++;
            if (status == 'completed') completedCount++;
            if (status == 'cancelled') cancelledCount++;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary card
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    const Text('Payment Summary',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimary)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _summaryItem('Purchases', docs.length.toString(), Colors.blue),
                        _summaryItem('Total Spent', _fmtMoney(totalSpent), Colors.green),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _pill('Active: $activeCount', Colors.green),
                        _pill('Completed: $completedCount', Colors.blue),
                        _pill('Cancelled: $cancelledCount', Colors.red),
                      ],
                    ),
                  ],
                ),
              ),

              // Individual purchases
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['planName'] ?? data['planTitle'] ?? 'Plan') as String;
                final category = (data['planCategory'] ?? data['planSubtitle'] ?? '') as String;
                final price = (data['price'] as num?) ?? 0;
                final status = (data['status'] as String? ?? 'active');
                final payStatus = (data['paymentStatus'] as String? ?? 'completed');
                final purchaseDate = data['purchaseDate'];
                final cancelledDate = data['cancelledDate'];
                final total = (data['totalSessions'] as num?)?.toInt()
                              ?? (data['sessions'] as num?)?.toInt() ?? 0;
                final remaining = (data['remainingSessions'] as num?)?.toInt() ?? 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.payments, color: kPrimary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 16)),
                                    if (category.isNotEmpty)
                                      Text(category, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(_fmtDate(purchaseDate),
                                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                              ),
                              _statusChip(status),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Price', style: TextStyle(color: Colors.grey)),
                              Text(_fmtMoney(price), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Payment', style: TextStyle(color: Colors.grey)),
                              Text(payStatus[0].toUpperCase() + payStatus.substring(1),
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          if (total > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Sessions', style: TextStyle(color: Colors.grey)),
                                Text('$remaining / $total remaining',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ],
                          if (cancelledDate != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Cancelled', style: TextStyle(color: Colors.grey)),
                                Text(_fmtDate(cancelledDate),
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  static Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  static Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}