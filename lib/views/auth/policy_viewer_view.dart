// In-app viewer for a policy/legal document - the mobile counterpart of
// webapp's DocumentViewerModal. Renders, in order of preference:
//   1. `content` - rich-text (HTML) stored in the DB, shown inline in a
//      WebView (JS disabled, so the untrusted-ish markup can't execute).
//   2. `url` - a fallback external document, loaded in the WebView.
// If neither is available, a short "unavailable" message is shown - matching
// the webapp's fallback exactly.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PolicyViewerPage extends StatefulWidget {
  final String title;
  final String? content;
  final String? url;
  final bool isDark;

  const PolicyViewerPage({
    super.key,
    required this.title,
    this.content,
    this.url,
    required this.isDark,
  });

  @override
  State<PolicyViewerPage> createState() => _PolicyViewerPageState();
}

class _PolicyViewerPageState extends State<PolicyViewerPage> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    final hasContent = (widget.content ?? '').trim().isNotEmpty;
    final hasUrl = (widget.url ?? '').trim().isNotEmpty;
    if (!hasContent && !hasUrl) return;

    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(
          widget.isDark ? const Color(0xFF0B0E14) : Colors.white);
    if (hasContent) {
      c.loadHtmlString(_wrap(widget.content!, widget.isDark));
    } else {
      c.loadRequest(Uri.parse(widget.url!));
    }
    _controller = c;
  }

  // Wrap the raw DB HTML in a minimal, theme-matched document so it reads
  // well on a phone (viewport meta, comfortable type, images that fit).
  String _wrap(String content, bool isDark) {
    final bg = isDark ? '#0B0E14' : '#FFFFFF';
    final fg = isDark ? '#E8EBF1' : '#14161A';
    return '''<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { background: $bg; color: $fg; margin: 0; padding: 16px;
    font-family: -apple-system, Roboto, "Segoe UI", sans-serif;
    font-size: 15px; line-height: 1.55; }
  a { color: #1C7DEF; }
  h1, h2, h3 { line-height: 1.3; }
  img { max-width: 100%; height: auto; }
  table { max-width: 100%; }
</style></head><body>$content</body></html>''';
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF0B0E14) : Colors.white;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            widget.isDark ? const Color(0xFF151A23) : Colors.white,
        foregroundColor:
            widget.isDark ? const Color(0xFFE8EBF1) : const Color(0xFF14161A),
        title: Text(widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: _controller != null
          ? WebViewWidget(controller: _controller!)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This document is currently unavailable. Please try again later.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: widget.isDark
                          ? const Color(0xFF99A1B1)
                          : const Color(0xFF5B606B)),
                ),
              ),
            ),
    );
  }
}
