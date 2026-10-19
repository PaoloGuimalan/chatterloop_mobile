import 'package:chatterloop_app/core/notifications/notification_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
      'worker processing preserves circular transparent avatars and square content images',
      () async {
    final source = img.Image(width: 400, height: 200);
    img.fill(source, color: img.ColorRgb8(220, 40, 20));
    final jpeg = img.encodeJpg(source);
    final avatarBytes = await NotificationRenderer.processNotificationImage(
        jpeg,
        circle: true,
        size: 128);
    final avatar = img.decodePng(avatarBytes!)!;
    expect(avatar.width, 128);
    expect(avatar.height, 128);
    expect(avatar.getPixel(0, 0).a, 0);
    expect(avatar.getPixel(64, 64).a, 255);
    final contentBytes = await NotificationRenderer.processNotificationImage(
        jpeg,
        circle: false,
        size: 64);
    final content = img.decodePng(contentBytes!)!;
    expect(content.width, 64);
    expect(content.height, 64);
    expect(content.getPixel(0, 0).a, 255);
  });
}
