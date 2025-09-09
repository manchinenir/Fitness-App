import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SquareWebCheckout extends StatefulWidget {
  const SquareWebCheckout({
    super.key,
    required this.amountCents,
    required this.appId,
    required this.locationId,
    required this.functionsBaseUrl, // e.g. https://us-central1-<project>.cloudfunctions.net/api
    this.production = false,
  });

  final int amountCents;
  final String appId;
  final String locationId;
  final String functionsBaseUrl;
  final bool production;

  @override
  State<SquareWebCheckout> createState() => _SquareWebCheckoutState();
}

class _SquareWebCheckoutState extends State<SquareWebCheckout> {
  late final WebViewController _controller;
  bool _loading = true;

  String get _checkoutUrl {
    final env = widget.production ? 'production' : 'sandbox';
    final encodedAppId = Uri.encodeComponent(widget.appId);
    final encodedApiUrl =
        Uri.encodeComponent('${widget.functionsBaseUrl}/process-payment');

    // endpoint served by the Cloud Function
    return '${widget.functionsBaseUrl}/checkout'
        '?amountCents=${widget.amountCents}'
        '&appId=$encodedAppId'
        '&locationId=${widget.locationId}'
        '&env=$env'
        '&apiUrl=$encodedApiUrl';
  }

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'SquareBridge',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            if (mounted) Navigator.of(context).pop(data);
          } catch (_) {
            if (mounted) {
              Navigator.of(context).pop(
                {'ok': false, 'error': 'Malformed message from checkout page'},
              );
            }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (NavigationRequest req) {
            if (req.url.startsWith('sqbridge://message')) {
              final uri = Uri.parse(req.url);
              final raw = uri.queryParameters['data'];
              Map<String, dynamic> payload = {'ok': false};
              if (raw != null) {
                try {
                  payload = jsonDecode(raw) as Map<String, dynamic>;
                } catch (_) {
                  payload['error'] = 'Malformed message';
                }
              } else {
                payload['error'] = 'Empty message';
              }
              if (mounted) Navigator.of(context).pop(payload);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secure Checkout')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
