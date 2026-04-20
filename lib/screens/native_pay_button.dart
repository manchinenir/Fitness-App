// lib/screens/native_pay_button.dart
//
// Drop-in widget that shows a Google Pay or Apple Pay button and calls back
// with the resulting payment token string (from the pay package).
//
// Usage:
//   NativePayButton(
//     amountCents: 18500,
//     planName: '4 Sessions Monthly',
//     onToken: (token) async { /* forward token to your Cloud Function */ },
//   )
//
// The widget is invisible on platforms / devices that don't support the
// selected payment method (pay package returns PaymentResult.notSupported).

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:pay/pay.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class NativePayButton extends StatefulWidget {
  final int amountCents;
  final String planName;

  /// Called with the raw payment-method token (JSON string) on success.
  final Future<void> Function(String token) onToken;

  const NativePayButton({
    super.key,
    required this.amountCents,
    required this.planName,
    required this.onToken,
  });

  @override
  State<NativePayButton> createState() => _NativePayButtonState();
}

class _NativePayButtonState extends State<NativePayButton> {
  bool _processing = false;

  String get _totalAmount =>
      (widget.amountCents / 100).toStringAsFixed(2);

  PaymentConfiguration? _paymentConfiguration;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = Platform.isIOS
          ? await PaymentConfiguration.fromAsset(
              'assets/pay/apple_pay_config.json')
          : await PaymentConfiguration.fromAsset(
              'assets/pay/google_pay_config.json');
      if (mounted) setState(() => _paymentConfiguration = config);
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
    }
  }

  Future<void> _onPaymentResult(Map<String, dynamic> result) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      // Extract the raw token string from the payment result
      final token = result.toString();
      await widget.onToken(token);
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _onPaymentError(Object? error) {
    if (error != null) {
      FirebaseCrashlytics.instance.recordError(
        error,
        null,
        fatal: false,
        reason: 'Native pay error',
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment was cancelled or unavailable.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_paymentConfiguration == null) return const SizedBox.shrink();

    final paymentItems = [
      PaymentItem(
        label: widget.planName,
        amount: _totalAmount,
        status: PaymentItemStatus.final_price,
      ),
    ];

    if (_processing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Platform.isIOS
        ? ApplePayButton(
            paymentConfiguration: _paymentConfiguration!,
            paymentItems: paymentItems,
            style: ApplePayButtonStyle.black,
            type: ApplePayButtonType.buy,
            margin: const EdgeInsets.symmetric(vertical: 8),
            onPaymentResult: _onPaymentResult,
            loadingIndicator: const Center(child: CircularProgressIndicator()),
            onError: _onPaymentError,
          )
        : GooglePayButton(
            paymentConfiguration: _paymentConfiguration!,
            paymentItems: paymentItems,
            type: GooglePayButtonType.buy,
            margin: const EdgeInsets.symmetric(vertical: 8),
            onPaymentResult: _onPaymentResult,
            loadingIndicator: const Center(child: CircularProgressIndicator()),
            onError: _onPaymentError,
          );
  }
}
