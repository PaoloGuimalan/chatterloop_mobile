import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/sse_connection.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class HomeViewContainer extends StatefulWidget {
  const HomeViewContainer({super.key});

  @override
  HomeViewContainerState createState() => HomeViewContainerState();
}

class HomeViewContainerState extends State<HomeViewContainer> {
  SseConnection sse = SseConnection();
  bool isSSEInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    sse.closeConnection();
    super.dispose();
  }

  void initSSEConnection() {
    sse.initializeConnection();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        isSSEInitialized = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      if (!isSSEInitialized) {
        initSSEConnection();
      }
      return MaterialApp(
        navigatorKey: AppRoutes.privateNavigatorKey,
        initialRoute: '/main',
        routes: AppRoutes.privateroutes,
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
