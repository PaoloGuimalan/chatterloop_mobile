import 'package:chatterloop_app/core/routes/app_routes.dart';

class RoutingTools {
  void redirectTimeout(String path, int secondsDelayed) {
    Future.delayed(Duration(seconds: secondsDelayed), () {
      navigatorKey.currentState?.pushNamed(path);
    });
  }
}
