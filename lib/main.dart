import 'package:chatterloop_app/core/auth/auth_controller.dart';
import 'package:chatterloop_app/core/design/theme_provider.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/notifications/push_notification_service.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/routes/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

// Background message handler
@pragma(
    'vm:entry-point') // Required for background handlers in newer Flutter versions
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase inside the background process
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
// 2. Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // 3. Initialize Firebase using the generated configuration
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 4. Set the background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthController _authController;
  late final GoRouter _router;
  final ThemeController _themeController = ThemeController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _authController = AuthController(appStore);
    _router = buildAppRouter(_authController);
    // Firebase is already initialized in main(); wire FCM now that the router
    // exists so notification taps can deep-link. Fire-and-forget - it caches
    // the token (sent via the fcm-token header) and sets up display/tap
    // handlers. The permission prompt is triggered later, from the logged-in
    // shell, not here.
    PushNotificationService.instance.init();
    _authController.resolve();
    _themeController.load();
  }

  @override
  void dispose() {
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      notifier: _themeController,
      child: AnimatedBuilder(
        animation: _themeController,
        builder: (context, _) {
          return StoreProvider<AppState>(
            store: appStore,
            child: MaterialApp.router(
              title: 'Chatterloop',
              theme: buildCLTheme(Brightness.light),
              darkTheme: buildCLTheme(Brightness.dark),
              themeMode: _themeController.mode,
              routerConfig: _router,
            ),
          );
        },
      ),
    );
  }
}
