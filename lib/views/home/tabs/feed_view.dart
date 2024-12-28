// ignore_for_file: use_build_context_synchronously

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_item_widget.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/post_models/user_post_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class FeedView extends StatefulWidget {
  const FeedView({super.key});

  @override
  FeedStateView createState() => FeedStateView();
}

class FeedStateView extends State<FeedView> {
  final ScrollController _scrollController = ScrollController();
  int postLength = 10;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> getPostsProcess(BuildContext context, int postLengthProp) async {
    APIRequests apiRequests = APIRequests();
    JwtTools jwt = JwtTools();

    PostsResponse? postsResponse =
        await apiRequests.getPostsRequest(postLengthProp.toString());

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

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;

      if (currentScroll >= maxScroll - 800 &&
          currentScroll <= maxScroll - 770) {
        if (kDebugMode) {
          print('Triggered 500 pixels before bottom!');
          setState(() {
            int newPostLength = postLength + 10;
            postLength = newPostLength;

            getPostsProcess(context, newPostLength);
          });
        }
        // You can load more items here or perform any action.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(builder: (context, state) {
      if (state.posts.isEmpty) {
        getPostsProcess(context, postLength);
      }
      return MaterialApp(
        home: Scaffold(
          body: Container(
            width: MediaQuery.of(context).size.width,
            color: Color(0xfff0f2f5),
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: ListView.builder(
                    shrinkWrap: true,
                    controller: _scrollController,
                    itemCount: state.posts.length,
                    itemBuilder: (context, index) {
                      return PostItemWidget(post: state.posts[index]);
                    }),
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
