import 'package:chatterloop_app/core/utils/chat_mentions.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter_test/flutter_test.dart';

UsersContactPreview m(String userID, String first, String last, String entity) =>
    UsersContactPreview(userID, entity, UserFullname(first, "", last), "none",
        null, true, true);

void main() {
  final anna = m("anna", "Anna", "Reyes", "E1");
  final annabelle = m("annabelle", "Annabelle", "Cruz", "E2");
  final members = [anna, annabelle];

  group('activeMentionQuery', () {
    test('opens at start and after whitespace', () {
      expect(activeMentionQuery("@an", 3)?.query, "an");
      expect(activeMentionQuery("hi @an", 6)?.query, "an");
      expect(activeMentionQuery("@", 1)?.query, "");
    });
    test('does not open mid-word (email)', () {
      expect(activeMentionQuery("mail@anna", 9), isNull);
    });
    test('closes after the mention is completed with a space', () {
      expect(activeMentionQuery("@anna ", 6), isNull);
    });
  });

  test('insertMention replaces the query and trails a space', () {
    final r = insertMention("hi @an", 3, 6, anna);
    expect(r.text, "hi @anna ");
    expect(r.cursor, 9);
  });

  test('suggestions match handle or full name, capped', () {
    expect(mentionSuggestions(members, "ann").length, 2);
    expect(mentionSuggestions(members, "reyes").single.userID, "anna");
    expect(mentionSuggestions(members, "").length, 2);
  });

  group('splitMentionSpans', () {
    test('longest label wins - @annabelle is not clipped to @anna', () {
      final spans = splitMentionSpans("hey @annabelle ok", members);
      expect(spans.where((s) => s.isMention).single.text, "@annabelle");
    });
    test('highlights before punctuation', () {
      final spans = splitMentionSpans("thanks @anna!", members);
      expect(spans.where((s) => s.isMention).single.text, "@anna");
    });
    test('unknown handle is not highlighted', () {
      final spans = splitMentionSpans("hi @nobody", members);
      expect(spans.any((s) => s.isMention), isFalse);
    });
    test('no members -> single plain span', () {
      expect(splitMentionSpans("hi @anna", const []).single.isMention, isFalse);
    });
  });

  test('mentionableMembers drops self and caps single conversations', () {
    final all = [anna, annabelle];
    expect(
        mentionableMembers(all, currentEntityId: "E1", conversationType: "group")
            .single
            .userID,
        "annabelle");
    expect(
        mentionableMembers(all, currentEntityId: "ZZ", conversationType: "single")
            .length,
        1);
  });

  // The two member lists answer DIFFERENT questions and must not be swapped:
  //
  //   mentionableMembers      "who can I mention"        -> excludes you
  //   mentionHighlightMembers "whose @handle lights up"  -> includes you
  //
  // Rendering used the first, so your own name was the one handle in the
  // conversation that never highlighted - the mention that matters most.
  group('mentionHighlightMembers', () {
    test('includes you, unlike the suggestion list', () {
      final all = [anna, annabelle];
      expect(mentionHighlightMembers(all).map((m) => m.userID),
          ["anna", "annabelle"]);
    });

    test('dedupes but never caps a single conversation', () {
      // mentionableMembers trims a DM to one suggestion; doing that while
      // rendering would drop a real participant's mentions.
      expect(mentionHighlightMembers([anna, annabelle, anna]).length, 2);
    });

    test('your own handle highlights', () {
      // anna is the viewer here (currentEntityId E1).
      final spans =
          splitMentionSpans("hey @anna check this", mentionHighlightMembers([anna, annabelle]));
      expect(spans.where((s) => s.isMention).single.text, "@anna");
    });

    test('regression: the suggestion list could not highlight the viewer', () {
      final suggestions = mentionableMembers([anna, annabelle],
          currentEntityId: "E1", conversationType: "group");
      final spans = splitMentionSpans("hey @anna check this", suggestions);
      expect(spans.any((s) => s.isMention), isFalse);
    });
  });
}
