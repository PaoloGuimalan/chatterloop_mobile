import 'package:chatterloop_app/views/auth/login_view.dart';
import 'package:chatterloop_app/views/home/home_view.dart';
import 'package:flutter/material.dart';

class AppRoutes {
  static Map<String, WidgetBuilder> routes = {
    "/login": (context) => LoginScreen(),
    "/": (context) => Container(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.only(top: 30),
            child: HomeView(),
          ),
        )
  };
}
