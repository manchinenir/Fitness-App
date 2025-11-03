import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'square_checkout.dart';
import 'invoice_review_page.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'pdf_workouts_tab.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Add this import

class ClientPlansScreen extends StatefulWidget {
  const ClientPlansScreen({super.key});
  @override
  State<ClientPlansScreen> createState() => _ClientPlansScreenState();
}

class _ClientPlansScreenState extends State<ClientPlansScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  final Set<String> _purchasedKeys = {};
  final Set<String> _completedKeys = {};
  final Set<String> _cancelledKeys = {};
  List<Map<String, dynamic>> _myActivePlans = [];
  String? _errorMessage;

  // Add these stream subscriptions
  StreamSubscription<QuerySnapshot>? _sessionsSubscription;
  StreamSubscription<QuerySnapshot>? _purchasesSubscription;

  static const String _squareApplicationId = 'sq0idp-agy7z_bYdVWuflGeopSwCw';
  static const String _squareLocationId = 'L8S08PC1N6RPJ';
  bool _isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeData();
    _setupRealTimeListeners(); // Add this
    
    // Auto-refresh every hour to catch completed sessions
    Timer.periodic(Duration(hours: 1), (timer) {
      if (mounted) {
        _refreshSessionCounts();
      }
    });
    
    // Also refresh when the app comes to foreground
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshSessionCounts();
    });
  }

  // Add this method to set up real-time listeners
  void _setupRealTimeListeners() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    // Listen for changes in trainer_slots (session updates)
    _sessionsSubscription = _firestore
        .collection('trainer_slots')
        .where('booked_by', arrayContains: userId)
        .snapshots()
        .listen((_) {
      // When sessions change, refresh the counts
      if (mounted) {
        _refreshSessionCounts();
      }
    });

    // Listen for changes in client_purchases (plan status updates)
    _purchasesSubscription = _firestore
        .collection('client_purchases')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((_) {
      // When purchases change, refresh the data
      if (mounted) {
        _loadPurchasedPlans();
        _loadMyActivePlans();
      }
    });
  }

  @override
  void dispose() {
    // Cancel the subscriptions when the widget is disposed
    _sessionsSubscription?.cancel();
    _purchasesSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // Rest of your existing methods remain the same...
  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (_auth.currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view plans';
          _isLoading = false;
        });
        return;
      }
      await Future.wait([
        _loadPurchasedPlans(),
        _loadMyActivePlans(),
      ]);
    } catch (e) {
      print('Error initializing data');
      setState(() {
        _errorMessage = 'Error loading data';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPurchasedPlans() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;
      
      final snapshot = await _firestore
          .collection('client_purchases')
          .where('userId', isEqualTo: userId)
          .get();

      setState(() {
        _purchasedKeys.clear();
        _completedKeys.clear();
        _cancelledKeys.clear();
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final key = '${data['planName']}_${data['planId']}';
          final status = (data['status'] as String? ?? 'active').toLowerCase();
          final remainingSessions = data['remainingSessions'] as int? ?? 0;

          if (status == 'cancelled') {
            _cancelledKeys.add(key);
          } else if (status == 'completed' || remainingSessions <= 0) {
            _completedKeys.add(key);
          } else if (remainingSessions > 0) {
            _purchasedKeys.add(key);
          } else {
            _completedKeys.add(key);
          }
        }
      });
    } catch (e) {
      print('Error loading purchased plans');
    }
  }

  Future<void> _loadMyActivePlans() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;
      final snapshot = await _firestore
          .collection('client_purchases')
          .where('userId', isEqualTo: userId)
          .get();
      final plans = snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();
      plans.sort((a, b) {
        final dateA = a['purchaseDate'] as Timestamp?;
        final dateB = b['purchaseDate'] as Timestamp?;
        if (dateA == null || dateB == null) return 0;
        return dateB.compareTo(dateA);
      });
      setState(() {
        _myActivePlans = plans;
      });
    } catch (e) {
      print('Error loading my plans');
    }
  }

  Future<void> _purchasePlan(Map<String, dynamic> plan) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        _showSnackBar('Please login to purchase plans', Colors.red);
        return;
      }

      final planId = plan['docId'] as String;
      final planName = plan['name'] as String;
      final key = '${planName}_$planId';
      
      // Allow purchase if plan is completed, cancelled, or not purchased
      final isPurchased = _purchasedKeys.contains(key);
      final isCancelled = _cancelledKeys.contains(key);
      final isCompleted = _completedKeys.contains(key);
      
      if (isPurchased && !isCancelled && !isCompleted) {
        _showSnackBar('You currently have an active plan of this type. Complete all sessions first.', Colors.orange);
        return;
      }
      _navigateToPaymentPage(plan);
    } catch (e) {
      print('Error initiating purchase');
      _showSnackBar('Error initiating purchase', Colors.red);
    }
  }

  Future<void> _completePlanPurchaseAfterPayment(Map<String, dynamic> plan) async {
    try {
      setState(() => _isLoading = true);

      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final planId = plan['docId'] as String;
      final planName = plan['name'] as String;
      final totalSessions = plan['sessions'] as int? ?? 0;
      final price = (plan['price'] ?? 0).toDouble();

      // Fetch client name
      final userDoc = await _firestore.collection('users').doc(userId).get();
      String clientName = '';
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        clientName = userData['name'] ?? '';
      }

      // Check if this is a repurchase
      final existingPurchases = await _firestore
          .collection('client_purchases')
          .where('userId', isEqualTo: userId)
          .where('planId', isEqualTo: planId)
          .get();

      bool isRepurchase = false;
      for (final doc in existingPurchases.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'active';
        if (status == 'cancelled' || status == 'completed') {
          isRepurchase = true;
          break;
        }
      }

      // Create new purchase doc
      final newPurchaseDocRef = _firestore.collection('client_purchases').doc();
      final newPurchaseId = newPurchaseDocRef.id;
      final purchaseTimestamp = FieldValue.serverTimestamp();

      final purchaseData = {
        'purchaseId': newPurchaseId,
        'docId': newPurchaseId,
        'userId': userId,
        'clientName': clientName,
        'planId': planId,
        'planName': planName,
        'planCategory': plan['category'] ?? '',
        'price': price,
        'sessions': totalSessions,
        'totalSessions': totalSessions,
        'remainingSessions': totalSessions,
        'bookedSessions': 0,
        'usedSessions': 0,
        'availableSessions': totalSessions,
        'description': plan['description'] ?? '',
        'isActive': true,
        'status': 'active',
        'purchaseDate': purchaseTimestamp,
        'createdAt': purchaseTimestamp,
        'updatedAt': purchaseTimestamp,
        'paymentMethod': 'square',
        'paymentStatus': 'completed',
        'isRepurchase': isRepurchase,
      };

      await newPurchaseDocRef.set(purchaseData);

      // Refresh local state
      await Future.wait([
        _loadPurchasedPlans(),
        _loadMyActivePlans(),
      ]);

      _showSnackBar('Payment successful! Plan purchased.', Colors.green);

      // ---------- NEW: Generate & open a receipt PDF automatically ----------
      await _generatePurchaseReceiptPDF(
        clientName: clientName,
        planName: planName,
        sessions: totalSessions,
        price: price,
        purchaseId: newPurchaseId,
        purchaseDate: DateTime.now(), // local time for the receipt
      );

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showSnackBar('Error completing purchase', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelPlan(String purchaseDocId, String planName) async {
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Text('Cancel Plan'),
              ],
            ),
            content: Text(
              'Are you sure you want to cancel "$planName"? Plan You won’t be able to book the leftover sessions.',
              style: const TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No, Keep Plan'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Yes, Cancel Plan'),
              ),
            ],
          );
        },
      );

      if (confirm == true) {
        setState(() => _isLoading = true);

        await _firestore.collection('client_purchases').doc(purchaseDocId).update({
          'isActive': false,
          'status': 'cancelled',
          'cancelledDate': FieldValue.serverTimestamp(),
          // Remove completedDate if it exists
          'completedDate': FieldValue.delete(), // This is OK here because it's in update()
        });

        await Future.delayed(const Duration(milliseconds: 500));

        await _loadPurchasedPlans();
        await _loadMyActivePlans();
        print('Plan "$planName" cancelled, refreshed purchased and active plans');
        _showSnackBar('Plan "$planName" cancelled successfully!', Colors.green);
      }
    } catch (e) {
      print('Error cancelling plan');
      _showSnackBar('Error cancelling plan', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _navigateToPaymentPage(Map<String, dynamic> plan) async {
    setState(() => _isProcessingPayment = true);
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SquarePaymentPage(
          plan: plan,
          squareApplicationId: _squareApplicationId,
          squareLocationId: _squareLocationId,
        ),
      ),
    );

   // if (result == true) {
   //   await _completePlanPurchaseAfterPayment(plan);
   // }
    setState(() => _isProcessingPayment = false);
  }

  Widget _buildCategoryHeader(String category, int planCount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [Colors.blueAccent.withOpacity(0.1), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.fitness_center,
                  color: Colors.blueAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                    Text(
                      '$planCount session plan${planCount != 1 ? 's' : ''} available',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final planId = plan['docId'] as String? ?? '';
    final planName = plan['name'] as String? ?? 'Unnamed Plan';
    final planCategory = plan['category'] as String? ?? 'General';
    final sessions = plan['sessions'] as int? ?? 0;
    final price = (plan['price'] ?? 0).toDouble();
    final description = plan['description'] as String? ?? 'No description available';
    final status = (plan['status'] as String? ?? 'active').toLowerCase();
    final key = '${planName}_$planId';
    
    // Check purchase status
    // Check purchase status - prioritize current active purchase over historical status
    final isPurchased = _purchasedKeys.contains(key);
    final isCompleted = _completedKeys.contains(key);
    final isActive = status == 'active';

    // For status determination, only consider cancelled if it's the current active purchase
    bool isCancelled = false;
    String? purchaseDocId;
    int? remainingSessions;
    bool isRepurchased = false;

    if (isPurchased) {
      // Find the most recent active purchase for this plan
      final purchases = _myActivePlans.where(
        (p) => p['planName'] == planName && p['planId'] == planId,
      ).toList();
      
      if (purchases.isNotEmpty) {
        // Get the most recent purchase
        final purchase = purchases.first;
        purchaseDocId = purchase['docId'];
        remainingSessions = purchase['remainingSessions'] as int? ?? 0;
        isRepurchased = purchase['isRepurchase'] as bool? ?? false;
        
        // Only show cancelled if the CURRENT purchase is cancelled
        final currentStatus = purchase['status'] as String? ?? 'active';
        isCancelled = currentStatus == 'cancelled';
      }
    } else {
      // If not purchased, check historical cancellation status
      isCancelled = _cancelledKeys.contains(key);
    }

    // Build status widget
    // In _buildPlanCard method, update the status widget logic:

    // Build status widget
    Widget statusWidget;

    if (isPurchased && remainingSessions != null) {
      final totalSessions = plan['sessions'] as int? ?? 0;
      final usedSessions = totalSessions - remainingSessions; // This now shows ONLY completed sessions
      
      if (isCancelled) {
        statusWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:Colors.grey.withOpacity(0.1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.1),),
          ),
          child: const Text(
            "Inactive",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        );
      } else if (remainingSessions <= 0) {
        statusWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.1),),
          ),
          child: const Text(
            "Inactive",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        );
      } else {
        statusWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Text(
            "Active ($usedSessions/$totalSessions completed)",
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        );
      }
    } else if (isCancelled) {
      statusWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.05)),
        ),
        child: const Text(
          "Inactive",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color:Colors.grey,
          ),
        ),
      );
    } else if (isCompleted) {
      statusWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: const Text(
          "Inactive",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      );
    } else {
      statusWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Text(
          isActive ? "Inactive" : "Inactive",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.grey : Colors.grey[500],
          ),
        ),
      );
    }

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isActive ? Colors.white : Colors.grey[200],
      child: Opacity(
        opacity: isActive ? 1.0 : 0.6,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: isActive
                  ? [Colors.white, Colors.grey.withOpacity(0.05)]
                  : [Colors.grey[300]!, Colors.grey[400]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row with sessions, price, and status on the right
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$sessions sessions',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isActive ? Colors.orange : Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isActive ? Colors.green : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    statusWidget,
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  planCategory,
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive ? Colors.grey[600] : Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: isActive ? Colors.grey : Colors.grey[500],
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Button logic: Show Cancel button for active purchased plans (including repurchased ones)
                if (isPurchased && purchaseDocId != null && remainingSessions != null && remainingSessions > 0 && !isCancelled)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _cancelPlan(purchaseDocId!, planName),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cancel, size: 16),
                      label: Text(
                        _isLoading ? 'Processing...' : 'Cancel Plan',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  )
                // Show Purchase/Repurchase button for non-purchased, cancelled, or completed plans
                else if (!isPurchased || isCancelled || isCompleted)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (!isActive || _isLoading || _isProcessingPayment)
                          ? null
                          : () => _purchasePlan(plan),
                      icon: (_isLoading || _isProcessingPayment)
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(FontAwesomeIcons.cartPlus, size: 14),
                      label: Text(
                        (_isLoading || _isProcessingPayment)
                            ? 'Processing...'
                            : isActive
                                ? (isCancelled || isCompleted) ? 'Purchase Plan' : 'Purchase Plan'
                                : 'Plan Inactive',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive ? Colors.blueAccent : Colors.grey[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  )
                // For purchased plans with no sessions remaining but still active (edge case), show completed message
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        'Plan Completed',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _refreshSessionCounts() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;
      
      final now = DateTime.now().toUtc();
      
      // Get all purchased plans
      final purchasesSnapshot = await _firestore
          .collection('client_purchases')
          .where('userId', isEqualTo: userId)
          .get();

      // Get all booked slots (both upcoming and past)
      final slotsSnapshot = await _firestore
          .collection('trainer_slots')
          .where('booked_by', arrayContains: userId)
          .get();

      // Create a batch for efficient updates
      final batch = _firestore.batch();
      bool hasUpdates = false;

      for (final purchaseDoc in purchasesSnapshot.docs) {
        final purchaseData = purchaseDoc.data();
        final purchaseId = purchaseDoc.id;
        final planName = purchaseData['planName'] as String?;
        final planId = purchaseData['planId'] as String?;
        final totalSessions = purchaseData['totalSessions'] as int? ?? 0;
        final status = purchaseData['status'] as String? ?? 'active';

        // Skip cancelled or already completed plans
        if (status == 'cancelled' || status == 'completed') continue;
        if (planName == null || planId == null) continue;

        // Get current booked sessions to preserve them
        final currentBookedSessionsInDB = purchaseData['bookedSessions'] as int? ?? 0;

        // Count ONLY COMPLETED sessions (past sessions where end time has passed)
        int completedSessionsInThisPurchase = 0;
        
        for (final slotDoc in slotsSnapshot.docs) {
          try {
            final slotData = slotDoc.data();
            final slotDate = (slotData['date'] as Timestamp).toDate().toUtc();
            final slotTime = slotData['time'] as String? ?? '';
            
            // Parse the slot time to get exact end time
            DateTime slotEndTime = slotDate;
            if (slotTime.isNotEmpty) {
              try {
                final endTimeStr = slotTime.split(' - ')[1].trim();
                final endTime = DateFormat.jm().parse(endTimeStr);
                slotEndTime = DateTime(
                  slotDate.year,
                  slotDate.month,
                  slotDate.day,
                  endTime.hour,
                  endTime.minute,
                ).toUtc();
              } catch (e) {
                continue;
              }
            }

            // Check if this slot belongs to this purchase
            final slotPurchaseIds = List<String>.from(slotData['purchase_ids'] ?? []);
            final userPurchaseMap = Map<String, dynamic>.from(slotData['user_purchase_map'] ?? {});
            
            bool belongsToThisPurchase = slotPurchaseIds.contains(purchaseId) || 
                                        userPurchaseMap[userId] == purchaseId;

            if (belongsToThisPurchase) {
              // Check slot status
              final statusByUser = Map<String, dynamic>.from(slotData['status_by_user'] ?? {});
              final userSlotStatus = statusByUser[userId] as String?;
              final isCancelled = userSlotStatus == 'Cancelled';
              final isCompleted = userSlotStatus == 'Completed';
              
              if (!isCancelled) {
                if (isCompleted || slotEndTime.isBefore(now)) {
                  // Count as completed (session end time has passed OR marked as completed)
                  completedSessionsInThisPurchase++;
                }
                // ❌ REMOVED: Don't count booked sessions here - preserve the original booked count
              }
            }
          } catch (e) {
            continue;
          }
        }

        // Calculate remaining sessions based on completed sessions only
        final remainingSessions = totalSessions - completedSessionsInThisPurchase;
        
        // Plan is completed ONLY when ALL sessions are completed
        final newStatus = (completedSessionsInThisPurchase >= totalSessions) ? 'completed' : 'active';
        final isActive = newStatus == 'active';

        // Check if update is needed
        final currentUsed = purchaseData['usedSessions'] as int? ?? 0;
        final currentRemaining = purchaseData['remainingSessions'] as int? ?? totalSessions;
        final currentStatus = purchaseData['status'] as String? ?? 'active';
        final currentIsActive = purchaseData['isActive'] as bool? ?? true;
        
        // ❌ REMOVED: Don't check bookedSessions changes - preserve original value
        bool needsUpdate = currentUsed != completedSessionsInThisPurchase || 
                          currentRemaining != remainingSessions ||
                          currentStatus != newStatus ||
                          currentIsActive != isActive;

        if (needsUpdate) {
          hasUpdates = true;
          Map<String, dynamic> updateData = {
            'usedSessions': completedSessionsInThisPurchase,
            'remainingSessions': remainingSessions,
            // ❌ REMOVED: 'bookedSessions': currentBookedSessions, - preserve original booked count
            'availableSessions': totalSessions - currentBookedSessionsInDB, // Use preserved booked count
            'isActive': isActive,
            'status': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          };

          // Add completion date only if plan is completed
          if (newStatus == 'completed') {
            updateData['completedDate'] = FieldValue.serverTimestamp();
          } else {
            updateData['completedDate'] = FieldValue.delete();
          }

          batch.update(purchaseDoc.reference, updateData);
          
          print('🔄 Updated purchase ${purchaseData['planName']}: '
              'Used: $completedSessionsInThisPurchase, '
              'Booked: $currentBookedSessionsInDB, ' // Show preserved count
              'Remaining: $remainingSessions, '
              'Status: $newStatus');
        }
      }

      // Commit all updates at once if there are any
      if (hasUpdates) {
        await batch.commit();
        
        // Force refresh the local state
        await Future.wait([
          _loadPurchasedPlans(),
          _loadMyActivePlans(),
        ]);
      }
      
    } catch (e) {
      print('❌ Error refreshing session counts: $e');
    }
  }
  // ----- PDF: Receipt after purchase -----
  Future<void> _generatePurchaseReceiptPDF({
    required String clientName,
    required String planName,
    required int sessions,
    required double price,
    required String purchaseId,
    required DateTime purchaseDate,
  }) async {
    try {
      final df = DateFormat('MMMM d, y – h:mm a'); // Month Day, Year – time
      final pdf = pw.Document();
      final currency = NumberFormat.simpleCurrency(name: 'USD');

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Purchase Receipt',
                    style: pw.TextStyle(
                      fontSize: 28,
                      fontWeight: pw.FontWeight.bold,
                    )),
                pw.SizedBox(height: 8),
                pw.Text('Thank you for your purchase!',
                    style: const pw.TextStyle(fontSize: 14)),
                pw.SizedBox(height: 24),
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  padding: const pw.EdgeInsets.all(14),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _kv('Client', clientName),
                      _kv('Purchase ID', purchaseId),
                      _kv('Date', df.format(purchaseDate)),
                      pw.SizedBox(height: 12),
                      pw.Divider(color: PdfColors.grey300),
                      pw.SizedBox(height: 12),
                      _kv('Plan', planName),
                      _kv('Sessions', sessions.toString()),
                      _kv('Price', currency.format(price)),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'Flex Facility — Secured by Square',
                    style: pw.TextStyle(
                      color: PdfColors.grey600,
                      fontSize: 12,
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      );

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/receipt_$purchaseId.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        _showSnackBar('Could not open PDF: ${result.message}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error creating receipt PDF', Colors.red);
    }
  }

  static pw.Widget _kv(String k, String v) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: pw.TextStyle(color: PdfColors.grey700)),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Text(
              v,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildErrorWidget(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 80, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Error Loading Data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeData,
              child: const Text('Retry'),
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
        title: const Text(
          'Fitness Plans',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1C2D5E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorWeight: 3,
          tabs: const [
            Tab(
              icon: Icon(Icons.fitness_center),
              text: 'Plans',
            ),
            Tab(
              icon: Icon(Icons.picture_as_pdf),
              text: 'PDF Workouts',
            ),
          ],
        ),
        actions: [
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPlansContent(),
          const PDFWorkoutsTab(),
        ],
      ),
    );
  }

  Widget _buildPlansContent() {
    return _errorMessage != null
        ? _buildErrorWidget(_errorMessage!)
        : _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 18),
                    Text('Loading plans...'),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadPurchasedPlans();
                  await _loadMyActivePlans();
                },
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('plans').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: _buildErrorWidget(snapshot.error.toString()),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 18),
                              Text('Loading plans...'),
                            ],
                          ),
                        ),
                      );
                    }

                    final Map<String, Map<String, dynamic>> uniquePlansMap = {};
                    for (var doc in snapshot.data!.docs) {
                      final docId = doc.id;
                      if (!uniquePlansMap.containsKey(docId)) {
                        uniquePlansMap[docId] = {
                          ...doc.data() as Map<String, dynamic>,
                          'docId': docId,
                        };
                      }
                    }
                    final List<Map<String, dynamic>> allPlans = uniquePlansMap.values.toList();

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ...(() {
                          final Map<String, List<Map<String, dynamic>>> groupedPlans = {};
                          for (final plan in allPlans) {
                            final category = plan['category'] as String? ?? 'Uncategorized';
                            if (!groupedPlans.containsKey(category)) {
                              groupedPlans[category] = [];
                            }
                            groupedPlans[category]!.add(plan);
                          }
                          groupedPlans.forEach((category, plans) {
                            plans.sort((a, b) {
                              final sa = a['sessions'] as int? ?? 0;
                              final sb = b['sessions'] as int? ?? 0;
                              return sa.compareTo(sb);
                            });
                          });
                          
                          const categoryOrder = [
                            'Semi Private Monthly Plans',
                            'Semi Private Bi Weekly Plans',
                            'Semi Private Day Pass',
                            'Group Training or Class',
                            'Strength & Agility Session (High School Athlete)',
                            'Strength & Agility Session (Kids)',
                            'Athletic Performance (Adult)',
                          ];
                          
                          final sortedCategories = groupedPlans.keys.toList()
                            ..sort((a, b) {
                              int indexA = categoryOrder.indexOf(a);
                              int indexB = categoryOrder.indexOf(b);
                              if (indexA == -1) indexA = categoryOrder.length;
                              if (indexB == -1) indexB = categoryOrder.length;
                              return indexA.compareTo(indexB);
                            });
                          
                          return sortedCategories.map((category) {
                            final categoryPlans = groupedPlans[category]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCategoryHeader(category, categoryPlans.length),
                                ...categoryPlans.map((plan) => _buildPlanCard(plan)),
                              ],
                            );
                          }).toList();
                        })(),
                      ],
                    );
                  },
                ),
              );
  }
}

