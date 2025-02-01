import 'package:flutter/material.dart';

class ServerView extends StatefulWidget {
  const ServerView({super.key});

  @override
  ServerStateView createState() => ServerStateView();
}

class ServerStateView extends State<ServerView> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text("Server"),
        ),
      ),
    );
  }
}
