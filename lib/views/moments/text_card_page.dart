import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/text_card_image.dart';
import 'package:flutter/material.dart';

/// Writing a text layer: the words, their colour, bold or not, on a box or
/// not, and which way they line up - seen as they will look.
///
/// Pops with the [TextCard], or null when nothing is to be added.
class TextCardPage extends StatefulWidget {
  final TextCard? initial;

  const TextCardPage({super.key, this.initial});

  static Future<TextCard?> open(BuildContext context, {TextCard? initial}) =>
      Navigator.of(context, rootNavigator: true).push<TextCard>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => TextCardPage(initial: initial),
        ),
      );

  static const colors = [
    0xFFFFFFFF,
    0xFF000000,
    0xFFFFD60A,
    0xFFFF453A,
    0xFFFF9F0A,
    0xFF30D158,
    0xFF64D2FF,
    0xFF0A84FF,
    0xFFBF5AF2,
    0xFFFF375F,
  ];

  @override
  State<TextCardPage> createState() => _TextCardPageState();
}

class _TextCardPageState extends State<TextCardPage> {
  late TextCard _card = widget.initial ?? const TextCard(text: '');
  late final _words = TextEditingController(text: _card.text);

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  void _nextAlign() => setState(() => _card = _card.copyWith(
      align: switch (_card.align) {
        'center' => 'left',
        'left' => 'right',
        _ => 'center',
      }));

  IconData get _alignIcon => switch (_card.align) {
        'left' => Icons.format_align_left_rounded,
        'right' => Icons.format_align_right_rounded,
        _ => Icons.format_align_center_rounded,
      };

  Widget _toggle(
          {required IconData icon,
          required String tooltip,
          required bool on,
          required VoidCallback onTap}) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: on ? Colors.white : Colors.white12,
          foregroundColor: on ? Colors.black : Colors.white,
        ),
        icon: Icon(icon),
      );

  @override
  Widget build(BuildContext context) {
    final color = Color(_card.argb);
    final written = _words.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFF15181D),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: "Don't add",
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text("Text",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: CLType.screenTitle,
                            fontWeight: FontWeight.w800)),
                  ),
                  CLBtn(
                    label: "Done",
                    size: CLBtnSize.sm,
                    onPressed: written
                        ? () => Navigator.pop(
                            context, _card.copyWith(text: _words.text.trim()))
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: _card.boxed
                        ? const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8)
                        : EdgeInsets.zero,
                    decoration: _card.boxed
                        ? BoxDecoration(
                            color: TextCardImage.boxColorFor(color),
                            borderRadius: BorderRadius.circular(10),
                          )
                        : null,
                    child: IntrinsicWidth(
                      child: TextField(
                        controller: _words,
                        autofocus: true,
                        maxLines: null,
                        minLines: 1,
                        textAlign: TextCardImage.alignOf(_card),
                        cursorColor: color,
                        style: TextCardImage.styleOf(_card, size: 32),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                          hintText: "Type something",
                          hintStyle: TextCardImage.styleOf(_card, size: 32)
                              .copyWith(color: color.withValues(alpha: 0.4)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _toggle(
                    icon: Icons.format_bold_rounded,
                    tooltip: "Bold",
                    on: _card.bold,
                    onTap: () =>
                        setState(() => _card = _card.copyWith(bold: !_card.bold)),
                  ),
                  const SizedBox(width: 10),
                  _toggle(
                    icon: Icons.format_color_fill_rounded,
                    tooltip: "Box behind",
                    on: _card.boxed,
                    onTap: () => setState(
                        () => _card = _card.copyWith(boxed: !_card.boxed)),
                  ),
                  const SizedBox(width: 10),
                  _toggle(
                    icon: _alignIcon,
                    tooltip: "Line up",
                    on: false,
                    onTap: _nextAlign,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
                children: [
                  for (final argb in TextCardPage.colors)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _card = _card.copyWith(argb: argb)),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(argb),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: argb == _card.argb
                                  ? Colors.white
                                  : Colors.white24,
                              width: argb == _card.argb ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
