import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:square_in_app_payments/in_app_payments.dart';
import 'package:square_in_app_payments/models.dart' as square_models;

class ClientPlansScreen extends StatefulWidget {
  const ClientPlansScreen({super.key});
  @override
  State<ClientPlansScreen> createState() => _ClientPlansScreenState();
}

class _ClientPlansScreenState extends State<ClientPlansScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  final Set<String> _purchasedKeys = {};
  final Set<String> _completedKeys = {};
  List<Map<String, dynamic>> _myActivePlans = [];
  String? _errorMessage;
  final Map<String, bool> _expandedCategories = {};

  // Square payment configuration - updated IDs below
  static const String _squareApplicationId = 'sandbox-sq0idb-b_5NuSv1kYCZWkITbVqS4w';
  static const String _squareLocationId = 'LPSE4AB75KF7G';
  bool _isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    _initializeSquareSDK();
    _initializeData();
  }

  Future<void> _initializeSquareSDK() async {
    try {
      await InAppPayments.setSquareApplicationId(_squareApplicationId);
    } catch (e) {
      print('Error initializing Square SDK: $e');
    }
  }

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
      print('Error initializing data: $e');
      setState(() {
        _errorMessage = 'Error loading data: $e';
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
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final key = '${data['planName']}_${data['planId']}';
          final isActive = data['isActive'] as bool? ?? false;
          final remainingSessions = data['remainingSessions'] as int? ?? 0;

          if (isActive && remainingSessions > 0) {
            _purchasedKeys.add(key);
          } else if (remainingSessions == 0) {
            _completedKeys.add(key);
          }
        }
      });
    } catch (e) {
      print('Error loading purchased plans: $e');
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
      print('Error loading my plans: $e');
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
      if (_purchasedKeys.contains(key)) {
        _showSnackBar('You currently have an active plan of this type. Complete all sessions first.', Colors.orange);
        return;
      }
      
      // Navigate to payment page first, then card entry
      _navigateToPaymentPage(plan);
    } catch (e) {
      print('Error initiating purchase: $e');
      _showSnackBar('Error initiating purchase: $e', Colors.red);
    }
  }

  Future<void> _startSquareCardEntry(Map<String, dynamic> plan) async {
    setState(() {
      _isProcessingPayment = true;
      _errorMessage = null;
    });

    try {
      await InAppPayments.startCardEntryFlow(
        onCardNonceRequestSuccess: (square_models.CardDetails cardDetails) async {
          final nonce = cardDetails.nonce;
          final planPrice = (plan['price'] ?? 0).toDouble();

          // Process payment with nonce on backend
          final paymentSuccess = await _processPaymentOnBackend(nonce, planPrice);

          if (paymentSuccess) {
            await _completePlanPurchaseAfterPayment(plan);
            InAppPayments.completeCardEntry(onCardEntryComplete: () {
              setState(() {
                _isProcessingPayment = false;
              });
            });
          } else {
            InAppPayments.showCardNonceProcessingError('Payment failed. Please try again.');
            setState(() {
              _isProcessingPayment = false;
            });
          }
        },
        onCardEntryCancel: () {
          setState(() {
            _isProcessingPayment = false;
          });
        },
      );
    } catch (e) {
      print('Error starting payment: $e');
      setState(() {
        _errorMessage = 'Error starting payment: $e';
        _isProcessingPayment = false;
      });
    }
  }

  Future<bool> _processPaymentOnBackend(String nonce, double amount) async {
    // TODO: Send nonce and amount to your backend for actual payment processing
    // Simulate backend processing for now
    await Future.delayed(const Duration(seconds: 2));
    return true; // Return actual payment result from your backend
  }

  void _navigateToPaymentPage(Map<String, dynamic> plan) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SquarePaymentPage(
          plan: plan,
          squareApplicationId: _squareApplicationId,
          squareLocationId: _squareLocationId,
        ),
      ),
    );

    if (result == true) {
      await _completePlanPurchaseAfterPayment(plan);
    }
  }

  Future<void> _completePlanPurchaseAfterPayment(Map<String, dynamic> plan) async {
    try {
      setState(() => _isLoading = true);

      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final planId = plan['docId'] as String;
      final planName = plan['name'] as String;

      await _firestore.collection('client_purchases').add({
        'userId': userId,
        'planId': planId,
        'planName': planName,
        'planCategory': plan['category'] ?? '',
        'price': (plan['price'] ?? 0).toDouble(),
        'sessions': plan['sessions'] ?? 0,
        'description': plan['description'] ?? '',
        'purchaseDate': FieldValue.serverTimestamp(),
        'remainingSessions': plan['sessions'] ?? 0,
        'totalSessions': plan['sessions'] ?? 0,
        'isActive': true,
        'status': 'active',
        'usedSessions': 0,
        'paymentMethod': 'square',
        'paymentStatus': 'completed',
      });

      await _loadPurchasedPlans();
      await _loadMyActivePlans();
      _showSnackBar('Payment successful! Plan purchased.', Colors.green);
    } catch (e) {
      print('Error completing purchase: $e');
      _showSnackBar('Error completing purchase: $e', Colors.red);
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
              'Are you sure you want to cancel "$planName"? This action cannot be undone and you will lose all remaining sessions.',
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
        });

        await _loadPurchasedPlans();
        await _loadMyActivePlans();
        _showSnackBar('Plan "$planName" cancelled successfully!', Colors.green);
      }
    } catch (e) {
      print('Error cancelling plan: $e');
      _showSnackBar('Error cancelling plan: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _useSession(String purchaseDocId, int currentRemaining, int totalSessions) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return; 
      final newRemaining = currentRemaining - 1;
      final usedSessions = totalSessions - newRemaining; 
      if (newRemaining == 1) {
        _showLastSessionReminder(totalSessions);
      } else if (newRemaining == 0) {
        _showPlanCompletedDialog(totalSessions);
      } else if (newRemaining == 2) {
        _showBeforeLastSessionAlert();
      }

      await _firestore.collection('client_purchases').doc(purchaseDocId).update({
        'remainingSessions': newRemaining,
        'usedSessions': usedSessions,
        'lastUsedDate': FieldValue.serverTimestamp(),
        'isActive': newRemaining > 0,
        'status': newRemaining > 0 ? 'active' : 'completed',
      });

      await _loadPurchasedPlans();
      await _loadMyActivePlans();
    } catch (e) {
      print('Error updating session: $e');
      _showSnackBar('Error updating session: $e', Colors.red);
    }
  }

  void _showBeforeLastSessionAlert() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Almost at Last Session!'),
            ],
          ),
          content: const Text(
            'You have only ONE session remaining in your plan after today!',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Got it!'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _showLastSessionReminder(int totalSessions) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Last Session Alert'),
            ],
          ),
          content: Text(
            'This is your LAST SESSION! You have completed ${totalSessions - 1} out of $totalSessions sessions. After this session, your plan will be completed and you can purchase it again if needed.',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Got it!'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  void _showPlanCompletedDialog(int totalSessions) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.celebration, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Plan Completed!'),
            ],
          ),
          content: Text(
            'Congratulations! You have successfully completed all $totalSessions sessions of your fitness plan. The plan is now available for purchase again if you want to continue your fitness journey.',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('Great!'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('View Plans'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryHeader(String category, int planCount) {
    final isExpanded = _expandedCategories[category] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _expandedCategories[category] = !isExpanded;
            });
          },
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
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.blueAccent,
                  size: 28,
                ),
              ],
            ),
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
    final isPurchased = _purchasedKeys.contains(key);
    final isActive = status == 'active'; 
    String? purchaseDocId;
    if (isPurchased) {
      final purchase = _myActivePlans.firstWhere(
        (p) => p['planName'] == planName && p['planId'] == planId,
        orElse: () => {},
      );
      purchaseDocId = purchase['docId'];
    }
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$sessions sessions',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPurchased
                          ? Colors.green.withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isPurchased
                            ? Colors.green.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      isPurchased ? "Active" : "Inactive",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isPurchased ? Colors.green : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                planCategory,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!isPurchased)
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
                              ? 'Purchase Plan'
                              : 'Plan Inactive',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? Colors.blueAccent : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading || purchaseDocId == null)
                        ? null
                        : () => _cancelPlan(purchaseDocId!, planName),
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyPlanCard(Map<String, dynamic> purchase) {
    final planName = purchase['planName'] as String? ?? 'Unknown Plan';
    final planCategory = purchase['planCategory'] as String? ?? 'General';
    final remainingSessions = purchase['remainingSessions'] as int? ?? 0;
    final totalSessions = purchase['totalSessions'] as int? ?? 0;
    final usedSessions = purchase['usedSessions'] as int? ?? 0;
    final price = (purchase['price'] ?? 0).toDouble();
    final isActive = purchase['isActive'] as bool? ?? false;
    final purchaseDocId = purchase['docId'] as String? ?? '';
    final progress =
        totalSessions > 0 ? usedSessions / totalSessions : 0.0;
    final planActive = isActive && remainingSessions > 0; 
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: planActive
                ? [Colors.green.withOpacity(0.1), Colors.white]
                : [Colors.grey.withOpacity(0.1), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          planName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: planActive ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          planCategory,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: planActive
                          ? Colors.green.withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      planActive ? 'Active' : 'Completed',
                      style: TextStyle(
                        color: planActive ? Colors.green : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sessions Progress',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      Text(
                        '$usedSessions / $totalSessions used',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      planActive ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: planActive
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fitness_center,
                          size: 16,
                          color: planActive ? Colors.orange : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$remainingSessions Left',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: planActive ? Colors.orange : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attach_money, size: 16, color: Colors.blue),
                        Text(
                          '\$${price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (planActive && remainingSessions > 0) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _useSession(
                            purchaseDocId, remainingSessions, totalSessions),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Use Session'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _cancelPlan(purchaseDocId, planName),
                        icon: const Icon(Icons.cancel),
                        label: const Text('Cancel Plan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
      ),
      body: _errorMessage != null
          ? _buildErrorWidget(_errorMessage!)
          : _isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading plans...'),
                    ],
                  ),
                )
              : StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('plans').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _buildErrorWidget(
                          'Error loading plans: ${snapshot.error}');
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Loading plans...'),
                          ],
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fitness_center,
                                size: 80, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No plans available',
                              style: TextStyle(
                                  fontSize: 18, color: Colors.grey),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Plans will appear here when available',
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }
                    final allPlans = snapshot.data!.docs.map((doc) {
                      final data = doc.data()! as Map<String, dynamic>;
                      data['docId'] = doc.id;
                      return data;
                    }).toList();
                    final activePlans = allPlans.where((plan) {
                      final status = (plan['status'] as String? ?? 'active').toLowerCase();
                      return status == 'active';
                    }).toList();
                    if (activePlans.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fitness_center,
                                size: 80, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No active plans available',
                              style: TextStyle(
                                  fontSize: 18, color: Colors.grey),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Active plans will appear here',
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }
                    final Map<String, List<Map<String, dynamic>>> groupedPlans = {};
                    for (final plan in activePlans) {
                      final category = plan['category'] as String? ?? 'General';
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
                    return RefreshIndicator(
                      onRefresh: () async {
                        await _loadPurchasedPlans();
                      },
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: groupedPlans.entries.map((entry) {
                          final category = entry.key;
                          final categoryPlans = entry.value;
                          final isExpanded = _expandedCategories[category] ?? false;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCategoryHeader(category, categoryPlans.length),
                              if (isExpanded) ...[
                                ...categoryPlans.map((plan) {
                                  return _buildPlanCard(plan);
                                }),
                              ],
                            ],
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
    );
  }
}

// Square Payment Page
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

  @override
  void initState() {
    super.initState();
    _initializeSquareSDK();
  }

  Future<void> _initializeSquareSDK() async {
    try {
      await InAppPayments.setSquareApplicationId(widget.squareApplicationId);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing payment system: $e';
      });
    }
  }

  void _startCardEntryFlow() async {
    setState(() {
      _isProcessingPayment = true;
      _errorMessage = null;
    });

    try {
      await InAppPayments.startCardEntryFlow(
        onCardNonceRequestSuccess: (square_models.CardDetails result) {
          _onCardEntryComplete(result);
        },
        onCardEntryCancel: () {
          _onCardEntryCancel();
        },
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error starting payment: $e';
        _isProcessingPayment = false;
      });
    }
  }

  void _onCardEntryComplete(square_models.CardDetails cardDetails) async {
    try {
      final nonce = cardDetails.nonce;
      final planPrice = (widget.plan['price'] ?? 0).toDouble();

      final paymentSuccess = await _processPaymentOnBackend(nonce, planPrice);

      if (paymentSuccess) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _errorMessage = 'Payment failed. Please try again.';
          _isProcessingPayment = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error processing payment: $e';
        _isProcessingPayment = false;
      });
    }
  }

  void _onCardEntryCancel() {
    setState(() {
      _isProcessingPayment = false;
    });
  }

  Future<bool> _processPaymentOnBackend(String nonce, double amount) async {
    // Simulate backend payment processing for demo
    await Future.delayed(const Duration(seconds: 2));
    return true;
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      planName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$sessions Sessions',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          '\$${planPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Payment Method',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.credit_card, color: Colors.blue),
                ),
                title: const Text(
                  'Credit/Debit Card',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Secure payment via Square'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _isProcessingPayment ? null : _startCardEntryFlow,
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
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
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
                    Text(
                      'Processing Payment...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startCardEntryFlow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Pay \$${planPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
                  Text(
                    'Secured by Square',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}