import 'dart:convert';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart';
import 'package:parchment/codecs.dart';
import 'package:parchment/parchment.dart';

/// Use the same API-safe HTML as the web editor. The stock codec does not
/// understand Quill indentation/checklists and emits stripped tags for strike.
ParchmentDocument decodeWritingHtml(String value) {
  final root = _normalizeWritingHtml(value);
  for (final element in root.querySelectorAll('s,strike,b,i')) {
    final replacement = html.Element.tag({
      's': 'del',
      'strike': 'del',
      'b': 'strong',
      'i': 'em'
    }[element.localName]!);
    replacement.nodes.addAll(element.nodes.toList());
    element.replaceWith(replacement);
  }
  for (final element in root.querySelectorAll('.ql-divider')) {
    element.replaceWith(html.Element.tag('hr'));
  }
  // A <br> inside text is a real line break; the stock codec ignores it.
  for (final br in root.querySelectorAll('br')) {
    if (br.parentNode!.nodes.length > 1) br.replaceWith(html.Text('\n'));
  }
  for (final element in root.querySelectorAll('[class]')) {
    final indent = element.classes
        .where((c) => RegExp(r'^ql-indent-\d+$').hasMatch(c))
        .firstOrNull;
    if (indent != null && !['li', 'ul', 'ol'].contains(element.localName)) {
      element.attributes['style'] =
          '${element.attributes['style'] ?? ''};padding-left:${int.parse(indent.substring(10)) * 24}px;';
    }
  }
  final result = Delta();
  void append(html.Node node, [int depth = 0]) {
    if (node is html.Element && ['ul', 'ol'].contains(node.localName)) {
      for (final item in node.children) {
        // Older native HTML nests a list directly inside its parent list.
        // Quill/pasted HTML usually nests it inside the preceding li.
        if (['ul', 'ol'].contains(item.localName)) {
          append(item, depth + 1);
          continue;
        }
        if (item.localName != 'li') continue;
        final own = item.clone(true);
        own.querySelectorAll('ul,ol').forEach((list) => list.remove());
        final wrapper = html.Element.tag(node.localName!)..append(own);
        final part = parchmentHtml.decode(wrapper.outerHtml);
        final indentClass = item.classes
            .where((c) => RegExp(r'^ql-indent-\d+$').hasMatch(c))
            .firstOrNull;
        final indent =
            indentClass == null ? depth : int.parse(indentClass.substring(10));
        final checked = node.classes.contains('ql-list-checked') ||
            node.attributes['data-checked'] == 'true';
        final checklist = checked ||
            node.classes.contains('ql-list-unchecked') ||
            node.attributes.containsKey('data-checked');
        for (final operation in part.toDelta().toList()) {
          final attributes = {...?operation.attributes};
          if (operation.data == '\n') {
            if (checklist) {
              attributes[ParchmentAttribute.block.key] =
                  ParchmentAttribute.cl.value;
              if (checked) attributes[ParchmentAttribute.checked.key] = true;
            }
            if (indent > 0) attributes[ParchmentAttribute.indent.key] = indent;
          }
          result.insert(operation.data, attributes.isEmpty ? null : attributes);
        }
        part.close();
        for (final child in item.children
            .where((child) => ['ul', 'ol'].contains(child.localName))) {
          append(child, indent + 1);
        }
      }
    } else {
      final part = parchmentHtml.decode(node is html.Element
          ? node.outerHtml
          : const HtmlEscape().convert(node.text ?? ''));
      final indent = node is html.Element
          ? node.classes
              .where((c) => RegExp(r'^ql-indent-\d+$').hasMatch(c))
              .firstOrNull
          : null;
      for (final op in part.toDelta().toList()) {
        final attributes = {...?op.attributes};
        if (indent != null && op.data == '\n') {
          attributes[ParchmentAttribute.indent.key] =
              int.parse(indent.substring(10));
        }
        result.insert(op.data, attributes.isEmpty ? null : attributes);
      }
      part.close();
    }
  }

  // The stock encoder omits <p> for a single line. Keep consecutive inline
  // nodes together so opening "bold + plain text" does not add new lines.
  html.Element? paragraph;
  const blocks = {
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'blockquote',
    'pre',
    'hr'
  };
  for (final node in root.nodes.toList()) {
    if (node is html.Element && blocks.contains(node.localName)) {
      if (paragraph != null) {
        append(paragraph);
        paragraph = null;
      }
      append(node);
    } else {
      paragraph ??= html.Element.tag('p');
      paragraph.append(node);
    }
  }
  if (paragraph != null) append(paragraph);
  if (result.isEmpty) result.insert('\n');
  return ParchmentDocument.fromDelta(result);
}

String encodeWritingHtml(ParchmentDocument document) {
  final output = html.Element.tag('div');
  var line = Delta();
  void finish(Map<String, dynamic>? attributes) {
    final style = {...?attributes};
    final indent = style.remove(ParchmentAttribute.indent.key) as int? ?? 0;
    final checklist =
        style[ParchmentAttribute.block.key] == ParchmentAttribute.cl.value;
    final checked = style.remove(ParchmentAttribute.checked.key) == true;
    if (checklist) {
      style[ParchmentAttribute.block.key] = ParchmentAttribute.ul.value;
    }
    line.insert('\n', style.isEmpty ? null : style);
    // The stock multi-line encoder crashes on some decreasing indent levels.
    // Serialize one line at a time, keeping indentation in Quill's flat format.
    final part = ParchmentDocument.fromDelta(line);
    final root = parseFragment(parchmentHtml.encode(part));
    _normalizePresentation(root);
    part.close();
    line = Delta();
    for (final element in root.querySelectorAll('del')) {
      element.replaceWith(
          html.Element.tag('s')..nodes.addAll(element.nodes.toList()));
    }
    for (final rule in root.querySelectorAll('hr')) {
      rule.replaceWith(html.Element.tag('div')..classes.add('ql-divider'));
    }
    final list = root.querySelector('ul,ol');
    html.Element block;
    if (list != null) {
      block = list;
      if (checklist) {
        block.classes.add(checked ? 'ql-list-checked' : 'ql-list-unchecked');
      }
      if (indent > 0) {
        block.querySelector('li')!.classes.add('ql-indent-$indent');
      }
    } else if (root.nodes.length == 1 &&
        root.nodes.first is html.Element &&
        {'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'div', 'pre'}
            .contains((root.nodes.first as html.Element).localName)) {
      block = root.nodes.first as html.Element;
    } else {
      block = html.Element.tag('p')..nodes.addAll(root.nodes.toList());
      if (block.nodes.isEmpty) block.append(html.Element.tag('br'));
    }
    if (list == null && indent > 0) block.classes.add('ql-indent-$indent');
    final previous = output.children.lastOrNull;
    if (list != null &&
        previous?.localName == block.localName &&
        previous?.className == block.className) {
      previous!.nodes.addAll(block.nodes.toList());
    } else {
      output.append(block);
    }
  }

  for (final operation in document.toDelta().toList()) {
    if (operation.data is! String) {
      line.insert(operation.data, operation.attributes);
      continue;
    }
    final chunks = (operation.data as String).split('\n');
    for (var i = 0; i < chunks.length; i++) {
      if (chunks[i].isNotEmpty) line.insert(chunks[i], operation.attributes);
      if (i < chunks.length - 1) finish(operation.attributes);
    }
  }
  return output.innerHtml;
}

// This only prepares the in-memory representation; opening an old entry never
// rewrites its stored HTML. Older native Diary used disabled input/label pairs.
html.DocumentFragment _normalizeWritingHtml(String value) {
  final root = parseFragment(value);
  _normalizePresentation(root);
  for (final legacy in root.querySelectorAll('div.checklist')) {
    final replacement = html.Element.tag('div');
    for (final item in legacy.querySelectorAll('.checklist-item')) {
      final input = item.querySelector('input[type="checkbox"]');
      final label = item.querySelector('label');
      final li = html.Element.tag('li')
        ..classes.addAll(item.classes.where((c) => c != 'checklist-item'))
        ..attributes.addAll({
          if (item.attributes['style'] case final String style) 'style': style
        })
        ..nodes.addAll((label ?? item).nodes.toList());
      li.querySelectorAll('input').forEach((input) => input.remove());
      // The native codec inserted a nonbreaking spacer before the label.
      if (li.nodes.firstOrNull case final html.Text first) {
        first.data = first.data.replaceFirst(RegExp(r'^\u00a0'), '');
      }
      replacement.append(html.Element.tag('ul')
        ..classes.add(input?.attributes.containsKey('checked') == true
            ? 'ql-list-checked'
            : 'ql-list-unchecked')
        ..append(li));
    }
    for (final list in replacement.nodes.toList()) {
      legacy.parentNode!.insertBefore(list, legacy);
    }
    legacy.remove();
  }
  for (final element in root.querySelectorAll('.ql-divider')) {
    element.replaceWith(html.Element.tag('hr'));
  }
  return root;
}

void _normalizePresentation(html.DocumentFragment root) {
  for (final element in root.querySelectorAll('[style]')) {
    final styles = <String, String>{};
    for (final declaration in element.attributes['style']!.split(';')) {
      final separator = declaration.indexOf(':');
      if (separator > 0) {
        styles[declaration.substring(0, separator).trim().toLowerCase()] =
            declaration.substring(separator + 1).trim();
      }
    }
    // The older Parchment HTML codec encoded each indent as 32 CSS pixels.
    final padding = styles['padding-left'];
    final pixels =
        padding == null ? null : RegExp(r'^(\d+)px$').firstMatch(padding);
    if (pixels != null) {
      final width = int.parse(pixels.group(1)!);
      if (width > 0 &&
          width % 32 == 0 &&
          !element.classes.any((c) => RegExp(r'^ql-indent-\d+$').hasMatch(c))) {
        element.classes.add('ql-indent-${width ~/ 32}');
        styles.remove('padding-left');
      }
    }
    // Stock quote presentation overrides the shared theme in HTML readers.
    if (element.localName == 'blockquote') {
      styles.removeWhere((key, _) =>
          key == 'margin' ||
          key.startsWith('margin-') ||
          key == 'border-left' ||
          key.startsWith('border-left-') ||
          key == 'padding-left');
    }
    if (styles.isEmpty) {
      element.attributes.remove('style');
    } else {
      element.attributes['style'] = styles.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .join(';');
    }
  }
}

/// Reader-compatible markup for Quill classes and legacy native Diary HTML.
/// Checklist markers are rendered as read-only widgets by WritingHtmlBody.
String writingHtmlForReader(String value) {
  final root = _normalizeWritingHtml(value);
  // HtmlWidget counts every flat li in one sequence. Quill instead keeps a
  // counter per indentation level and cycles decimal/alpha/roman markers.
  // Give each read-only item its own explicit start/type, without inventing
  // parent items when the first item is indented. Stored HTML stays canonical.
  bool isList(html.Element element) => ['ul', 'ol'].contains(element.localName);
  bool hasListParent(html.Element element, [html.Element? until]) {
    for (var parent = element.parent;
        parent != null && parent != until;
        parent = parent.parent) {
      if (isList(parent)) return true;
    }
    return false;
  }

  // Walk both legacy shapes: nested lists directly under a list, or inside
  // the preceding li. Flatten only this display copy, preserving mixed types
  // and item order before giving every item its explicit marker and depth.
  for (final list in root
      .querySelectorAll('ul,ol')
      .where((list) => !hasListParent(list))
      .toList()) {
    final counters = <int, int>{};
    final blocks = <html.Element>[];
    void walk(html.Element source, int depth) {
      for (final item in source.children) {
        if (isList(item)) {
          walk(item, depth + 1);
          continue;
        }
        if (item.localName != 'li') continue;
        final indent = item.classes
            .where((c) => RegExp(r'^ql-indent-\d+$').hasMatch(c))
            .firstOrNull;
        final level = indent == null ? depth : int.parse(indent.substring(10));
        final own = item.clone(true);
        own.querySelectorAll('ul,ol').forEach((list) => list.remove());
        own.classes.removeWhere((c) => RegExp(r'^ql-indent-\d+$').hasMatch(c));
        if (level > 0) own.classes.add('ql-indent-$level');
        final block = source.clone(false)
          ..classes.removeWhere((c) => RegExp(r'^ql-indent-\d+$').hasMatch(c))
          ..attributes['style'] =
              '${source.attributes['style'] ?? ''};margin-top:0;margin-bottom:0px;'
          ..append(own);
        counters.removeWhere((depth, _) => depth > level);
        if (source.localName == 'ol') {
          final index = (counters[level] ??
                  (int.tryParse(source.attributes['start'] ?? '') ?? 1) - 1) +
              1;
          counters[level] = index;
          block.attributes['start'] = '$index';
          block.attributes['type'] = ['1', 'a', 'i'][level % 3];
        }
        blocks.add(block);
        for (final nested in item
            .querySelectorAll('ul,ol')
            .where((nested) => !hasListParent(nested, item))) {
          walk(nested, level + 1);
        }
      }
    }

    walk(list, 0);
    if (blocks.isNotEmpty) {
      final last = blocks.last;
      last.attributes['style'] =
          '${last.attributes['style']}margin-bottom:12px;';
    }
    for (final block in blocks) {
      list.parentNode!.insertBefore(block, list);
    }
    list.remove();
  }
  for (final list in root.querySelectorAll('ul,ol')) {
    final checked = list.classes.contains('ql-list-checked') ||
        list.attributes['data-checked'] == 'true';
    final checklist = checked ||
        list.classes.contains('ql-list-unchecked') ||
        list.attributes.containsKey('data-checked');
    if (!checklist) continue;
    for (final item
        in list.children.where((child) => child.localName == 'li')) {
      item.attributes['style'] =
          '${item.attributes['style'] ?? ''};list-style-type:none;';
      item.nodes.insert(
          0,
          html.Element.tag('span')
            ..attributes['data-writing-checkbox'] = checked ? 'true' : 'false');
    }
  }
  for (final element in root.querySelectorAll('[class]')) {
    final indent = element.classes
        .where((c) => RegExp(r'^ql-indent-\d+$').hasMatch(c))
        .firstOrNull;
    if (indent != null) {
      element.attributes['style'] =
          '${element.attributes['style'] ?? ''};margin-left:${int.parse(indent.substring(10)) * 24}px;';
    }
  }
  return root.nodes
      .map((node) => node is html.Element
          ? node.outerHtml
          : const HtmlEscape().convert(node.text ?? ''))
      .join();
}
