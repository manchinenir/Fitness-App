import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'square_checkout.dart';
import 'invoice_review_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

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

  // Square payment configuration (same as plans screen)
  static const String _squareApplicationId = 'sandbox-sq0idb-b_5NuSv1kYCZWkITbVqS4w';
  static const String _squareLocationId = 'LPSE4AB75KF7G';

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
    _loadPDFWorkouts();
  }

  DateTime _getCurrentLocalTime() {
    return DateTime.now().toLocal();
  }

  DateTime _addDaysToLocalTime(DateTime startDate, int days) {
    return startDate.add(Duration(days: days));
  }

  // Convert DateTime to Firestore format while preserving local time as ISO string
  String _convertToLocalTimeString(DateTime dateTime) {
    return dateTime.toIso8601String(); // This preserves the local time
  }

  // Helper method to convert stored string back to local DateTime
  DateTime _convertStringToLocalDateTime(String dateString) {
    return DateTime.parse(dateString).toLocal();
  }

  Future<void> _checkSubscriptionStatus() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final subscriptionSnapshot = await _firestore
          .collection('client_subscriptions')
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .get();

      if (subscriptionSnapshot.docs.isNotEmpty) {
        final subscription = subscriptionSnapshot.docs.first.data();
        
        // Handle both string and timestamp formats for backward compatibility
        DateTime endDate;
        if (subscription['endDate'] is String) {
          // New format: stored as local time string
          endDate = _convertStringToLocalDateTime(subscription['endDate'] as String);
        } else if (subscription['endDate'] is Timestamp) {
          // Old format: timestamp (UTC) - convert to local
          endDate = (subscription['endDate'] as Timestamp).toDate().toLocal();
        } else {
          throw Exception('Invalid endDate format');
        }
        
        // Get current local time for comparison
        final currentLocalTime = _getCurrentLocalTime();
        
        setState(() {
          _hasActiveSubscription = currentLocalTime.isBefore(endDate);
          _subscriptionEndDate = endDate;
        });
        
        print('Subscription check:');
        print('Current local time: $currentLocalTime');
        print('Subscription end date: $endDate');
        print('Is active: ${currentLocalTime.isBefore(endDate)}');
      } else {
        setState(() {
          _hasActiveSubscription = false;
          _subscriptionEndDate = null;
        });
      }
    } catch (e) {
      print('Error checking subscription: $e');
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

  Future<void> _loadPDFWorkouts() async {
    try {
      final snapshot = await _firestore
          .collection('pdf_workouts')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _pdfWorkouts = snapshot.docs.map((doc) {
          final data = doc.data();
          data['docId'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading PDF workouts: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

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
    // Create a subscription plan object similar to fitness plans
    final subscriptionPlan = {
      'docId': 'pdf_subscription_monthly',
      'name': 'PDF Workouts Monthly Subscription',
      'category': 'PDF Access',
      'sessions': 1, // This represents 1 month access
      'price': 29.99, // Monthly subscription price
      'description': 'Unlimited access to all PDF workouts for 30 days',
      'type': 'subscription'
    };

    setState(() => _isProcessingPayment = true);
    
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriptionPaymentPage(
          plan: subscriptionPlan,
          squareApplicationId: _squareApplicationId,
          squareLocationId: _squareLocationId,
        ),
      ),
    );

    if (result == true) {
      await _completeSubscriptionPurchase();
    }
    setState(() => _isProcessingPayment = false);
  }

  Future<void> _completeSubscriptionPurchase() async {
    try {
      setState(() => _isLoading = true);

      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // Use local time for subscription dates
      final now = _getCurrentLocalTime();
      final endDate = _addDaysToLocalTime(now, 30); // 30-day subscription

      await _firestore.collection('client_subscriptions').add({
        'userId': userId,
        'planName': 'PDF Workouts Monthly Subscription',
        'price': 29.99,
        'purchaseDate': _convertToLocalTimeString(now), // Save as local time string
        'startDate': _convertToLocalTimeString(now), // Save as local time string
        'endDate': _convertToLocalTimeString(endDate), // Save as local time string
        'isActive': true,
        'status': 'active',
        'paymentMethod': 'square',
        'paymentStatus': 'completed',
        'timezone': 'Local/Device', // Track that we're using local time
        'createdAt': FieldValue.serverTimestamp(), // Server timestamp for ordering
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
      
      print('Subscription created:');
      print('Start date (local): $now');
      print('End date (local): $endDate');
    } catch (e) {
      print('Error completing subscription purchase: $e');
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

  Future<String> _getPDFDownloadUrl(String pdfPath) async {
    try {
      final ref = _storage.ref().child(pdfPath);
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error getting PDF download URL: $e');
      throw Exception('Could not load PDF: $e');
    }
  }

  void _showPDFViewer(Map<String, dynamic> pdfWorkout) {
    if (!_hasActiveSubscription) {
      _showSubscriptionRequiredDialog();
      return;
    }

    // Check if PDF URL exists before opening viewer
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

    // Prevent screenshots and recording
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

  Widget _buildPDFWorkoutCard(Map<String, dynamic> pdfWorkout, int index) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              Colors.grey[50]!,
              Colors.white,
            ],
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
            pdfWorkout['name'],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _hasActiveSubscription ? Colors.black : Colors.grey,
            ),
          ),
          subtitle: pdfWorkout['description'] != null
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
          colors: [
            Colors.orange[400]!,
            Colors.orange[600]!,
          ],
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
    
    // Format as "Month Day, Year" (e.g., "December 25, 2024")
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

// PDF Viewer Screen - SIMPLIFIED VERSION
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
  String? _pdfUrl;
  String? _errorMessage;
  PDFViewController? _pdfViewController;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _pdfReady = false;

  @override
  void initState() {
    super.initState();
    _loadPDF();
  }

  @override
  void dispose() {
    _pdfViewController?.dispose();
    // Restore system UI mode when screen is disposed
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadPDF() async {
    try {
      final pdfUrl = widget.pdfWorkout['pdfUrl'];

      if (pdfUrl == null || pdfUrl.isEmpty) {
        throw Exception('PDF URL not found or empty');
      }

      if (!pdfUrl.startsWith('http')) {
        throw Exception('Invalid PDF URL format');
      }

      // Download PDF file to temporary directory
      final response = await http.get(Uri.parse(pdfUrl));
      final bytes = response.bodyBytes;

      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/${widget.pdfWorkout['name']}.pdf");

      await file.writeAsBytes(bytes, flush: true);

      setState(() {
        _pdfUrl = file.path; // ✅ Use local file path here
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading PDF: $e');
      setState(() {
        _errorMessage = 'Failed to load PDF: ${e.toString()}';
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
              onPressed: _loadPDF,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_pdfUrl != null) {
      return Stack(
        children: [
          PDFView(
            filePath: _pdfUrl,
            autoSpacing: true,
            enableSwipe: true,
            pageSnap: true,
            swipeHorizontal: false,
            nightMode: false,
            fitPolicy: FitPolicy.BOTH, // ✅ Fit PDF to screen
            onError: (error) {
              print('PDF Error: $error');
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
          
          // Page number indicator at the bottom
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
                    color: const Color(0xFF1C2D5E).withOpacity(0.8), // ✅ Changed to match UI color
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

    return const Center(
      child: Text('PDF not available'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pdfWorkout['name'],
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

// Subscription Payment Page (same as before)
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
  State<SubscriptionPaymentPage> createState() => _SubscriptionPaymentPageState();
}

class _SubscriptionPaymentPageState extends State<SubscriptionPaymentPage> {
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
        _errorMessage = 'Error starting checkout: $e';
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
    final planName = widget.plan['name'] as String? ?? 'PDF Subscription';
    final description = widget.plan['description'] as String? ?? 'Monthly access to PDF workouts';

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
                        Icon(Icons.picture_as_pdf, color: Colors.blueAccent, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Subscription Summary',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(planName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(description, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Monthly Access', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        Text('\$${planPrice.toStringAsFixed(2)}/month',
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
                    'Subscribe \$${planPrice.toStringAsFixed(2)}/month',
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