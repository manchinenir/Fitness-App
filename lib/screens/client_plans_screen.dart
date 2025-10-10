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
  bool _canExportPDF = false;

  // Add these stream subscriptions
  StreamSubscription<QuerySnapshot>? _sessionsSubscription;
  StreamSubscription<QuerySnapshot>? _purchasesSubscription;

  static const String _squareApplicationId = 'sandbox-sq0idb-b_5NuSv1kYCZWkITbVqS4w';
  static const String _squareLocationId = 'LPSE4AB75KF7G';
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
        _updateCanExportPDF();
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
      _updateCanExportPDF();
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

      // Fetch client name
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      String clientName = '';
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        clientName = userData['name'] ?? '';
      }

      // Check if this is a repurchase of a previously cancelled/completed plan
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

      // Create new purchase doc with generated ID
      final newPurchaseDocRef = _firestore.collection('client_purchases').doc();
      final newPurchaseId = newPurchaseDocRef.id;

      // In the purchase data creation, ensure all fields are set correctly:
      Map<String, dynamic> purchaseData = {
        'purchaseId': newPurchaseId,
        'docId': newPurchaseId,
        'userId': userId,
        'clientName': clientName,
        'planId': planId,
        'planName': planName,
        'planCategory': plan['category'] ?? '',
        'price': (plan['price'] ?? 0).toDouble(),
        'sessions': totalSessions,
        'totalSessions': totalSessions,
        'remainingSessions': totalSessions, // Total available sessions
        'bookedSessions': 0, // No sessions booked yet
        'usedSessions': 0, // No sessions used yet
        'availableSessions': totalSessions, // Available = remaining - booked = total - 0
        'description': plan['description'] ?? '',
        'isActive': true,
        'status': 'active',
        'purchaseDate': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'paymentMethod': 'square',
        'paymentStatus': 'completed',
        'isRepurchase': isRepurchase,
      };

      await newPurchaseDocRef.set(purchaseData);

      print('✅ New purchase created with ID: $newPurchaseId');
      print('📋 Plan: $planName | 🔢 Sessions: 0/$totalSessions used | 👤 Client: $clientName');
      print('🎯 Status: ACTIVE | Is Repurchase: $isRepurchase');

      // Refresh local state
      await Future.wait([
        _loadPurchasedPlans(),
        _loadMyActivePlans(),
      ]);
      _updateCanExportPDF();

      _showSnackBar('Payment successful! Plan purchased.', Colors.green);

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      print('❌ Error completing purchase');
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
        _updateCanExportPDF();
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

    if (result == true) {
      await _completePlanPurchaseAfterPayment(plan);
    }
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

  // ✅ FIXED: Enhanced session counting that only counts PAST sessions as completed
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

        // Count ONLY COMPLETED sessions (past sessions where end time has passed)
        int completedSessionsInThisPurchase = 0;
        int currentBookedSessions = 0;
        
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
                } else {
                  // Count as currently booked (upcoming session)
                  currentBookedSessions++;
                }
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
        final currentBooked = purchaseData['bookedSessions'] as int? ?? 0;
        final currentStatus = purchaseData['status'] as String? ?? 'active';
        final currentIsActive = purchaseData['isActive'] as bool? ?? true;
        
        bool needsUpdate = currentUsed != completedSessionsInThisPurchase || 
                          currentRemaining != remainingSessions ||
                          currentBooked != currentBookedSessions ||
                          currentStatus != newStatus ||
                          currentIsActive != isActive;

        if (needsUpdate) {
          hasUpdates = true;
          Map<String, dynamic> updateData = {
            'usedSessions': completedSessionsInThisPurchase,
            'remainingSessions': remainingSessions,
            'bookedSessions': currentBookedSessions, // Update booked sessions count
            'availableSessions': totalSessions - currentBookedSessions, // Recalculate available
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
              'Booked: $currentBookedSessions, '
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
        _updateCanExportPDF();
      }
      
    } catch (e) {
      print('❌ Error refreshing session counts: $e');
    }
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
  Future<void> _exportPDF() async {
    final now = DateTime.now();
    final exportPlans = _myActivePlans.where((p) {
      if (p['isActive'] != true) return false;
      final pd = (p['purchaseDate'] as Timestamp?)?.toDate();
      if (pd == null) return false;
      return now.difference(pd).inDays <= 30;
    }).toList();

    if (exportPlans.isEmpty) {
      _showSnackBar('No plans available for export', Colors.orange);
      return;
    }

    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      _showSnackBar('User not logged in', Colors.red);
      return;
    }

    // Fetch workouts from users/{userId}/workouts
    final workoutSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('workouts')
        .where('assigned_at', isGreaterThan: Timestamp(0, 0))
        .get();
    final List<Map<String, dynamic>> userWorkouts = workoutSnapshot.docs.map((doc) {
      Map<String, dynamic> data = doc.data();
      data['docId'] = doc.id;
      return data;
    }).toList();

    userWorkouts.sort((a, b) {
      final tsA = a['assigned_at'] as Timestamp?;
      final tsB = b['assigned_at'] as Timestamp?;
      if (tsA == null || tsB == null) return 0;
      return tsB.compareTo(tsA);
    });

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('My Workout Plans History',
                  style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 30),
              for (var workout in userWorkouts)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (workout['title'] != null)
                      pw.Text('Title: ${workout['title']}',
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    if (workout['assigned_at'] != null)
                      pw.Text('Assigned At: ${(workout['assigned_at'] as Timestamp).toDate().toLocal().toString()}',
                          style: pw.TextStyle(fontSize: 20)),
                    if (workout['trainer'] != null)
                      pw.Text('Trainer: ${workout['trainer']}',
                          style: pw.TextStyle(fontSize: 20)),
                    if (workout['rating'] != null)
                      pw.Text('Rating: ${workout['rating']}',
                          style: pw.TextStyle(fontSize: 20)),
                    if (workout['workouts'] != null)
                      pw.Text('Workouts:',
                          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                    if (workout['workouts'] != null)
                      ...((workout['workouts'] as Map<String, dynamic>).entries).map((entry) {
                        return pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('${entry.key.toUpperCase()}:',
                                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                            ...(entry.value as List).map((exercise) => pw.Text('  - $exercise',
                                style: pw.TextStyle(fontSize: 18))).toList(),
                          ],
                        );
                      }).toList(),
                    pw.SizedBox(height: 30),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/workout_plans_history.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    try {
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        _showSnackBar('Could not open PDF: ${result.message}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error opening PDF', Colors.red);
    }
  }
  void _updateCanExportPDF() {
    final now = DateTime.now();
    bool can = false;
    for (var p in _myActivePlans) {
      if (p['isActive'] == true) {
        final pd = (p['purchaseDate'] as Timestamp?)?.toDate();
        if (pd != null && now.difference(pd).inDays <= 30) {
          can = true;
          break;
        }
      }
    }
    setState(() {
      _canExportPDF = can;
    });
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
          if (_canExportPDF && !_isLoading && _tabController.index == 0)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              onPressed: _exportPDF, // This now correctly calls _exportPDF
              tooltip: 'Export PDF',
            ),
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
                  _updateCanExportPDF();
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

class SquarePaymentPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final String squareApplicationId;
  final String squareLocationId;

  const SquarePaymentPage({
    super.key,
    required this.plan,
    required this.squareApplicationId,
    required this.squareLocationId,
  });

  @override
  State<SquarePaymentPage> createState() => _SquarePaymentPageState();
}

class _SquarePaymentPageState extends State<SquarePaymentPage> {
  bool _isProcessingPayment = false;
  String? _errorMessage;

  static const String _apiUrl =
      'https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api/process-payment';

  Future<void> _openWebCheckout() async {
    setState(() {
      _isProcessingPayment = true;
      _errorMessage = null;
    });

    try {
      final double price = (widget.plan['price'] ?? 0).toDouble();
      final int amountCents = (price * 100).round();

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SquareWebCheckout(
            amountCents: amountCents,
            appId: widget.squareApplicationId,
            locationId: widget.squareLocationId,
            functionsBaseUrl: 'https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api',
            production: false,
          ),
        ),
      );

      if (!mounted) return;

      if (result != null && result['ok'] == true) {
        Navigator.of(context).pop(true);
      } else if (result != null) {
        setState(() {
          _errorMessage = result['error']?.toString() ?? 'Payment failed';
          _isProcessingPayment = false;
        });
      } else {
        setState(() => _isProcessingPayment = false);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error starting checkout';
        _isProcessingPayment = false;
      });
    }
  }

  Future<void> _openInvoicePage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceReviewPage(
          plan: widget.plan,
          squareApplicationId: widget.squareApplicationId,
          squareLocationId: widget.squareLocationId,
          functionsBaseUrl: 'https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api',
        ),
      ),
    );

    if (!mounted) return;
    if (result == true) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planPrice = (widget.plan['price'] ?? 0).toDouble();
    final planName = widget.plan['name'] as String? ?? 'Fitness Plan';
    final sessions = widget.plan['sessions'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Payment',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1C2D5E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [Colors.blueAccent.withOpacity(0.1), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.fitness_center, color: Colors.blueAccent, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Plan Summary',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(planName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$sessions Sessions', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                        Text('\$${planPrice.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Payment Method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.credit_card, color: Colors.blue),
                ),
                title: const Text('Credit/Debit Card', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Secure payment via Square'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _isProcessingPayment ? null : _openWebCheckout,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long, color: Colors.blue),
                ),
                title: const Text('Invoice', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Open Square hosted invoice'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _isProcessingPayment ? null : _openInvoicePage,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ],
            const Spacer(),
            if (_isProcessingPayment)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('Processing Payment...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openWebCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Pay \$${planPrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.security, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Text('Secured by Square', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}