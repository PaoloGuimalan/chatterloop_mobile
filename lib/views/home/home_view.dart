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
            child: Stack(
              children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Expanded(
                      child: Container(
                    width: MediaQuery.of(context).size.width,
                    color: Color(0xfff0f2f5),
                    child: Center(
                      child: Text("Hello, Home!"),
                    ),
                  )),
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                            top: BorderSide(
                                width: 0.5, color: Color(0xffd2d2d2)))),
                    height: 70,
                    padding: EdgeInsets.all(10),
                    width: MediaQuery.of(context).size.width,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        ElevatedButton(onPressed: () {}, child: Text("H")),
                        ElevatedButton(onPressed: () {}, child: Text("M")),
                        ElevatedButton(onPressed: () {}, child: Text("C")),
                        ElevatedButton(onPressed: () {}, child: Text("S")),
                        ElevatedButton(onPressed: () {}, child: Text("P*")),
                      ],
                    ),
                  )
                ]),
                Positioned(
                    top: 0,
                    height: 70,
                    width: MediaQuery.of(context).size.width,
                    child: Padding(
                      padding: EdgeInsets.only(
                          top: 30, bottom: 10, left: 10, right: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Text(
                            "Chatterloop",
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF565656)),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton(
                                  onPressed: () {}, child: Text("M*")),
                              SizedBox(
                                width: 5,
                              ),
                              ElevatedButton(
                                  onPressed: () {}, child: Text("N")),
                              SizedBox(
                                width: 5,
                              ),
                              ElevatedButton(
                                  onPressed: () async {
                                    await storage.delete(key: 'token');
                                    StoreProvider.of<AppState>(context)
                                        .dispatch(DispatchModel(
                                            setUserAuthT,
                                            UserAuth(
                                                false,
                                                UserAccount(
                                                    "",
                                                    UserFullname("", "", ""),
                                                    "",
                                                    false,
                                                    false))));
                                    navigatorKey.currentState
                                        ?.pushNamed("/login");
                                  },
                                  child: Text("L")),
                            ],
                          )
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
