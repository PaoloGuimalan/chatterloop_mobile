import 'package:chatterloop_app/main.dart';

class RoutingTools {
  void redirectTimeout(String path, int secondsDelayed) {
    Future.delayed(Duration(seconds: secondsDelayed), () {
      navigatorKey.currentState?.pushNamed(path);
    });
  }
}
