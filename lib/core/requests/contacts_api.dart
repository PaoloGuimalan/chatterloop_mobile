// Contacts endpoints. Mirrors chatterloop_mobile/lib/services/contacts_api.dart's role.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:flutter/foundation.dart';

class ContactsApi {
  final _dio = ApiClient.instance.dio;
  final _userDio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  Future<EncodedResponse?> getContactsRequest() async {
    ContentValidator().printer('${_endpoints.apiUrl}${_endpoints.getContacts}');
    try {
      final response = await _dio.get(_endpoints.getContacts);
      if (response.data["status"] == false) return null;
      return EncodedResponse(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// addUsername is misleadingly named on the backend - it actually expects
  /// the target account's UUID id, not their username string.
  Future<bool> requestContactRequest(String accountId) async {
    try {
      final response = await _userDio
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
}
