import 'package:chatterloop_app/models/messages_models/reply_target_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a quoted message carries the card it held (attached)", () {
    final t = ReplyTarget.tryParse({
      "type": "message",
      "id": "m1",
      "status": "active",
      "content": {
        "message_type": "post",
        "text": "Sent a post",
        "attached": {
          "type": "post",
          "id": "p1",
          "status": "active",
          "content": {"caption": "hello"}
        }
      }
    });
    expect(t!.text, "Sent a post");
    expect(t.attached?.type, "post");
    expect(t.attached?.caption, "hello");
  });

  test("no attached card on an ordinary quote", () {
    final t = ReplyTarget.tryParse({
      "type": "message",
      "id": "m2",
      "status": "active",
      "content": {"message_type": "text", "text": "hi"}
    });
    expect(t!.attached, isNull);
  });
}
