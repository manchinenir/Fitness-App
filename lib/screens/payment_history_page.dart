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

  // New function for formatting dates as month/day/year (no time)
  String _fmtDateShort(dynamic v) {
    DateTime d;
    if (v is Timestamp) {
      d = v.toDate();
    } else if (v is DateTime) d = v;
    else d = DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    return DateFormat('MM/dd/yyyy').format(d);
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'active': return Colors.green;
      case 'completed': return Colors.blue;
      case 'cancelled': return Colors.red;
      case 'inactive': return Colors.grey;
      case 'expired': return Colors.orange;
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

  // Helper function to check if subscription is expired
  bool _isSubscriptionExpired(dynamic endDate) {
    if (endDate == null) return false;
    
    DateTime end;
    if (endDate is Timestamp) {
      end = endDate.toDate();
    } else if (endDate is DateTime) {
      end = endDate;
    } else {
      end = DateTime.tryParse(endDate.toString()) ?? DateTime.now().add(const Duration(days: 1));
    }
    
    return end.isBefore(DateTime.now());
  }

  // Helper function to calculate remaining sessions for plans
  int _calculateRemainingSessions(Map<String, dynamic> payment) {
    // If it's a subscription type, return 0 for remaining sessions
    if (payment['type'] == 'subscription') return 0;
    
    // For plans, use the remainingSessions field directly from Firestore
    // This matches how it's displayed in the Plans tab
    final remainingSessions = (payment['remainingSessions'] as num?)?.toInt() ?? 0;
    
    return remainingSessions >= 0 ? remainingSessions : 0;
  }


  // Helper function to determine plan status - FIXED VERSION
  String _determinePlanStatus(Map<String, dynamic> payment) {
    final currentStatus = (payment['status'] as String? ?? '').toLowerCase();
    
    // If already cancelled, keep as cancelled
    if (currentStatus == 'cancelled') return 'cancelled';
    
    // For subscriptions
    if (payment['type'] == 'subscription') {
      final isActive = payment['isActive'] == true;
      final endDate = payment['endDate'];
      
      // If subscription is expired, mark as completed (same as PDF workouts page)
      if (endDate != null && _isSubscriptionExpired(endDate)) {
        return 'completed';
      }
      
      // Otherwise use the current active status
      return isActive ? 'active' : 'inactive';
    }
    
    // For plans - use remainingSessions to determine status (same as Plans tab)
    if (payment['type'] == 'purchase') {
      final remainingSessions = _calculateRemainingSessions(payment);
      final totalSessions = (payment['totalSessions'] as num?)?.toInt() ?? 
                          (payment['sessions'] as num?)?.toInt() ?? 0;
      
      // If plan is already marked as completed in Firestore, use that
      if (currentStatus == 'completed') {
        return 'completed';
      }
      
      // If no sessions remaining, mark as completed (same as Plans tab logic)
      if (remainingSessions <= 0 && totalSessions > 0) {
        return 'completed';
      }
      
      // If cancelled, return cancelled
      if (currentStatus == 'cancelled') {
        return 'cancelled';
      }
      
      // Otherwise use the current status or default to active
      return currentStatus.isEmpty ? 'active' : currentStatus;
    }
    
    return currentStatus.isEmpty ? 'active' : currentStatus;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    // Stream for purchases
    final purchasesStream = FirebaseFirestore.instance
        .collection('client_purchases')
        .where('userId', isEqualTo: user.uid)
        .snapshots();

    // Stream for subscriptions
    final subscriptionsStream = FirebaseFirestore.instance
        .collection('client_subscriptions')
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
        stream: purchasesStream,
        builder: (context, purchasesSnap) {
          return StreamBuilder<QuerySnapshot>(
            stream: subscriptionsStream,
            builder: (context, subscriptionsSnap) {
              // Handle loading state
              if (purchasesSnap.connectionState == ConnectionState.waiting || 
                  subscriptionsSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Handle errors
              if (purchasesSnap.hasError || subscriptionsSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: ${purchasesSnap.error ?? subscriptionsSnap.error}'),
                  ),
                );
              }

              // Combine and process data
              final purchaseDocs = purchasesSnap.data?.docs ?? [];
              final subscriptionDocs = subscriptionsSnap.data?.docs ?? [];

              // Convert subscriptions to purchase-like format for unified display
              final allPayments = <Map<String, dynamic>>[];

              // Add purchases
              for (final doc in purchaseDocs) {
                final data = doc.data() as Map<String, dynamic>;
                allPayments.add({
                  ...data,
                  'type': 'purchase',
                  'docId': doc.id,
                });
              }

              // Add subscriptions
              for (final doc in subscriptionDocs) {
                final data = doc.data() as Map<String, dynamic>;
                allPayments.add({
                  ...data,
                  'type': 'subscription',
                  'docId': doc.id,
                  // Map subscription fields to match purchase structure
                  'planName': data['planName'] ?? 'PDF Subscription',
                  'price': data['price'] ?? 0,
                  'status': data['isActive'] == true ? 'active' : (data['status'] ?? 'inactive'),
                  'paymentStatus': data['paymentStatus'] ?? 'completed',
                  'purchaseDate': data['purchaseDate'] ?? data['startDate'] ?? data['createdAt'],
                });
              }

              // Sort by purchaseDate DESC on client
              allPayments.sort((a, b) {
                DateTime ad = DateTime.fromMillisecondsSinceEpoch(0);
                DateTime bd = DateTime.fromMillisecondsSinceEpoch(0);

                // Handle purchase date extraction for different types
                final aDate = a['purchaseDate'];
                final bDate = b['purchaseDate'];

                if (aDate is Timestamp) ad = aDate.toDate();
                else if (aDate is DateTime) ad = aDate;
                else if (aDate is String) ad = DateTime.tryParse(aDate) ?? ad;

                if (bDate is Timestamp) bd = bDate.toDate();
                else if (bDate is DateTime) bd = bDate;
                else if (bDate is String) bd = DateTime.tryParse(bDate) ?? bd;

                return bd.compareTo(ad);
              });

              if (allPayments.isEmpty) {
                return const Center(child: Text('No payment history found.'));
              }

              // Summary calculations including subscriptions
              double totalSpent = 0;
              int activeCount = 0, completedCount = 0, cancelledCount = 0, inactiveCount = 0;
              int purchaseCount = 0;
              int subscriptionCount = 0;

              for (final payment in allPayments) {
                final price = (payment['price'] as num?)?.toDouble() ?? 0.0;
                final status = _determinePlanStatus(payment);
                final payStatus = (payment['paymentStatus'] as String? ?? '').toLowerCase();
                final type = payment['type'] as String? ?? 'purchase';

                // Count by type
                if (type == 'purchase') purchaseCount++;
                if (type == 'subscription') subscriptionCount++;

                // Calculate total spent (only completed payments)
                if (payStatus == 'completed') {
                  totalSpent += price;
                }

                // Count statuses using the determined status
                if (status == 'active') activeCount++;
                if (status == 'completed') completedCount++;
                if (status == 'cancelled') cancelledCount++;
                if (status == 'inactive') inactiveCount++;
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Enhanced Summary card
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
                            _summaryItem('Total Payments', allPayments.length.toString(), Colors.blue),
                            _summaryItem('Total Spent', _fmtMoney(totalSpent), Colors.green),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _pill('Active: $activeCount', Colors.green),
                            _pill('Completed: $completedCount', Colors.blue),
                            _pill('Cancelled: $cancelledCount', Colors.red),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Individual payments
                  ...allPayments.map((payment) {
                    final type = payment['type'] as String? ?? 'purchase';
                    final name = payment['planName'] as String? ?? 'Unnamed Item';
                    final category = type == 'subscription' 
                        ? 'PDF Subscription' 
                        : (payment['planCategory'] as String? ?? payment['planSubtitle'] as String? ?? 'Fitness Plan');
                    final price = (payment['price'] as num?) ?? 0;
                    final status = _determinePlanStatus(payment); // Use the determined status
                    final payStatus = (payment['paymentStatus'] as String? ?? 'completed');
                    final purchaseDate = payment['purchaseDate'];
                    final cancelledDate = payment['cancelledDate'];
                    final total = (payment['totalSessions'] as num?)?.toInt()
                                  ?? (payment['sessions'] as num?)?.toInt() ?? 0;
                    final remaining = _calculateRemainingSessions(payment); // Use calculated remaining sessions
                    final endDate = payment['endDate'];
                    final isActive = payment['isActive'] == true;

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
                              // Header row with type badge
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: type == 'subscription' ? Colors.purple.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: type == 'subscription' ? Colors.purple : Colors.orange,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      type == 'subscription' ? 'SUBSCRIPTION' : 'PLAN',
                                      style: TextStyle(
                                        color: type == 'subscription' ? Colors.purple : Colors.orange,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  _statusChip(status),
                                ],
                              ),
                              const SizedBox(height: 8),
                              
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      type == 'subscription' ? Icons.subscriptions : Icons.payments,
                                      color: kPrimary,
                                    ),
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

                              // Update the subscription-specific fields to show expiration status:
                              if (type == 'subscription') ...[
                                const SizedBox(height: 6),
                                if (endDate != null) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Valid Until', style: TextStyle(color: Colors.grey)),
                                      Text(_fmtDateShort(endDate),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: _isSubscriptionExpired(endDate) ? Colors.red : Colors.black,
                                          )),
                                    ],
                                  ),
                                ],
                                // Add a warning message if subscription is expired
                                if (_isSubscriptionExpired(endDate)) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.orange),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.warning, color: Colors.orange, size: 16),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Subscription expired - renew to access PDF workouts',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                              
                              // Plan-specific fields - Updated session display
                              if (type == 'purchase' && total > 0) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Sessions', style: TextStyle(color: Colors.grey)),
                                    Text('${total - remaining}/$total completed', // This matches "Active (1/4 completed)" format
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: remaining == 0 ? Colors.red : Colors.green,
                                        )),
                                  ],
                                ),
                              ],
                              
                              if (cancelledDate != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Cancelled', style: TextStyle(color: Colors.grey)),
                                    Text(_fmtDateShort(cancelledDate), // Using the new short format function
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