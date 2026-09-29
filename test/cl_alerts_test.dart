// The app's notice surface. The widget test is the one that matters: the host
// exists so a notice can't be covered by whatever the app has open, so it has
// to be seen OVER a dialog.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(CLAlerts.resetForTest);

  group('the queue', () {
    test('the same notice twice is one notice', () {
      CLAlerts.error("We couldn't create that channel.");
      CLAlerts.error("We couldn't create that channel.");
      expect(CLAlerts.active.value, hasLength(1));
    });

    test('newest first, and never more than three', () {
      for (var i = 0; i < 5; i++) {
        CLAlerts.info('notice $i');
      }
      final shown = CLAlerts.active.value.map((a) => a.message).toList();
      expect(shown, ['notice 4', 'notice 3', 'notice 2']);
    });

    test('blank text is not a notice', () {
      CLAlerts.warning('   ');
      expect(CLAlerts.active.value, isEmpty);
    });
  });

  testWidgets('a notice shows above an open dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      builder: (context, child) => CLAlertHost(child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(content: Text('A dialog')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('A dialog'), findsOneWidget);

    CLAlerts.error('You are not allowed to create channels in this server.');
    await tester.pumpAndSettle();

    final notice =
        find.text('You are not allowed to create channels in this server.');
    expect(notice, findsOneWidget);

    // The tap lands on the NOTICE - dismissing it and leaving the dialog up.
    // Were the dialog's barrier on top, the same tap would close the dialog
    // and the notice would still be showing.
    await tester.tap(notice);
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(find.text('A dialog'), findsOneWidget);

    CLAlerts.clear();
  });

  testWidgets('a notice goes by itself', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.dark),
      builder: (context, child) => CLAlertHost(child: child!),
      home: const Scaffold(),
    ));
    CLAlerts.success('Saved.');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Saved.'), findsNothing);
  });
}
