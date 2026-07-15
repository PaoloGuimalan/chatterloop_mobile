// Full-screen interstitial shown while an entity switch is in flight -
// mirrors webapp's own post-switch UX (a full-viewport blurred overlay +
// spinner + "Switching..." text, because webapp settles a switch with an
// actual page reload). This screen IS that reload's mobile equivalent: it's
// a real route replacing the whole visible UI (no bottom nav/top bar), runs
// the switch + AppState reset while it's the only thing on screen, then
// redirects into the shell once done - so nothing renders against
// half-cleared state along the way.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SwitchingScreen extends StatefulWidget {
  final Future<bool> Function() perform;
  const SwitchingScreen({super.key, required this.perform});

  @override
  State<SwitchingScreen> createState() => _SwitchingScreenState();
}

class _SwitchingScreenState extends State<SwitchingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    await widget.perform();
    if (!mounted) return;
    context.go('/messages');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: p.brand),
            const SizedBox(height: 16),
            Text("Switching…", style: TextStyle(fontSize: 14, color: p.text2)),
          ],
        ),
      ),
    );
  }
}
