import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const AadnandaApp());
}

class AadnandaApp extends StatelessWidget {
  const AadnandaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'aadnanda.com',
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() => _loading = true),
          onPageFinished: (url) async {
            _updateNavState();
            setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse('https://aadnanda.com'));
  }

  Future<void> _updateNavState() async {
    setState(() {
      _canGoBack = false;
      _canGoForward = false;
    });
    _canGoBack = await _controller.canGoBack();
    _canGoForward = await _controller.canGoForward();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.only(top: topInset + 14),
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _canGoBack ? () => _controller.goBack() : null,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
            ),
            const SizedBox(width: 24),
            IconButton(
              onPressed: _canGoForward
                  ? () => _controller.goForward()
                  : null,
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'Forward',
            ),
            const SizedBox(width: 24),
            IconButton(
              onPressed: () => _controller.reload(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
    );
  }
}