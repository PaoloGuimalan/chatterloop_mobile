import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class HomeViewContainer extends StatefulWidget {
  const HomeViewContainer({super.key});

  @override
  HomeViewContainerState createState() => HomeViewContainerState();
}

class HomeViewContainerState extends State<HomeViewContainer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      return MaterialApp(
        navigatorKey: privateNavigatorKey,
        initialRoute: '/main',
        routes: AppRoutes.privateroutes,
      );
    }, converter: (store) {
      return store.state;
    });
  }
}