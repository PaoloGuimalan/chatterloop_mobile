import 'package:chatterloop_app/core/auth/auth_controller.dart';
import 'package:chatterloop_app/core/design/theme_provider.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/routes/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

void main() {
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
