// Own-profile update, avatar/cover upload, and other-user profile lookup.
// Split out from AuthApi since these aren't session/credential concerns.

import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ProfileApi {
  final _userDio = ApiClient.userService.dio;
  final _mainDio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  /// PUT (not signup's POST flow) - partial update, only send changed
  /// fields. Response envelope is `{status, message, data: account}`, not
  /// the usual {status, result} shape used elsewhere in this app.
  Future<Map<String, dynamic>?> updateProfileRequest(
      Map<String, dynamic> fieldsToUpdate) async {
    try {
      final response =
          await _userDio.put(_endpoints.updateProfile, data: fieldsToUpdate);
      if (response.data["status"] == false) return null;
      return response.data["data"] is Map
          ? Map<String, dynamic>.from(response.data["data"])
          : null;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Response is {"data": {...}} - not wrapped in {status, result} either.
  Future<PublicProfile?> getPublicProfileRequest(String username) async {
    try {
      final response =
          await _userDio.get('${_endpoints.publicProfile}$username/');
      final data = response.data["data"];
      if (data is! Map) return null;
      return PublicProfile.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Same endpoint as getPublicProfileRequest above (webapp reuses the
  /// exact same `/api/user/auth/<slug>/` route for both - it branches on the
  /// response's data.type: "user" -> Profile, "page" -> RealmProfile,
  /// confirmed against ProfileContainer.tsx). Only ever called here when
  /// the caller already knows (via UserAccount.activeEntity.type == "realm")
  /// that the slug in question is a page, so no branching is needed on
  /// this side - always parsed as a realm.
  ///
  /// [handle] is a realm SLUG from a profile link, or a conversation's
  /// contactID when coming from a group chat - the route resolves both, which
  /// is why webapp's ManageRealmContainer can pass `params.realm_id` straight
  /// through. [forManage] adds web's `?type=manage`.
  Future<RealmProfile?> getRealmProfileRequest(String handle,
      {bool forManage = false}) async {
    try {
      final response = await _userDio.get(
        '${_endpoints.publicProfile}$handle/',
        queryParameters: forManage ? {'type': 'manage'} : null,
      );
      final data = response.data["data"];
      if (data is! Map) return null;
      return RealmProfile.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Edits a page's own details. Mirrors webapp's UpdateRealmRequest:
  /// PUT /api/realm/my-list {realm_id, fields} - the same route that LISTS
  /// the realms you administer, which is also how the server authorises the
  /// edit (it is your list, so it is yours to change).
  ///
  /// [fields] is a partial - web sends only what actually changed, and so
  /// does this, so an untouched field can never be overwritten by a stale
  /// value the screen was holding.
  Future<bool> updateRealmRequest(
      String realmId, Map<String, dynamic> fields) async {
    if (fields.isEmpty) return true;
    try {
      final response = await _userDio.put(
        _endpoints.myRealms,
        data: {'realm_id': realmId, 'fields': fields},
      );
      return response.data != null;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// The public realm directory - webapp's GetTopRealmsRequest.
  ///
  /// [type] is the realm kind ("server" for the Servers tab). Rows are the same
  /// RealmSerializer shape the profile uses, so they parse as RealmProfile.
  Future<PagedResult<RealmProfile>> getTopRealmsRequest({
    required String type,
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    try {
      final response = await _userDio.get(
        _endpoints.realmTop,
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          'type': type,
          // Null rather than "" for an empty box, matching web - the two are
          // not the same to the server's filter.
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
      );
      return PagedResult.fromDrf(response.data, RealmProfile.fromJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// The servers this entity belongs to - webapp's InitServerListRequest.
  /// NODE, and JWT-wrapped: the result decodes to {data: [...]}.
  Future<List<RealmSummary>> getMyServersRequest() async {
    try {
      final response = await _mainDio.get(_endpoints.initServerList);
      if (response.data?["status"] == false) return const [];
      final decoded =
          JwtCodec.decode(response.data["result"]?.toString() ?? '');
      final rows = decoded?["data"];
      if (rows is! List) return const [];
      // NOT RealmSummary.fromJson: that parses the DJANGO realm serializer
      // (id/name/slug), and this is the NODE server list, whose rows are
      // serverID/serverName/profile. Reusing it produced rows with empty ids
      // and empty names - which showed up as a rail of "?" avatars, since
      // CLAvatar has no initials to draw from an empty name, and taps that went
      // nowhere.
      return rows.whereType<Map>().map((item) {
        final row = Map<String, dynamic>.from(item);
        return RealmSummary(
          id: (row["serverID"] ?? row["id"] ?? "").toString(),
          name: (row["serverName"] ?? row["name"] ?? "").toString(),
          slug: row["slug"]?.toString(),
          profile: row["profile"]?.toString(),
          type: (row["type"] ?? "server").toString(),
          isAdmin: row["is_admin"] == true || row["isAdmin"] == true,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return const [];
    }
  }

  /// A server's channels AND whether you administer it - webapp's
  /// InitServerChannelsRequest.
  ///
  /// Both, because they arrive on the SAME object and web reads both off it.
  ///
  /// `response.data[0]` is the server itself - `serverName`, `profile`,
  /// `is_admin`, `channels`. ServerInfoModal gates its Manage button on
  /// `serverdetails.is_admin` from exactly this payload. Reading only
  /// `channels` and then asking a second endpoint who the admins are was both
  /// an extra round trip and the wrong answer: the member-role check missed
  /// owners, and the realm-profile route cannot resolve a server id at all.
  Future<({List<ServerChannel> channels, bool isAdmin})>
      getServerChannelsRequest(String serverId) async {
    try {
      final response =
          await _mainDio.get('${_endpoints.initServerChannels}$serverId');
      if (response.data?["status"] == false) {
        return (channels: const <ServerChannel>[], isAdmin: false);
      }
      final decoded =
          JwtCodec.decode(response.data["result"]?.toString() ?? '');
      // DOUBLE-wrapped, and this is where it was going wrong. Web request
      // returns `decodedResult.data`, and Channels.tsx then reads
      // `response.data[0].channels` - so the array lives at data.data[0], not
      // at data[0]. Bailing on "data is not a List" returned an empty list
      // every time, which looked exactly like a server with no channels.
      //
      // Self-detecting rather than a fixed depth, same as
      // getConversationInfoModelRequest: unwrap once more only when the first
      // level is a Map holding its own `data`.
      final level1 = decoded?["data"];
      final rows = level1 is Map ? level1["data"] : level1;
      if (rows is! List || rows.isEmpty) {
        if (kDebugMode) {
          print("[channels] no rows. level1=${level1.runtimeType} "
              "keys=${level1 is Map ? level1.keys.toList() : 'n/a'}");
        }
        return (channels: const <ServerChannel>[], isAdmin: false);
      }
      final first = rows.first;
      final isAdmin = first is Map && first["is_admin"] == true;
      final channels = first is Map ? first["channels"] : null;
      if (channels is! List) {
        if (kDebugMode) {
          print("[channels] first row has no channels list. "
              "keys=${first is Map ? first.keys.toList() : first.runtimeType}");
        }
        return (channels: const <ServerChannel>[], isAdmin: isAdmin);
      }
      if (kDebugMode) {
        print("[channels] parsed ${channels.length}, is_admin=$isAdmin");
      }
      return (
        channels: channels
            .whereType<Map>()
            .map((item) =>
                ServerChannel.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        isAdmin: isAdmin,
      );
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return (channels: const <ServerChannel>[], isAdmin: false);
    }
  }

  /// A realm's members. Mirrors webapp's GetRealmMembersRequest.
  Future<PagedResult<RealmPerson>> getRealmMembersRequest(
    String realmId, {
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    try {
      final response = await _userDio.get(
        _endpoints.realmMembers,
        queryParameters: {
          'realm_id': realmId,
          'page': page,
          'page_size': pageSize,
          // Web sends null rather than "" for an empty search, and the two are
          // not the same to the server's filter.
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
      );
      return PagedResult.fromDrf(response.data, RealmPerson.fromMemberJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// Removes members. Note this is the NODE api, not Django, and it takes a
  /// LIST even for one person (webapp's RemoveRealmMemberRequest).
  Future<bool> removeRealmMembersRequest(
      String realmId, List<String> accountIds) async {
    if (accountIds.isEmpty) return true;
    try {
      final response = await _mainDio.delete(
        _endpoints.realmRemoveUser,
        data: {'realm_id': realmId, 'account_ids': accountIds},
      );
      return response.data?["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Joining a public server - webapp's PublicServerItem.joinServerProcess.
  ///
  /// There is no join endpoint for a server. Joining IS adding yourself, so this
  /// posts the same /s/addnewmembertoserver web does, with one entry describing
  /// the ACTING entity - which is also what gets you into the server's public
  /// channels.
  ///
  /// Not /api/realm/join/v2: that route is strictly conversationType "group"
  /// (see endpoints), so it accepted the call and did nothing for a server -
  /// which is exactly how the button looked, busy then unchanged.
  ///
  /// Only entityID matters to the community_member row it creates; userID and
  /// fullName are cosmetic, feeding the notification text, and web fills them
  /// from the page's slug/name when acting as one.
  Future<bool> joinServerRequest(String serverId) async {
    try {
      final user = appStore.state.userAuth.user;
      final acting = user.activeEntity;
      final asPage = user.isActingAsEntity;
      final payload = {
        'serverID': serverId,
        'memberstoadd': [
          {
            'userID': asPage
                ? (acting?.slug ?? acting?.name ?? user.username)
                : user.username,
            'entityID': user.entityId,
            'fullName': asPage
                ? (acting?.name ?? user.personalDisplayName)
                : user.personalDisplayName,
          }
        ],
        // The ENTITY id here, which is what web sends for a self-join - the
        // admin-driven add path sends account ids instead. It only drives SSE
        // fan-out, and the one person to notify is you.
        'receivers': [user.entityId],
      };
      final response = await _mainDio.post(
        _endpoints.addNewMemberToServer,
        data: {'token': JwtCodec.sign(payload)},
      );
      return response.data?["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Creates a SERVER - webapp's CreateServerRequest.
  ///
  /// [memberEntityIds] are ENTITY ids. Web's picker stores `id: cnts.entityID`
  /// and then sends `otherUsers: markedMembers.map(m => m.id)`, so despite the
  /// name that list has always been entity ids - the same contract the rest of
  /// the realm endpoints use (see removeRealmMembersRequest).
  ///
  /// The creator is not in the list; the server makes them owner.
  Future<bool> createServerRequest({
    required String name,
    required bool isPrivate,
    List<String> memberEntityIds = const [],
  }) async {
    try {
      final response = await _mainDio.post(
        _endpoints.createServer,
        data: {
          'token': JwtCodec.sign({
            // Web calls it groupName even for a server - a server IS a realm
            // with a conversation behind it.
            'groupName': name,
            'privacy': isPrivate,
            'otherUsers': memberEntityIds,
          })
        },
      );
      return response.data?["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Creates a channel inside a server - webapp's CreateChannelRequest.
  ///
  /// [type] is "channel" (text) or "voice", matching web's select values.
  /// [memberEntityIds] are ENTITY ids, as above; web only collects them for a
  /// PRIVATE channel, since a public one takes its membership from the server.
  Future<bool> createChannelRequest({
    required String serverId,
    required String name,
    required bool isPrivate,
    required String type,
    List<String> memberEntityIds = const [],
  }) async {
    try {
      final response = await _mainDio.post(
        _endpoints.createChannel,
        data: {
          'token': JwtCodec.sign({
            'serverID': serverId,
            'groupName': name,
            'privacy': isPrivate,
            'otherUsers': memberEntityIds,
            'type': type,
          })
        },
      );
      return response.data?["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Adds people to a realm. Mirrors webapp's AddNewMemberRequest:
  /// POST /m/addnewmember with the payload JWT-SIGNED as {token: ...}, the same
  /// envelope call_api and sharePost already use for Node mutations.
  ///
  /// The payload shape is web's exactly, including that `receivers` carries
  /// ACCOUNT ids (it feeds SSE fan-out) while each entry also names its
  /// entityID - the two are different keys and both are read:
  ///
  ///   `memberstoadd: [{id: account, entityID: entity, userID: username,`
  ///   `                fullName: "First Middle Last"}]`
  ///   `receivers: [account, ...]`
  ///
  /// [conversationId] is the realm id - for a group that IS its conversation
  /// id, which is what web passes as `conversationID`.
  ///
  /// [isServer] switches to /s/addnewmembertoserver, which also fans the member
  /// out to the server's PUBLIC CHANNELS. /m/addnewmember adds to one
  /// conversation only, so using it for a server would leave the person in the
  /// server and in none of its channels - present but unable to see anything.
  /// Web branches on `realm.type === "server"` at the same point.
  Future<bool> addRealmMembersRequest({
    required String conversationId,
    required List<RealmMemberInvite> members,
    bool isServer = false,
  }) async {
    if (members.isEmpty) return true;
    try {
      final payload = <String, dynamic>{
        // The id's KEY changes with the endpoint - serverID there,
        // conversationID here - even though the value is the same realm id.
        (isServer ? 'serverID' : 'conversationID'): conversationId,
        'memberstoadd': members.map((m) => m.toJson()).toList(),
        'receivers': members.map((m) => m.accountId).toList(),
      };
      final response = await _mainDio.post(
        isServer ? _endpoints.addNewMemberToServer : _endpoints.addNewMember,
        data: {'token': JwtCodec.sign(payload)},
      );
      return response.data?["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Promote to admin / demote to member. NODE, and keyed by the MEMBER ROW's
  /// id rather than by who the person is - webapp's UpdateMemberRoleRequest.
  ///
  /// [role] is "admin" or "member"; those two are the only values web sends.
  Future<bool> updateRealmMemberRoleRequest({
    required String realmId,
    required String memberId,
    required String role,
  }) async {
    try {
      final response = await _mainDio.put(
        _endpoints.realmMemberRole,
        data: {'realm_id': realmId, 'member_id': memberId, 'new_role': role},
      );
      return response.data?["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// A realm's followers - pages only, since nothing else can be followed.
  Future<PagedResult<RealmPerson>> getRealmFollowersRequest(
    String realmId, {
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    try {
      final response = await _userDio.get(
        _endpoints.realmFollowers,
        queryParameters: {
          'realm_id': realmId,
          'page': page,
          'page_size': pageSize,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
      );
      return PagedResult.fromDrf(response.data, RealmPerson.fromFollowerJson);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return PagedResult.empty();
    }
  }

  /// Drops one follower. Keyed by follow_id (the FOLLOW row), not by who they
  /// are - see RealmPerson.removalId.
  Future<bool> removeRealmFollowerRequest(
      String realmId, String followId) async {
    try {
      await _userDio.delete(
        _endpoints.realmFollowers,
        data: {'realm_id': realmId, 'follow_id': followId},
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Replaces a realm's avatar or cover. One multipart POST to NODE, unlike a
  /// user's avatar which goes through /posts/upload and then a post - a realm
  /// has no feed post to file, so this endpoint does the whole job.
  ///
  /// [mediaType] is "profile" or "cover_photo", matching the content_type
  /// values the personal-account flow uses.
  Future<bool> updateRealmMediaRequest({
    required String realmId,
    required String realmType,
    required String mediaType,
    required String filePath,
  }) async {
    try {
      final fileName = filePath.split(RegExp(r'[\\/]')).last;
      final form = FormData.fromMap({
        'realm_id': realmId,
        'realm_type': realmType,
        'media_type': mediaType,
        'image': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final response =
          await _mainDio.post(_endpoints.realmUploadMedia, data: form);
      return response.data?["status"] == true;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Step 1 of the avatar/cover upload flow - uploads the raw file, returns
  /// {url, mediaType, fileName} for the returned CDN reference (result[0]
  /// .fileDetails.data - confirmed by reading saveFileRecordToDatabase in
  /// server/reusables/hooks/firebaseupload.js).
  Future<({String url, String mediaType, String fileName, String? fileId})?>
      uploadMediaRequest(String filePath, String mediaType) async {
    try {
      final fileName = filePath.split(RegExp(r'[\\/]')).last;
      final form = FormData.fromMap({
        'media': await MultipartFile.fromFile(filePath, filename: fileName),
        'captions': '[""]',
        'referenceMediaTypes': '["$mediaType"]',
      });

      final response = await _mainDio.post('/posts/upload', data: form);

      if (response.data["status"] == false) return null;
      final result = response.data["result"];
      if (result is! List || result.isEmpty) return null;

      final first = Map<String, dynamic>.from(result[0]);
      final fileDetails = first["fileDetails"] is Map
          ? Map<String, dynamic>.from(first["fileDetails"])
          : const {};
      final url = fileDetails["data"]?.toString();
      if (url == null) return null;

      return (
        url: url,
        mediaType: (first["fileType"] ?? mediaType).toString(),
        fileName: (first["fileName"] ?? fileName).toString(),
        // Diary attachments persist this as Attachment.file_id (see
        // diary/models.py); the profile/cover flow ignores it. Nullable
        // because only the diary path actually depends on it - a missing
        // fileID shouldn't fail an avatar upload.
        fileId: first["fileID"]?.toString(),
      );
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Step 2 - also creates a visible feed post as a side effect (confirmed
  /// by reading server/routes/posts/index.js's /createpost handler: it both
  /// updates user_account.profile/coverphoto AND inserts into
  /// newsfeed_post when content_type is "profile"/"cover_photo").
  Future<bool> setProfileOrCoverMediaRequest({
    required String url,
    required String mediaType,
    required String fileName,
    required bool isCover,
  }) async {
    final payload = {
      'content': {
        'references': [
          {
            'name': fileName,
            'caption': '',
            'reference': url,
            'referenceMediaType': mediaType,
          }
        ],
        'isShared': false,
        'data': '',
      },
      'type': {
        'fileType': 'media',
        'contentType': isCover ? 'cover_photo' : 'profile',
      },
      'onfeed': true,
      'tagging': {'isTagged': false},
      'privacy': {'status': 'public'},
    };

    try {
      final response = await _mainDio
          .post('/posts/createpost', data: {'token': JwtCodec.sign(payload)});
      return response.data["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Approves or declines a pending follow request addressed to the acting
  /// entity - the answering half of [setEntityFollowRequest].
  ///
  /// The acting entity is always the one being FOLLOWED (you can only answer
  /// requests made to you), so `requesterEntityId` is the other side: the
  /// requester's entity id, which the follow_request notification carries as
  /// its referenceID. The action travels as a header to match the
  /// contact-request accept/reject call.
  ///
  /// Idempotent server side: answering an already-settled request returns 200
  /// with `changed: false` rather than an error, so a stale notification is
  /// safe to tap. It also settles the notification, which is what makes the
  /// buttons stay gone after a refetch.
  Future<bool> answerFollowRequest({
    required String requesterEntityId,
    required bool approve,
  }) async {
    try {
      final response = await _userDio.put(
        _endpoints.realmFollow,
        data: {'target_id': requesterEntityId},
        options: Options(
          headers: {'action': approve ? 'approve' : 'decline'},
        ),
      );
      return response.data is Map
          ? response.data["status"] != false
          : response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Follows or unfollows ANY entity - a page or a person. Same endpoint
  /// either way, distinguished by method: POST to follow, DELETE to unfollow.
  ///
  /// Following is entity->entity now (the backend's Follow row targets an
  /// entity, not a realm), so this takes an entity id and a person can be
  /// followed exactly like a page. `entity_id` is the canonical key; the
  /// legacy `realm_id` is still accepted server side but no longer sent.
  /// Returns `ok` plus `isPending`: following a PRIVATE profile does not take
  /// effect immediately, it creates a request its owner must approve, and the
  /// response says so. A caller that ignores `isPending` will show "Following"
  /// for someone who cannot actually see the profile yet.
  ///
  /// `isPending` is always false for an unfollow, and for a realm - a realm is
  /// never private, so a follow of one is always established at once.
  Future<({bool ok, bool isPending})> setEntityFollowRequest({
    required String entityId,
    required bool follow,
  }) async {
    try {
      final body = {'entity_id': entityId};
      final response = follow
          ? await _userDio.post(_endpoints.realmFollow, data: body)
          : await _userDio.delete(_endpoints.realmFollow, data: body);
      final data = response.data;
      final ok =
          data is Map ? data["status"] != false : response.statusCode == 200;
      final pending = follow && ok && data is Map && data["is_pending"] == true;
      return (ok: ok, isPending: pending);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return (ok: false, isPending: false);
    }
  }
}
