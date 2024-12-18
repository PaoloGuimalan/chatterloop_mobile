// ignore_for_file: use_build_context_synchronously, depend_on_referenced_packages

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_item_widget.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/main.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/post_models/user_post_model.dart';
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
  // HomeView({super.key});

  final storage = FlutterSecureStorage();

  ButtonStyle _buttonStyle(bool fromHeader) {
    return ElevatedButton.styleFrom(
        backgroundColor: fromHeader ? Colors.white : Colors.white,
        fixedSize: Size(50, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(60), // Rounded corners if needed
        ),
        elevation: 0,
        padding: EdgeInsets.zero,
        iconColor: Color(0xFF565656),
        overlayColor: Color(0xFF565656));
  }

  Future<void> getPostsProcess(BuildContext context) async {
    APIRequests apiRequests = APIRequests();
    JwtTools jwt = JwtTools();

    PostsResponse? postsResponse =
        await apiRequests.getPostsRequest(10.toString());

    if (postsResponse != null) {
      Map<String, dynamic>? decodedPostResponse =
          jwt.verifyJwt(postsResponse.result, secretKey);

      List<dynamic> postsInJson = decodedPostResponse?["data"]["posts"];

      List<UserPost> postresponse =
          postsInJson.map((post) => UserPost.fromJson(post)).toList();

      StoreProvider.of<AppState>(context)
          .dispatch(DispatchModel(setFeedPostsT, postresponse));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      if (state.posts.isEmpty) {
        getPostsProcess(context);
      }
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
                      child: Padding(
                        padding: EdgeInsets.only(top: 45),
                        child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: state.posts.length,
                            itemBuilder: (context, index) {
                              return PostItemWidget(post: state.posts[index]);
                            }),
                      ),
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
                        ElevatedButton(
                          onPressed: () {},
                          style: _buttonStyle(false),
                          child: Center(
                            child: Icon(
                              Icons.home_outlined,
                              size: 30,
                            ),
                          ),
                        ),
                        ElevatedButton(
                            onPressed: () {},
                            style: _buttonStyle(false),
                            child: Icon(
                              Icons.map_outlined,
                              size: 27,
                            )),
                        ElevatedButton(
                            onPressed: () {},
                            style: _buttonStyle(false),
                            child: Icon(
                              Icons.contacts_outlined,
                              size: 25,
                            )),
                        ElevatedButton(
                            onPressed: () {},
                            style: _buttonStyle(false),
                            child: Icon(
                              Icons.dataset_outlined,
                              size: 27,
                            )),
                        ElevatedButton(
                            onPressed: () {},
                            style: _buttonStyle(false),
                            child: Icon(
                              Icons.person_2_sharp,
                              size: 30,
                            )),
                      ],
                    ),
                  )
                ]),
                Positioned(
                    top: 0,
                    height: 60,
                    width: MediaQuery.of(context).size.width,
                    child: Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                              bottom: BorderSide(
                                  width: 0.5, color: Color(0xffd2d2d2)))),
                      child: Padding(
                        padding: EdgeInsets.only(
                            top: 0, bottom: 0, left: 10, right: 10),
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
                                    style: _buttonStyle(true),
                                    onPressed: () {},
                                    child: Center(
                                      child: Icon(
                                        Icons.messenger_outline_rounded,
                                        size: 25,
                                      ),
                                    )),
                                SizedBox(
                                  width: 2,
                                ),
                                ElevatedButton(
                                    style: _buttonStyle(true),
                                    onPressed: () {},
                                    child: Center(
                                      child: Icon(
                                        Icons.notifications_none,
                                        size: 27,
                                      ),
                                    )),
                                SizedBox(
                                  width: 2,
                                ),
                                ElevatedButton(
                                    style: _buttonStyle(true),
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
                                                      false,
                                                      null,
                                                      null,
                                                      null,
                                                      null))));
                                      navigatorKey.currentState
                                          ?.pushNamed("/login");
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.logout,
                                        size: 25,
                                        color: Colors.red,
                                      ),
                                    )),
                              ],
                            )
                          ],
                        ),
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
