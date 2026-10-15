import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';

class _Line extends StatelessWidget {
  const _Line(this.fraction, {this.height = 12});
  final double fraction;
  final double height;
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
      widthFactor: fraction,
      alignment: Alignment.centerLeft,
      child: CLSkeleton(width: double.infinity, height: height));
}

class _BodyLines extends StatelessWidget {
  const _BodyLines({this.lines = 3, this.step = 8});
  final int lines;
  final double step;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < lines; i++) ...[
          _Line(i == lines - 1
              ? .64
              : i.isEven
                  ? .96
                  : .88),
          if (i < lines - 1) SizedBox(height: step),
        ]
      ]);
}

/// Mirrors the two-column, 235px note cards including their footer controls.
class NotesListSkeleton extends StatelessWidget {
  const NotesListSkeleton(
      {super.key = const ValueKey('writing-notes-skeleton')});
  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Semantics(
        label: 'Loading notes',
        child: ExcludeSemantics(
            child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 235),
          itemCount: 8,
          itemBuilder: (_, index) => Container(
              padding: const EdgeInsets.fromLTRB(12, 13, 8, 5),
              decoration: BoxDecoration(
                  color: p.surface,
                  border: Border.all(color: p.border),
                  borderRadius: BorderRadius.circular(14)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Line(.82, height: 15),
                    const SizedBox(height: 12),
                    _BodyLines(lines: index.isEven ? 6 : 4),
                    const Spacer(),
                    const SizedBox(
                        height: 48,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              CLSkeleton(width: 38, height: 10),
                              Padding(
                                  padding: EdgeInsets.only(right: 12),
                                  child: CLSkeleton(width: 12, height: 18))
                            ])),
                  ])),
        )));
  }
}

/// Same date headings, card surfaces, title/mood row, tags, body and metadata.
class DiaryListSkeleton extends StatelessWidget {
  const DiaryListSkeleton(
      {super.key = const ValueKey('writing-diary-skeleton')});
  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Semantics(
        label: 'Loading diary entries',
        child: ExcludeSemantics(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
              for (var day = 0; day < 3; day++) ...[
                Padding(
                    padding:
                        const EdgeInsets.only(left: 2, top: 13, bottom: 10),
                    child: SizedBox(
                        height: 16,
                        child: Row(children: [
                          const CLSkeleton(width: 115, height: 13),
                          const SizedBox(width: 10),
                          Expanded(child: Divider(color: p.border, height: 1))
                        ]))),
                for (var i = 0; i < (day == 0 ? 2 : 1); i++)
                  Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                          color: p.surface,
                          border: Border.all(color: p.border),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                                height: 19,
                                child: Row(children: [
                                  Expanded(child: _Line(.86, height: 17)),
                                  SizedBox(width: 16),
                                  CLSkeleton(width: 65, height: 12)
                                ])),
                            SizedBox(height: 8),
                            Row(children: [
                              CLSkeleton(width: 48, height: 22),
                              SizedBox(width: 6),
                              CLSkeleton(width: 60, height: 22)
                            ]),
                            SizedBox(height: 8),
                            SizedBox(
                                height: 40,
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _BodyLines(lines: 2))),
                            SizedBox(height: 10),
                            SizedBox(
                                height: 16,
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      CLSkeleton(width: 56, height: 13),
                                      CLSkeleton(width: 43, height: 11)
                                    ])),
                          ])),
                const SizedBox(height: 6),
              ],
            ])));
  }
}

/// Document geometry follows the reader or the editor, rather than list rows.
class WritingDocumentSkeleton extends StatelessWidget {
  const WritingDocumentSkeleton({super.key, this.editor = false});
  final bool editor;
  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Semantics(
        label: editor ? 'Loading note' : 'Loading diary entry',
        child: ExcludeSemantics(
            child: Column(children: [
          Expanded(
              child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      19, editor ? 18 : 23, 19, editor ? 24 : 28),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (editor)
                          const SizedBox(
                              height: 48,
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _Line(.78, height: 29)))
                        else
                          const Row(children: [
                            CLSkeleton(width: 22, height: 26),
                            SizedBox(width: 10),
                            Expanded(child: _Line(.85, height: 22))
                          ]),
                        SizedBox(height: editor ? 16 : 8),
                        Row(children: [
                          CLSkeleton(
                              width: editor ? 110 : 150,
                              height: editor ? 16 : 14),
                          if (!editor) ...[
                            const SizedBox(width: 12),
                            const CLSkeleton(width: 65, height: 14)
                          ]
                        ]),
                        SizedBox(height: editor ? 24 : 14),
                        if (editor) const SizedBox(height: 8),
                        const _BodyLines(lines: 4, step: 13),
                        const SizedBox(height: 24),
                        const _BodyLines(lines: 3, step: 13),
                        const SizedBox(height: 24),
                        const _BodyLines(lines: 4, step: 13),
                      ]))),
          if (editor)
            SafeArea(
                top: false,
                child: Container(
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: p.border))),
                    child: const Column(children: [
                      SizedBox(
                          height: 48,
                          child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Row(children: [
                                CLSkeleton(width: 20, height: 20),
                                SizedBox(width: 28),
                                CLSkeleton(width: 20, height: 20),
                                Spacer(),
                                CLSkeleton(width: 20, height: 20)
                              ]))),
                      SizedBox(
                          height: 56,
                          child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _Line(.9, height: 20)))),
                    ]))),
        ])));
  }
}
