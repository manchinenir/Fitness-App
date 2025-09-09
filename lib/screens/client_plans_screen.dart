import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'square_checkout.dart';

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

  // Square payment configuration
  static const String _squareApplicationId = 'sandbox-sq0idb-b_5NuSv1kYCZWkITbVqS4w';
  static const String _squareLocationId = 'LPSE4AB75KF7G';
  bool _isProcessingPayment = false;

  // Hardcoded plans with all specified categories
  static final List<Map<String, dynamic>> _allPlans = [
    // Semi Private Monthly Plans
    {
      'docId': 'sp_monthly_4',
      'name': 'Semi Private Monthly (4 Sessions)',
      'category': 'Semi Private Monthly Plans',
      'sessions': 4,
      'price': 185.0,
      'description': '4 sessions per month',
      'status': 'active',
    },
    {
      'docId': 'sp_monthly_8',
      'name': 'Semi Private Monthly (8 Sessions)',
      'category': 'Semi Private Monthly Plans',
      'sessions': 8,
      'price': 375.0,
      'description': '8 sessions per month',
      'status': 'active',
    },
    {
      'docId': 'sp_monthly_12',
      'name': 'Semi Private Monthly (12 Sessions)',
      'category': 'Semi Private Monthly Plans',
      'sessions': 12,
      'price': 500.0,
      'description': '12 sessions per month',
      'status': 'active',
    },
    {
      'docId': 'sp_monthly_16',
      'name': 'Semi Private Monthly (16 Sessions)',
      'category': 'Semi Private Monthly Plans',
      'sessions': 16,
      'price': 600.0,
      'description': '16 sessions per month',
      'status': 'active',
    },
    // Semi Private Bi Weekly Plans
    {
      'docId': 'sp_biweekly_4',
      'name': 'Semi Private Bi Weekly (4 Sessions)',
      'category': 'Semi Private Bi Weekly Plans',
      'sessions': 4,
      'price': 94.0,
      'description': '4 sessions per month',
      'status': 'active',
    },
    {
      'docId': 'sp_biweekly_8',
      'name': 'Semi Private Bi Weekly (8 Sessions)',
      'category': 'Semi Private Bi Weekly Plans',
      'sessions': 8,
      'price': 187.0,
      'description': '8 sessions per month',
      'status': 'active',
    },
    {
      'docId': 'sp_biweekly_12',
      'name': 'Semi Private Bi Weekly (12 Sessions)',
      'category': 'Semi Private Bi Weekly Plans',
      'sessions': 12,
      'price': 260.0,
      'description': '12 sessions per month',
      'status': 'active',
    },
    {
      'docId': 'sp_biweekly_16',
      'name': 'Semi Private Bi Weekly (16 Sessions)',
      'category': 'Semi Private Bi Weekly Plans',
      'sessions': 16,
      'price': 310.0,
      'description': '16 sessions per month',
      'status': 'active',
    },
    // Semi Private Day Pass
    {
      'docId': 'sp_day_pass',
      'name': 'Semi Private Day Pass',
      'category': 'Semi Private Day Pass',
      'sessions': 1,
      'price': 40.0,
      'description': 'One-day access',
      'status': 'active',
    },
    // Group Training or Class
    {
      'docId': 'group_training',
      'name': 'Group Training or Class',
      'category': 'Group Training or Class',
      'sessions': 1,
      'price': 25.0,
      'description': 'Single group training session or class',
      'status': 'active',
    },
    // Strength & Agility Session (High School Athlete)
    {
      'docId': 'strength_agility_hs',
      'name': 'Strength & Agility (High School Athlete)',
      'category': 'Strength & Agility Session (High School Athlete)',
      'sessions': 1,
      'price': 25.0,
      'description': 'Strength and agility session for high school athletes',
      'status': 'active',
    },
    // Strength & Agility Session (Kids)
    {
      'docId': 'strength_agility_kids',
      'name': 'Strength & Agility (Kids)',
      'category': 'Strength & Agility Session (Kids)',
      'sessions': 1,
      'price': 25.0,
      'description': 'Strength and agility session for kids',
      'status': 'active',
    },
    // Athletic Performance (Adult)
    {
      'docId': 'athletic_adult',
      'name': 'Athletic Performance (Adult)',
      'category': 'Athletic Performance (Adult)',
      'sessions': 1,
      'price': 25.0,
      'description': 'Athletic performance session for adults',
      'status': 'active',
    },
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
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

      _navigateToPaymentPage(plan);
    } catch (e) {
      print('Error initiating purchase: $e');
      _showSnackBar('Error initiating purchase: $e', Colors.red);
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

        await Future.delayed(const Duration(milliseconds: 500));

        await _loadPurchasedPlans();
        await _loadMyActivePlans();
        print('Plan "$planName" cancelled, refreshed purchased and active plans');
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

      await Future.delayed(const Duration(milliseconds: 500));

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
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadPurchasedPlans();
                    await _loadMyActivePlans();
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Group and sort plans
                      ...(() {
                        final Map<String, List<Map<String, dynamic>>> groupedPlans = {};
                        for (final plan in _allPlans) {
                          final category = plan['category'] as String;
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
                        // Define the desired category order
                        const categoryOrder = [
                          'Semi Private Monthly Plans',
                          'Semi Private Bi Weekly Plans',
                          'Semi Private Day Pass',
                          'Group Training or Class',
                          'Strength & Agility Session (High School Athlete)',
                          'Strength & Agility Session (Kids)',
                          'Athletic Performance (Adult)',
                        ];
                        // Sort categories based on the order
                        final sortedCategories = groupedPlans.keys.toList()
                          ..sort((a, b) {
                            final indexA = categoryOrder.indexOf(a);
                            final indexB = categoryOrder.indexOf(b);
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
                  ),
                ),
    );
  }
}

// Square Payment Page (WebView-based)
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
        _errorMessage = 'Error starting checkout: $e';
        _isProcessingPayment = false;
      });
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