// ignore_for_file: use_build_context_synchronously
import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/views/splash/welcome_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

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
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  final storage = FlutterSecureStorage();

  Future<void> checkToken(BuildContext context) async {
    APIRequests apiRequests = APIRequests();
    JwtTools jwt = JwtTools();
    String? token = await storage.read(key: 'token');

    if (kDebugMode) {
      print("JWT Checker Triggered");
    }

    if (!mounted) return;

    UserAuth userAuth = StoreProvider.of<AppState>(context).state.userAuth;

    if (token == null) {
      Future.delayed(Duration(seconds: 3), () {
        StoreProvider.of<AppState>(context).dispatch(
            DispatchModel(setUserAuthT, UserAuth(false, userAuth.user)));
      });
      AppRoutes.navigatorKey.currentState?.pushNamed('/login');
      return;
    }

    JWTCheckerResponse? jwtcheckResponse =
        await apiRequests.jwtCheckerRequest();

    if (jwtcheckResponse?.usertoken != null) {
      Map<String, dynamic>? userResponse =
          jwt.verifyJwt(jwtcheckResponse?.usertoken ?? '', secretKey);
      Future.delayed(Duration(seconds: 3), () {
        StoreProvider.of<AppState>(context).dispatch(DispatchModel(
            setUserAuthT,
            UserAuth(
                true,
                UserAccount(
                    userResponse?["userID"],
                    UserFullname(
                        userResponse?["fullname"]["firstName"],
                        userResponse?["fullname"]["middleName"],
                        userResponse?["fullname"]["lastName"]),
                    userResponse?["email"],
                    userResponse?["isActivated"],
                    userResponse?["isVerified"],
                    null,
                    null,
                    null,
                    null))));
        AppRoutes.navigatorKey.currentState?.pushNamed("/home");
      });
    } else {
      await storage.delete(key: 'token');
      StoreProvider.of<AppState>(context).dispatch(DispatchModel(
          setUserAuthT,
          UserAuth(
              false,
              UserAccount("", UserFullname("", "", ""), "", false, false, null,
                  null, null, null))));
      AppRoutes.navigatorKey.currentState?.pushNamed("/login");
    }
  }

  @override
  Widget build(BuildContext context) {
    checkToken(context);
    return StoreConnector<AppState, UserAuth>(builder: (context, userAuth) {
      bool? isLoggedIn = userAuth.auth;
      return isLoggedIn != null
          ? MaterialApp(
              navigatorKey: AppRoutes.navigatorKey,
              initialRoute: isLoggedIn ? '/home' : '/login',
              routes: AppRoutes.routes,
            )
          : WelcomeScreen();
    }, converter: (store) {
      return store.state.userAuth;
    });
  }
}
