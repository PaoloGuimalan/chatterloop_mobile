import 'package:flutter/material.dart';

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  NotificationsStateView createState() => NotificationsStateView();
}

class NotificationsStateView extends State<NotificationsView> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text("Notifications"),
        ),
      ),
    );
  }
}
