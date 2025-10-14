import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';

import 'square_checkout.dart';
import 'invoice_review_page.dart';
import 'pdf_workouts_tab.dart';
import 'package:intl/intl.dart';

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
  String? _errorMessage;

  final Set<String> _purchasedKeys = {};
  final Set<String> _completedKeys = {};
  final Set<String> _cancelledKeys = {};
  List<Map<String, dynamic>> _myActivePlans = [];

  // Real-time listeners
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
    _setupRealTimeListeners();

    // Auto-refresh every hour to catch completed sessions
    Timer.periodic(const Duration(hours: 1), (timer) {
      if (mounted) _refreshSessionCounts();
    });

    // Also refresh when the first frame is done
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshSessionCounts();
    });
  }

  @override
  void dispose() {
    _sessionsSubscription?.cancel();
    _purchasesSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ----- Initial load & listeners -----
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
      setState(() => _errorMessage = 'Error loading data');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _setupRealTimeListeners() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _sessionsSubscription = _firestore
        .collection('trainer_slots')
        .where('booked_by', arrayContains: userId)
        .snapshots()
        .listen((_) {
      if (mounted) _refreshSessionCounts();
    });

    _purchasesSubscription = _firestore
        .collection('client_purchases')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((_) async {
      if (mounted) {
        await _loadPurchasedPlans();
        await _loadMyActivePlans();
      }
    });
  }

  // ----- Data loads -----
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
      // ignore
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
        final data = doc.data();
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
      // ignore
    }
  }

  // ----- Purchase Flow -----
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
        _showSnackBar(
          'You currently have an active plan of this type. Complete all sessions first.',
          Colors.orange,
        );
        return;
      }
      _navigateToPaymentPage(plan);
    } catch (e) {
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
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Cancel plan -----
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
          'completedDate': FieldValue.delete(),
        });

        await Future.delayed(const Duration(milliseconds: 500));

        await _loadPurchasedPlans();
        await _loadMyActivePlans();

        _showSnackBar('Plan "$planName" cancelled successfully!', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error cancelling plan', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ----- Helpers -----
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

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Fitness Plans',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1C2D5E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        // PDF button removed per request
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.fitness_center), text: 'Plans'),
            Tab(icon: Icon(Icons.picture_as_pdf), text: 'PDF Workouts'),
          ],
        ),
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
                        physics: AlwaysScrollableScrollPhysics(),
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
                            groupedPlans.putIfAbsent(category, () => []);
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

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 80, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Error Loading Data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _initializeData, child: const Text('Retry')),
          ],
        ),
      ),
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
                child: const Icon(Icons.fitness_center, color: Colors.blueAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    Text(
                      '$planCount session plan${planCount != 1 ? 's' : ''} available',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
    final isCompleted = _completedKeys.contains(key);
    final isActive = status == 'active';

    bool isCancelled = false;
    String? purchaseDocId;
    int? remainingSessions;

    if (isPurchased) {
      final purchases = _myActivePlans.where(
        (p) => p['planName'] == planName && p['planId'] == planId,
      ).toList();

      if (purchases.isNotEmpty) {
        final purchase = purchases.first;
        purchaseDocId = purchase['docId'];
        remainingSessions = purchase['remainingSessions'] as int? ?? 0;
        final currentStatus = purchase['status'] as String? ?? 'active';
        isCancelled = currentStatus == 'cancelled';
      }
    } else {
      isCancelled = _cancelledKeys.contains(key);
    }

    // Status chip
    Widget statusWidget;
    if (isPurchased && remainingSessions != null) {
      final totalSessions = sessions;
      final usedSessions = totalSessions - remainingSessions;

      if (isCancelled || remainingSessions <= 0) {
        statusWidget = _chip('Inactive', Colors.grey);
      } else {
        statusWidget = _chip('Active ($usedSessions/$totalSessions completed)', Colors.green);
      }
    } else if (isCancelled || isCompleted) {
      statusWidget = _chip('Inactive', Colors.grey);
    } else {
      statusWidget = _chip('Inactive', Colors.grey);
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
                // top row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    ]),
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

                // Buttons
                if (isPurchased && purchaseDocId != null && (remainingSessions ?? 0) > 0 && !isCancelled)
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
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  )
                else if (!isPurchased || isCancelled || isCompleted)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          (!isActive || _isLoading || _isProcessingPayment) ? null : () => _purchasePlan(plan),
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
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive ? Colors.blueAccent : Colors.grey[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text(
                        'Plan Completed',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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

  Future<void> _refreshSessionCounts() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final now = DateTime.now().toUtc();

      final purchasesSnapshot = await _firestore
          .collection('client_purchases')
          .where('userId', isEqualTo: userId)
          .get();

      final slotsSnapshot = await _firestore
          .collection('trainer_slots')
          .where('booked_by', arrayContains: userId)
          .get();

      final batch = _firestore.batch();
      bool hasUpdates = false;

      for (final purchaseDoc in purchasesSnapshot.docs) {
        final purchaseData = purchaseDoc.data();
        final planName = purchaseData['planName'] as String?;
        final planId = purchaseData['planId'] as String?;
        final totalSessions = purchaseData['totalSessions'] as int? ?? 0;
        final status = purchaseData['status'] as String? ?? 'active';

        if (status == 'cancelled' || status == 'completed') continue;
        if (planName == null || planId == null) continue;

        final currentBookedSessionsInDB = purchaseData['bookedSessions'] as int? ?? 0;

        int completedSessionsInThisPurchase = 0;

        for (final slotDoc in slotsSnapshot.docs) {
          try {
            final slotData = slotDoc.data();
            final slotDate = (slotData['date'] as Timestamp).toDate().toUtc();
            final slotTime = slotData['time'] as String? ?? '';

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
              } catch (_) {}
            }

            final slotPurchaseIds = List<String>.from(slotData['purchase_ids'] ?? []);
            final userPurchaseMap = Map<String, dynamic>.from(slotData['user_purchase_map'] ?? {});
            final belongsToThisPurchase =
                slotPurchaseIds.contains(purchaseDoc.id) || userPurchaseMap[userId] == purchaseDoc.id;

            if (belongsToThisPurchase) {
              final statusByUser = Map<String, dynamic>.from(slotData['status_by_user'] ?? {});
              final userSlotStatus = statusByUser[userId] as String?;
              final isCancelled = userSlotStatus == 'Cancelled';
              final isCompleted = userSlotStatus == 'Completed';

              if (!isCancelled) {
                if (isCompleted || slotEndTime.isBefore(now)) {
                  completedSessionsInThisPurchase++;
                }
              }
            }
          } catch (_) {}
        }

        final remainingSessions = totalSessions - completedSessionsInThisPurchase;
        final newStatus = (completedSessionsInThisPurchase >= totalSessions) ? 'completed' : 'active';
        final isActive = newStatus == 'active';

        final currentUsed = purchaseData['usedSessions'] as int? ?? 0;
        final currentRemaining = purchaseData['remainingSessions'] as int? ?? totalSessions;
        final currentStatus = purchaseData['status'] as String? ?? 'active';
        final currentIsActive = purchaseData['isActive'] as bool? ?? true;

        final needsUpdate = currentUsed != completedSessionsInThisPurchase ||
            currentRemaining != remainingSessions ||
            currentStatus != newStatus ||
            currentIsActive != isActive;

        if (needsUpdate) {
          hasUpdates = true;
          final updateData = {
            'usedSessions': completedSessionsInThisPurchase,
            'remainingSessions': remainingSessions,
            'availableSessions': totalSessions - currentBookedSessionsInDB,
            'isActive': isActive,
            'status': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          };

          if (newStatus == 'completed') {
            updateData['completedDate'] = FieldValue.serverTimestamp();
          } else {
            updateData['completedDate'] = FieldValue.delete();
          }

          batch.update(purchaseDoc.reference, updateData);
        }
      }

      if (hasUpdates) {
        await batch.commit();
        await _loadPurchasedPlans();
        await _loadMyActivePlans();
      }
    } catch (e) {
      // ignore
    }
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
