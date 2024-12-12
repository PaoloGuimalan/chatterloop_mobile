import 'package:chatterloop_app/views/auth/login_view.dart';
import 'package:chatterloop_app/views/home/home_view.dart';
import 'package:flutter/material.dart';

class AppRoutes {
  static Map<String, WidgetBuilder> routes = {
    "/": (context) => HomeView(),
    "/login": (context) => LoginScreen()
  };
}
