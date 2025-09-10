// lib/screens/invoice_review_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class InvoiceReviewPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final String squareApplicationId; // (unused here but kept if you pass it around)
  final String squareLocationId;    // (unused here but kept if you pass it around)
  final String functionsBaseUrl;    // e.g. https://<region>-<project>.cloudfunctions.net/api

  const InvoiceReviewPage({
    super.key,
    required this.plan,
    required this.squareApplicationId,
    required this.squareLocationId,
    required this.functionsBaseUrl,
  });

  @override
  State<InvoiceReviewPage> createState() => _InvoiceReviewPageState();
}

class _InvoiceReviewPageState extends State<InvoiceReviewPage> {
  bool _sending = false;
  String? _error;

  /// Sends a Square pay link email to the currently signed-in user's email.
  Future<void> _emailPayLinkAuto() async {
    final user = FirebaseAuth.instance.currentUser;
    final recipientEmail = user?.email?.trim() ?? '';
    final recipientName = (user?.displayName ?? '').trim();

    if (recipientEmail.isEmpty) {
      setState(() => _error = 'No user email found. Please sign in first.');
      return;
    }

    final planName = widget.plan['name'] as String? ?? 'Fitness Plan';
    final price = (widget.plan['price'] ?? 0).toDouble();
    final amountCents = (price * 100).round();

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('${widget.functionsBaseUrl}/payment-link/email');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'planName': planName,
          'amountCents': amountCents,
          'recipientEmail': recipientEmail,
          'recipientName': recipientName,
          // server creates the link & emails it; no publicUrl needed here
        }),
      );

      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['ok'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pay link emailed to $recipientEmail')),
        );
      } else {
        throw Exception(data['error'] ?? 'Failed to send pay link');
      }
    } catch (e) {
      setState(() => _error = 'Email failed: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.plan['name'] as String? ?? 'Fitness Plan';
    final sessions = widget.plan['sessions'] as int? ?? 0;
    final price = (widget.plan['price'] ?? 0).toDouble();
    final desc = widget.plan['description'] as String? ?? '—';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Plan'),
        backgroundColor: const Color(0xFF1C2D5E),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Plan Summary',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('$sessions Sessions',
                        style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 6),
                    Text(desc, style: const TextStyle(color: Colors.grey)),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('\$${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),

            if (_error != null) ...[
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
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Single primary action: Email Pay Link to the signed-in user
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _emailPayLinkAuto,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.email_outlined),
                label: Text(
                  _sending ? 'Sending…' : 'Email Pay Link',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
