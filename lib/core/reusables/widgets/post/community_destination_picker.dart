import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:go_router/go_router.dart';
import 'post_tagging.dart';

bool communityDestinationAllowed(BuildContext context) {
  if (CommunityPostScope.of(context) != null) return true;
  final segments = GoRouter.maybeOf(context)
          ?.routeInformationProvider
          .value
          .uri
          .pathSegments ??
      [];
  final actor = appStore.state.userAuth.user;
  if (segments.length >= 2 && segments.first == 'user') {
    return !actor.isActingAsEntity && segments[1] == actor.username;
  }
  if (segments.length >= 2 && segments.first == 'realm') {
    return segments[1] == actor.activeEntity?.slug;
  }
  return segments.isEmpty || segments.first != 'bot';
}

/// A destination must admit every ordinary tag. The server repeats this check
/// when publishing, since membership can change while the sheet is open.
Future<Community?> pickCommunityDestination(BuildContext context,
    {List<String> taggedEntityIds = const [], Community? privateSource}) async {
  final choices = <Community>[];
  var page = 1;
  while (true) {
    final result = await CommunityApi()
        .discover(joined: true, page: page++, taggedEntityIds: taggedEntityIds);
    choices.addAll(result.results.where((community) =>
        community.isMember &&
        (privateSource == null ||
            community.entityId == privateSource.entityId)));
    if (!result.hasNext) break;
  }
  if (!context.mounted) return null;
  final options = [
    if (privateSource == null)
      const Community(realmId: '', entityId: '', name: 'Your timeline'),
    ...choices,
  ];
  return showModalBottomSheet<Community>(
      context: context,
      useRootNavigator: true,
      backgroundColor: cl(context).surface,
      builder: (context) => SafeArea(
          child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(14),
              itemCount: options.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text(
                          taggedEntityIds.isEmpty
                              ? 'Post in'
                              : 'Post in · matching tagged members',
                          style: const TextStyle(
                              fontSize: CLType.title,
                              fontWeight: FontWeight.w600)));
                }
                final choice = options[index - 1];
                return ListTile(
                    minLeadingWidth: 20,
                    minTileHeight: 52,
                    minVerticalPadding: 4,
                    horizontalTitleGap: 10,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                        choice.entityId.isEmpty
                            ? Icons.home_outlined
                            : Icons.groups_outlined,
                        size: 20,
                        color: cl(context).brand),
                    title: Text(choice.name,
                        style: const TextStyle(fontSize: CLType.label)),
                    subtitle: Text(
                        choice.entityId.isEmpty
                            ? 'Personal timeline'
                            : choice.isPrivate
                                ? 'Private community'
                                : 'Public community',
                        style: TextStyle(
                            fontSize: CLType.caption,
                            color: cl(context).text2)),
                    onTap: () => Navigator.pop(context, choice));
              })));
}
