import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/encryption/diary_session.dart';

class LockedDiaryTitle extends StatelessWidget {
  const LockedDiaryTitle({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Encrypted title',
      child: ExcludeSemantics(
          child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final width in [.85, .6])
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FractionallySizedBox(
                    widthFactor: width,
                    child: Container(
                        height: 17,
                        decoration: BoxDecoration(
                            color: cl(context).border,
                            borderRadius: BorderRadius.circular(4))))),
        ]),
      )));
}

class LockedDiaryContent extends StatelessWidget {
  const LockedDiaryContent({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Encrypted writing',
      child: ExcludeSemantics(
          child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var paragraph = 0; paragraph < 3; paragraph++)
            Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final width in [.96, .9, .98, .65])
                        Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: FractionallySizedBox(
                                widthFactor: width,
                                child: Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: cl(context).border,
                                        borderRadius:
                                            BorderRadius.circular(4))))),
                    ])),
        ]),
      )));
}

class LockedDiary extends StatelessWidget {
  const LockedDiary({super.key, this.onUnlock});
  final VoidCallback? onUnlock;
  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ExcludeSemantics(
          child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final width in [170.0, 240.0, 195.0])
                      Container(
                          width: width,
                          height: 9,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                              color: p.border,
                              borderRadius: BorderRadius.circular(4))),
                  ]))),
      Row(children: [
        Icon(Icons.lock_outline, size: 16, color: p.text2),
        const SizedBox(width: 6),
        Expanded(
            child: Text(
                DiarySession.instance.purposeEnabled
                    ? 'Entry needs a different or older key to unlock'
                    : 'Diary protection is temporarily unavailable.',
                style: TextStyle(color: p.text2, fontSize: CLType.bodySm)))
      ]),
      if (onUnlock != null && DiarySession.instance.purposeEnabled)
        TextButton(onPressed: onUnlock, child: const Text('Unlock entry')),
    ]);
  }
}
