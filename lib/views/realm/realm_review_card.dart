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
  final bool loading;
  final ValueChanged<T>? onChanged;
  const RealmReviewTabs(
      {super.key,
      required this.tabs,
      required this.value,
      required this.onChanged,
      this.loading = false});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final style = TextStyle(
        fontFamily: 'Inter',
        fontSize: CLType.bodySm,
        fontWeight: FontWeight.w600);
    return Container(
        padding: loading ? EdgeInsets.zero : const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: p.surface3, borderRadius: BorderRadius.circular(CLRadii.sm)),
        child: LayoutBuilder(builder: (context, constraints) {
          // Measure the same inner width in both states, but replace the whole
          // navigation surface while loading, including its outer padding.
          final availableWidth = loading
              ? (constraints.maxWidth - 6).clamp(0.0, double.infinity)
              : constraints.maxWidth;
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
            final width = desired > availableWidth ? availableWidth : desired;
            if (rows.isEmpty || used + 4 + width > availableWidth) {
              rows.add([]);
              used = 0;
            }
            if (rows.last.isNotEmpty) used += 4;
            rows.last.add((value: tab.value, label: tab.label, width: width));
            used += width;
          }
          if (loading) {
            final minimumHeight = Theme.of(context).materialTapTargetSize ==
                    MaterialTapTargetSize.padded
                ? kMinInteractiveDimension
                : 40.0;
            var height = 6.0;
            for (final row in rows) {
              final extra = (availableWidth -
                      row.fold<double>(0, (sum, item) => sum + item.width) -
                      4 * (row.length - 1)) /
                  row.length;
              var rowHeight = minimumHeight;
              for (final tab in row) {
                final painter = TextPainter(
                    text: TextSpan(text: tab.label, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context))
                  ..layout(
                      maxWidth:
                          (tab.width + extra - 20).clamp(0.0, double.infinity));
                final textHeight = painter.height + 16;
                painter.dispose();
                if (textHeight > rowHeight) rowHeight = textHeight;
              }
              height += rowHeight;
            }
            height += rows.isEmpty ? minimumHeight : (rows.length - 1) * 4;
            return CLSkeleton(
                width: constraints.maxWidth,
                height: height,
                baseColor: Theme.of(context).brightness == Brightness.light
                    ? p.surface
                    : null,
                highlightColor: Theme.of(context).brightness == Brightness.light
                    ? p.surface2
                    : null,
                borderRadius: BorderRadius.circular(CLRadii.sm));
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

/// Mirrors the compact name, context line and decision actions of a join/invite.
class RealmRequestReviewSkeleton extends StatelessWidget {
  const RealmRequestReviewSkeleton({super.key});
  @override
  Widget build(BuildContext context) => const RealmReviewCard(
      child: Padding(
          padding: EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FractionallySizedBox(
                widthFactor: .55,
                child: CLSkeleton(width: double.infinity, height: 16)),
            SizedBox(height: 6),
            FractionallySizedBox(
                widthFactor: .8,
                child: CLSkeleton(width: double.infinity, height: 14)),
            SizedBox(height: 10),
            RealmReviewActions(children: [
              CLSkeleton(width: 88, height: 40),
              CLSkeleton(width: 88, height: 40),
            ]),
          ])));
}
