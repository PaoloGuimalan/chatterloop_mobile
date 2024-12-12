import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/main.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      UserAuth userAuth = state.userAuth;
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Hello, Login!"),
              ElevatedButton(
                  onPressed: () {
                    if (kDebugMode) {
                      print(userAuth.auth);
                    }
                    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
                        setUserAuthT, UserAuth(true, userAuth.user)));
                    navigatorKey.currentState?.pushNamed("/");
                  },
                  child: Text("Click"))
            ]),
          ),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
