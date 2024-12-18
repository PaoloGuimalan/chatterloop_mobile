import 'package:chatterloop_app/models/user_models/user_auth_model.dart';

class UserPostsList {
  final List<UserPost> posts;

  UserPostsList(this.posts);

  factory UserPostsList.fromJson(Map<String, dynamic> json) {
    return UserPostsList(
      (json['posts'] as List).map((post) => UserPost.fromJson(post)).toList(),
    );
  }
}

class UserPost {
  final String postID;
  final String userID;
  final PostContent content;
  final PostType type;
  final PostTagging tagging;
  final PostPrivacy privacy;
  final String onfeed;
  final bool isSponsored;
  final bool isLive;
  final PostIsOnMap isOnMap;
  final bool fromSystem;
  final int dateposted;
  final UserAccount postOwner;
  final List<UserAccount> taggedUsers;

  UserPost(
      this.postID,
      this.userID,
      this.content,
      this.type,
      this.tagging,
      this.privacy,
      this.onfeed,
      this.isSponsored,
      this.isLive,
      this.isOnMap,
      this.fromSystem,
      this.dateposted,
      this.postOwner,
      this.taggedUsers);

  factory UserPost.fromJson(Map<String, dynamic> json) {
    return UserPost(
        json['postID'],
        json['userID'],
        PostContent.fromJson(json['content']),
        PostType.fromJson(json['type']),
        PostTagging.fromJson(json['tagging']),
        PostPrivacy.fromJson(json['privacy']),
        json['onfeed'],
        json['isSponsored'],
        json['isLive'],
        PostIsOnMap.fromJson(json['isOnMap']),
        json['fromSystem'],
        json['dateposted'],
        UserAccount.fromJson(json['post_owner']),
        (json['tagged_users'] as List)
            .map((tagged) => UserAccount.fromJson(tagged))
            .toList());
  }
}

class PostContent {
  final bool isShared;
  final String data;
  final List<PostReferences> references;

  PostContent(this.isShared, this.data, this.references);

  factory PostContent.fromJson(Map<String, dynamic> json) {
    return PostContent(
      json['isShared'],
      json['data'],
      (json['references'] as List)
          .map((reference) => PostReferences.fromJson(reference))
          .toList(),
    );
  }
}

class PostReferences {
  final String? name;
  final String? referenceID;
  final String reference;
  final String caption;
  final String referenceMediaType;

  PostReferences(this.name, this.referenceID, this.reference, this.caption,
      this.referenceMediaType);

  factory PostReferences.fromJson(Map<String, dynamic> json) {
    return PostReferences(
      json["name"],
      json["referenceID"],
      json["reference"],
      json["caption"],
      json["referenceMediaType"],
    );
  }
}

class PostType {
  final String fileType;
  final String contentType;

  PostType(this.fileType, this.contentType);

  factory PostType.fromJson(Map<String, dynamic> json) {
    return PostType(
      json["fileType"],
      json["contentType"],
    );
  }
}

class PostTagging {
  final bool isTagged;
  final List<dynamic> users;

  PostTagging(this.isTagged, this.users);

  factory PostTagging.fromJson(Map<String, dynamic> json) {
    return PostTagging(
      json["isTagged"],
      List<dynamic>.from(json["users"]),
    );
  }
}

class PostPrivacy {
  final String status;
  final List<String> users;

  PostPrivacy(this.status, this.users);

  factory PostPrivacy.fromJson(Map<String, dynamic> json) {
    return PostPrivacy(
      json["status"],
      List<String>.from(json["users"]),
    );
  }
}

class PostIsOnMap {
  final bool status;
  final bool isStationary;

  PostIsOnMap(this.status, this.isStationary);

  factory PostIsOnMap.fromJson(Map<String, dynamic> json) {
    return PostIsOnMap(
      json["status"],
      json["isStationary"],
    );
  }
}
