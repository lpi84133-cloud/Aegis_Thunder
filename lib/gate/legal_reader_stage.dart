import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/user_agent_client.dart';

// Small self-contained WebView used ONLY from the game menu to open
// the public legal pages (privacy policy / support). Kept separate
// from PortalStage so the game side never depends on the gray-flow
// scaffolding.

class LegalReaderStage extends StatefulWidget {
  final String title;
  final String url;

  const LegalReaderStage({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<LegalReaderStage> createState() => _LegalReaderStageState();
}

class _LegalReaderStageState extends State<LegalReaderStage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(uaClient.userAgent)
      ..setBackgroundColor(const Color(0xFF0B0F1A))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF120C05),
        foregroundColor: const Color(0xFFF6D36B),
        title: Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFE8B94A),
              ),
            ),
        ],
      ),
    );
  }
}
