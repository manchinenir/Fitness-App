import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:square_in_app_payments/in_app_payments.dart';
import 'package:square_in_app_payments/models.dart';
import 'package:url_launcher/url_launcher.dart';

/// Simple Apple Pay badge: " Pay"
class ApplePayBadge extends StatelessWidget {
  final double fontSize;
  final EdgeInsets padding;

  const ApplePayBadge({
    super.key,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.black,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '\uF8FF', // Apple logo
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: fontSize,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Pay',
            style: TextStyle(
              fontSize: fontSize,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple chip UI
class InfoChip extends StatelessWidget {
  final String label;

  const InfoChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Main Square checkout screen: Card (web) + Apple Pay (native)
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
  bool _applePayAvailable = false;

  bool get isIpad {
    final size = MediaQuery.of(context).size;
    return size.shortestSide >= 600;
  }

  @override
  void initState() {
    super.initState();
    // MediaQuery isn't ready in initState — defer to after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkApplePay());
  }

  Future<void> _checkApplePay() async {
    if (!mounted) return;
    if (isIpad) return;
    try {
      await InAppPayments.setSquareApplicationId(widget.squareApplicationId);
      await InAppPayments.initializeApplePay('merchant.com.flexfacility.app');
      final available = await InAppPayments.canUseApplePay;
      if (mounted) setState(() => _applePayAvailable = available);
    } catch (_) {
      // Apple Pay unavailable — button stays hidden
    }
  }

  /// Base URL for your Firebase Functions
  static const String _functionsBase =
      'https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api';

  /// Build hosted checkout URL for /checkout (card payments)
  String _buildCheckoutUrl({
    required int amountCents,
    required String planName,
    required String firstName,
    required String lastName,
    required String email,
    required String referenceId,
    required String userId,
    required String planId,
    required int sessions,
    required double priceDollars,
    required String planCategory,
    required String planDescription,
    String env = 'production', // use 'sandbox' while testing if you want
  }) {
    final Map<String, String> params = {
      // **Square Web Payments config**
      'appId': widget.squareApplicationId,
      'locationId': widget.squareLocationId,
      'env': env,
      // Where the card token is POSTed
      'apiUrl': '$_functionsBase/process-payment',

      // Plan + amount
      'planName': planName,
      'amountCents': amountCents.toString(),

      // Buyer / plan details used by checkout.html
      'userId': userId,
      'planId': planId,
      'sessions': sessions.toString(),
      'priceDollars': priceDollars.toStringAsFixed(2),
      'planCategory': planCategory,
      'planDescription': planDescription,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,

      // Idempotency / reference
      'ref': referenceId,
    };

    final qp = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    return '$_functionsBase/checkout?$qp';
  }

  /// Open Square hosted checkout (card payment) in browser
  Future<void> _openWebCheckout({String paymentMethod = 'card'}) async {
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

      String firstName = '';
      String lastName = '';

      // Try to get name from Firestore, then from Firebase user profile
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final name = (doc.data()?['name'] as String?)?.trim() ??
            (user?.displayName ?? '').trim();

        if (name.isNotEmpty) {
          final parts = name.split(RegExp(r'\s+'));
          firstName = parts.first;
          if (parts.length > 1) {
            lastName = parts.sublist(1).join(' ');
          }
        }
      } catch (_) {
        // Ignore Firestore errors here, user can still pay
      }

      final planId = (widget.plan['docId'] ?? 'plan').toString();
      final sessions = (widget.plan['sessions'] as int?) ?? 0;
      final category = (widget.plan['category'] as String?) ?? '';
      final description = (widget.plan['description'] as String?) ?? '';

      // Reference / idempotency key
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
        userId: uid,
        planId: planId,
        sessions: sessions,
        priceDollars: price,
        planCategory: category,
        planDescription: description,
        env: 'production', // or 'sandbox' while testing
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error starting checkout: $e';
        _isProcessingPayment = false;
      });
    }
  }

  /// Apple Pay → native nonce → POST to /process-payment
  /// Uses callbacks so we don't throw "Failed to retrieve Apple Pay nonce"
  Future<void> _payWithApplePayDirect() async {
    setState(() {
      _isProcessingPayment = true;
      _errorMessage = null;
    });

    // NEW: extra guard to prevent Apple Pay flow on iPad
    if (isIpad) {
      if (!mounted) return;
      setState(() {
        _isProcessingPayment = false;
        _errorMessage = 'Apple Pay is not available on iPad.';
      });
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'anon';
      final email = user?.email ?? '';

      final double price = (widget.plan['price'] ?? 0).toDouble();
      final int amountCents = (price * 100).round();
      final String planName =
          (widget.plan['name'] as String?) ?? 'Training Plan';

      final String planId = (widget.plan['docId'] ?? 'plan').toString();
      final int sessions = (widget.plan['sessions'] as int?) ?? 0;
      final String category = (widget.plan['category'] as String?) ?? '';
      final String description =
          (widget.plan['description'] as String?) ?? '';

      // Reference / idempotency key
      final String refId = [
        uid.length >= 8 ? uid.substring(0, 8) : uid,
        planId.length >= 8 ? planId.substring(0, 8) : planId,
        DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      ].join('-');

      // Lookup first/last name once, before requestApplePayNonce
      String firstName = '';
      String lastName = '';
      try {
        if (uid != 'anon') {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          final name = (doc.data()?['name'] as String?)?.trim() ??
              (user?.displayName ?? '').trim();
          if (name.isNotEmpty) {
            final parts = name.split(RegExp(r'\s+'));
            firstName = parts.first;
            if (parts.length > 1) {
              lastName = parts.sublist(1).join(' ');
            }
          }
        }
      } catch (_) {
        // ignore
      }

      // Request Apple Pay nonce with callbacks
      await InAppPayments.requestApplePayNonce(
        price: price.toStringAsFixed(2),
        summaryLabel: planName,
        countryCode: 'US',
        currencyCode: 'USD',
        paymentType: ApplePayPaymentType.finalPayment,

        // ✅ SUCCESS: we got a nonce from Apple Pay
        onApplePayNonceRequestSuccess: (result) async {
          try {
            final body = {
              'token': {'id': result.nonce}, // Apple Pay nonce
              'amountCents': amountCents,
              'currency': 'USD',
              'locationId': widget.squareLocationId,
              'planName': planName,
              'buyer': {
                'userId': uid,
                'planId': planId,
                'sessions': sessions,
                'price': price,
                'planCategory': category,
                'description': description,
                'email': email,
                'firstName': firstName,
                'lastName': lastName,
              },
              'billingDetails': {},
              'referenceId': refId,
              'paymentMethod': 'applepay',
            };

            final resp = await http.post(
              Uri.parse('$_functionsBase/process-payment'),
              headers: const {
                'Content-Type': 'application/json',
                // 'sandbox' while testing; 'production' when live
                'x-square-env': 'production',
              },
              body: jsonEncode(body),
            );

            final data = jsonDecode(resp.body);
            if (resp.statusCode != 200 || data['ok'] != true) {
              throw Exception(data['error'] ?? 'Apple Pay payment failed');
            }

            // ✅ Tell iOS the transaction succeeded
            await InAppPayments.completeApplePayAuthorization(isSuccess: true);

            if (!mounted) return;

            // ✅ Update UI state
            setState(() {
              _isProcessingPayment = false;
            });

            // ✅ SAFE NAVIGATION - prevents app from "closing"
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(true); // back to previous screen
            } else {
              // Fallback: go to client dashboard if there's nothing to pop
              Navigator.of(context).pushReplacementNamed('/client');
            }
          } catch (e) {
            // Backend/Firestore failure
            await InAppPayments.completeApplePayAuthorization(
              isSuccess: false,
              errorMessage: e.toString(),
            );

            if (!mounted) return;
            setState(() {
              _isProcessingPayment = false;
              _errorMessage = 'Apple Pay failed: $e';
            });
          }
        },

        // ❌ FAILURE: Apple Pay itself failed or was cancelled
        onApplePayNonceRequestFailure: (error) async {
          await InAppPayments.completeApplePayAuthorization(
            isSuccess: false,
            errorMessage: error.message,
          );

          if (!mounted) return;
          setState(() {
            _isProcessingPayment = false;
            _errorMessage =
                error.message ?? 'Apple Pay was cancelled or failed.';
          });
        },

        // Called when sheet is fully closed
        onApplePayComplete: () {
          debugPrint('Apple Pay flow completed');
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessingPayment = false;
        _errorMessage = 'Apple Pay error: $e';
      });
    }
  }

  /// Bottom sheet UX to confirm Apple Pay purchase
  void _showApplePaySheet() {
    final planPrice = (widget.plan['price'] ?? 0).toDouble();
    final planName = widget.plan['name'] as String? ?? 'Fitness Plan';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom +
            MediaQuery.of(ctx).padding.bottom;

        return Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              const Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirm',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'your purchase',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Plan info card
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PLAN',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            planName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Payment via Apple Pay',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '\$${planPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // TOTAL section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '\$${planPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Includes applicable taxes and fees.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Apple Pay info text
              const Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apple Pay',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'You’ll use the cards stored in your Apple Wallet.\nFace ID / Touch ID will confirm your purchase.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Apple Pay button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessingPayment
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          await _payWithApplePayDirect();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ApplePayBadge(
                        fontSize: 16,
                        padding:
                            EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Buy with Apple Pay',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final planPrice = (widget.plan['price'] ?? 0).toDouble();
    final planName = widget.plan['name'] as String? ?? 'Fitness Plan';
    final sessions = (widget.plan['sessions'] as int?) ?? 0;
    final category = widget.plan['category'] as String? ?? '';
    final description = widget.plan['description'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_errorMessage != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.red.shade50,
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() => _errorMessage = null);
                      },
                    ),
                  ],
                ),
              ),

            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Plan summary card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            planName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              InfoChip(label: '$sessions Sessions'),
                              if (category.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                InfoChip(label: category),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Price',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '\$${planPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Payment Options',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Card payment option
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pay with Card',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Use your debit or credit card in a secure hosted checkout.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isProcessingPayment
                                  ? null
                                  : () => _openWebCheckout(
                                        paymentMethod: 'card',
                                      ),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _isProcessingPayment
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation(Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Pay with Card',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Apple Pay option - only shown when available and not on iPad
                    if (_applePayAvailable && !isIpad)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Apple Pay',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Pay directly using the cards in your Apple Wallet.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _isProcessingPayment
                                    ? null
                                    : _showApplePaySheet,
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(
                                    color: Colors.black.withOpacity(0.1),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ApplePayBadge(),
                                    SizedBox(width: 8),
                                    Text(
                                      'Use Apple Pay',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // else: nothing rendered for Apple Pay on iPad

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom processing bar
            if (_isProcessingPayment)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Processing payment...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFF7F8FA),
    );
  }
}
