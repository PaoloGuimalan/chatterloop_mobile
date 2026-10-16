import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/utils/writing_html.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

const writingHeadingSizes = <double>[24, 17, 15, 14, 13.5, 13];

TextStyle writingBodyStyle(CLPalette p) =>
    TextStyle(fontFamily: 'Inter', color: p.text, fontSize: 14, height: 1.8);

/// Shared native Notes/Diary editor typography, matching the web writing body.
FleatherThemeData writingEditorTheme(BuildContext context) {
  final p = cl(context);
  final body = writingBodyStyle(p);
  TextBlockTheme heading(int level) => TextBlockTheme(
      style: body.copyWith(
          fontSize: writingHeadingSizes[level - 1],
          fontWeight: FontWeight.w600,
          height: 1.3),
      spacing: const VerticalSpacing(top: 16, bottom: 8));
  return FleatherThemeData.fallback(context).copyWith(
    paragraph:
        TextBlockTheme(style: body, spacing: const VerticalSpacing(bottom: 12)),
    heading1: heading(1),
    heading2: heading(2),
    heading3: heading(3),
    heading4: heading(4),
    heading5: heading(5),
    heading6: heading(6),
    lists:
        TextBlockTheme(style: body, spacing: const VerticalSpacing(bottom: 12)),
    quote: TextBlockTheme(
        style: body.copyWith(color: p.text2),
        spacing: const VerticalSpacing(top: 12, bottom: 12),
        decoration: const BoxDecoration(
            border: BorderDirectional(
                start: BorderSide(color: CLColors.brand, width: 3)))),
    link: const TextStyle(
        color: CLColors.brand, decoration: TextDecoration.underline),
    horizontalRuleThemeData:
        HorizontalRuleThemeData(height: 37, thickness: 1, color: p.border),
  );
}

class WritingHtmlBody extends StatelessWidget {
  const WritingHtmlBody({super.key, required this.html});
  final String html;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    String cssColor(Color color) =>
        '#${color.toARGB32().toRadixString(16).substring(2)}';
    return HtmlWidget(
      writingHtmlForReader(html),
      textStyle: writingBodyStyle(p),
      customStylesBuilder: (element) {
        final name = element.localName ?? '';
        if (RegExp(r'^h[1-6]$').hasMatch(name)) {
          return {
            'font-size':
                '${writingHeadingSizes[int.parse(name.substring(1)) - 1]}px',
            'font-weight': '600',
            'line-height': '1.3',
            'margin-top': '16px',
            'margin-bottom': '8px',
            'margin-left': '0',
            'margin-right': '0'
          };
        }
        return switch (name) {
          'p' => {'margin-top': '0', 'margin-bottom': '12px'},
          'ul' || 'ol' => {
              'margin-top': '0',
              'margin-bottom': '12px',
              'padding-left': '24px'
            },
          'blockquote' => {
              'border-left': '3px solid ${cssColor(CLColors.brand)}',
              'padding-left': '12px',
              'margin': '12px 0',
              'color': cssColor(p.text2)
            },
          'hr' => {
              'border': '0',
              'border-top': '1px solid ${cssColor(p.border)}',
              'margin': '18px 0'
            },
          _ => null,
        };
      },
      customWidgetBuilder: (element) {
        final value = element.attributes['data-writing-checkbox'];
        if (value == null) return null;
        final checked = value == 'true';
        return InlineCustomWidget(
            alignment: PlaceholderAlignment.middle,
            child: Semantics(
                checked: checked,
                readOnly: true,
                label: checked ? 'Checked' : 'Unchecked',
                child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                        checked
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 16,
                        color: checked ? p.brand : p.text2))));
      },
      onTapUrl: (url) async {
        final uri = Uri.tryParse(url);
        if (uri == null) return false;
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}
