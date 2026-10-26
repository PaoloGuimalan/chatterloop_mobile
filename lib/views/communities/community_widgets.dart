import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/servers/servers_view.dart';

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
    return ServerCard(
      server: RealmProfile(
        id: community.realmId,
        entityId: community.entityId,
        name: community.name,
        slug: community.slug,
        profile: community.profile,
        coverPhoto: community.coverPhoto,
        description: community.description,
        type: 'community',
        isPrivate: community.isPrivate,
        followersCount: 0,
        membersCount: community.memberCount ?? 0,
        isMember: community.isMember,
        isAdmin: false,
        isVerified: community.isVerified,
      ),
      isMember: community.isMember,
      busy: false,
      actionLabel: community.isMember ? 'Open' : 'View',
      onOpen: onOpen,
      onJoin: onOpen,
    );
  }
}
