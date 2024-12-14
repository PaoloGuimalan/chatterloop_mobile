// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/main.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  HomeViewState createState() => HomeViewState();
}

class HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
  }

  final storage = FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Hello, Home!"),
              ElevatedButton(
                  onPressed: () async {
                    await storage.delete(key: 'token');
                    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
                        setUserAuthT,
                        UserAuth(
                            false,
                            UserAccount("", UserFullname("", "", ""), "", false,
                                false))));
                    navigatorKey.currentState?.pushNamed("/login");
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
