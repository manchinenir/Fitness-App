// lib/screens/checkout_webview.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// NOTE: We won't call Android-only methods that aren't available in 4.10.x

class CheckoutWebView extends StatefulWidget {
  final String url;
  const CheckoutWebView({super.key, required this.url});

  @override
  State<CheckoutWebView> createState() => _CheckoutWebViewState();
}

class _CheckoutWebViewState extends State<CheckoutWebView> {
  late final WebViewController _c;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (req) {
            // Allow normal https flows
            return NavigationDecision.navigate;
          },
          onWebResourceError: (e) {
            // Ignore subresource errors; soft-retry only if main frame failed
            if (e.isForMainFrame == true) {
              Future.delayed(const Duration(milliseconds: 700), () {
                if (mounted) _c.reload();
              });
            }
          },
          onHttpError: (_) {
            // Be quiet in UI; most gateways still succeed after transient http errors
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Handle target=_blank / window.open flows by redirecting in-page.
    // This helps Square/3DS in some environments even without multiple-windows APIs.
    _c.runJavaScript(
      "window.open = (u)=>{ try{ window.location.href = u; }catch(e){} };",
    );

    // Optional: set a friendly UA if your gateway is picky (safe to comment out)
    // _c.setUserAgent(
    //   'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
    //   '(KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
    // );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Secure Checkout',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1C2D5E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _c),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
