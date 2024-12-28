import 'package:chatterloop_app/views/auth/login_view.dart';
import 'package:chatterloop_app/views/home/home_view.dart';
import 'package:chatterloop_app/views/home/tabs/contacts_view.dart';
import 'package:chatterloop_app/views/home/tabs/feed_view.dart';
import 'package:chatterloop_app/views/home/tabs/map_view.dart';
import 'package:chatterloop_app/views/home/tabs/profile_view.dart';
import 'package:chatterloop_app/views/home/tabs/server_view.dart';
import 'package:chatterloop_app/views/messages/messages_view.dart';
import 'package:chatterloop_app/views/notifications/notifications_view.dart';
import 'package:flutter/material.dart';

class AppRoutes {
  static Map<String, WidgetBuilder> routes = {
    "/login": (context) => LoginScreen(),
    "/home": (context) => Container(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.only(top: 30),
            child: HomeView(),
          ),
        ),
    "/messages": (context) => MessagesView(),
    "/notifications": (context) => NotificationsView(),
    "/profile": (context) => ProfileView()
  };

  static Map<String, WidgetBuilder> tabs = {
    "/home": (context) => FeedView(),
    "/map": (context) => MapView(),
    "/contacts": (context) => ContactsView(),
    "/servers": (context) => ServerView()
  };
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> navigatorTabKey = GlobalKey<NavigatorState>();
