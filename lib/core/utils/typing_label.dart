import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';

// The conversation list's typing line. The webapp builds the same one
// (src/reusables/hooks/typing.ts) - keep the two in step.

/// The name a typer goes by in a label: a person's first name, the way group
/// threads label senders, and a page's or bot's whole name ("Neon Systems",
/// not "Neon"). Null when the ping carried no name (an older server).
String? typerName(IsTypingMetaData typer) {
  final name = (typer.displayName ?? "").trim();
  if (name.isEmpty) return null;
  final type = typer.entityType;
  return type != null && type != 'user' ? name : name.split(RegExp(r'\s+')).first;
}

/// A DM's row is already titled with the person, so it says only
/// "is typing…"; a group or channel row says who.
String typingLabel(List<IsTypingMetaData> typers, {required bool isGroupLike}) {
  if (!isGroupLike) return "is typing…";
  if (typers.length > 1) return "multiple people are typing…";
  final name = typers.isEmpty ? null : typerName(typers.first);
  return name != null ? "$name is typing…" : "someone is typing…";
}
