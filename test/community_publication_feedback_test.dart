import 'package:flutter_test/flutter_test.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:chatterloop_app/core/notifications/push_payload.dart';

void main() {
  test(
      'pending publication explains private Submissions and human decision push routes survive validation',
      () {
    expect(communityPublicationMessage({'status': true, 'approval': 0}),
        contains('Submissions'));
    expect(
        communityPublicationMessage({'status': true, 'approval': 1}), isNull);
    expect(PushPayload.allowedRoutePrefixes, contains('/realm-review/'));
  });
}
