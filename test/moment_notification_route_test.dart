import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a moment notification opens your moments, not the post page", () {
    final r = NotificationRedirect.fromJson(
        {"platform": "android", "type": "moment", "route": "/post/abc123"});
    expect(r.route, "/moments/self?post=abc123");
  });

  test("everything else keeps the server's route", () {
    expect(
        NotificationRedirect.fromJson(
                {"platform": "android", "type": "post", "route": "/post/abc"})
            .route,
        "/post/abc");
    expect(NotificationRedirect.momentAwareRoute("moment", "/messages"),
        "/messages");
  });
}
