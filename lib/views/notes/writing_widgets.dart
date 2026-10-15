import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:flutter/material.dart';

class WritingOwner extends StatelessWidget {
  const WritingOwner({super.key, this.diary = false});
  final bool diary;
  @override
  Widget build(BuildContext context) {
    final user = appStore.state.userAuth.user;
    final p = cl(context);
    return Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: Row(children: [
          CLAvatar(
              id: user.activeAvatarSeed,
              name: user.activeDisplayName,
              src: user.activeAvatarSrc,
              size: 34),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(user.activeDisplayName,
                    style: TextStyle(
                        color: p.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(
                    diary
                        ? 'Your personal diary'
                        : user.isActingAsEntity
                            ? 'Your realm notebook'
                            : 'Your personal notebook',
                    style: TextStyle(color: p.text3, fontSize: 11)),
              ])),
        ]));
  }
}

InputDecoration writingInput(String hint) => InputDecoration(
      hintText: hint,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
