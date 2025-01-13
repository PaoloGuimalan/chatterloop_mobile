import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';

class ConversationFilesModel {
  String fileID;
  List<String> foreignID;
  FileDetailsModel fileDetails;
  String fileOrigin;
  String fileType;
  String action;
  ActionDate dateUploaded;

  ConversationFilesModel(this.fileID, this.foreignID, this.fileDetails,
      this.fileOrigin, this.fileType, this.action, this.dateUploaded);

  factory ConversationFilesModel.fromJson(Map<String, dynamic> json) {
    return ConversationFilesModel(
        json["fileID"],
        (json["foreignID"] as List).map((id) => id.toString()).toList(),
        FileDetailsModel.fromJson(json["fileDetails"]),
        json["fileOrigin"],
        json["fileType"],
        json["action"],
        ActionDate.fromJson(json["dateUploaded"]));
  }
}

class FileDetailsModel {
  String data;

  FileDetailsModel(this.data);

  factory FileDetailsModel.fromJson(Map<String, dynamic> json) {
    return FileDetailsModel(json["data"]);
  }
}
