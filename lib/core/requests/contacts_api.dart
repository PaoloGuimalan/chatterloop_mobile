// Contacts endpoints - verified against the actual webapp
// (webapp/src/app/tabs/feed/Contacts.tsx, requests.ts ContactsListInitRequest
// /ContactRequest/AcceptContactRequest/DeclineContactRequest). The list lives
// on the Django user_service (/api/user/contacts), NOT the old Node
// /u/getContacts endpoint this file previously called - that endpoint isn't
// used by the live webapp at all.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/user_models/contact_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ContactsApi {
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// Plain DRF pagination envelope {count, next, previous, results} - not
  /// wrapped in {status, result} the way most Node endpoints are.
  Future<({List<Contact> results, bool hasNext})> getContactsRequest(
      {int page = 1, int pageSize = 20}) async {
    try {
      final response = await _dio.get(_endpoints.contacts,
          queryParameters: {'page': page, 'page_size': pageSize});

      final results = response.data["results"];
      if (results is! List) return (results: <Contact>[], hasNext: false);
      return (
        results: results
            .whereType<Map>()
            .map((item) => Contact.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        hasNext: response.data["next"] != null,
      );
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return (results: <Contact>[], hasNext: false);
    }
  }

  /// addUsername is misleadingly named on the backend - it actually expects
  /// the target account's UUID id, not their username string.
  Future<bool> requestContactRequest(String accountId) async {
    try {
      final response = await _dio
          .post(_endpoints.contacts, data: {'addUsername': accountId});
      return response.data["status"] == true;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// POST /api/user/poke - only succeeds between already-connected accounts
  /// (server 403s otherwise); the message is a user-facing toast either
  /// way ("You poked @username" on success, a reason on failure), matches
  /// webapp's PokeUserRequest showing response.data.message regardless of
  /// status.
  Future<({bool success, String? message})> pokeUserRequest(
      String targetId) async {
    try {
      final response =
          await _dio.post(_endpoints.poke, data: {'target_id': targetId});
      return (
        success: response.data["status"] == true,
        message: response.data["message"]?.toString(),
      );
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return (success: false, message: null);
    }
  }

  Future<bool> acceptContactRequest(
      {required String connectionId, required String toUserId}) async {
    try {
      final response = await _dio.put(_endpoints.contacts,
          data: {'connection_id': connectionId, 'to_user_id': toUserId});
      return response.data["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// action is sent as a header (not just in the body) - matches the
  /// webapp's DeclineContactRequest exactly. Use "decline" to reject an
  /// incoming request, "remove" to cancel a sent one or unfriend someone.
  Future<bool> declineContactRequest(
      {required String connectionId,
      required String toUserId,
      required String action}) async {
    try {
      final response = await _dio.delete(_endpoints.contacts,
          data: {'connection_id': connectionId, 'to_user_id': toUserId},
          options: Options(headers: {'action': action}));
      return response.data["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }
}
