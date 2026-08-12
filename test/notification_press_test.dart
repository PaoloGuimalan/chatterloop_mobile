// The notification row's press feedback.
//
// Regression guard for a specific bug: the row used to be
// Material(transparent) > InkWell > Container(opaque colour), so the ink
// splash painted UNDERNEATH the background and the row looked dead while
// responding to taps perfectly well. Structure is what makes it visible, so
// structure is what this asserts.
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/notification_row.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationV2 _n({required bool withRoute}) => NotificationV2(
      notificationID: 'n1',
      referenceID: 'r1',
      referenceStatus: null,
      fromUserID: 'u1',
      headline: 'Post Reaction',
      details: 'reacted to your post.',
      date: '2026-08-12',
      time: null,
      type: 'post_reaction',
      isRead: false,
      redirects: withRoute
          ? [
              NotificationRedirect(
                platform: kNotificationPlatform,
                type: 'post',
                route: '/post/P1',
              )
            ]
          : const [],
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

void main() {
  testWidgets('a tappable row changes colour while pressed, and reverts',
      (tester) async {
    await _pump(
      tester,
      CLNotificationRow(
        notification: _n(withRoute: true),
        busy: false,
        onAccept: (_) {},
        onDecline: (_) {},
        onOpen: (_) {},
      ),
    );

    Color? rowColour() => tester
        .widget<Material>(find
            .ancestor(
                of: find.byType(InkWell).first, matching: find.byType(Material))
            .first)
        .color;

    final resting = rowColour();
    expect(resting, isNotNull);

    // Press and HOLD - the colour must change while the finger is down. This
    // is the property an InkWell alone could not give: its splash is an
    // animation that the navigation on tap tears down before it is visible.
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InkWell).first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(rowColour(), isNot(resting),
        reason: 'row should visibly highlight while held');

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(rowColour(), resting, reason: 'row should revert once released');
  });

  testWidgets('a row with no destination has no InkWell at all', (tester) async {
    await _pump(
      tester,
      CLNotificationRow(
        notification: _n(withRoute: false),
        busy: false,
        onAccept: (_) {},
        onDecline: (_) {},
        onOpen: (_) {},
      ),
    );
    // No press feedback where a press would do nothing.
    expect(find.byType(InkWell), findsNothing);
  });
}
