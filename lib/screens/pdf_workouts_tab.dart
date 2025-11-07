import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// import 'invoice_review_page.dart'; // 👈 removed
import 'square_checkout.dart';

class PDFWorkoutsTab extends StatefulWidget {
  const PDFWorkoutsTab({super.key});

  @override
  State<PDFWorkoutsTab> createState() => _PDFWorkoutsTabState();
}

class _PDFWorkoutsTabState extends State<PDFWorkoutsTab> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  bool _isLoading = true;
  List<Map<String, dynamic>> _pdfWorkouts = [];
  bool _hasActiveSubscription = false;
  DateTime? _subscriptionEndDate;
  bool _isCheckingSubscription = true;
  bool _isProcessingPayment = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pdfWorkoutsSubscription;

  // Square payment configuration (same as plans screen)
  static const String _squareApplicationId = 'sq0idp-agy7z_bYdVWuflGeopSwCw';
  static const String _squareLocationId = 'L8S08PC1N6RPJ';

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
    _setupPDFWorkoutsListener();
  }

  @override
  void dispose() {
    _pdfWorkoutsSubscription?.cancel();
    super.dispose();
  }

  // ---------- Time helpers (store local time strings for clarity) ----------
  DateTime _getCurrentLocalTime() => DateTime.now().toLocal();
  DateTime _addDaysToLocalTime(DateTime startDate, int days) => startDate.add(Duration(days: days));
  String _convertToLocalTimeString(DateTime dateTime) => dateTime.toIso8601String();
  DateTime _convertStringToLocalDateTime(String dateString) => DateTime.parse(dateString).toLocal();

  // ---------- User profile (for subscription metadata) ----------
  Future<Map<String, String>> _getCurrentUserProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return {'name': '', 'email': ''};

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final name = (data['name'] ?? '').toString();
      final email = (data['email'] ?? _auth.currentUser?.email ?? '').toString();
      return {'name': name, 'email': email};
    } catch (_) {
      return {'name': '', 'email': _auth.currentUser?.email ?? ''};
    }
  }

  // ---------- Subscription status ----------
  Future<void> _checkSubscriptionStatus() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final subscriptionSnapshot = await _firestore
          .collection('client_subscriptions')
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .where('type', isEqualTo: 'pdf') // 👈 pdf-only
          .get();

      if (subscriptionSnapshot.docs.isNotEmpty) {
        final subscription = subscriptionSnapshot.docs.first.data();

        DateTime endDate;
        if (subscription['endDate'] is String) {
          endDate = _convertStringToLocalDateTime(subscription['endDate'] as String);
        } else if (subscription['endDate'] is Timestamp) {
          endDate = (subscription['endDate'] as Timestamp).toDate().toLocal();
        } else {
          throw Exception('Invalid endDate format');
        }

        final currentLocalTime = _getCurrentLocalTime();

        setState(() {
          _hasActiveSubscription = currentLocalTime.isBefore(endDate);
          _subscriptionEndDate = endDate;
        });
      } else {
        setState(() {
          _hasActiveSubscription = false;
          _subscriptionEndDate = null;
        });
      }
    } catch (e) {
      setState(() {
        _hasActiveSubscription = false;
        _subscriptionEndDate = null;
      });
    } finally {
      setState(() {
        _isCheckingSubscription = false;
      });
    }
  }

  // ---------- Realtime listener for pdf_workouts ----------
  void _setupPDFWorkoutsListener() {
    _pdfWorkoutsSubscription = _firestore
        .collection('pdf_workouts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (!mounted) return;
      setState(() {
        _pdfWorkouts = snapshot.docs.map((doc) {
          final data = doc.data();
          data['docId'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    }, onError: (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    });
  }

  // ---------- Subscription flow ----------
  void _showSubscriptionRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.orange),
              SizedBox(width: 8),
              Text('Subscription Required'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Access to PDF workouts requires an active subscription.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (_subscriptionEndDate != null && !_hasActiveSubscription)
                Text(
                  'Your subscription expired on ${_formatDisplayDate(_subscriptionEndDate)}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Maybe Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToSubscriptionPayment();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Subscribe Now'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _navigateToSubscriptionPayment() async {
    final subscriptionPlan = {
      'docId': 'pdf_subscription_monthly',
      'name': 'PDF Workouts Monthly Subscription',
      'category': 'PDF Access',
      'sessions': 1,
      'price': 9.99,
      'description': 'Unlimited access to all PDF workouts for 30 days',
      'type': 'subscription',
    };

    setState(() => _isProcessingPayment = true);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriptionPaymentPage(
          plan: subscriptionPlan,
          squareApplicationId: _squareApplicationId,
          squareLocationId: _squareLocationId,
        ),
      ),
    );

    // 🔁 When user returns from browser, check backend state
    await _checkSubscriptionStatus();

    setState(() => _isProcessingPayment = false);
  }

  Future<void> _completeSubscriptionPurchase() async {
    try {
      setState(() => _isLoading = true);

      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final now = _getCurrentLocalTime();
      final endDate = _addDaysToLocalTime(now, 30); // 30-day subscription

      // fetch user profile for metadata
      final profile = await _getCurrentUserProfile();
      final userName = profile['name'] ?? '';
      final userEmail = profile['email'] ?? '';

      // write to client_subscriptions
      final subRef = await _firestore.collection('client_subscriptions').add({
        'userId': userId,
        'userName': userName,
        'userEmail': userEmail,
        'planName': 'PDF Workouts Monthly Subscription',
        'price': 9.99,
        'purchaseDate': _convertToLocalTimeString(now),
        'startDate': _convertToLocalTimeString(now),
        'endDate': _convertToLocalTimeString(endDate),
        'isActive': true,
        'status': 'active',
        'paymentMethod': 'square',
        'paymentStatus': 'completed',
        'timezone': 'Local/Device',
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'pdf',
        'isPdf': true,
      });

      // mirror to pdf_subscribers (for admin listing)
      await _firestore.collection('pdf_subscribers').doc(subRef.id).set({
        'userId': userId,
        'userName': userName,
        'userEmail': userEmail,
        'startDate': _convertToLocalTimeString(now),
        'endDate': _convertToLocalTimeString(endDate),
        'isActive': true,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _checkSubscriptionStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subscription activated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error activating subscription: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ---------- Storage helper (optional) ----------
  Future<String> _getPDFDownloadUrl(String pdfPath) async {
    try {
      final ref = _storage.ref().child(pdfPath);
      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception('Could not load PDF: $e');
    }
  }

  // ---------- Open viewer ----------
  void _showPDFViewer(Map<String, dynamic> pdfWorkout) {
    if (!_hasActiveSubscription) {
      _showSubscriptionRequiredDialog();
      return;
    }

    final pdfUrl = pdfWorkout['pdfUrl'];
    if (pdfUrl == null || pdfUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF URL not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Prevent screenshots/recording UI exposure (immersive mode)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PDFViewerScreen(
          pdfWorkout: pdfWorkout,
          subscriptionEndDate: _subscriptionEndDate,
        ),
      ),
    );
  }

  // ---------- UI ----------
  Widget _buildPDFWorkoutCard(Map<String, dynamic> pdfWorkout, int index) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.grey[50]!, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _hasActiveSubscription ? Colors.red[50] : Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.picture_as_pdf,
              color: _hasActiveSubscription ? Colors.red : Colors.grey,
              size: 28,
            ),
          ),
          title: Text(
            pdfWorkout['name'] ?? 'Workout',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _hasActiveSubscription ? Colors.black : Colors.grey,
            ),
          ),
          subtitle: (pdfWorkout['description'] != null)
              ? Text(
                  pdfWorkout['description'],
                  style: TextStyle(
                    color: _hasActiveSubscription ? Colors.grey : Colors.grey[400],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _hasActiveSubscription ? Colors.green[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hasActiveSubscription ? Colors.green : Colors.orange,
              ),
            ),
            child: Text(
              _hasActiveSubscription ? 'Subscribed' : 'Subscribe',
              style: TextStyle(
                color: _hasActiveSubscription ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          onTap: () => _showPDFViewer(pdfWorkout),
        ),
      ),
    );
  }

  Widget _buildSubscriptionBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange[400]!, Colors.orange[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.star, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasActiveSubscription ? 'Active Subscription' : 'Premium PDF Access',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hasActiveSubscription
                      ? 'Valid until ${_formatDisplayDate(_subscriptionEndDate)}'
                      : 'Subscribe to access all PDF workouts',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (_hasActiveSubscription)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Active',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else
            ElevatedButton(
              onPressed: _isProcessingPayment ? null : _navigateToSubscriptionPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isProcessingPayment
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Subscribe',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
        ],
      ),
    );
  }

  String _formatDisplayDate(DateTime? date) {
    if (date == null) return 'N/A';
    final month = _getMonthName(date.month);
    return '$month ${date.day}, ${date.year}';
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSubscription || _isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading PDF workouts...'),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSubscriptionBanner(),
          Expanded(
            child: _pdfWorkouts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.picture_as_pdf,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No PDF Workouts Available',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hasActiveSubscription
                              ? 'Check back later for new workouts'
                              : 'Subscribe to access PDF workouts',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _pdfWorkouts.length,
                    itemBuilder: (context, index) {
                      return _buildPDFWorkoutCard(_pdfWorkouts[index], index);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ================= PDF Viewer =================

class PDFViewerScreen extends StatefulWidget {
  final Map<String, dynamic> pdfWorkout;
  final DateTime? subscriptionEndDate;

  const PDFViewerScreen({
    super.key,
    required this.pdfWorkout,
    required this.subscriptionEndDate,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  bool _isLoading = true;
  String? _pdfPath; // local file path after download
  String? _errorMessage;
  PDFViewController? _pdfViewController;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _pdfReady = false;

  @override
  void initState() {
    super.initState();
    _downloadPDFToLocalAndOpen();
  }

  @override
  void dispose() {
    _pdfViewController?.dispose();
    // Restore system UI mode when screen is disposed
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _downloadPDFToLocalAndOpen() async {
    try {
      final pdfUrl = widget.pdfWorkout['pdfUrl'];
      if (pdfUrl == null || pdfUrl.isEmpty) {
        throw Exception('PDF URL not found or empty');
      }
      if (!pdfUrl.startsWith('http')) {
        throw Exception('Invalid PDF URL format');
      }

      final response = await http.get(Uri.parse(pdfUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch PDF (status ${response.statusCode})');
      }

      final dir = await getTemporaryDirectory();
      final safeName = (widget.pdfWorkout['name'] ?? 'workout').toString().replaceAll(RegExp(r'[^\w\-\.\ ]'), '_');
      final file = File("${dir.path}/$safeName.pdf");
      await file.writeAsBytes(response.bodyBytes, flush: true);

      setState(() {
        _pdfPath = file.path; // Use local file path for crisp rendering
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load PDF: $e';
        _isLoading = false;
      });
    }
  }

  Widget _buildPDFContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading PDF...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error Loading PDF',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500]),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _downloadPDFToLocalAndOpen,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_pdfPath != null) {
      return Stack(
        children: [
          PDFView(
            filePath: _pdfPath,
            autoSpacing: true,
            enableSwipe: true,
            pageSnap: true,
            swipeHorizontal: false,
            nightMode: false,
            fitPolicy: FitPolicy.BOTH, // Fit page; avoids blur on scaling
            onError: (error) {
              setState(() {
                _errorMessage = 'Error displaying PDF: $error';
              });
            },
            onRender: (_pages) {
              setState(() {
                _totalPages = _pages ?? 0;
                _pdfReady = true;
              });
            },
            onViewCreated: (PDFViewController controller) {
              setState(() {
                _pdfViewController = controller;
              });
            },
            onPageChanged: (int? page, int? total) {
              setState(() {
                _currentPage = page ?? 0;
                _totalPages = total ?? 0;
              });
            },
            onPageError: (int? page, dynamic error) {
              setState(() {
                _errorMessage = 'Error on page $page: $error';
              });
            },
          ),
          if (_pdfReady && _totalPages > 0)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Container(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2D5E).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentPage + 1}/$_totalPages',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return const Center(child: Text('PDF not available'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pdfWorkout['name'] ?? 'Workout',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: _buildPDFContent(),
    );
  }
}

// ================= Subscription Payment Page =================

class SubscriptionPaymentPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final String squareApplicationId;
  final String squareLocationId;

  const SubscriptionPaymentPage({
    super.key,
    required this.plan,
    required this.squareApplicationId,
    required this.squareLocationId,
  });

  @override
  State<SubscriptionPaymentPage> createState() =>
      _SubscriptionPaymentPageState();
}

class _SubscriptionPaymentPageState extends State<SubscriptionPaymentPage> {
  bool _isProcessingPayment = false;
  String? _errorMessage;

  static const String _apiBase =
      'https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api';

  /// Build the same Square checkout URL as plans (card details page in HTML)
  String _buildSubscriptionCheckoutUrl({
    required int amountCents,
    required String planName,
    String? firstName,
    String? lastName,
    String? email,
    String? userId, // 👈 add this
  }) {
    const env = 'production';

    final double price = (widget.plan['price'] ?? 0).toDouble();

    final params = <String, String>{
      'amountCents': amountCents.toString(),
      'appId': widget.squareApplicationId,
      'locationId': widget.squareLocationId,
      'env': env,
      'apiUrl': '$_apiBase/process-payment',
      'planName': planName,

      // ✅ send userId so backend can attach to correct user
      if (userId != null && userId.isNotEmpty) 'userId': userId,

      'planId': widget.plan['docId'] ?? 'pdf_subscription_monthly',
      'planCategory': widget.plan['category'] ?? 'PDF Access',
      'sessions': '1',
      'priceDollars': price.toStringAsFixed(2),
      'planDescription':
          widget.plan['description'] as String? ??
          'Unlimited access to all PDF workouts for 30 days',

      'type': 'pdf',
      'isPdf': 'true',

      if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
      if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
      if (email != null && email.isNotEmpty) 'email': email,
    };

    final qp = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '$_apiBase/checkout?$qp';
  }

  Future<void> _openWebCheckout() async {
    setState(() {
      _isProcessingPayment = true;
      _errorMessage = null;
    });

    try {
      final double price = (widget.plan['price'] ?? 0).toDouble();
      final int amountCents = (price * 100).round();

      // Get user info for prefill
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? ''; // 👈 this is what we need
      String email = user?.email ?? '';
      String firstName = '';
      String lastName = '';

      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = doc.data();

        final fullName = (data?['name'] as String?)?.trim() ??
            (user?.displayName ?? '').trim();
        if (fullName.isNotEmpty) {
          final parts = fullName.split(RegExp(r'\s+'));
          firstName = parts.first;
          if (parts.length > 1) {
            lastName = parts.sublist(1).join(' ');
          }
        }

        final docEmail = (data?['email'] as String?)?.trim();
        if (docEmail != null && docEmail.isNotEmpty) {
          email = docEmail;
        }
      } catch (_) {
        // ignore profile errors
      }

      final url = _buildSubscriptionCheckoutUrl(
        amountCents: amountCents,
        planName: widget.plan['name'] as String? ??
            'PDF Workouts Monthly Subscription',
        firstName: firstName,
        lastName: lastName,
        email: email,
        userId: uid, // ✅ send to checkout.html
      );

      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        throw 'Could not launch checkout';
      }

      if (!mounted) return;
      setState(() => _isProcessingPayment = false);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Complete the payment in your browser, then return to the app.',
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error starting checkout: $e';
        _isProcessingPayment = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final planPrice = (widget.plan['price'] ?? 0).toDouble();
    final planName =
        widget.plan['name'] as String? ?? 'PDF Subscription';
    final description = widget.plan['description'] as String? ??
        'Monthly access to PDF workouts';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Subscription Payment',
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
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        Icon(Icons.picture_as_pdf,
                            color: Colors.blueAccent, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Subscription Summary',
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
                    Text(
                      description,
                      style:
                          TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Monthly Access',
                          style:
                              TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        Text(
                          '\$${planPrice.toStringAsFixed(2)}/month',
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                subtitle: const Text(
                    'Secure payment via Square (opens in browser)'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _isProcessingPayment ? null : _openWebCheckout,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
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
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                  ),
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
                  onPressed: _openWebCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Subscribe \$${planPrice.toStringAsFixed(2)}/month',
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
                    style: TextStyle(color: Colors.grey, fontSize: 12),
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
