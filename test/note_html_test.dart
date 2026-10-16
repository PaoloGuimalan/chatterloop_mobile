import 'package:chatterloop_app/core/utils/writing_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchment/parchment.dart';
import 'package:html/parser.dart';

void main() {
  test(
      'reader numbers flat list levels separately, including orphan first indent',
      () {
    final html = writingHtmlForReader('<ol><li class="ql-indent-2">Orphan</li>'
        '<li>Parent</li><li class="ql-indent-1">Child</li>'
        '<li class="ql-indent-2">Grandchild</li><li>Peer</li></ol>');
    final lists = parseFragment(html).querySelectorAll('ol');
    expect(lists.map((e) => e.attributes['type']), ['i', '1', 'a', 'i', '1']);
    expect(lists.map((e) => e.attributes['start']), ['1', '1', '1', '1', '2']);
    expect(
        lists
            .take(4)
            .every((e) => e.attributes['style']!.contains('margin-bottom:0px')),
        isTrue);
    expect(lists.last.attributes['style'], contains('margin-bottom:12px'));
  });
  test('legacy indented native Diary checklist retains its class and style',
      () {
    const html =
        '<div class="checklist"><div class="checklist-item" style="padding-left:64px;color:red">'
        '<input type="checkbox" checked disabled><label>&nbsp;Done</label></div></div>';
    final doc = decodeWritingHtml(html);
    expect(doc.toDelta().toJson().toString(), contains('indent: 2'));
    final rendered = writingHtmlForReader(html);
    expect(rendered, contains('ql-indent-2'));
    expect(rendered, contains('margin-left:48px'));
    expect(rendered, contains('color:red'));
    doc.close();
  });
  test(
      'quote presentation is shared and legacy numeric indentation retains levels',
      () {
    final doc = decodeWritingHtml(
        '<blockquote style="margin:0 0 0 0.8ex; border-left:1px solid gray; padding-left:1ex">Quote</blockquote>'
        '<p style="padding-left:64px">Indented</p>');
    final encoded = encodeWritingHtml(doc);
    expect(encoded, isNot(contains('border-left')));
    expect(encoded, isNot(contains('1ex')));
    expect(encoded, contains('ql-indent-2'));
    final again = decodeWritingHtml(encoded);
    expect(again.toDelta(), doc.toDelta());
    expect(
        writingHtmlForReader(
            '<blockquote style="margin:0; border-left:1px solid gray;padding-left:1ex">Quote</blockquote>'),
        '<blockquote>Quote</blockquote>');
    doc.close();
    again.close();
  });
  test('legacy Diary checklist states and literal label markup survive', () {
    final doc = decodeWritingHtml('<div class="checklist">'
        '<div class="checklist-item"><input type="checkbox" checked disabled>'
        '<label>&nbsp;<strong>Done</strong> &lt;literal&gt;</label></div>'
        '<div class="checklist-item"><input type="checkbox" disabled>'
        '<label>&nbsp;Later</label></div></div>');
    expect(doc.toPlainText(), 'Done <literal>\nLater\n');
    final encoded = encodeWritingHtml(doc);
    expect(encoded, contains('ql-list-checked'));
    expect(encoded, contains('ql-list-unchecked'));
    expect(encoded, contains('&lt;literal&gt;'));
    final again = decodeWritingHtml(encoded);
    expect(again.toDelta(), doc.toDelta());
    doc.close();
    again.close();
  });
  test('legacy nested native lists retain their child and following peer', () {
    final doc = decodeWritingHtml(
        '<ul><li>Parent</li><ul><li>Child</li></ul><li>Peer</li></ul>');
    expect(doc.toPlainText(), 'Parent\nChild\nPeer\n');
    final again = decodeWritingHtml(encodeWritingHtml(doc));
    expect(again.toDelta(), doc.toDelta());
    doc.close();
    again.close();
  });
  for (final tag in ['ul', 'ol']) {
    test('flat $tag levels and nested native output retain every item in order',
        () {
      final doc = decodeWritingHtml(
          '<$tag><li class="ql-indent-2">First indented</li><li>Parent</li><li class="ql-indent-1">Child</li><li>Peer</li></$tag>');
      final encoded = encodeWritingHtml(doc);
      final again = decodeWritingHtml(encoded);
      expect(again.toPlainText(), doc.toPlainText());
      expect(again.toDelta(), doc.toDelta(), reason: encoded);
      doc.close();
      again.close();
    });
  }
  test('inline nodes remain one paragraph and literal markup remains text', () {
    final doc = decodeWritingHtml('<strong>Bold</strong> and &lt;literal&gt;');
    expect(doc.toPlainText(), 'Bold and <literal>\n');
    doc.close();
  });
  test(
      'web checklist states, heading, strike and indent survive native editing',
      () {
    final doc = decodeWritingHtml(
        '<h1>Heading</h1><p><s>Strike</s></p><ul class="ql-list-checked"><li class="ql-indent-2">Done</li></ul><ul class="ql-list-unchecked"><li>Later</li></ul>');
    final json = doc.toDelta().toJson().toString();
    expect(json, contains('checked: true'));
    expect(json, contains('indent: 2'));
    expect(json, contains('cl'));
    final encoded = encodeWritingHtml(doc);
    expect(encoded, contains('<s>Strike</s>'));
    expect(encoded, contains('ql-list-checked'));
    expect(encoded, contains('ql-list-unchecked'));
    expect(encoded, contains('ql-indent-2'));
    expect(encoded, isNot(contains('<input')));
    final again = decodeWritingHtml(encoded);
    expect(again.toDelta(), doc.toDelta());
    again.close();
    doc.close();
  });
  test('line breaks and blank paragraphs survive conversion', () {
    final doc =
        decodeWritingHtml('<p>First<br>Second</p><p><br></p><p>Last</p>');
    expect(doc.toPlainText(), 'First\nSecond\n\nLast\n');
    final again = decodeWritingHtml(encodeWritingHtml(doc));
    expect(again.toPlainText(), doc.toPlainText());
    again.close();
    doc.close();
  });
  test('a native divider is represented with markup retained by the Notes API',
      () {
    final doc = ParchmentDocument()..insert(0, BlockEmbed.horizontalRule);
    final html = encodeWritingHtml(doc);
    expect(html, contains('ql-divider'));
    final again = decodeWritingHtml(html);
    expect(again.toDelta(), doc.toDelta());
    again.close();
    doc.close();
  });
}
