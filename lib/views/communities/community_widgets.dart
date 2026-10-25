import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/community_name.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';

class CommunitySectionTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  const CommunitySectionTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: selected == i,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: selected == i ? p.brand : p.text2,
                    padding: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(),
                  ),
                  onPressed: () => onSelected(i),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                        color: selected == i ? p.brand : Colors.transparent,
                        width: 2,
                      )),
                    ),
                    child: Text(labels[i],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: CLType.label,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CommunityDirectoryCard extends StatelessWidget {
  final Community community;
  final VoidCallback onOpen;

  const CommunityDirectoryCard(
      {super.key, required this.community, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final cover = community.coverPhoto;
    return CLCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CLRadii.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 76,
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [p.brandSoft, p.surface3])),
              child: cover == null || cover.isEmpty || cover == 'none'
                  ? null
                  : Image.network(cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    CLAvatar(
                        id: community.realmId,
                        src: community.profile,
                        name: community.name,
                        size: 28),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text.rich(
                      TextSpan(
                          children: communityNameSpans(context, community,
                              style: TextStyle(
                                  color: p.text,
                                  fontSize: CLType.title,
                                  fontWeight: FontWeight.w700))),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                  const SizedBox(height: 10),
                  Text(community.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: CLType.caption,
                          color: p.text2,
                          height: 1.45)),
                  const SizedBox(height: 10),
                  Text(
                      '${community.isPrivate ? 'Private' : 'Public'} · ${community.memberCount ?? 0} members',
                      style: TextStyle(fontSize: CLType.meta, color: p.text3)),
                  const SizedBox(height: 12),
                  CLBtn(
                      label: community.isMember ? 'Open' : 'View',
                      onPressed: onOpen,
                      variant: community.isMember
                          ? CLBtnVariant.outline
                          : CLBtnVariant.primary,
                      size: CLBtnSize.sm,
                      labelSize: CLType.label,
                      block: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
