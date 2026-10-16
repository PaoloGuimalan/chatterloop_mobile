import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/writing_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder richText(String text) => find.byWidgetPredicate((widget) =>
      widget is RichText && widget.text.toPlainText().contains(text));

  for (final lists in [
    '<ol><li>Parent row</li><ol><li>Child row</li></ol><li>Peer row</li></ol>',
    '<ol><li>Parent row</li><ul><li>Child row</li></ul><li>Peer row</li></ol>',
    '<ul><li>Parent row</li><ol><li>Child row</li></ol><li>Peer row</li></ul>',
    '<ol><li>Parent row<ol><li>Child row</li></ol></li><li>Peer row</li></ol>',
    '<ol><ol><li>Child row</li></ol><li>Peer row</li></ol>',
  ]) {
    testWidgets('reader preserves every legacy list item in $lists',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Scaffold(body: WritingHtmlBody(html: lists))));
      await tester.pumpAndSettle();
      expect(richText('Child row'), findsOneWidget);
      expect(richText('Peer row'), findsOneWidget);
      expect(tester.getTopLeft(richText('Child row')).dy,
          lessThan(tester.getTopLeft(richText('Peer row')).dy));
      expect(
          tester.getTopLeft(richText('Child row')).dx -
              tester.getTopLeft(richText('Peer row')).dx,
          closeTo(24, .1));
      if (lists.contains('Parent row')) {
        expect(richText('Parent row'), findsOneWidget);
        expect(tester.getTopLeft(richText('Parent row')).dy,
            lessThan(tester.getTopLeft(richText('Child row')).dy));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reader preserves nested numbering and indented legacy checklist',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: WritingHtmlBody(
                html: '<ul class="ql-list-checked"><li>Base check</li></ul>'
                    '<div class="checklist"><div class="checklist-item" style="padding-left:64px">'
                    '<input type="checkbox" checked disabled><label>&nbsp;Legacy check</label></div></div>'
                    '<ol><li>First number</li><li class="ql-indent-1">Child number</li>'
                    '<li class="ql-indent-2">Grandchild number</li><li class="ql-indent-1">Sibling number</li>'
                    '<li>Second number</li></ol>'
                    '<p>After list</p>'))));
    await tester.pumpAndSettle();
    expect(richText('1.'), findsOneWidget);
    expect(richText('a.'), findsOneWidget);
    expect(richText('i.'), findsOneWidget);
    expect(richText('b.'), findsOneWidget);
    expect(richText('2.'), findsOneWidget);
    expect(
        tester.getTopLeft(richText('Legacy check')).dx -
            tester.getTopLeft(richText('Base check')).dx,
        closeTo(48, .1));
    expect(
        tester.getTopLeft(richText('Child number')).dy -
            tester.getBottomLeft(richText('First number')).dy,
        closeTo(0, .1));
    expect(
        tester.getTopLeft(richText('After list')).dy -
            tester.getBottomLeft(richText('Second number')).dy,
        closeTo(12, .1));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'reader shows checklist state, indentation and heading in $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(brightness),
          home: const Scaffold(
              body: SizedBox(
                  width: 360,
                  child: WritingHtmlBody(
                    html: '<h2>A heading</h2><ul><li>Parent</li>'
                        '<li class="ql-indent-2">Indented</li><li>Peer</li></ul>'
                        '<ul class="ql-list-checked"><li>Done</li></ul>'
                        '<div class="checklist"><div class="checklist-item">'
                        '<input type="checkbox" disabled><label>&nbsp;Later</label>'
                        '</div></div><div class="ql-divider"></div>',
                  )))));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(richText('Done'), findsOneWidget);
      expect(richText('Later'), findsOneWidget);
      expect(tester.getCenter(find.byIcon(Icons.check_box_outlined)).dy,
          closeTo(tester.getCenter(richText('Done')).dy, 2));
      expect(
          tester.getTopLeft(richText('Indented')).dx -
              tester.getTopLeft(richText('Parent')).dx,
          closeTo(48, .1));
      expect(tester.getTopLeft(richText('Peer')).dx,
          tester.getTopLeft(richText('Parent')).dx);
      final heading = tester.widget<RichText>(richText('A heading'));
      expect(heading.text.style?.fontSize, 17);
      expect(heading.text.style?.height, 1.3);
      expect(heading.text.style?.fontWeight, FontWeight.w600);
      expect(
          tester.getTopLeft(richText('Parent')).dy -
              tester.getBottomLeft(richText('A heading')).dy,
          closeTo(8, .1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('writing editor theme follows the shared body and heading scale',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Builder(builder: (context) {
          final theme = writingEditorTheme(context);
          expect(theme.paragraph.style.fontFamily, 'Inter');
          expect(theme.paragraph.style.fontSize, 14);
          expect(theme.paragraph.style.height, 1.8);
          expect(theme.paragraph.spacing.bottom, 12);
          final headings = [
            theme.heading1,
            theme.heading2,
            theme.heading3,
            theme.heading4,
            theme.heading5,
            theme.heading6
          ];
          for (var i = 0; i < headings.length; i++) {
            expect(headings[i].style.fontSize, writingHeadingSizes[i]);
            expect(headings[i].style.height, 1.3);
            expect(headings[i].style.fontWeight, FontWeight.w600);
            expect(headings[i].spacing.top, 16);
            expect(headings[i].spacing.bottom, 8);
          }
          expect(theme.horizontalRule.thickness, 1);
          return const SizedBox();
        })));
  });
}
