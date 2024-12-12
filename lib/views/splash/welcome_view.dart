import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  WelcomeScreenState createState() => WelcomeScreenState();
}

class WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    // RoutingTools routingTools = RoutingTools();
    // routingTools.redirectTimeout("/login", 3);
  }

  @override
  Widget build(BuildContext context) {
    UserAuth userAuth = StoreProvider.of<AppState>(context).state.userAuth;

    Future.delayed(Duration(seconds: 5), () {
      StoreProvider.of<AppState>(context)
          .dispatch(DispatchModel(setUserAuthT, UserAuth(true, userAuth.user)));
    });

    return MaterialApp(
      home: Scaffold(
        body: Container(
          color: Colors.white,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 180,
                    maxWidth: 180,
                  ),
                  child: Image.asset(
                    'lib/assets/images/chatterloop.png',
                    fit: BoxFit.cover,
                  ),
                ),
                Text(
                  "Chatterloop",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF565656)),
                ),
                Text("Link . Share . Explore",
                    style: TextStyle(fontSize: 14, color: Color(0xFF565656)))
              ],
            ),
          ),
        ),
      ),
    );
  }
}
