import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/views/splash/welcome_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

void main() {
  StateStore reduxStore = StateStore();

  runApp(StoreProvider<AppState>(
    store: reduxStore.store, // Wrap with StoreProvider
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chatterloop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Chatterloop'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AppContainer();
  }
}

class AppContainer extends StatefulWidget {
  const AppContainer({super.key});

  @override
  State<AppContainer> createState() => AppContainerState();
}

class AppContainerState extends State<AppContainer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, UserAuth>(builder: (context, userAuth) {
      bool? isLoggedIn = userAuth.auth;
      return isLoggedIn != null
          ? MaterialApp(
              navigatorKey: navigatorKey,
              initialRoute: isLoggedIn ? '/' : '/login',
              routes:
                  isLoggedIn ? AppRoutes.privateroutes : AppRoutes.publicroutes,
            )
          : WelcomeScreen();
    }, converter: (store) {
      return store.state.userAuth;
    });
  }
}
