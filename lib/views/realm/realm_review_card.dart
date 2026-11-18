import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/design/tokens.dart';

/// Existing realm card styling with consistent spacing between review items.
class RealmReviewCard extends StatelessWidget {
  final Widget child;
  const RealmReviewCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CLCard(
          padding: EdgeInsets.zero,
          child: Material(type: MaterialType.transparency, child: child)));
}

/// Keeps existing controls content-sized, with a gap when narrow layouts stack.
class RealmReviewActions extends StatelessWidget {
  final List<Widget> children;
  const RealmReviewActions({super.key, required this.children});

  @override
  Widget build(BuildContext context) => OverflowBar(
      alignment: MainAxisAlignment.end,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: 8,
      overflowSpacing: 8,
      children: [for (final child in children) IntrinsicWidth(child: child)]);
}

/// Text-only review selections, sharing each row's width as on mobile web.
class RealmReviewTabs<T> extends StatelessWidget {
  final List<({T value, String label})> tabs;
  final T? value;
  final ValueChanged<T>? onChanged;
  const RealmReviewTabs(
      {super.key,
      required this.tabs,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final style = TextStyle(
        fontFamily: 'Inter',
        fontSize: CLType.bodySm,
        fontWeight: FontWeight.w600);
    return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: p.surface3, borderRadius: BorderRadius.circular(CLRadii.sm)),
        child: LayoutBuilder(builder: (context, constraints) {
          final rows = <List<({T value, String label, double width})>>[];
          var used = 0.0;
          for (final tab in tabs) {
            final painter = TextPainter(
                text: TextSpan(text: tab.label, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context))
              ..layout();
            final desired = painter.width + 20;
            painter.dispose();
            final width =
                desired > constraints.maxWidth ? constraints.maxWidth : desired;
            if (rows.isEmpty || used + 4 + width > constraints.maxWidth) {
              rows.add([]);
              used = 0;
            }
            if (rows.last.isNotEmpty) used += 4;
            rows.last.add((value: tab.value, label: tab.label, width: width));
            used += width;
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const SizedBox(height: 4),
              Builder(builder: (context) {
                final row = rows[index];
                final extra = (constraints.maxWidth -
                        row.fold<double>(0, (sum, item) => sum + item.width) -
                        4 * (row.length - 1)) /
                    row.length;
                return Row(children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    SizedBox(
                        width: row[i].width + extra,
                        child: Semantics(
                            selected: row[i].value == value,
                            child: TextButton(
                                onPressed: onChanged == null
                                    ? null
                                    : () => onChanged!(row[i].value),
                                style: TextButton.styleFrom(
                                    minimumSize: const Size(0, 40),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    textStyle: style,
                                    backgroundColor: row[i].value == value
                                        ? p.surface
                                        : Colors.transparent,
                                    foregroundColor: row[i].value == value
                                        ? p.text
                                        : p.text2,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(CLRadii.xs))),
                                child: Text(row[i].label,
                                    textAlign: TextAlign.center))))
                  ]
                ]);
              })
            ]
          ]);
        }));
  }
}
