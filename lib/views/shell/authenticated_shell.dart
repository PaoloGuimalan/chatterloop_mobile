// Owns the SSE connection lifecycle for the whole authenticated route
// subtree. Replaces HomeViewContainer's lazy-init-on-build SSE handling and
// the old restart()-based logout hack: when the auth guard's redirect kicks
// an unauthenticated session out of this subtree, dispose() fires and
// closes SSE deterministically - no engine restart needed.

import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:flutter/material.dart';

class AuthenticatedShell extends StatefulWidget {
  final Widget child;
  const AuthenticatedShell({super.key, required this.child});

  @override
  State<AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<AuthenticatedShell> {
  final SseConnection _sse = SseConnection();

  @override
  void initState() {
    super.initState();
    _sse.initializeConnection();
  }

  @override
  void dispose() {
    _sse.closeConnection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
