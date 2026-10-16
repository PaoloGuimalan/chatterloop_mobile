import 'package:chatterloop_app/views/notes/note_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchment/parchment.dart';

void main() {
  test('legacy nested native lists retain their child and following peer', () {
    final doc = decodeNoteHtml(
        '<ul><li>Parent</li><ul><li>Child</li></ul><li>Peer</li></ul>');
    expect(doc.toPlainText(), 'Parent\nChild\nPeer\n');
    final again = decodeNoteHtml(encodeNoteHtml(doc));
    expect(again.toDelta(), doc.toDelta());
    doc.close();
    again.close();
  });
  for (final tag in ['ul', 'ol']) {
    test('flat $tag levels and nested native output retain every item in order',
        () {
      final doc = decodeNoteHtml(
          '<$tag><li class="ql-indent-2">First indented</li><li>Parent</li><li class="ql-indent-1">Child</li><li>Peer</li></$tag>');
      final encoded = encodeNoteHtml(doc);
      final again = decodeNoteHtml(encoded);
      expect(again.toPlainText(), doc.toPlainText());
      expect(again.toDelta(), doc.toDelta(), reason: encoded);
      doc.close();
      again.close();
    });
  }
  test('inline nodes remain one paragraph and literal markup remains text', () {
    final doc = decodeNoteHtml('<strong>Bold</strong> and &lt;literal&gt;');
    expect(doc.toPlainText(), 'Bold and <literal>\n');
    doc.close();
  });
  test(
      'web checklist states, heading, strike and indent survive native editing',
      () {
    final doc = decodeNoteHtml(
        '<h1>Heading</h1><p><s>Strike</s></p><ul class="ql-list-checked"><li class="ql-indent-2">Done</li></ul><ul class="ql-list-unchecked"><li>Later</li></ul>');
    final json = doc.toDelta().toJson().toString();
    expect(json, contains('checked: true'));
    expect(json, contains('indent: 2'));
    expect(json, contains('cl'));
    final encoded = encodeNoteHtml(doc);
    expect(encoded, contains('<s>Strike</s>'));
    expect(encoded, contains('ql-list-checked'));
    expect(encoded, contains('ql-list-unchecked'));
    expect(encoded, contains('ql-indent-2'));
    expect(encoded, isNot(contains('<input')));
    final again = decodeNoteHtml(encoded);
    expect(again.toDelta(), doc.toDelta());
    again.close();
    doc.close();
  });
  test('line breaks and blank paragraphs survive conversion', () {
    final doc = decodeNoteHtml('<p>First<br>Second</p><p><br></p><p>Last</p>');
    expect(doc.toPlainText(), 'First\nSecond\n\nLast\n');
    final again = decodeNoteHtml(encodeNoteHtml(doc));
    expect(again.toPlainText(), doc.toPlainText());
    again.close();
    doc.close();
  });
  test('a native divider is represented with markup retained by the Notes API',
      () {
    final doc = ParchmentDocument()..insert(0, BlockEmbed.horizontalRule);
    final html = encodeNoteHtml(doc);
    expect(html, contains('ql-divider'));
    final again = decodeNoteHtml(html);
    expect(again.toDelta(), doc.toDelta());
    again.close();
    doc.close();
  });
}
