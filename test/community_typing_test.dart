import 'dart:convert';
import 'package:chatterloop_app/core/requests/post_sse_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('anonymous typing self marker suppresses only the writer echo', () {
    PostActivityEvent parse(Map<String, dynamic> values) =>
        PostActivityEvent.fromFrame(jsonEncode({
          'auth': true,
          'status': true,
          'result': {
            'post_id': 'post',
            'event_type': 'typing',
            'is_anonymous': true,
            'entity': null,
            ...values,
          }
        }))!;
    final own = parse({'is_self': true});
    expect(own.isFromViewer('viewer'), isTrue);
    expect(own.actor!.entityId, 'anonymous');
    expect(own.actor!.handle, isNull);
    expect(parse({'is_self': false}).isFromViewer('viewer'), isFalse);
    expect(parse({}).isFromViewer('viewer'), isFalse);
    expect(
        parse({
          'is_anonymous': false,
          'entity': {'entity_id': 'viewer', 'name': 'Viewer'}
        }).isFromViewer('viewer'),
        isTrue);
  });
}
