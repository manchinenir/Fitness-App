import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

/// (Optional) old in-app WebView launcher, now unused if you only use external browser
class SquareWebCheckout extends StatefulWidget {
  const SquareWebCheckout({
    super.key,
    required this.amountCents,
    required this.appId,
    required this.locationId,
    required this.functionsBaseUrl, // e.g. https://us-central1-<project>.cloudfunctions.net/api
    this.production = false,
    this.planName = "Training Plan",
    this.firstName,
    this.lastName,
    this.email,
    this.referenceId,
  });

  final int amountCents;
  final String appId;
  final String locationId;
  final String functionsBaseUrl;
  final bool production;

  final String planName;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? referenceId;

  @override
  State<SquareWebCheckout> createState() => _SquareWebCheckoutState();
}

class _SquareWebCheckoutState extends State<SquareWebCheckout> {
  String get _checkoutUrl {
    final env = widget.production ? 'production' : 'sandbox';
    final params = {
      'amountCents': widget.amountCents.toString(),
      'appId': widget.appId,
      'locationId': widget.locationId,
      'env': env,
      'apiUrl': '${widget.functionsBaseUrl}/process-payment',
      'planName': widget.planName,
      if (widget.firstName != null) 'firstName': widget.firstName!,
      if (widget.lastName != null) 'lastName': widget.lastName!,
      if (widget.email != null) 'email': widget.email!,
      if (widget.referenceId != null) 'ref': widget.referenceId!,
    };

    final qp = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '${widget.functionsBaseUrl}/checkout?$qp';
  }

  @override
  void initState() {
    super.initState();
    _launchExternal();
  }

  Future<void> _launchExternal() async {
    final uri = Uri.parse(_checkoutUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    // After handing off to the browser, just return to the previous screen.
    if (mounted) Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    // Simple placeholder while the browser opens
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Payment page used by your client plans screen
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

  String _buildCheckoutUrl({
    required int amountCents,
    required String planName,
    String? firstName,
    String? lastName,
    String? email,
    String? referenceId,
  }) {
    const base =
        'https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api';

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    final sessions = (widget.plan['sessions'] as int?) ?? 0;
    final price = (widget.plan['price'] ?? 0).toDouble();
    final category = (widget.plan['category'] as String?) ?? '';
    final description = (widget.plan['description'] as String?) ?? '';
    final planId = (widget.plan['docId'] ?? '').toString();

    final params = {
      'amountCents': amountCents.toString(),
      'appId': widget.squareApplicationId,
      'locationId': widget.squareLocationId,
      'env': 'production',
      'apiUrl': '$base/process-payment',
      'planName': planName,
      'userId': uid,
      'planId': planId,
      'sessions': sessions.toString(),
      'priceDollars': price.toStringAsFixed(2),
      'planCategory': category,
      'planDescription': description,
      if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
      if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
      if (email != null && email.isNotEmpty) 'email': email,
      if (referenceId != null && referenceId.isNotEmpty) 'ref': referenceId,
    };

    final qp = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$base/checkout?$qp';
  }

  Future<void> _openWebCheckout() async {
    setState(() {
      _isProcessingPayment = true;
      _errorMessage = null;
    });

    try {
      final double price = (widget.plan['price'] ?? 0).toDouble();
      final int amountCents = (price * 100).round();

      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'anon';
      final email = user?.email ?? '';

      String firstName = '', lastName = '';
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final name = (doc.data()?['name'] as String?)?.trim() ??
            (user?.displayName ?? '').trim();
        if (name.isNotEmpty) {
          final parts = name.split(RegExp(r'\s+'));
          firstName = parts.first;
          if (parts.length > 1) lastName = parts.sublist(1).join(' ');
        }
      } catch (_) {}

      // Short reference (<= 40 chars)
      final planId = (widget.plan['docId'] ?? 'plan').toString();
      final refId = [
        uid.length >= 8 ? uid.substring(0, 8) : uid,
        planId.length >= 8 ? planId.substring(0, 8) : planId,
        DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      ].join('-');

      final url = _buildCheckoutUrl(
        amountCents: amountCents,
        planName: (widget.plan['name'] as String?) ?? 'Training Plan',
        firstName: firstName,
        lastName: lastName,
        email: email,
        referenceId: refId,
      );

      // ✅ Always open in system browser now
      final ok =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) {
        throw 'Could not launch checkout';
      }

      if (!mounted) return;
      setState(() => _isProcessingPayment = false);

      // Backend writes client_purchases; UI updates via streams.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error starting checkout';
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
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueAccent.withOpacity(0.1),
                      Colors.white
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.fitness_center,
                            color: Colors.blueAccent, size: 28),
                        SizedBox(width: 12),
                        Text('Plan Summary',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(planName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$sessions Sessions',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[600])),
                        Text('\$${planPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Payment Method',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.credit_card, color: Colors.blue),
                ),
                title: const Text('Credit/Debit Card',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Secure payment via Square'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _isProcessingPayment ? null : _openWebCheckout,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  border:
                      Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_errorMessage!,
                            style:
                                const TextStyle(color: Colors.red))),
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
                    borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('Processing Payment...',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold))
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
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Pay \$${planPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            const SizedBox(height: 16),
            const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.security, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Text('Secured by Square',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
