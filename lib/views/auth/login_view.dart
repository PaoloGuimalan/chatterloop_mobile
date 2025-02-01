// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/routes/app_routes.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  String email = "";
  String password = "";
  bool obscurePassword = true;
  final storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
  }

  void loginApiRequest() async {
    APIRequests apiRequests = APIRequests();
    JwtTools jwt = JwtTools();
    LoginResponse? loginResponse =
        await apiRequests.loginRequest(email, password);

    if (loginResponse?.authtoken != null && loginResponse?.usertoken != null) {
      await storage.write(key: 'token', value: loginResponse?.authtoken);
      Map<String, dynamic>? userResponse =
          jwt.verifyJwt(loginResponse?.usertoken ?? '', secretKey);
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
      // navigatorKey.currentState?.popAndPushNamed("/home");
      AppRoutes.navigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/home', (Route<dynamic> route) => false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF1c7def),
          body: SingleChildScrollView(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: MediaQuery.of(context).size.height),
              child: IntrinsicHeight(
                child: Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.3,
                          child: Transform.translate(
                            offset: Offset(0, 0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  margin: EdgeInsets.only(bottom: 80),
                                  child: Text(
                                    "Chatterloop",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 20),
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                            child: Container(
                          decoration: BoxDecoration(
                              color: Color(0xFFdfdfdf),
                              borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20))),
                          width: double.infinity,
                          child: Padding(
                            padding: EdgeInsets.only(
                                top: 0, right: 10, left: 10, bottom: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Transform.translate(
                                  offset: Offset(0, -50),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: 120,
                                      maxWidth: 120,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                          border: Border.all(
                                              color: Color(0xFF1c7def),
                                              width: 7),
                                          borderRadius:
                                              BorderRadius.circular(100)),
                                      child: Image.asset(
                                        'assets/images/chatterloop.png',
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                    child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    ConstrainedBox(
                                      constraints:
                                          BoxConstraints(maxWidth: 350),
                                      child: Container(
                                        height: 50,
                                        padding: EdgeInsets.only(
                                            left: 10, right: 10),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          color: Colors.white,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            TextField(
                                              onChanged: (value) {
                                                setState(() {
                                                  email = value;
                                                });
                                              },
                                              style: TextStyle(fontSize: 14),
                                              decoration: InputDecoration(
                                                  fillColor: Colors.white,
                                                  hintText: 'Email or Username',
                                                  border: InputBorder.none),
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 10,
                                    ),
                                    ConstrainedBox(
                                      constraints:
                                          BoxConstraints(maxWidth: 350),
                                      child: Container(
                                        height: 50,
                                        padding: EdgeInsets.only(
                                            left: 10, right: 10),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          color: Colors.white,
                                        ),
                                        child: TextField(
                                          obscureText: obscurePassword,
                                          onChanged: (value) {
                                            setState(() {
                                              password = value;
                                            });
                                          },
                                          style: TextStyle(fontSize: 14),
                                          decoration: InputDecoration(
                                            contentPadding:
                                                EdgeInsets.only(top: 14),
                                            fillColor: Colors.white,
                                            hintText: 'Password',
                                            border: InputBorder.none,
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                obscurePassword
                                                    ? Icons.visibility_off
                                                    : Icons.visibility,
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  obscurePassword =
                                                      !obscurePassword;
                                                });
                                              }, // Toggle visibility
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 10,
                                    ),
                                    ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Color(0xFF1c7def),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10))),
                                        onPressed: () {
                                          // if (kDebugMode) {
                                          //   print(userAuth.auth);
                                          // }
                                          // StoreProvider.of<AppState>(context).dispatch(DispatchModel(
                                          //     setUserAuthT, UserAuth(true, userAuth.user)));
                                          // navigatorKey.currentState?.pushNamed("/");
                                          loginApiRequest();
                                        },
                                        child: Text(
                                          "Login",
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white),
                                        )),
                                    SizedBox(
                                      height: 10,
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          "Don't have an account yet?",
                                          style: TextStyle(fontSize: 14),
                                        ),
                                        TextButton(
                                            onPressed: () {},
                                            child: Text(
                                              "Sign Up",
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: Color(0xFF1c7def),
                                                  fontWeight: FontWeight.bold),
                                            ))
                                      ],
                                    )
                                  ],
                                ))
                              ],
                            ),
                          ),
                        ))
                      ]),
                ),
              ),
            ),
          ),
        ),
      );
    }, converter: (store) {
      return store.state;
    });
  }
}
