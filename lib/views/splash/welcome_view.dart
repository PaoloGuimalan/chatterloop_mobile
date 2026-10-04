import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CLLogoTile(size: 120),
            const SizedBox(height: 16),
            Text(
              "Chatterloop",
              style: TextStyle(
                  fontSize: CLType.hero,
                  fontWeight: FontWeight.w800,
                  color: p.text,
                  letterSpacing: -0.5),
            ),
            const SizedBox(height: 4),
            Text("Link · Share · Explore",
                style: TextStyle(fontSize: CLType.body, color: p.text2)),
          ],
        ),
      ),
    );
  }
}
