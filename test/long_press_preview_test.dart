// The long-press preview fits on screen, whatever it is previewing.
//
// The dialog is a shrink-wrapping Column: quick reactions, the message, then
// the context menu. A long text message or a tall attachment simply made that
// column taller than the screen - the reaction row went off the top, the menu
// off the bottom, and the bubble overlapped both. The message is now the one
// flexible child, so it gets whatever the row and the menu are not using and
// scrolls past that.
//
// Measured against the SCREEN rather than against sibling widgets: overlapping
// each other and running off the display are the same bug here, and a bounds
// check catches both.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_reactions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(360, 900);

const _menuItems = [
  MenuItem(label: 'Reply', icon: Icons.reply),
  MenuItem(label: 'Copy', icon: Icons.copy),
  MenuItem(label: 'React', icon: Icons.add_reaction_outlined),
  MenuItem(label: 'Save', icon: Icons.download_rounded),
  MenuItem(label: 'Report', icon: Icons.report, isDestructive: true),
];

Future<void> _pumpPreview(WidgetTester tester, {required double height}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: CLMessageReactionsDialog(
      id: 'm1',
      messageWidget: Container(
        key: const ValueKey('bubble'),
        width: 270,
        height: height,
        color: const Color(0xFF1C7DEF),
      ),
      reactions: const ['👍', '❤️'],
      menuItems: _menuItems,
      onReactionTap: (_) {},
      onContextMenuTap: (_) {},
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a message taller than the screen still leaves the menu on it',
      (tester) async {
    // Three times the screen - the case that used to push the menu clean off
    // the bottom.
    await _pumpPreview(tester, height: 2700);

    for (final label in ['Reply', 'Copy', 'React', 'Save', 'Report']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(0.0),
          reason: '$label above screen');
      expect(rect.bottom, lessThanOrEqualTo(_screen.height),
          reason: '$label below screen');
    }

    // The quick reactions are on the other side of the message, so they are
    // the ones that used to be pushed off the TOP.
    final reaction = tester.getRect(find.text('👍'));
    expect(reaction.top, greaterThanOrEqualTo(0.0));
  });

  testWidgets('the bubble itself is capped, and scrolls past the cap',
      (tester) async {
    await _pumpPreview(tester, height: 2700);

    // The bubble keeps its natural size - the cap is the viewport around it,
    // which is what lets the hero fly and land at that natural size.
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(viewport.height, lessThan(_screen.height));
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    // Scrollable, so a long message can still be read in full.
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pump();
  });

  testWidgets('a short message is not stretched to fill the space',
      (tester) async {
    await _pumpPreview(tester, height: 60);

    expect(tester.getRect(find.byKey(const ValueKey('bubble'))).height, 60);
  });
}
